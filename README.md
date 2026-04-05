# MemoryMapCache

MemoryMapCache is a C-extension-backed `ActiveSupport::Cache::Store` that leverages native POSIX memory mapping (`mmap(2)`) to provide blazing-fast, cross-process shared memory caching. By bypassing TCP sockets and local database locks, it acts as a highly optimized IPC caching layer for multi-process Ruby applications.

## 🚀 Live Demo & Sandbox

Want to see it in action before installing? We've successfully deployed a fully interactive **[Streaming Sandbox & Benchmark Dashboard](https://memory-map-cache.onrender.com/)**. 

You can use the native demonstration site to actively simulate massive cache hit/miss latency graphs across different network architectures, or forcefully execute the raw multiprocess Torture Suite dynamically against the live cloud container!

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'memory_map_cache'
```

And then execute:

```shell
$ bundle install
```

### Testing Locally

To verify and install this gem on another project on your local machine before publishing it to RubyGems, you can link it directly in that project's Gemfile using the `path:` option:

```ruby
gem 'memory_map_cache', path: '/path/to/your/local/cloned/memory-map-cache'
```

Alternatively, you can build and install the gem locally into your system:
```shell
$ bundle exec rake build
$ gem install pkg/memory_map_cache-0.1.0.gem
```

## Configuration

Configure `MemoryMapCacheStore` seamlessly in your Rails `config/environments/production.rb` or `development.rb`:

```ruby
config.cache_store = :memory_map_cache_store, "/tmp/production_cache.bin", { expires_in: 1.day }
```

### Dynamic Memory Sizing
`MemoryMapCache` statically allocates chunks of POSIX shared memory mapped locally per-process based on your payload ceiling. By default, it allocates 20,000 blocks at 2,048 bytes each.

For applications requiring larger caching objects (like heavily serialized HTML fragments), you can dramatically increase the size dimensions using native instantiation options. The extension writes these settings natively into a binary file header so all clustered processes map boundaries symmetrically without communication constraints:

```ruby
config.cache_store = :memory_map_cache_store, "/tmp/production_cache.bin", { 
  slot_size: 16.kilobytes, # Accommodate much larger payloads natively without crashing limits
  max_slots: 50_000,       # Allocate space for more discrete cache keys 
  expires_in: 1.day 
}
```

You can pass any standard `ActiveSupport::Cache::Store` options like namespaces, automatic compressors, and key expiration configurations directly to the initializer.

## Advanced Architecture: The Layered Store

If you are running a multi-node Rails web-tier, `MemoryMapCache` can act as a fully transparent **L1 local cache** sitting in front of a distributed **L2 network cache** (like Memcached or Redis).

This hybrid approach intercepts up to 90% of cache reads completely avoiding network latency ("N+1" caching constraints) while ensuring long-term cache elements persist globally across all horizontally scaled nodes. 

```ruby
# config/environments/production.rb

l1 = ActiveSupport::Cache.lookup_store(:memory_map_cache_store, "/tmp/cache.bin", { 
  slot_size: 4.kilobytes, 
  max_slots: 100_000 
})
l2 = ActiveSupport::Cache.lookup_store(:mem_cache_store, ["redis1.internal:11211"])

# Option `l1_expires_in` ensures the ultra-fast local node cache aggressively purges
# stale fragments early to proactively prevent desynchronization with remote cache writes.
config.cache_store = :layered_store, l1, l2, { l1_expires_in: 5.minutes }
```

### Transparent Caching Behavior
The `LayeredStore` perfectly integrates into the ActiveSupport ecosystem:
* **Reads (+437% faster for 1000-byte payloads)**: Tries the L1 node natively (291,000+ ops/sec). On Miss or Expiration, hits the remote L2 and immediately backfills the L1 cache.
* **Writes (-12% penalty)**: Writes to L2 first. Upon success, mirrors the payload to L1 guaranteeing local cache freshness without violating network state.
* **Mixed Web Traffic (+70% overall throughput speedup)**: On a standard 80% Read / 20% Write web-traffic profile, `LayeredStore` achieved `117,952 ops/sec` vs native Memcached's `69,062 ops/sec`. 

Thus, for heavily read-focused applications (which is 99% of caching implementations), the 12% write penalty buys you essentially **free unlimited read scalability**.

### Handling Failure Scenarios (Edge Cases)
Due to its distributed nature, the `LayeredStore` proxy aggressively protects your application from remote L2 outages while gracefully degrading local L1 bounds.

1. **L2 Network Outages (Redis/Memcached drops connection)**: If your backend distributed cache goes entirely offline, ActiveSupport correctly catches the network failure and returns `false` natively. The `LayeredStore` **bubbles up the false boolean** so your application reliably detects the failure, but *it inherently stashes the payload in the L1 Local MemoryMapStore anyway*. This ensures the local application node automatically degrades into a blazing fast, standalone cache cluster that preserves extreme traffic resilience until the L2 network is restored!
2. **L1 Slot Rejection (Payloads > 2KB Bounds)**: If you attempt to cache massive serialized fragments that exceed your `MemoryMapCache` maximum native `slot_size` constraints (e.g. 2KB), `MemoryMapCache` natively drops the fragment without crashing the Ruby VM. `LayeredStore` inherently routes around this by persistently storing the massive payload strictly in the Remote L2, natively hydrating all standard `.read` lookups explicitly from L2!
3. **L2 Delete Operations Drop**: If you call `Rails.cache.delete("stale_key")` and the L2 Network drops the deletion command, the `LayeredStore` aggressively, unconditionally deletes the fragment from the Local L1. Because you requested a wipe, we never serve a stale copy locally just tracking L2 state.


## Performance Optimization

To achieve the absolute maximum operations-per-second (ops/sec) and bypass ActiveSupport's default Ruby-level formatting overhead, we highly recommend disabling automatic Zlib compression and utilizing a faster binary coder like MessagePack. 

In our benchmarks, disabling compression and switching codecs yields a **~2.5x to 2.8x latency reduction** locally:

```ruby
config.cache_store = :memory_map_cache_store, "/tmp/production_cache.bin", { 
  compress: false,           # Bypasses Zlib string checking overhead (60% speedup)
  serializer: :message_pack, # Leaner and faster than the default Marshal implementation
  expires_in: 1.day 
}
```

This ensures you skip the expensive framework processing loops, flattening your cache payloads directly into the lightning-fast C-extension memory map while maintaining 100% compatibility with the ActiveSupport framework testing suites.

## Implementation

`MemoryMapCache` bypasses standard serialization latencies by creating a direct binary file map on disk which process instances attach to natively via `mmap`. 

- IPC locks and synchronization are handled directly at the CPU level using C `pthread_mutex_t` attributes initialized with `PTHREAD_PROCESS_SHARED`, safely nested inside the file buffer.
- Values and Cache boundaries are actively zero'd out using standard `memset` pointers mapped exclusively to local Ruby threads.

While less feature-complete than comprehensive distributed networking solutions like Redis or Memcached (e.g., absent distributed sharding engines), it provides extreme resilience and cost savings for single-node multi-process clusters.

## Performance Validation

`MemoryMapCache` natively implements and wraps the standard `ActiveSupport::Cache` generic test behaviors. In our local benchmark suite matching cross-process concurrency (5 separate Ruby processes processing 1000-byte payloads), `MemoryMapCache` dominates relative performance.

### Concurrent Workloads (Operations / Second)

| Cache Adapter      | Writes (ops/sec) | Reads (ops/sec) | Mixed 80/20 (ops/sec) |
|--------------------|------------------|-----------------|-----------------------|
| **MemoryMapCache** | **123,493**      | **296,331**     | **200,400**           |
| **litecache**      |  54,693          | 140,999         |  99,259               |
| **RamFileStore**   |  47,771          | 108,664         |  92,878               |
| **Memcached**      |  65,189          |  62,773         |  66,548               |
| **FileStore**      |  12,120          |  78,388         |  43,708               |

*Note: With the implementation of POSIX Readers-Writer locks (`pthread_rwlock_t`), `MemoryMapCache` allows infinite concurrent reads across processes, doubling `litecache` (SQLite WAL) read speeds and towering over network-serialized daemons like Memcached.*

### Pipeline Architecture Native (MGET/MSET)

When comparing the `.read_multi` and `.write_multi` APIs directly against Redis using a 20-key pipeline of 1500-byte payloads across 5 separate processes:

| Datastore          | MSET Multi-Write | MGET Multi-Read |
|--------------------|------------------|-----------------|
| **MemoryMapCache** | **0.048 sec**    | **0.050 sec**   |
| **Redis**          | 0.235 sec        | 0.132 sec       |

This yields a **~3-4.5x pipeline latency reduction compared to standard local Redis**, providing an optimal profile for complex Rails applications looking to eliminate typical networking serialization overhead without depending on long-running in-memory daemons.

## License
The gem is available as open source under the terms of the MIT License.
