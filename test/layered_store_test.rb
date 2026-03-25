require "minitest/autorun"
require "memory_map_cache"

class LayeredStoreTest < ActiveSupport::TestCase
  def setup
    @l1 = ActiveSupport::Cache.lookup_store(:memory_store)
    @l2 = ActiveSupport::Cache.lookup_store(:memory_store)
    @cache = ActiveSupport::Cache::LayeredStore.new(@l1, @l2)
  end

  def test_write_and_read
    @cache.write("foo", "bar")

    assert_equal "bar", @cache.read("foo")

    # Should be in both
    assert_equal "bar", @l1.read("foo")
    assert_equal "bar", @l2.read("foo")
  end

  def test_read_miss_populates_l1
    @l2.write("remote", "data")

    assert_nil @l1.read("remote")

    assert_equal "data", @cache.read("remote")
    assert_equal "data", @l1.read("remote")
  end

  def test_delete_removes_from_both
    @cache.write("key", "val")
    @cache.delete("key")

    assert_nil @l1.read("key")
    assert_nil @l2.read("key")
  end

  def test_l1_expires_in
    @cache = ActiveSupport::Cache::LayeredStore.new(@l1, @l2, l1_expires_in: 0.1)

    @cache.write("fast", "furious")

    assert_equal "furious", @l1.read("fast")
    assert_equal "furious", @l2.read("fast")

    sleep 0.2

    # L1 should be expired, L2 should still be there
    assert_nil @l1.read("fast")
    assert_equal "furious", @l2.read("fast")

    # Reading through cache should repopulate L1
    assert_equal "furious", @cache.read("fast")
    assert_equal "furious", @l1.read("fast")
  end

  def test_read_multi
    @l2.write("a", 1)
    @l2.write("b", 2)
    @l2.write("c", 3)
    @l1.write("a", 1) # Only "a" is in L1

    results = @cache.read_multi("a", "b", "c")

    assert_equal({ "a" => 1, "b" => 2, "c" => 3 }, results)

    # b and c should have been backfilled to L1
    assert_equal 2, @l1.read("b")
    assert_equal 3, @l1.read("c")
  end

  def test_write_multi
    @cache.write_multi("x" => 10, "y" => 20)

    assert_equal 10, @l1.read("x")
    assert_equal 20, @l2.read("y")
  end
end
