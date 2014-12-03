# -*- encoding: utf-8 -*-
$:.push File.expand_path(File.join('..', 'lib'), __FILE__)
require 'kitchen_hooks'

Gem::Specification.new do |s|
  s.name        = 'kitchen_hooks'
  s.version     = KitchenHooks::VERSION
  s.platform    = Gem::Platform::RUBY
  s.author      = KitchenHooks::AUTHOR
  s.email       = KitchenHooks::EMAIL
  s.summary     = KitchenHooks::SUMMARY
  s.description = KitchenHooks::SUMMARY + '.'
  s.homepage    = KitchenHooks::HOMEPAGE
  s.license     = KitchenHooks::LICENSE

  s.add_runtime_dependency 'retryable', '~> 1'
  s.add_runtime_dependency 'berkshelf', '~> 3'
  s.add_runtime_dependency 'mime-types', '~> 1'
  s.add_runtime_dependency 'chef', '~> 11.16.4'
  s.add_runtime_dependency 'thor', '~> 0'
  s.add_runtime_dependency 'git', '~> 1.2'
  s.add_runtime_dependency 'sinatra', '~> 1.4'
  s.add_runtime_dependency 'ridley', '~> 4.1'

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- test/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map { |f| File::basename(f) }
  s.require_paths = %w[ lib ]
end