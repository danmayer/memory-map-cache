#!/usr/bin/env bash
# exit on error
set -o errexit

echo "Compiling Native C-Extensions for memory-map-cache..."
cd ..
bundle install
bundle exec rake compile
cd demo

echo "Building Rails Environment..."
bundle install
bundle exec rake assets:precompile
bundle exec rake assets:clean
