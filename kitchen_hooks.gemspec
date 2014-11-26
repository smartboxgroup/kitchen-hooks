Gem::Specification.new do |s|
  s.name        = 'kitchen_hooks'
  s.version     = '0.1.0'
  s.licenses    = ['MIT']
  s.summary     = "Uploads chef cookbooks to chef server"
  s.description = "Uploads chef cookbooks to chef server"
  s.authors     = ["Kelly Wong"]
  s.email       = 'netops@bluejeans.com'
  s.files       = Dir['lib/**/*.rb'] + Dir['bin/*']
  s.homepage    = 'http://git.bluejeansnet.com/kelly/kitchen-hooks'
  s.executables = ['kitchen_hooks']
  s.default_executable = 'kitchen_hooks'
end
