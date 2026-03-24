require "mkmf"

# Relax the strict aborts because macOS sometimes hides these from mkmf
have_header("sys/mmap.h")
have_header("pthread.h")
have_header("fcntl.h")
have_header("zlib.h")
abort "missing zlib library" unless have_library("z", "crc32")

create_makefile("memory_map_cache/memory_map_cache")
