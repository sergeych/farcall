# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'farcall/version'

Gem::Specification.new do |spec|
  spec.name          = "farcall"
  spec.version       = Farcall::VERSION
  spec.authors       = ["sergeych"]
  spec.email         = ["real.sergeych@gmail.com"]
  spec.summary       = %q{Simple, elegant and cross-platofrm RPC protocol}
  spec.description   = <<-End
    Simple and effective cross-platform RPC protocol. Can work with any transport capable to
    pass structures (dictionaries, hashes, whatever you name it). Out of the box provides
    JSON and BOSS formats over streams and sockets.
    End
  spec.homepage      = "https://github.com/sergeych/farcall"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_dependency 'hashie'
  spec.add_development_dependency 'bundler', '>= 1.7'
  spec.add_development_dependency 'rake', '>= 10.0'
  spec.add_development_dependency 'rspec'
  spec.add_development_dependency 'em-websocket'
  spec.add_development_dependency 'websocket-client-simple'
  spec.add_development_dependency 'boss-protocol', '>= 1.4.3'
end
