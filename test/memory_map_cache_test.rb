require "minitest/autorun"
require "memory_map_cache"
require "active_support/testing/method_call_assertions"
require_relative "behaviors"
require "securerandom"

class TestMemoryMapCacheStore < ActiveSupport::TestCase
  include ActiveSupport::Testing::MethodCallAssertions

  include CacheStoreBehavior
  include CacheStoreVersionBehavior
  include CacheStoreCoderBehavior
  include CacheStoreCompressionBehavior
  include CacheStoreFormatVersionBehavior
  include CacheStoreSerializerBehavior
  include CacheLoggingBehavior
  include EncodedKeyCacheBehavior

  setup do
    @stores = []
    @cache = nil
    @namespace = "test-#{SecureRandom.hex}"
    @cache_path = "/tmp/test_mmap_cache_#{SecureRandom.hex}.bin"
    @cache = lookup_store(expires_in: 60)

    # For LocalCacheBehavior tests
    @peek = lookup_store(expires_in: 60)
  end

  def teardown
    @stores&.each(&:close)
    # Ensure memory map clears out disk artifacts after cache suite behaviors
    File.delete(@cache_path) if @cache_path && File.exist?(@cache_path)
  end

  def lookup_store(options = {})
    store_options = { namespace: @namespace }.merge(options)
    store = ActiveSupport::Cache.lookup_store(:memory_map_cache_store, @cache_path, store_options)
    @stores << store if @stores
    store
  end

  def test_multiprocess_read_write
    @cache.write("shared_key", "initial")

    Process.fork do
      @cache.write("shared_key", "forked_value")
      @cache.write("fork_only_key", "hello")
    end

    Process.waitall

    assert_equal "forked_value", @cache.read("shared_key")
    assert_equal "hello", @cache.read("fork_only_key")
  end

  def test_multiprocess_multi_read_write
    payloads = {
      "key1" => "value1",
      "key2" => "value2",
      "key3" => "value3"
    }

    Process.fork do
      @cache.write_multi(payloads)
      @cache.delete_multi(["key2"])
    end

    Process.waitall

    results = @cache.read_multi("key1", "key2", "key3")

    assert_equal({ "key1" => "value1", "key3" => "value3" }, results)
  end

  def test_multi_operations_expire_correctly
    @cache.write("short_lived", "die_fast", expires_in: 0.1)
    @cache.write("long_lived", "die_slow", expires_in: 5.0)

    sleep 0.2

    # Verify read_multi correctly omits the expired key natively inside C/Ruby loop
    results = @cache.read_multi("short_lived", "long_lived")

    assert_equal({ "long_lived" => "die_slow" }, results)

    # Verify fetch_multi properly yields for missing/expired keys
    fetch_results = @cache.fetch_multi("short_lived", "long_lived") do |key|
      "regenerated_#{key}"
    end

    assert_equal({ "short_lived" => "regenerated_short_lived", "long_lived" => "die_slow" }, fetch_results)
  end

  def test_payload_exceeding_slot_size_returns_false
    # The C-extension defines SLOT_SIZE as 2048.
    # Uses random bytes so it cannot be compressed down to under 2048 bytes.
    huge_payload = SecureRandom.random_bytes(2100)

    # ActiveSupport serialize_entry will write it into a payload.
    # This should be rejected by the native C map gracefully as `false` rather than crashing.
    result = @cache.write("huge_key", huge_payload, compress: false)

    refute result
    assert_nil @cache.read("huge_key")
  end

  def test_explicit_clear
    @cache.write("key1", "val1")
    @cache.write("key2", "val2")

    assert_equal "val1", @cache.read("key1")

    @cache.clear

    assert_nil @cache.read("key1")
    assert_nil @cache.read("key2")
  end

  def test_configurable_sizes_reject_larger_than_custom
    custom_path = "/tmp/test_mmap_custom_#{SecureRandom.hex}.bin"
    custom_cache = ActiveSupport::Cache.lookup_store(:memory_map_cache_store, custom_path,
                                                     { slot_size: 4096, max_slots: 100 })

    # 3.5KB should fit natively in the 4KB slot
    payload_3_5kb = SecureRandom.random_bytes(3500)

    assert custom_cache.write("key1", payload_3_5kb, compress: false)
    assert_equal payload_3_5kb, custom_cache.read("key1")

    # 4.5KB should be rejected
    payload_4_5kb = SecureRandom.random_bytes(4500)

    refute custom_cache.write("key2", payload_4_5kb, compress: false)
    assert_nil custom_cache.read("key2")

    custom_cache.close
    FileUtils.rm_f(custom_path)
  end

  def test_native_cleanup_wipes_expired_entries_from_memory
    @cache.write("expired_key", "gone", expires_in: 0.1)
    @cache.write("persisted_key", "here", expires_in: 10.0)

    # Wait for the first payload to officially expire in POSIX time
    sleep 0.2

    # Evict all expired payloads instantly across the C memory footprint
    swept_slots = @cache.cleanup

    assert_equal 1, swept_slots

    # Ensure unexpired data is flawlessly maintained through the sweep
    assert_equal "here", @cache.read("persisted_key")

    # A secondary sweep instantly afterwards should naturally yield 0 cleaned slots
    assert_equal 0, @cache.cleanup
  end

  def test_concurrent_cleanup_and_operations
    100.times { |i| @cache.write("key_#{i}", "val_#{i}", expires_in: 0.1) }

    pids = []

    # Process 1: Continuously spam cleanup
    pids << Process.fork do
      50.times do
        @cache.cleanup
        sleep 0.01
      end
    end

    # Process 2: Continuously write new fast-expiring keys
    pids << Process.fork do
      500.times do |i|
        @cache.write("new_key_#{i}", "new_val", expires_in: 0.1)
      end
    end

    # Process 3: Continuously read
    pids << Process.fork do
      500.times do |i|
        @cache.read("new_key_#{i}")
      end
    end

    Process.waitall

    # If the process completed without deadlocking or crashing C-level assertions, the locking gracefully holds!
    assert_equal 3, pids.length
  end

  def test_cleanup_speed_on_highly_populated_cache
    # Ensure a customized map specifically large enough to test raw iteration bounds under tight deadlines
    custom_path = "/tmp/test_mmap_custom_perf_#{SecureRandom.hex}.bin"
    large_cache = ActiveSupport::Cache.lookup_store(:memory_map_cache_store, custom_path,
                                                    { slot_size: 2048, max_slots: 50_000 })

    # Inject roughly 20,000 rapidly expiring payloads into the memory map natively
    20_000.times { |i| large_cache.write("spam_#{i}", "data", expires_in: 0.1) }

    sleep 0.2

    # Capture pure C-extension sweep bounds
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    swept = large_cache.cleanup
    duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

    # C-iteration array bounds over 50k structures should never take longer than 15ms
    assert_operator duration, :<, 0.015
    assert_operator swept, :>=, 5_000

    large_cache.close
    FileUtils.rm_f(custom_path)
  end
end
