#include <fcntl.h>
#include <pthread.h>
#include <ruby.h>
#include <ruby/io.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
#include <zlib.h>

// Forward declaring mmap since sys/mmap.h cannot be found
#ifndef MAP_SHARED
#define PROT_READ 0x01
#define PROT_WRITE 0x02
#define MAP_SHARED 0x0001
#define MAP_FAILED ((void *)-1)
extern void *mmap(void *, size_t, int, int, int, off_t);
extern int munmap(void *, size_t);
#endif

// Memory block arrangement:
// [ CACHE HEADER ] (sizeof cache_header_t)
// [ SLOT 0 ] (slot_size bytes)
// [ SLOT 1 ] ...

typedef struct {
  pthread_rwlock_t rwlock;
  uint32_t slot_size;
  uint32_t max_slots;
} cache_header_t;

#define METADATA_OFFSET (sizeof(cache_header_t))

// Struct wrapped by TypedData
typedef struct {
  int fd;
  char *mmap_ptr;
  pid_t mapped_pid;
  pthread_rwlock_t *rwlock;
  uint32_t slot_size;
  uint32_t max_slots;
} mmap_cache_t;

static void cache_free(void *ptr) {
  mmap_cache_t *mc = (mmap_cache_t *)ptr;
  if (mc) {
    if (mc->mmap_ptr != MAP_FAILED && mc->mmap_ptr != NULL) {
      munmap(mc->mmap_ptr, ((size_t)mc->slot_size * (size_t)mc->max_slots) + METADATA_OFFSET);
      mc->mmap_ptr = MAP_FAILED; // explicitly clear after free
    }
    if (mc->fd >= 0) {
      close(mc->fd);
      mc->fd = -1; // explicitly invalidate fd
    }
    xfree(mc);
  }
}

static size_t cache_memsize(const void *ptr) {
  return ptr ? sizeof(mmap_cache_t) : 0;
}

static const rb_data_type_t mmap_cache_type = {"MemoryMapCache",
                                               {
                                                   NULL,
                                                   cache_free,
                                                   cache_memsize,
                                               },
                                               0,
                                               0,
                                               RUBY_TYPED_FREE_IMMEDIATELY};

static VALUE mmap_cache_alloc(VALUE klass) {
  mmap_cache_t *mc = ALLOC(mmap_cache_t);
  memset(mc, 0, sizeof(mmap_cache_t)); // zero out before giving to ruby GC

  mc->fd = -1;
  mc->mmap_ptr = MAP_FAILED;
  mc->mapped_pid = 0;
  mc->rwlock = NULL;
  mc->slot_size = 0;
  mc->max_slots = 0;

  return TypedData_Wrap_Struct(klass, &mmap_cache_type, mc);
}

static void ensure_mmap(mmap_cache_t *mc) {
  pid_t current_pid = getpid();
  if (mc->mapped_pid != current_pid) {
    if (mc->mmap_ptr != MAP_FAILED && mc->mmap_ptr != NULL) {
      // Already mapped in a parent process, we should re-map for safety or it
      // inherits actually mmap inherits across forks automatically on most
      // POSIX, but we map MAP_SHARED so we just record the pid to know we
      // checked.
    } else {
      size_t file_size = (size_t)mc->slot_size * (size_t)mc->max_slots;
      mc->mmap_ptr = mmap(NULL, file_size + METADATA_OFFSET,
                          PROT_READ | PROT_WRITE, MAP_SHARED, mc->fd, 0);
      if (mc->mmap_ptr == MAP_FAILED) {
        rb_raise(rb_eRuntimeError, "Failed to mmap memory slice");
      }

      // The first sizeof(cache_header_t) bytes are dedicated to the
      // interprocess lock and configuration metadata.
      cache_header_t *header = (cache_header_t *)mc->mmap_ptr;
      mc->rwlock = &(header->rwlock);
    }
    mc->mapped_pid = current_pid;
  }
}

static VALUE mmap_cache_initialize(VALUE self, VALUE rb_path, VALUE rb_slot_size, VALUE rb_max_slots) {
  mmap_cache_t *mc;
  TypedData_Get_Struct(self, mmap_cache_t, &mmap_cache_type, mc);

  if (mc == NULL) {
    rb_raise(rb_eRuntimeError, "Failed to allocate memory map cache struct");
  }

  const char *path = StringValueCStr(rb_path);
  int is_new_file = 0;

  // Open or create the file
  mc->fd = open(path, O_RDWR | O_CREAT, 0666);
  if (mc->fd < 0) {
    rb_sys_fail("Failed to open cache file");
  }

  struct stat st;
  fstat(mc->fd, &st);

  uint32_t req_slot_size = (uint32_t)NUM2UINT(rb_slot_size);
  uint32_t req_max_slots = (uint32_t)NUM2UINT(rb_max_slots);

  if (st.st_size >= METADATA_OFFSET) {
    cache_header_t disk_header;
    pread(mc->fd, &disk_header, sizeof(disk_header), 0);
    mc->slot_size = disk_header.slot_size;
    mc->max_slots = disk_header.max_slots;
  } else {
    mc->slot_size = req_slot_size;
    mc->max_slots = req_max_slots;
  }

  size_t file_size = (size_t)mc->slot_size * (size_t)mc->max_slots;

  if (st.st_size < (file_size + METADATA_OFFSET)) {
    // Expand file to required size
    if (ftruncate(mc->fd, file_size + METADATA_OFFSET) != 0) {
      close(mc->fd);
      mc->fd = -1;
      rb_sys_fail("Failed to truncate cache file format");
    }
    is_new_file = 1;
  }

  ensure_mmap(mc);

  // We must re-init the mutex if the file is new.
  // Minitest `teardown` calls File.delete but doesn't clear the mmap properly
  // sometimes, leading to a race or garbage lock memory.
  if (is_new_file) {
    pthread_rwlockattr_t attr;
    pthread_rwlockattr_init(&attr);
    pthread_rwlockattr_setpshared(&attr, PTHREAD_PROCESS_SHARED);

    if (mc->rwlock != NULL) {
      memset(mc->rwlock, 0, sizeof(pthread_rwlock_t));
      int ret = pthread_rwlock_init(mc->rwlock, &attr);
      pthread_rwlockattr_destroy(&attr);

      if (ret != 0) {
        rb_raise(rb_eRuntimeError, "Failed to initialize rwlock");
      }
    }
    
    // Write dynamic configuration to the header for future processes.
    cache_header_t *disk_header = (cache_header_t *)mc->mmap_ptr;
    disk_header->slot_size = mc->slot_size;
    disk_header->max_slots = mc->max_slots;
  }

  return self;
}

static inline int find_slot(mmap_cache_t *mc, const char *key_str,
                            size_t key_len, int insert) {
  unsigned long crc = crc32(0L, Z_NULL, 0);
  crc = crc32(crc, (const Bytef *)key_str, key_len);

  int start_idx = crc % mc->max_slots;
  int idx = start_idx;

  char *base = mc->mmap_ptr + METADATA_OFFSET;

  while (1) {
    char *slot_ptr = base + (idx * mc->slot_size);
    uint16_t k_len = *(uint16_t *)slot_ptr;

    if (k_len == 0) {
      if (insert)
        return idx;
    } else {
      char *stored_key = slot_ptr + 12;
      if (k_len == key_len && memcmp(stored_key, key_str, key_len) == 0) {
        return idx;
      }
    }

    idx = (idx + 1) % mc->max_slots;
    if (idx == start_idx)
      return -1; // Full
  }
}

static VALUE mmap_cache_write(int argc, VALUE *argv, VALUE self) {
  VALUE key, payload, rb_expires_at;
  rb_scan_args(argc, argv, "21", &key, &payload, &rb_expires_at);

  mmap_cache_t *mc;
  TypedData_Get_Struct(self, mmap_cache_t, &mmap_cache_type, mc);
  ensure_mmap(mc);

  VALUE key_str = rb_funcall(key, rb_intern("to_s"), 0);
  const char *k_ptr = RSTRING_PTR(key_str);
  size_t k_len = RSTRING_LEN(key_str);

  const char *v_ptr = RSTRING_PTR(payload);
  size_t v_len = RSTRING_LEN(payload);

  uint64_t expires_at = 0;
  if (!NIL_P(rb_expires_at)) {
    expires_at = (uint64_t)NUM2ULL(rb_expires_at);
  }

  // 2 + 2 + 8 = 12 bytes header
  if (k_len + v_len + 12 > mc->slot_size) {
    return Qfalse; // Too large for slot
  }

  pthread_rwlock_wrlock(mc->rwlock);

  int slot = find_slot(mc, k_ptr, k_len, 1);
  if (slot >= 0) {
    char *slot_ptr = mc->mmap_ptr + METADATA_OFFSET + (slot * mc->slot_size);

    // Write layout: [key_len(2)] [val_len(2)] [expires_at(8)] [KEY] [VAL]
    *(uint16_t *)slot_ptr = (uint16_t)k_len;
    *(uint16_t *)(slot_ptr + 2) = (uint16_t)v_len;
    *(uint64_t *)(slot_ptr + 4) = expires_at;

    memcpy(slot_ptr + 12, k_ptr, k_len);
    memcpy(slot_ptr + 12 + k_len, v_ptr, v_len);

    pthread_rwlock_unlock(mc->rwlock);
    return Qtrue;
  }

  pthread_rwlock_unlock(mc->rwlock);
  return Qfalse; // Out of slots
}

static VALUE mmap_cache_cleanup(VALUE self) {
  mmap_cache_t *mc;
  TypedData_Get_Struct(self, mmap_cache_t, &mmap_cache_type, mc);
  ensure_mmap(mc);

  uint64_t now = (uint64_t)time(NULL);
  int cleaned = 0;

  pthread_rwlock_wrlock(mc->rwlock);

  char *base = mc->mmap_ptr + METADATA_OFFSET;
  for (uint32_t i = 0; i < mc->max_slots; i++) {
    char *slot_ptr = base + (i * mc->slot_size);
    uint16_t k_len = *(uint16_t *)slot_ptr;

    if (k_len > 0) {
      uint64_t expires_at = *(uint64_t *)(slot_ptr + 4);
      // If expires_at is correctly set and is perfectly eclipsed by current epoch time
      if (expires_at > 0 && expires_at <= now) {
        *(uint16_t *)slot_ptr = 0; // Tombstone / Empty
        cleaned++;
      }
    }
  }

  pthread_rwlock_unlock(mc->rwlock);
  return INT2NUM(cleaned);
}

static VALUE mmap_cache_read(VALUE self, VALUE key) {
  mmap_cache_t *mc;
  TypedData_Get_Struct(self, mmap_cache_t, &mmap_cache_type, mc);
  ensure_mmap(mc);

  VALUE key_str = rb_funcall(key, rb_intern("to_s"), 0);
  const char *k_ptr = RSTRING_PTR(key_str);
  size_t k_len = RSTRING_LEN(key_str);

  VALUE result = Qnil;

  pthread_rwlock_rdlock(mc->rwlock);

  int slot = find_slot(mc, k_ptr, k_len, 0);
  if (slot >= 0) {
    char *slot_ptr = mc->mmap_ptr + METADATA_OFFSET + (slot * mc->slot_size);
    uint16_t v_len = *(uint16_t *)(slot_ptr + 2);

    if (v_len > 0) {
      char *v_ptr = slot_ptr + 12 + k_len;
      result = rb_str_new(v_ptr, v_len);
    }
  }

  pthread_rwlock_unlock(mc->rwlock);
  return result;
}

static VALUE mmap_cache_delete(VALUE self, VALUE key) {
  mmap_cache_t *mc;
  TypedData_Get_Struct(self, mmap_cache_t, &mmap_cache_type, mc);
  ensure_mmap(mc);

  VALUE key_str = rb_funcall(key, rb_intern("to_s"), 0);
  const char *k_ptr = RSTRING_PTR(key_str);
  size_t k_len = RSTRING_LEN(key_str);

  pthread_rwlock_wrlock(mc->rwlock);

  int slot = find_slot(mc, k_ptr, k_len, 0);
  VALUE result = Qfalse;
  if (slot >= 0) {
    char *slot_ptr = mc->mmap_ptr + METADATA_OFFSET + (slot * mc->slot_size);
    *(uint16_t *)slot_ptr = 0; // Tombstone / Empty
    result = Qtrue;
  }

  pthread_rwlock_unlock(mc->rwlock);
  return result;
}

static int write_multi_iter(VALUE key, VALUE val, VALUE data) {
  mmap_cache_t *mc = (mmap_cache_t *)data;

  VALUE key_str = rb_funcall(key, rb_intern("to_s"), 0);
  const char *k_ptr = RSTRING_PTR(key_str);
  size_t k_len = RSTRING_LEN(key_str);

  const char *v_ptr = RSTRING_PTR(val);
  size_t v_len = RSTRING_LEN(val);

  if (k_len + v_len + 12 > mc->slot_size) {
    return ST_CONTINUE;
  }

  int slot = find_slot(mc, k_ptr, k_len, 1);
  if (slot >= 0) {
    char *slot_ptr = mc->mmap_ptr + METADATA_OFFSET + (slot * mc->slot_size);
    *(uint16_t *)slot_ptr = (uint16_t)k_len;
    *(uint16_t *)(slot_ptr + 2) = (uint16_t)v_len;
    *(uint64_t *)(slot_ptr + 4) = 0; // Default no expiration on raw multi 
    memcpy(slot_ptr + 12, k_ptr, k_len);
    memcpy(slot_ptr + 12 + k_len, v_ptr, v_len);
  }
  return ST_CONTINUE;
}

static VALUE mmap_cache_write_multi(VALUE self, VALUE rb_hash) {
  mmap_cache_t *mc;
  TypedData_Get_Struct(self, mmap_cache_t, &mmap_cache_type, mc);
  ensure_mmap(mc);
  Check_Type(rb_hash, T_HASH);

  pthread_rwlock_wrlock(mc->rwlock);
  rb_hash_foreach(rb_hash, write_multi_iter, (VALUE)mc);
  pthread_rwlock_unlock(mc->rwlock);

  return Qtrue;
}

static VALUE mmap_cache_read_multi(VALUE self, VALUE rb_keys) {
  mmap_cache_t *mc;
  TypedData_Get_Struct(self, mmap_cache_t, &mmap_cache_type, mc);
  ensure_mmap(mc);
  Check_Type(rb_keys, T_ARRAY);

  VALUE result_hash = rb_hash_new();
  long len = RARRAY_LEN(rb_keys);

  pthread_rwlock_rdlock(mc->rwlock);
  for (long i = 0; i < len; i++) {
    VALUE key = rb_ary_entry(rb_keys, i);
    VALUE key_str = rb_funcall(key, rb_intern("to_s"), 0);
    const char *k_ptr = RSTRING_PTR(key_str);
    size_t k_len = RSTRING_LEN(key_str);

    int slot = find_slot(mc, k_ptr, k_len, 0);
    if (slot >= 0) {
      char *slot_ptr = mc->mmap_ptr + METADATA_OFFSET + (slot * mc->slot_size);
      uint16_t v_len = *(uint16_t *)(slot_ptr + 2);

      if (v_len > 0) {
        char *v_ptr = slot_ptr + 12 + k_len;
        VALUE val = rb_str_new(v_ptr, v_len);
        rb_hash_aset(result_hash, key_str, val);
      }
    }
  }
  pthread_rwlock_unlock(mc->rwlock);

  return result_hash;
}

static VALUE mmap_cache_delete_multi(VALUE self, VALUE rb_keys) {
  mmap_cache_t *mc;
  TypedData_Get_Struct(self, mmap_cache_t, &mmap_cache_type, mc);
  ensure_mmap(mc);
  Check_Type(rb_keys, T_ARRAY);

  long len = RARRAY_LEN(rb_keys);
  int deleted_count = 0;

  pthread_rwlock_wrlock(mc->rwlock);
  for (long i = 0; i < len; i++) {
    VALUE key = rb_ary_entry(rb_keys, i);
    VALUE key_str = rb_funcall(key, rb_intern("to_s"), 0);
    const char *k_ptr = RSTRING_PTR(key_str);
    size_t k_len = RSTRING_LEN(key_str);

    int slot = find_slot(mc, k_ptr, k_len, 0);
    if (slot >= 0) {
      char *slot_ptr = mc->mmap_ptr + METADATA_OFFSET + (slot * mc->slot_size);
      *(uint16_t *)slot_ptr = 0; // Tombstone / Empty
      deleted_count++;
    }
  }
  pthread_rwlock_unlock(mc->rwlock);

  return INT2NUM(deleted_count);
}

static VALUE mmap_cache_clear(VALUE self) {
  mmap_cache_t *mc;
  TypedData_Get_Struct(self, mmap_cache_t, &mmap_cache_type, mc);
  ensure_mmap(mc);

  if (mc->rwlock != NULL) {
    pthread_rwlock_wrlock(mc->rwlock);
  }
  // Zero out all slots (keeping rwlock intact)
  if (mc->mmap_ptr != MAP_FAILED && mc->mmap_ptr != NULL) {
    size_t file_size = (size_t)mc->slot_size * (size_t)mc->max_slots;
    memset(mc->mmap_ptr + METADATA_OFFSET, 0, file_size);
  }
  if (mc->rwlock != NULL) {
    pthread_rwlock_unlock(mc->rwlock);
  }

  return Qtrue;
}

static VALUE mmap_cache_close(VALUE self) {
  mmap_cache_t *mc;
  TypedData_Get_Struct(self, mmap_cache_t, &mmap_cache_type, mc);
  
  if (mc) {
    if (mc->mmap_ptr != MAP_FAILED && mc->mmap_ptr != NULL) {
      munmap(mc->mmap_ptr, ((size_t)mc->slot_size * (size_t)mc->max_slots) + METADATA_OFFSET);
      mc->mmap_ptr = MAP_FAILED;
    }
    if (mc->fd >= 0) {
      close(mc->fd);
      mc->fd = -1;
    }
  }
  return Qtrue;
}

void Init_memory_map_cache(void) {
  VALUE mActiveSupport = rb_define_module("ActiveSupport");
  VALUE mCache = rb_define_module_under(mActiveSupport, "Cache");

  VALUE cMemoryMapCacheNative =
      rb_define_class_under(mCache, "MemoryMapCacheNative", rb_cObject);
  rb_define_alloc_func(cMemoryMapCacheNative, mmap_cache_alloc);

  rb_define_method(cMemoryMapCacheNative, "initialize", mmap_cache_initialize,
                   3);
  rb_define_method(cMemoryMapCacheNative, "write_raw", mmap_cache_write, -1);
  rb_define_method(cMemoryMapCacheNative, "read_raw", mmap_cache_read, 1);
  rb_define_method(cMemoryMapCacheNative, "delete_raw", mmap_cache_delete, 1);
  rb_define_method(cMemoryMapCacheNative, "write_multi_raw",
                   mmap_cache_write_multi, 1);
  rb_define_method(cMemoryMapCacheNative, "read_multi_raw",
                   mmap_cache_read_multi, 1);
  rb_define_method(cMemoryMapCacheNative, "delete_multi_raw",
                   mmap_cache_delete_multi, 1);
  rb_define_method(cMemoryMapCacheNative, "clear", mmap_cache_clear, 0);
  rb_define_method(cMemoryMapCacheNative, "cleanup", mmap_cache_cleanup, 0);
  rb_define_method(cMemoryMapCacheNative, "close", mmap_cache_close, 0);
}
