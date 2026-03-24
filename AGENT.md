# MemoryMapCache - Agent Guide

This document is to assist any AI Agent or developer working on `MemoryMapCache`.

## Project Overview
MemoryMapCache is a C-extension-backed `ActiveSupport::Cache::Store` that uses native POSIX `mmap(2)` for blazing-fast, cross-process shared memory caching. Bypassing TCP sockets and local DB locks, it serves as a highly optimized IPC caching layer for multi-process Ruby applications (e.g., Puma, Unicorn).

## Architecture & Structure
- `ext/memory_map_cache/`: The core C extension where the native memory map (mmap) integration and IPC locks using `pthread_mutex_t` are implemented.
- `lib/`: The Ruby wrapper that hooks into the Rails `ActiveSupport::Cache::Store` interface (specifically as `:memory_map_cache_store`).
- `test/`: Standard Minitest suite ensuring full compatibility with ActiveSupport cache behaviors and testing multiprocess isolation.
- `bench/`: Benchmarking scripts, specially `bench_cache_multiprocess.rb`, testing multiprocessing single / multi-read/write performance against Memcached, Redis, and other file stores.

## Key Developer Commands
`memory_map_cache` uses Standard Ruby + `rake-compiler` for its extension.

### Compilation
- Compile the C Extension: `bundle exec rake compile`

### Testing
- Run the Test Suite: `bundle exec rake test` (Note: calling `test` also compiles the extension automatically via the `default` rake task).

### Benchmarking
To measure operations/sec and latency against other cache stores:
- Run Multi-process Benchmark: `bundle exec ruby bench/bench_cache_multiprocess.rb`
  - _You can change concurrency by setting the `PROCESSES` env var (default is 5)._

## Development Guidelines
- **C Extension Tweaks**: Changes to code in `ext/` demand recompilation before test runs (`rake compile`). Ensure memory maps handle fragmentation and clear out disk artifacts gracefully.
- **Multiprocess Concurrency**: When optimizing, thoroughly test both raw speed and multi-process correctness, especially concerning mmap memory boundaries and mutex lock safety.
- **ActiveSupport Compatibility**: Ensure new features or optimizations remain 100% compliant with standard Rails cache behaviors (look at `test/behaviors.rb`).
- **Performance Targets**: The recommended "fast path" configuration is MessagePack serialization with automatic Zlib compression disabled. Ensure architectural changes and benchmarks maintain or improve this `ops/sec` profile.
