require "active_support/cache"

module ActiveSupport
  module Cache
    # A caching proxy that layers a fast, node-local cache (L1) in front of a
    # persistent, distributed remote network cache (L2).
    class LayeredStore < Store
      attr_reader :l1_store, :l2_store

      def self.supports_cache_versioning?
        true
      end

      def initialize(l1_store, l2_store, **options)
        super(options)
        @l1_store = l1_store
        @l2_store = l2_store
        @l1_expires_in = options[:l1_expires_in]
      end

      def clear(options = nil)
        @l1_store.clear(options)
        @l2_store.clear(options)
      end

      def cleanup(options = nil)
        @l1_store.cleanup(options)
        @l2_store.cleanup(options)
      end

      def increment(name, amount = 1, **)
        @l1_store.delete(name, **) # Invalidate L1 on increment to prevent stale local counters
        @l2_store.increment(name, amount, **)
      end

      def decrement(name, amount = 1, **)
        @l1_store.delete(name, **) # Invalidate L1 on decrement
        @l2_store.decrement(name, amount, **)
      end

      def delete_matched(matcher, options = nil)
        begin
          @l1_store.delete_matched(matcher, options)
        rescue NotImplementedError => _e
        end
        @l2_store.delete_matched(matcher, options)
      end

      protected

      def read_entry(key, **options)
        entry = @l1_store.send(:read_entry, key, **options)
        return entry if entry && !entry.expired?

        entry = @l2_store.send(:read_entry, key, **options)
        if entry && !entry.expired?
          l1_options = options.dup
          l1_options[:expires_in] = @l1_expires_in if @l1_expires_in
          l1_entry = ActiveSupport::Cache::Entry.new(entry.value, **l1_options)
          @l1_store.send(:write_entry, key, l1_entry, **l1_options)
        end

        entry
      end

      def write_entry(key, entry, **options)
        # Always proxy L2 write first as the master distributed source of truth
        l2_status = @l2_store.send(:write_entry, key, entry, **options)

        # If L2 gracefully fails (i.e. network outage caught by ActiveSupport returning false)
        # we still attempt to hydrate L1 blindly so the node can cache locally and stay afloat during outages!
        l1_options = options.dup
        l1_options[:expires_in] = @l1_expires_in if @l1_expires_in
        l1_entry = ActiveSupport::Cache::Entry.new(entry.value, **l1_options)

        @l1_store.send(:write_entry, key, l1_entry, **l1_options)

        # Bubble up the remote L2 proxy truth so apps correctly detect distributed failure states
        l2_status
      end

      def delete_entry(key, **)
        l2_status = @l2_store.send(:delete_entry, key, **)

        # Defensively ALWAYS blindly delete from L1 avoiding local stale reads if the L2 connection drops
        @l1_store.send(:delete_entry, key, **)

        l2_status
      end

      def read_multi_entries(names, **options)
        l1_results = @l1_store.send(:read_multi_entries, names, **options)
        missing_names = names - l1_results.keys

        return l1_results if missing_names.empty?

        l2_results = @l2_store.send(:read_multi_entries, missing_names, **options)

        if l2_results.any?
          l1_options = options.dup
          l1_options[:expires_in] = @l1_expires_in if @l1_expires_in

          l1_entries_hash = l2_results.transform_values { |v| ActiveSupport::Cache::Entry.new(v, **l1_options) }
          @l1_store.send(:write_multi_entries, l1_entries_hash, **l1_options)
        end

        l1_results.merge(l2_results)
      end

      def write_multi_entries(hash, **options)
        l2_status = @l2_store.send(:write_multi_entries, hash, **options)

        l1_options = options.dup
        l1_options[:expires_in] = @l1_expires_in if @l1_expires_in

        l1_entries_hash = hash.transform_values do |entry|
          ActiveSupport::Cache::Entry.new(entry.value, **l1_options)
        end

        @l1_store.send(:write_multi_entries, l1_entries_hash, **l1_options)

        l2_status
      end

      def delete_multi_entries(names, **)
        l2_status = @l2_store.send(:delete_multi_entries, names, **)
        @l1_store.send(:delete_multi_entries, names, **)
        l2_status
      end
    end
  end
end
