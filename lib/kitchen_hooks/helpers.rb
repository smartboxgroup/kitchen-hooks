require 'shellwords'
require 'fileutils'
require 'tempfile'
require 'json'

require 'git'
require 'ridley'
require 'berkshelf'


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
        event.inspect, knives.inspect
      ]
      tmp_clone event, :tagged_commit do |clone|
        Dir.chdir clone do
          logger.info 'Applying constraints'
          constraints = lockfile_constraints 'Berksfile.lock'
          environment = tag_name event
          knives.each do |k|
            apply_constraints constraints, environment, k
          end
        end
      end

      logger.debug "finished perform_constraint_application: #{event['after']}"
      return # no error
    end


    def perform_kitchen_upload event, knives
      return false unless commit_to_master?(event)
      logger.debug 'started perform_kitchen_upload event=%s, knives=%s' % [
        event.inspect, knives.inspect
      ]

      tmp_clone event, :latest_commit do |clone|
        Dir.chdir clone do
          logger.info 'Uploading data_bags'
          with_each_knife 'upload data_bags --chef-repo-path .', knives

          logger.info 'Uploading roles'
          with_each_knife 'upload roles --chef-repo-path .', knives

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
        event.inspect, knives.inspect
      ]

      tmp_clone event, :tagged_commit do |clone|
        Dir.chdir clone do
          tagged_version = tag_name(event).delete('v')
          cookbook_version = File.read('VERSION').strip
          unless tagged_version == cookbook_version
            raise 'Tagged version does not match cookbook version'
          end

          logger.info 'Uploading cookbook'
          with_each_knife "cookbook upload #{cookbook_name event} -o .. --freeze", knives
        end

        berksfile = File::join clone, 'Berksfile'
        berksfile_lock = berksfile + '.lock'

        if File::exist? berksfile_lock
          logger.info 'Uploading dependencies'
          knives.each do |knife|
            berks_upload berksfile, knife
          end
        end
      end

      logger.debug "finished cookbook_upload: #{event['after']}"
      return # no error
    end


    def berks_upload berksfile, knife, options={}
      logger.debug 'started berks_upload berksfile=%s, knife=%s' % [
        berksfile.inspect, knife.inspect
      ]
      ridley = Ridley::from_chef_config knife
      options.merge! \
        berksfile: berksfile,
        debug: true,
        freeze: true,
        validate: true,
        server_url: ridley.server_url,
        client_name: ridley.client_name,
        client_key: ridley.client_key
      berksfile = Berkshelf::Berksfile.from_options(options)
      berksfile.install
      berksfile.upload [], options
      logger.debug 'finished berks_upload: %s' % berksfile
    end


    def tmp_clone event, commit_method, &block
      logger.debug 'started tmp_clone event=%s, commit_method=%s' % [
        event.inspect, commit_method.inspect
      ]
      Dir.mktmpdir do |tmp|
        dir = File::join tmp, Time.now.to_f.to_s, cookbook_name(event)
        FileUtils.mkdir_p dir
        repo = Git.clone git_daemon_style_url(event), dir, log: $stdout
        commit = self.send(commit_method, event)
        repo.checkout commit
        yield dir
      end
      logger.debug 'finished tmp_clone'
    end


    def with_each_knife command, knives
      knives.map do |k|
        cmd = "knife #{command} --config #{Shellwords::escape k}"
        logger.debug 'with_each_knife: %s' % cmd
        `#{cmd}`
      end
    end


    def apply_constraints constraints, environment, knife
      # Ripped from Berkshelf::Cli::apply and Berkshelf::Lockfile::apply
      # https://github.com/berkshelf/berkshelf/blob/master/lib/berkshelf/cli.rb
      # https://github.com/berkshelf/berkshelf/blob/master/lib/berkshelf/lockfile.rb
      logger.debug 'started apply_constraints constraints=%s, environment=%s, knife=%s' % [
        constraints.inspect, environment.inspect, knife.inspect
      ]
      Celluloid.logger = nil
      ridley = Ridley::from_chef_config knife
      chef_environment = ridley.environment.find(environment)
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