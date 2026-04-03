require "active_support/cache"
require_relative "../../memory_map_cache/native_loader"

module ActiveSupport
  module Cache
    class MemoryMapCacheStore < Store
      prepend Strategy::LocalCache

      def self.supports_cache_versioning?
        true
      end

      def initialize(cache_path, **options)
        super(options)
        @cache_path = cache_path
        slot_size = options.fetch(:slot_size, 2048).to_i
        max_slots = options.fetch(:max_slots, 20_000).to_i
        @native = MemoryMapCacheNative.new(cache_path, slot_size, max_slots)
      end

      def clear(_options = nil)
        @native.clear
      end

      def cleanup(_options = nil)
        @native.cleanup
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

      def decrement(name, amount = 1, **)
        increment(name, -amount, **)
      end

      def delete_matched(matcher, options = nil)
        raise NotImplementedError, "delete_matched is not supported by memory map mapping"
      end

      protected

      def write_entry(key, entry, **)
        payload = serialize_entry(entry, **)
        # the payload is a standard string output from internal ActiveSupport serializers
        expires_at = entry.expires_at ? entry.expires_at.to_i : 0
        @native.write_raw(key.to_s, payload, expires_at)
      end

      def read_entry(key, **)
        payload = @native.read_raw(key.to_s)
        payload ? deserialize_entry(payload, **) : nil
      end

      def read_multi_entries(names, **options)
        normalized_names = names.map { |name| normalize_key(name, options).to_s }
        raw_results = @native.read_multi_raw(normalized_names)
        results = {}
        names.each do |name|
          key = normalize_key(name, options).to_s
          payload = raw_results[key]
          next unless payload

          entry = deserialize_entry(payload, **options)
          version = normalize_version(name, options)
          results[name] = entry.value if entry && !entry.expired? && !entry.mismatched?(version)
        end
        results
      end

      def write_multi_entries(hash, **)
        raw_hash = {}
        hash.each do |key, entry|
          raw_hash[key.to_s] = serialize_entry(entry, **)
        end
        @native.write_multi_raw(raw_hash)
      end

      def delete_multi_entries(names, **_options)
        @native.delete_multi_raw(names.map(&:to_s))
      end

      def delete_entry(key, **_options)
        safe_key = key.to_s
        @native.delete_raw(safe_key)
      end
    end
  end
end
