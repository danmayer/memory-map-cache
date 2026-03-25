# frozen_string_literal: true

require "active_support"
begin
  # In a standard gem installation, rubygems places the compiled binary
  # safely nested in the namespace to prevent circular requires.
  require "memory_map_cache/memory_map_cache"
rescue LoadError
  # Local `rake compile` fallback drops it into the root `lib/` directory
  if RUBY_PLATFORM.include?('darwin')
    require_relative "memory_map_cache.bundle"
  else
    require_relative "memory_map_cache.so"
  end
end
require "active_support/cache/memory_map_cache_store"
require "active_support/cache/layered_store"
