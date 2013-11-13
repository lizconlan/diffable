# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'diffable/version'

Gem::Specification.new do |spec|
  spec.name          = "diffable"
  spec.version       = Diffable::VERSION
  spec.authors       = ["Liz Conlan"]
  spec.email         = ["lizconlan@gmail.com"]
  spec.description   = %q{Facilitates Active::Record object diffing}
  spec.summary       = %q{Adds ability to compare 2 Active::Record objects; returns the differences as a hash}
  spec.homepage      = "https://github.com/lizconlan/diffable"
  spec.license       = "MIT"
  
  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]
  
  spec.add_dependency "activerecord", ">= 3.2"
  
  spec.add_development_dependency "bundler", "~> 1.3"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "rspec"
  spec.add_development_dependency "activerecord-nulldb-adapter"
end
