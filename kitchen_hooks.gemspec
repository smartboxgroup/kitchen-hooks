Gem::Specification.new do |s|
  s.name        = 'kitchen_hooks'
  s.version     = '0.1.0'
  s.licenses    = [ ]
  s.summary     = "Uploads chef cookbooks to chef server"
  s.description = "Uploads chef cookbooks to chef server. Responds to posts from gitlab webooks."
  s.authors     = ["Kelly Wong"]
  s.email       = 'netops@bluejeans.com'
  s.files       = Dir['lib/**/*.rb'] + Dir['bin/*']
  s.homepage    = 'http://git.bluejeansnet.com/kelly/kitchen-hooks'
  s.executables = ['kitchen_hooks']
  s.default_executable = 'kitchen_hooks'
  s.add_runtime_dependency 'sinatra', '~> 1.4'
  s.add_runtime_dependency 'mail', '~> 2.6'
  s.add_runtime_dependency 'git', '~> 1.2'
end
