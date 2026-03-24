require "active_support/cache"

module ActiveSupport
  module Cache
    class MemoryMapCacheStore < Store
      prepend Strategy::LocalCache

      def initialize(cache_path, **options)
        super(options)
        @cache_path = cache_path
        slot_size = options.fetch(:slot_size, 2048).to_i
        max_slots = options.fetch(:max_slots, 20000).to_i
        @native = MemoryMapCacheNative.new(cache_path, slot_size, max_slots)
      end
      
      def clear(options = nil)
        @native.clear
      end

      def close
        @native.close
      end

      def increment(name, amount = 1, **options)
        options = merged_options(options)
        new_value = (read(name, **options) || 0).to_i + amount
        write(name, new_value, **options)
        new_value
      end

      def decrement(name, amount = 1, **options)
        increment(name, -amount, **options)
      end
      
      def delete_matched(matcher, options = nil)
         raise NotImplementedError, "delete_matched is not supported by memory map mapping"
      end

      protected

      def write_entry(key, entry, **options)
        payload = serialize_entry(entry, **options)
        # the payload is a standard string output from internal ActiveSupport serializers
        @native.write_raw(key.to_s, payload)
      end

      def read_entry(key, **options)
        payload = @native.read_raw(key.to_s)
        payload ? deserialize_entry(payload, **options) : nil
      end
      
      def read_multi_entries(names, **options)
        normalized_names = names.map { |name| normalize_key(name, options).to_s }
        raw_results = @native.read_multi_raw(normalized_names)
        results = {}
        names.each do |name|
          key = normalize_key(name, options).to_s
          payload = raw_results[key]
          if payload
            entry = deserialize_entry(payload, **options)
            version = normalize_version(name, options)
            if entry && !entry.expired? && !entry.mismatched?(version)
              results[name] = entry.value
            end
          end
        end
        results
      end

      def write_multi_entries(hash, **options)
        raw_hash = {}
        hash.each do |key, entry|
          raw_hash[key.to_s] = serialize_entry(entry, **options)
        end
        @native.write_multi_raw(raw_hash)
      end

      def delete_multi_entries(names, **options)
        @native.delete_multi_raw(names.map(&:to_s))
      end
      
      def delete_entry(key, **options)
        safe_key = key.to_s
        @native.delete_raw(safe_key)
      end
    end
  end
end
