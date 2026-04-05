#!/usr/bin/env bash
# exit on error
set -o errexit

echo "Compiling Native C-Extensions manually for memory-map-cache..."
cd ../ext/memory_map_cache
ruby extconf.rb
make
cp memory_map_cache.so ../../lib/
cd ../../demo

echo "Building Rails Environment..."
bundle install
bundle exec rake assets:precompile
bundle exec rake assets:clean
