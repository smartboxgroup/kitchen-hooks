require 'securerandom'
require 'shellwords'
require 'fileutils'
require 'tempfile'
require 'json'

require 'git'
require 'ridley'
require 'berkshelf'


Celluloid.logger = nil
Berkshelf.logger = Logger.new $stdout

module KitchenHooks
  module Helpers

    def report_error e, msg=nil
      msg = e.message if msg.nil?
      logger.error msg
      logger.error e.message
      logger.error e.backtrace.inspect
      msg
    end


    def perform_constraint_application event, knives
      logger.debug 'started perform_constraint_application event=%s, knives=%s' % [
        event['after'], knives.inspect
      ]

      tmp_clone event, :tagged_commit do |clone|
        Dir.chdir clone do

          logger.info 'Applying constraints'
          constraints = lockfile_constraints 'Berksfile.lock'
          environment = tag_name event
          knives.each do |k|
            apply_constraints constraints, environment, k
            verify_constraints constraints, environment, k
          end

        end
      end

      logger.debug "finished perform_constraint_application: #{event['after']}"
      return # no error
    end


    def perform_kitchen_upload event, knives
      return false unless commit_to_master?(event)
      logger.debug 'started perform_kitchen_upload event=%s, knives=%s' % [
        event['after'], knives.inspect
      ]

      tmp_clone event, :latest_commit do |clone|
        Dir.chdir clone do
          logger.info 'Uploading data_bags'
          with_each_knife_do 'upload data_bags --chef-repo-path .', knives

          logger.info 'Uploading roles'
          with_each_knife_do 'upload roles --chef-repo-path .', knives

          logger.info 'Uploading environments'
          Dir['environments/*'].each do |e|
            knives.each do |k|
              upload_environment e, k
            end
          end
        end
      end

      logger.debug "finished perform_kitchen_upload: #{event['after']}"
      return # no error
    end


    def perform_cookbook_upload event, knives
      logger.debug 'started perform_cookbook_upload event=%s, knives=%s' % [
        event['after'], knives.inspect
      ]

      tmp_clone event, :tagged_commit do |clone|
        Dir.chdir clone do
          tagged_version = tag_name(event).delete('v')
          cookbook_version = File.read('VERSION').strip
          unless tagged_version == cookbook_version
            raise 'Tagged version does not match cookbook version'
          end

          logger.info 'Uploading cookbook'
          with_each_knife_do "cookbook upload #{cookbook_name event} -o .. --freeze", knives
        end

        berksfile = File::join clone, 'Berksfile'
        berksfile_lock = berksfile + '.lock'

        if File::exist? berksfile_lock
          logger.info 'Uploading dependencies'
          berks_install berksfile
          knives.each do |knife|
            berks_upload berksfile, knife
          end
        end
      end

      logger.debug "finished cookbook_upload: #{event['after']}"
      return # no error
    end


    def berkshelf_config knife
      ridley = Ridley::from_chef_config knife
      config = {
        chef: {
          node_name: ridley.client_name,
          client_key: ridley.client_key,
          chef_server_url: ridley.server_url
        },
        ssl: {
          verify: false
        }
      }
      config_path = File.join tmp, "#{SecureRandom.hex}-berkshelf.json"
      File.open(config_path, 'w') do |f|
        f.puts JSON::pretty_generate config
      end
      return config_path
    end


    def berks_install berksfile
      logger.debug 'started berks_install berksfile=%s' % berksfile.inspect
      env_git_dir = ENV.delete 'GIT_DIR'
      env_git_work_tree = ENV.delete 'GIT_WORK_TREE'

      cmd = "berks install --debug --berksfile %s" % [
        Shellwords::escape(berksfile)
      ]
      logger.debug "berks_install: %s" % cmd
      system cmd
      raise 'Could not perform berks_install with config %s' % [
        berksfile.inspect
      ] unless $?.exitstatus.zero?

      ENV['GIT_DIR'] = env_git_dir
      ENV['GIT_WORK_TREE'] = env_git_work_tree
      logger.debug 'finished berks_install: %s' % berksfile
    end


    def berks_upload berksfile, knife, options={}
      logger.debug 'started berks_upload berksfile=%s, knife=%s' % [
        berksfile.inspect, knife.inspect
      ]
      config_path = berkshelf_config(knife)

      cmd = "berks upload --debug --berksfile %s --config %s" % [
        Shellwords::escape(berksfile), Shellwords::escape(config_path)
      ]
      logger.debug "berks_upload: %s" % cmd
      system cmd
      raise 'Could not perform berks_upload with config %s, knife %s' % [
        berksfile.inspect, knife.inspect
      ] unless $?.exitstatus.zero?

      FileUtils.rm_rf config_path
      logger.debug 'finished berks_upload: %s' % berksfile
    end


    def tmp_clone event, commit_method, &block
      logger.debug 'starting tmp_clone event=%s, commit_method=%s' % [
        event['after'], commit_method.inspect
      ]

      root = File::join tmp, SecureRandom.hex
      dir = File::join root, Time.now.to_f.to_s, cookbook_name(event)
      FileUtils.mkdir_p dir

      repo = Git.clone git_daemon_style_url(event), dir, log: $stdout

      commit = self.send(commit_method, event)

      logger.debug 'creating tmp_clone dir=%s, commit=%s' % [
        dir.inspect, commit.inspect
      ]

      repo.checkout commit

      yield dir

      FileUtils.rm_rf root
      logger.debug 'finished tmp_clone'
    end


    def with_each_knife_do command, knives
      with_each_knife "knife #{command} --config %{knife}", knives
    end

    def with_each_knife command, knives
      knives.map do |k|
        cmd = command % { knife: Shellwords::escape(k) }
        logger.debug 'with_each_knife: %s' % cmd
        system cmd
        # No error handling here; do that on "berks upload"
      end
    end


    def get_environment environment, knife
      ridley = Ridley::from_chef_config knife
      ridley.environment.find environment
    end


    def verify_constraints constraints, environment, knife
      logger.debug 'started verify_constraints environment=%s, knife=%s' % [
        environment.inspect, knife.inspect
      ]
      chef_environment = get_environment environment, knife
      unless constraints == chef_environment.cookbook_versions
        raise 'Environment did not match constraints'
      end
      logger.debug 'finished verify_constraints: %s' % environment
    end


    def apply_constraints constraints, environment, knife
      # Ripped from Berkshelf::Cli::apply and Berkshelf::Lockfile::apply
      # https://github.com/berkshelf/berkshelf/blob/master/lib/berkshelf/cli.rb
      # https://github.com/berkshelf/berkshelf/blob/master/lib/berkshelf/lockfile.rb
      logger.debug 'started apply_constraints environment=%s, knife=%s' % [
        environment.inspect, knife.inspect
      ]
      chef_environment = get_environment environment, knife
      raise 'Could not find environment "%s"' % environment if chef_environment.nil?
      chef_environment.cookbook_versions = constraints
      chef_environment.save
      logger.debug 'finished apply_constraints: %s' % environment
    end


    def lockfile_constraints lockfile_path
      # Ripped from Berkshelf::Cli::apply and Berkshelf::Lockfile::apply
      # https://github.com/berkshelf/berkshelf/blob/master/lib/berkshelf/cli.rb
      # https://github.com/berkshelf/berkshelf/blob/master/lib/berkshelf/lockfile.rb
      lockfile = Berkshelf::Lockfile.from_file lockfile_path
      constraints = lockfile.graph.locks.inject({}) do |hash, (name, dependency)|
        hash[name] = "= #{dependency.locked_version.to_s}"
        hash
      end
      logger.debug 'constraints: %s -> %s' % [ lockfile_path, constraints ]
      return constraints
    end


    def upload_environment environment, knife
      logger.debug 'started upload_environment environment=%s, knife=%s' % [
        environment.inspect, knife.inspect
      ]
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
      logger.debug 'finished upload_environment: %s' % environment
    end


    def notification entry
      return entry[:error] if entry[:error]
      event = entry[:event]
      case entry[:type]
      when 'kitchen upload'
        %Q| <i>#{author(event)}</i> updated <a href="#{gitlab_url(event)}">the Kitchen</a> |
      when 'cookbook upload'
        %Q| <i>#{author(event)}</i> released <a href="#{gitlab_tag_url(event)}">#{tag_name(event)}</a> of <a href="#{gitlab_url(event)}">#{cookbook_name(event)}</a> |
      when 'constraint application'
        %Q| <i>#{author(event)}</i> constrained <a href="#{gitlab_tag_url(event)}">#{tag_name(event)}</a> with <a href="#{gitlab_url(event)}">#{cookbook_name(event)}</a> |
      when 'release'
        %Q| Kitchen Hooks <b>v#{event}</b> released! |
      end.strip
    end


    def generic_details event
      return if event.nil?
      %Q|
        <i>#{author(event)}</i> pushed #{push_details(event)}
      |.strip
    end


    def push_details event
      return if event.nil?
      %Q|
        <a href="#{gitlab_url(event)}">#{event['after']}</a> to <a href="#{repo_url(event)}">#{repo_name(event)}</a>
      |.strip
    end


    def author event
      event['user_name']
    end


    def repo_name event
      File::basename event['repository']['url'], '.git'
    end


    def cookbook_name event
      repo_name(event).sub /^(app|base|realm|fork)_/, 'bjn_'
    end


    def cookbook_repo? event
      repo_name(event) =~ /^(app|base|realm|fork)_/
    end


    def repo_url event
      git_daemon_style_url(event).sub(/^git/, 'http').sub(/\.git$/, '')
    end


    def git_daemon_style_url event
      event['repository']['url'].sub(':', '/').sub('@', '://')
    end


    def gitlab_url event
      url = git_daemon_style_url(event).sub(/^git/, 'http').sub(/\.git$/, '')
      "#{url}/commit/#{event['after']}"
    end


    def gitlab_tag_url event
      url = git_daemon_style_url(event).sub(/^git/, 'http').sub(/\.git$/, '')
      "#{url}/commits/#{tag_name(event)}"
    end


    def latest_commit event
      event['commits'].last['id']
    end


    def tagged_commit event
      event['ref'] =~ %r{/tags/(.*)$}
      return $1 # First regex capture
    end

    alias_method :tag_name, :tagged_commit


    def commit_to_master? event
      event['ref'] == 'refs/heads/master'
    end


    def not_deleted? event
      event['after'] != '0000000000000000000000000000000000000000'
    end


    def commit_to_kitchen? event
      repo_name(event) == 'kitchen' && not_deleted?(event)
    end


    def tagged_commit_to_cookbook? event
      cookbook_repo?(event) &&
      event['ref'] =~ %r{/tags/} &&
      not_deleted?(event)
    end


    def tagged_commit_to_realm? event
      tagged_commit_to_cookbook?(event) &&
      repo_name(event) =~ /^realm_/
    end
  end
end