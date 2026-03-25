Gem::Specification.new do |spec|
  spec.name          = "memory_map_cache"
  spec.version       = "0.1.0"
  spec.authors       = ["Dan Mayer"]
  spec.email         = ["danmayer@gmail.com"]

  spec.summary       = "High-performance POSIX shared memory ActiveSupport cache store."
  spec.description   = "A blazing fast Rails/ActiveSupport cache store built on mmap(2) and robust pthread mutexes for concurrent interprocess caching without overhead."
  spec.homepage      = "https://github.com/danmayer/memory-map-cache"
  spec.license       = "MIT"

  spec.files = Dir["lib/**/*", "ext/**/*", "README.md", "LICENSE"]
  spec.require_paths = ["lib"]
  spec.extensions    = ["ext/memory_map_cache/extconf.rb"]

  spec.required_ruby_version = ">= 3.4.0"

  spec.add_dependency "activesupport", ">= 6.0"
  spec.add_dependency "concurrent-ruby"

  spec.add_development_dependency "bundler", "~> 2.0"
  spec.add_development_dependency "litestack"
  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rake-compiler"
  spec.add_development_dependency "rubocop", ">= 1.50"
  spec.add_development_dependency "rubocop-minitest"
  spec.add_development_dependency "rubocop-performance"
  spec.metadata['rubygems_mfa_required'] = 'true'
end
