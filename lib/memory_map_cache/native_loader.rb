begin
  # Load the precompiled version of the library published natively via cibuildgem
  ruby_version = /(\d+\.\d+)/.match(RUBY_VERSION)[1]
  require "memory_map_cache/#{ruby_version}/memory_map_cache"
rescue LoadError
  begin
    # In a standard source-based gem installation, rubygems places the compiled binary
    # safely nested in the namespace to prevent circular requires.
    require "memory_map_cache/memory_map_cache"
  rescue LoadError
    # Local `rake compile` fallback drops it into the root `lib/` directory
    if RUBY_PLATFORM.include?('darwin')
      require_relative "../memory_map_cache.bundle"
    else
      require_relative "../memory_map_cache.so"
    end
  end
end
