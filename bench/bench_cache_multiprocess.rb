$stdout.sync = true
$LOAD_PATH.unshift(File.expand_path("../../lib", __dir__))
$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "active_support"
require "benchmark"
require "litestack"
require "active_support/cache/ram_file_store"
require "memory_map_cache"

begin
  require "sqlite3"
  SQLite3::ForkSafety.suppress_warnings! if defined?(SQLite3::ForkSafety)
rescue LoadError
end

# Normal disk
# cache = ActiveSupport::Cache.lookup_store(:litecache, {path: '../db/rails_cache_multi.db', sync: 0})
# redis = ActiveSupport::Cache.lookup_store(:redis_cache_store)
# Clear old mmap file to ensure tests pick up the new dynamic configurations
FileUtils.rm_f('/tmp/rails_mmap_cache_multi.bin')

# RAMDISK /Volumes/RailsTestRAM
cache = ActiveSupport::Cache.lookup_store(:litecache, { path: '/Volumes/RailsTestRAM/lite_cache_multi.db', sync: 0 })
filestore = ActiveSupport::Cache.lookup_store(:file_store, '/Volumes/RailsTestRAM/rails_cache_multi/')
ramfilestore = ActiveSupport::Cache.lookup_store(:ram_file_store, '/Volumes/RailsTestRAM/ram_cache_multi')
mmapcache = ActiveSupport::Cache.lookup_store(:memory_map_cache_store, '/tmp/rails_mmap_cache_multi.bin',
                                              compress: false, slot_size: 8192, max_slots: 10_000, serializer: :message_pack)
memcache = ActiveSupport::Cache.lookup_store(:mem_cache_store, ["localhost:11211"])
redis = ActiveSupport::Cache.lookup_store(:redis_cache_store, url: "redis://localhost:6379/0")
layeredcache = ActiveSupport::Cache::LayeredStore.new(mmapcache, memcache, l1_expires_in: 5.minutes)

PROCESS_COUNT = (ENV['PROCESSES'] || 5).to_i
ITERATIONS = (ENV['ITERATIONS'] || 1000).to_i
PAYLOADS = ENV['PAYLOADS'] ? ENV['PAYLOADS'].split(',').map(&:to_i) : [100, 1000, 4000]

values = []
keys = []

PAYLOADS.each do |size|
  ITERATIONS.times do
    keys << (0...10).map { ('a'..'z').to_a[rand(26)] }.join
    values << (0...size).map { ('a'..'z').to_a[rand(26)] }.join
  end

  puts "Multiprocess Benchmarks for values of size #{size} bytes"
  puts "=========================================================="

  def bench_multiprocess(name, processes, iterations)
    print "Starting #{processes} processes with #{iterations} iterations of #{name} ... "

    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    processes.times do |process_idx|
      Process.fork do
        iterations.times do |i|
          yield(process_idx, i)
        end
      end
    end

    Process.waitall

    end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    elapsed = end_time - start_time
    total_ops = processes * iterations
    ips = total_ops / elapsed

    puts "\n .. finished in #{elapsed.round(3)} seconds (#{ips.round(2)} ops/sec)"
  end

  def bench_mixed_multiprocess(name, cache_store, iterations, processes)
    puts "Starting #{processes} processes with #{iterations} iterations of #{name} mixed ..."

    Benchmark.bm do |x|
      x.report("mixed") do
        pids = []
        processes.times do
          pids << Process.fork do
            # 20% write, 80% read workload
            (iterations / 5).times do |j|
              cache_store.write("key_#{j}", "value_#{j}")
              4.times do
                cache_store.read("key_#{j}")
              end
            end
          end
        end
        Process.waitall
      end
    end
  end

  def bench_multi_multiprocess(name, cache_store, iterations, processes, keys_count = 50)
    puts "Starting #{processes} processes with #{iterations} iterations of #{keys_count}-key multi PIPELINE on #{name} ..."

    keys = (1..keys_count).map { |i| "multi_key_#{i}" }
    payloads = keys.to_h { |k| [k, "a" * 1500] }

    Benchmark.bm do |x|
      x.report("write_multi") do
        pids = []
        processes.times do
          pids << Process.fork do
            iterations.times do
              cache_store.write_multi(payloads)
            end
          end
        end
        Process.waitall
      end

      x.report("read_multi") do
        pids = []
        processes.times do
          pids << Process.fork do
            iterations.times do
              cache_store.read_multi(*keys)
            end
          end
        end
        Process.waitall
      end
    end
  end

  puts "== Concurrent Writes =="
  bench_multiprocess("litecache writes", PROCESS_COUNT, ITERATIONS) do |p_idx, i|
    idx = ((p_idx * ITERATIONS) + i) % keys.length
    cache.write(keys[idx], values[idx])
  end

  bench_multiprocess("FileStore writes", PROCESS_COUNT, ITERATIONS) do |p_idx, i|
    idx = ((p_idx * ITERATIONS) + i) % keys.length
    filestore.write(keys[idx], values[idx])
  end

  bench_multiprocess("RamFileStore writes", PROCESS_COUNT, ITERATIONS) do |p_idx, i|
    idx = ((p_idx * ITERATIONS) + i) % keys.length
    ramfilestore.write(keys[idx], values[idx])
  end

  bench_multiprocess("MemoryMapCache writes", PROCESS_COUNT, ITERATIONS) do |p_idx, i|
    idx = ((p_idx * ITERATIONS) + i) % keys.length
    mmapcache.write(keys[idx], values[idx])
  end

  bench_multiprocess("LayeredStore writes", PROCESS_COUNT, ITERATIONS) do |p_idx, i|
    idx = ((p_idx * ITERATIONS) + i) % keys.length
    layeredcache.write(keys[idx], values[idx])
  end

  bench_multiprocess("Memcached writes", PROCESS_COUNT, ITERATIONS) do |p_idx, i|
    idx = ((p_idx * ITERATIONS) + i) % keys.length
    memcache.write(keys[idx], values[idx])
  end

  puts "== Concurrent Reads =="
  # Let's make sure the keys exist first
  ITERATIONS.times do |i|
    cache.write(keys[i], values[i])
    filestore.write(keys[i], values[i])
    ramfilestore.write(keys[i], values[i])
    mmapcache.write(keys[i], values[i])
    layeredcache.write(keys[i], values[i])
    memcache.write(keys[i], values[i])
  end

  random_keys = keys.shuffle

  bench_multiprocess("litecache reads", PROCESS_COUNT, ITERATIONS) do |_p_idx, i|
    cache.read(random_keys[i])
  end

  bench_multiprocess("FileStore reads", PROCESS_COUNT, ITERATIONS) do |_p_idx, i|
    filestore.read(random_keys[i])
  end

  bench_multiprocess("RamFileStore reads", PROCESS_COUNT, ITERATIONS) do |_p_idx, i|
    ramfilestore.read(random_keys[i])
  end

  bench_multiprocess("MemoryMapCache reads", PROCESS_COUNT, ITERATIONS) do |_p_idx, i|
    mmapcache.read(random_keys[i])
  end

  bench_multiprocess("LayeredStore reads", PROCESS_COUNT, ITERATIONS) do |_p_idx, i|
    layeredcache.read(random_keys[i])
  end

  bench_multiprocess("Memcached reads", PROCESS_COUNT, ITERATIONS) do |_p_idx, i|
    memcache.read(random_keys[i])
  end

  puts "== Mixed Workload (80% read, 20% write) =="
  bench_multiprocess("litecache mixed", PROCESS_COUNT, ITERATIONS) do |p_idx, i|
    idx = ((p_idx * ITERATIONS) + i) % keys.length
    if rand < 0.8
      cache.read(keys[idx])
    else
      cache.write(keys[idx], values[idx])
    end
  end

  bench_multiprocess("FileStore mixed", PROCESS_COUNT, ITERATIONS) do |p_idx, i|
    idx = ((p_idx * ITERATIONS) + i) % keys.length
    if rand < 0.8
      filestore.read(keys[idx])
    else
      filestore.write(keys[idx], values[idx])
    end
  end

  bench_multiprocess("RamFileStore mixed", PROCESS_COUNT, ITERATIONS) do |p_idx, i|
    idx = ((p_idx * ITERATIONS) + i) % keys.length
    if rand < 0.8
      ramfilestore.read(keys[idx])
    else
      ramfilestore.write(keys[idx], values[idx])
    end
  end

  bench_multiprocess("MemoryMapCache mixed", PROCESS_COUNT, ITERATIONS) do |p_idx, i|
    idx = ((p_idx * ITERATIONS) + i) % keys.length
    if rand < 0.8
      mmapcache.read(keys[idx])
    else
      mmapcache.write(keys[idx], values[idx])
    end
  end

  bench_multiprocess("LayeredStore mixed", PROCESS_COUNT, ITERATIONS) do |p_idx, i|
    idx = ((p_idx * ITERATIONS) + i) % keys.length
    if rand < 0.8
      layeredcache.read(keys[idx])
    else
      layeredcache.write(keys[idx], values[idx])
    end
  end

  bench_multiprocess("Memcached mixed", PROCESS_COUNT, ITERATIONS) do |p_idx, i|
    idx = ((p_idx * ITERATIONS) + i) % keys.length
    if rand < 0.8
      memcache.read(keys[idx])
    else
      memcache.write(keys[idx], values[idx])
    end
  end

  # Test via benchmark.bm for mixed blocks
  bench_mixed_multiprocess("FileStore", filestore, ITERATIONS, PROCESS_COUNT)
  bench_mixed_multiprocess("RamFileStore", ramfilestore, ITERATIONS, PROCESS_COUNT)
  bench_mixed_multiprocess("MemoryMapCache", mmapcache, ITERATIONS, PROCESS_COUNT)
  bench_mixed_multiprocess("LayeredStore", layeredcache, ITERATIONS, PROCESS_COUNT)
  bench_mixed_multiprocess("Memcached", memcache, ITERATIONS, PROCESS_COUNT)

  puts "=========================================================="
  puts "Comparing Pipeline Architectures natively (MGET/MSET)"
  puts "=========================================================="
  multi_iterations = 500
  bench_multi_multiprocess("Redis", redis, multi_iterations, PROCESS_COUNT, 20)
  bench_multi_multiprocess("MemoryMapCache", mmapcache, multi_iterations, PROCESS_COUNT, 20)

  puts "==========================================================\n\n"

  keys = []
  values = []
end

cache.clear
filestore.clear
ramfilestore.clear
mmapcache.clear
memcache.clear
