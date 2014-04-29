# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'zkexec/version'

Gem::Specification.new do |spec|
  spec.name          = "zkexec"
  spec.version       = ZkExec::VERSION
  spec.authors       = ["Kyle Maxwell"]
  spec.email         = ["kyle@kylemaxwell.com"]
  spec.summary       = %q{Run a process in a wrapper that manages config files from zookeeper}
  spec.description   = %q{Run a process in a wrapper that manages config files from zookeeper}
  spec.homepage      = ""
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_runtime_dependency "zk", "1.9.4"

  spec.add_development_dependency "bundler", "~> 1.5"
  spec.add_development_dependency "rake"
end
