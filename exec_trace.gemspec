# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name          = "exec_trace"
  spec.version       = "0.0.1"
  spec.authors       = ["Blake Williams"]
  spec.email         = ["blake@blakewilliams.me"]

  spec.summary       = "Trace your Ruby function's execution path"
  spec.description   = spec.summary
  spec.homepage      = "https://github.com/blakewilliams/exec_trace"
  spec.license       = "MIT"
  spec.required_ruby_version = Gem::Requirement.new(">= 2.4.0")

  spec.metadata["homepage_uri"] = spec.homepage

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{\A(?:test|spec|features)/}) }
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.extensions = ["ext/extconf.rb"]

  spec.add_dependency "rack", "~> 2"
  spec.add_development_dependency "rake-compiler", "~> 1.1"
end
