Rails.application.config.to_prepare do
  redis_url = ENV.fetch("REDIS_URL", "redis://localhost:6379/1")
  redis_options = { url: redis_url }
  redis_options[:ssl_params] = { verify_mode: OpenSSL::SSL::VERIFY_NONE } if redis_url.start_with?("rediss://")
  redis_options[:error_handler] = -> (method:, returning:, exception:) do
    Rails.logger.error "RedisCacheStore Native Error dynamically caught: #{exception.class} - #{exception.message}"
  end
  ::DEMO_REDIS = ActiveSupport::Cache.lookup_store(:redis_cache_store, redis_options)
  ::DEMO_MMAP = ActiveSupport::Cache.lookup_store(:memory_map_cache_store, "/tmp/demo_mmap.bin", compress: false, slot_size: 2048, max_slots: 10_000)
  ::DEMO_LAYERED = ActiveSupport::Cache::LayeredStore.new(::DEMO_MMAP, ::DEMO_REDIS, l1_expires_in: 5.minutes)
end
