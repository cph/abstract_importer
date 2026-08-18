# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "abstract_importer/version"

Gem::Specification.new do |spec|
  spec.name          = "abstract_importer"
  spec.version       = AbstractImporter::VERSION
  spec.authors       = ["Bob Lail"]
  spec.email         = ["bob.lail@cph.org"]
  spec.summary       = %q{Provides services for the mass-import of complex relational data}
  spec.homepage      = "https://github.com/cph/abstract_importer"
  spec.license       = "MIT"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_dependency "activerecord", ">= 7.0"
  spec.add_dependency "activesupport", ">= 7.0"
  spec.add_dependency "progressbar"
  spec.add_dependency "benchmark", ">= 0.4.0"
  spec.add_dependency "ostruct"

  spec.add_development_dependency "bundler"
  spec.add_development_dependency "minitest-reporters"
  spec.add_development_dependency "minitest-reporters-turn_reporter"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "sqlite3"
  spec.add_development_dependency "pg"
  spec.add_development_dependency "pry"
  spec.add_development_dependency "rr"
  spec.add_development_dependency "database_cleaner"
  spec.add_development_dependency "simplecov"
  spec.add_development_dependency "shoulda-context"
end
