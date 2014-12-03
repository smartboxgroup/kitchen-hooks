require 'rubygems'
require 'bundler'
require 'rake'


# "rake test"
require 'rake/testtask'
Rake::TestTask.new(:test) do |test|
  test.libs << 'lib' << 'test'
  test.test_files = FileList['test/test*.rb']
  test.verbose = true
end

task :default => :test


# "rake yard"
require 'yard'
YARD::Rake::YardocTask.new do |t|
  t.files = %w[ --readme Readme.md lib/**/*.rb - VERSION ]
end


# "rake build"
require 'rubygems/tasks'
Gem::Tasks.new({
  push: false,
  sign: {}
}) do |tasks|
  tasks.console.command = 'pry'
end
Gem::Tasks::Sign::Checksum.new sha2: true


# "rake version"
require 'rake/version_task'
Rake::VersionTask.new


# "rake fpm"
desc 'Convert all .GEMs to .DEBs with FPM'
task fpm: :build do
  system '[ -d pkg ] && fpm -s gem -t deb pkg/*.gem'
end