require "active_support/cache/file_store"
require "fileutils"

module ActiveSupport
  module Cache
    class RamFileStore < FileStore
      def initialize(cache_path, **options)
        super
        FileUtils.mkdir_p(cache_path)
      end

      private

      def write_entry(key, entry, **options)
        file_path = key_file_path(key)
        # A direct binary write is significantly faster than FileStore's atomic_write
        # which writes to a temporary file and renames it.
        # Since we are on a RAM disk, tearing is less of a concern.
        File.binwrite(file_path, Marshal.dump(entry))
        true
      end

      def read_entry(key, **options)
        file_path = key_file_path(key)
        if File.exist?(file_path)
          File.open(file_path, "rb") { |f| Marshal.load(f) }
        else
          nil
        end
      rescue StandardError
        nil
      end

      def delete_entry(key, **options)
        file_path = key_file_path(key)
        if File.exist?(file_path)
          File.delete(file_path)
          true
        else
          false
        end
      end

      # We flatten the hash structure to avoid FileStore's deep directory tree overhead.
      # By dropping the directory prefixing entirely, we avoid `ensure_cache_path` checks.
      def key_file_path(key)
        # Use an MD5 or simply a sanitized key. Given the workload, a URL-safe key is enough.
        # Replacing slashes and colons to keep it a flat file.
        safe_key = key.to_s.gsub(/[^0-9A-Za-z\-]/, '_')
        File.join(cache_path, safe_key)
      end
    end
  end
end
