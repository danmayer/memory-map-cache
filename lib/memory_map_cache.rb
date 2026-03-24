# frozen_string_literal: true

require "active_support"
require_relative "memory_map_cache.bundle" # Loads the native extension explicitly without recursion
require "active_support/cache/memory_map_cache_store"
require "active_support/cache/layered_store"
