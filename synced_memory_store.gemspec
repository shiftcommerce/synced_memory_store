# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'synced_memory_store/version'

Gem::Specification.new do |spec|
  spec.name          = "synced_memory_store"
  spec.version       = SyncedMemoryStore::VERSION
  spec.authors       = ["Gary Taylor"]
  spec.email         = ["gary.taylor@hismessages.com"]

  spec.summary       = "A redis backed, synchronised memory store"
  spec.description   = "A redis backed, synchronised memory store"
  spec.homepage      = "https://github.com/garytaylor/synced_memory_store"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.14"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "rspec-wait", "~> 0.0"
  spec.add_dependency "redis", "~> 3.3"
  spec.add_dependency "activesupport", "~> 5"
  spec.add_dependency "redis-activesupport", " ~> 5.0"
end
