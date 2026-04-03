Rails.application.config.to_prepare do
  ::DEMO_REDIS = ActiveSupport::Cache.lookup_store(:redis_cache_store, url: ENV.fetch("REDIS_URL", "redis://localhost:6379/1"))
  ::DEMO_MMAP = ActiveSupport::Cache.lookup_store(:memory_map_cache_store, "/tmp/demo_mmap.bin", compress: false, slot_size: 2048, max_slots: 10_000)
  ::DEMO_LAYERED = ActiveSupport::Cache::LayeredStore.new(::DEMO_MMAP, ::DEMO_REDIS, l1_expires_in: 5.minutes)
end
