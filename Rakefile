require "bundler/gem_tasks"
require "rake/testtask"
require "rake/extensiontask"

Rake::TestTask.new(:test) do |t|
  t.libs << "lib" << "test"
  t.pattern = "test/**/*_test.rb"
end

gemspec = Gem::Specification.load("memory_map_cache.gemspec")
Rake::ExtensionTask.new("memory_map_cache", gemspec) do |ext|
  ext.ext_dir = "ext/memory_map_cache"
end

task default: %i[compile test]

desc "Run multiprocess benchmarks"
task benchmark: :compile do
  ruby "bench/bench_cache_multiprocess.rb"
end
