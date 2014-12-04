require 'shellwords'
require 'json'

require 'git'
require 'ridley'
require 'berkshelf'


module KitchenHooks
  module Helpers
    def perform_constraint_application event, knives
      tag = tag_name event
      tmp_clone event, :tagged_commit do
        puts 'Applying constraints'
        constraints = lockfile_constraints 'Berksfile.lock'
        environment = tag_name event
        knives.each do |k|
          apply_constraints constraints, environment, k
        end
      end
    end

    def perform_kitchen_upload event, knives
      tmp_clone event, :latest_commit do
        puts 'Uploading data_bags'
        with_each_knife 'upload data_bags --chef-repo-path .', knives

        puts 'Uploading roles'
        with_each_knife 'upload roles --chef-repo-path .', knives

        puts 'Uploading environments'
        Dir['environments/*'].each do |e|
          knives.each do |k|
            upload_environment e, k
          end
        end
      end
    end

    def perform_cookbook_upload event, knives
      tmp_clone event, :tagged_commit do
        tagged_version = tag_name(event).delete('v')
        cookbook_version = File.read('VERSION').strip
        raise unless tagged_version == cookbook_version
        puts 'Uploading cookbook'
        with_each_knife "cookbook upload #{cookbook_name event} -o .. --freeze", knives
      end
    end

    def tmp_clone event, commit_method, &block
      Dir.mktmpdir do |tmp|
        dir = File::join tmp, cookbook_name(event)
        repo = Git.clone git_daemon_style_url(event), dir, log: $stdout
        repo.checkout self.send(commit_method, event)
        Dir.chdir dir do
          yield
        end
      end
    end

    def with_each_knife command, knives
      knives.map do |k|
        `knife #{command} --config #{Shellwords::escape k}`
      end
    end

    def apply_constraints constraints, environment, knife
      # Ripped from Berkshelf::Cli::apply and Berkshelf::Lockfile::apply
      # https://github.com/berkshelf/berkshelf/blob/master/lib/berkshelf/cli.rb
      # https://github.com/berkshelf/berkshelf/blob/master/lib/berkshelf/lockfile.rb
      Celluloid.logger = nil
      ridley = Ridley::from_chef_config knife
      chef_environment = ridley.environment.find(environment)
      raise if chef_environment.nil?
      chef_environment.cookbook_versions = constraints
      chef_environment.save
    end

    def lockfile_constraints lockfile_path
      # Ripped from Berkshelf::Cli::apply and Berkshelf::Lockfile::apply
      # https://github.com/berkshelf/berkshelf/blob/master/lib/berkshelf/cli.rb
      # https://github.com/berkshelf/berkshelf/blob/master/lib/berkshelf/lockfile.rb
      lockfile = Berkshelf::Lockfile.from_file lockfile_path
      lockfile.graph.locks.inject({}) do |hash, (name, dependency)|
        hash[name] = "= #{dependency.locked_version.to_s}"
        hash
      end
    end

    def upload_environment environment, knife
      # Load the local environment from a JSON file
      local_environment = JSON::parse File.read(environment)
      local_environment.delete 'chef_type'
      local_environment.delete 'json_class'
      local_environment.delete 'cookbook_versions'

      # Load existing environment object on Chef server
      Celluloid.logger = nil
      ridley = Ridley::from_chef_config knife
      chef_environment = ridley.environment.find(local_environment['name'])

      # Create environment object if it doesn't exist
      if chef_environment.nil?
        chef_environment = ridley.environment.create(local_environment)
      end

      # Merge the local environment into the existing object
      local_environment.each do |k, v|
        chef_environment.send "#{k}=".to_sym, v
      end

      # Make it so!
      chef_environment.save
    end

    def repo_name event
      File::basename event['repository']['url'], '.git'
    end

    def cookbook_name event
      repo_name(event).sub /^(app|base|realm|fork)_/, 'bjn_'
    end

    def git_daemon_style_url event
      event['repository']['url'].sub(':', '/').sub('@', '://')
    end

    def latest_commit event
      event['commits'].last['id']
    end

    def tagged_commit event
      event['ref'] =~ %r{/tags/(.*)$}
      return $1 # First regex capture
    end

    alias_method :tag_name, :tagged_commit

    def not_deleted? event
      event['after'] != '0000000000000000000000000000000000000000'
    end

    def commit_to_kitchen? event
      repo_name(event) == 'kitchen' && not_deleted?(event)
    end

    def tagged_commit_to_cookbook? event
      repo_name(event) =~ /^(app|base|realm|fork)_/ &&
      event['ref'] =~ %r{/tags/} &&
      not_deleted?(event)
    end

    def tagged_commit_to_realm? event
      tagged_commit_to_cookbook?(event) &&
      repo_name(event) =~ /^realm_/
    end
  end
end