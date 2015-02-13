require 'securerandom'
require 'shellwords'
require 'fileutils'
require 'tempfile'
require 'json'

require 'git'
require 'ridley'
require 'berkshelf'
require 'sinatra/base'
require 'pmap'

require_relative 'helpers/sync_servers'

Celluloid.logger = nil
Berkshelf.logger = Logger.new $stdout



module KitchenHooks
  class App < Sinatra::Application

    def self.pluralize n, singular, plural=nil
      plural = "#{singular}s" if plural.nil?
      return "no #{plural}" if n.zero?
      return "1 #{singular}" if n == 1
      "#{n} #{plural}"
    end

    # http://stackoverflow.com/questions/4136248/how-to-generate-a-human-readable-time-range-using-ruby-on-rails
    def self.humanize_seconds secs
      [
        [ 60, :seconds ],
        [ 60, :minutes ],
        [ 24, :hours ],
        [ 1000, :days ]
      ].map { |count, name|
        if secs > 0
          secs, n = secs.divmod(count)
          "#{n.to_i} #{name}"
        end
      }.compact.reverse.join(' ')
    end

    def self.sync_servers knives
      SyncServers.new knives
    end


    def self.report_error e, msg=nil
      msg = e.message if msg.nil?
      $stdout.puts msg
      $stdout.puts e.message
      $stdout.puts e.backtrace.inspect
      msg
    end



    def self.perform_constraint_application event, knives
      $stdout.puts 'started perform_constraint_application event=%s, knives=%s' % [
        event['after'], knives.inspect
      ]

      tmp_clone event, :tagged_commit do |clone|
        Dir.chdir clone do

          $stdout.puts 'Applying constraints'
          constraints = lockfile_constraints 'Berksfile.lock'
          environment = tag_name event
          knives.peach do |k|
            apply_constraints constraints, environment, k
            verify_constraints constraints, environment, k
          end

        end
      end

      $stdout.puts "finished perform_constraint_application: #{event['after']}"
      return # no error
    end


    def self.perform_kitchen_upload event, knives
      return false unless commit_to_master?(event)
      $stdout.puts 'started perform_kitchen_upload event=%s, knives=%s' % [
        event['after'], knives.inspect
      ]

      tmp_clone event, :latest_commit do |clone|
        Dir.chdir clone do
          kitchen_upload knives
        end
      end

      $stdout.puts "finished perform_kitchen_upload: #{event['after']}"
      return # no error
    end


    def self.perform_cookbook_upload event, knives
      $stdout.puts 'started perform_cookbook_upload event=%s, knives=%s' % [
        event['after'], knives.inspect
      ]

      tmp_clone event, :tagged_commit do |clone|
        Dir.chdir clone do
          tagged_version = tag_name(event).delete('v')
          cookbook_version = File.read('VERSION').strip
          unless tagged_version == cookbook_version
            raise 'Tagged version does not match cookbook version'
          end

          $stdout.puts 'Uploading cookbook'
          with_each_knife_do "cookbook upload #{cookbook_name event} -o .. --freeze", knives

          $stdout.puts 'Uploading bundled roles, environments, and data bags'
          kitchen_upload knives
        end

        berksfile = File::join clone, 'Berksfile'
        berksfile_lock = berksfile + '.lock'

        if File::exist? berksfile_lock
          $stdout.puts 'Uploading dependencies'
          berks_install berksfile
          knives.peach do |knife|
            berks_upload berksfile, knife
          end
        end
      end

      $stdout.puts "finished cookbook_upload: #{event['after']}"
      return # no error
    end



    def self.kitchen_upload knives
      $stdout.puts 'Uploading data_bags'
      with_each_knife_do 'upload data_bags --chef-repo-path .', knives

      $stdout.puts 'Uploading roles'
      with_each_knife_do 'upload roles --chef-repo-path .', knives

      $stdout.puts 'Uploading environments'
      Dir['environments/*'].peach do |e|
        knives.peach do |k|
          upload_environment e, k
        end
      end
    end


    def self.berkshelf_config knife
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


    def self.berks_install berksfile
      $stdout.puts 'started berks_install berksfile=%s' % berksfile.inspect
      env_git_dir = ENV.delete 'GIT_DIR'
      env_git_work_tree = ENV.delete 'GIT_WORK_TREE'

      cmd = "berks install --debug --berksfile %s" % [
        Shellwords::escape(berksfile)
      ]
      $stdout.puts "berks_install: %s" % cmd
      system cmd
      raise 'Could not perform berks_install with config %s' % [
        berksfile.inspect
      ] unless $?.exitstatus.zero?

      ENV['GIT_DIR'] = env_git_dir
      ENV['GIT_WORK_TREE'] = env_git_work_tree
      $stdout.puts 'finished berks_install: %s' % berksfile
    end


    def self.berks_upload berksfile, knife, options={}
      $stdout.puts 'started berks_upload berksfile=%s, knife=%s' % [
        berksfile.inspect, knife.inspect
      ]
      config_path = berkshelf_config(knife)

      cmd = "berks upload --debug --berksfile %s --config %s" % [
        Shellwords::escape(berksfile), Shellwords::escape(config_path)
      ]
      $stdout.puts "berks_upload: %s" % cmd
      system cmd
      raise 'Could not perform berks_upload with config %s, knife %s' % [
        berksfile.inspect, knife.inspect
      ] unless $?.exitstatus.zero?

      FileUtils.rm_rf config_path
      $stdout.puts 'finished berks_upload: %s' % berksfile
    end


    def self.tmp_clone event, commit_method, &block
      $stdout.puts 'starting tmp_clone event=%s, commit_method=%s' % [
        event['after'], commit_method.inspect
      ]

      root = File::join tmp, SecureRandom.hex
      dir = File::join root, Time.now.to_f.to_s, cookbook_name(event)
      FileUtils.mkdir_p dir

      repo = Git.clone git_daemon_style_url(event), dir, log: $stdout

      commit = self.send(commit_method, event)

      $stdout.puts 'creating tmp_clone dir=%s, commit=%s' % [
        dir.inspect, commit.inspect
      ]

      repo.checkout commit

      yield dir

      FileUtils.rm_rf root
      $stdout.puts 'finished tmp_clone'
    end


    def self.with_each_knife_do command, knives
      with_each_knife "knife #{command} --config %{knife}", knives
    end

    def self.with_each_knife command, knives
      knives.pmap do |k|
        cmd = command % { knife: Shellwords::escape(k) }
        $stdout.puts 'with_each_knife: %s' % cmd
        system cmd
        # No error handling here; do that on "berks upload"
      end
    end


    def self.get_environment environment, knife
      ridley = Ridley::from_chef_config knife
      ridley.environment.find environment
    end


    def self.verify_constraints constraints, environment, knife
      $stdout.puts 'started verify_constraints environment=%s, knife=%s' % [
        environment.inspect, knife.inspect
      ]
      chef_environment = get_environment environment, knife
      unless constraints == chef_environment.cookbook_versions
        raise 'Environment did not match constraints'
      end
      $stdout.puts 'finished verify_constraints: %s' % environment
    end


    def self.apply_constraints constraints, environment, knife
      # Ripped from Berkshelf::Cli::apply and Berkshelf::Lockfile::apply
      # https://github.com/berkshelf/berkshelf/blob/master/lib/berkshelf/cli.rb
      # https://github.com/berkshelf/berkshelf/blob/master/lib/berkshelf/lockfile.rb
      $stdout.puts 'started apply_constraints environment=%s, knife=%s' % [
        environment.inspect, knife.inspect
      ]
      chef_environment = get_environment environment, knife
      raise 'Could not find environment "%s"' % environment if chef_environment.nil?
      chef_environment.cookbook_versions = constraints
      chef_environment.save
      $stdout.puts 'finished apply_constraints: %s' % environment
    end


    def self.lockfile_constraints lockfile_path
      # Ripped from Berkshelf::Cli::apply and Berkshelf::Lockfile::apply
      # https://github.com/berkshelf/berkshelf/blob/master/lib/berkshelf/cli.rb
      # https://github.com/berkshelf/berkshelf/blob/master/lib/berkshelf/lockfile.rb
      lockfile = Berkshelf::Lockfile.from_file lockfile_path
      constraints = lockfile.graph.locks.inject({}) do |hash, (name, dependency)|
        hash[name] = "= #{dependency.locked_version.to_s}"
        hash
      end
      $stdout.puts 'constraints: %s -> %s' % [ lockfile_path, constraints ]
      return constraints
    end


    def self.upload_environment environment, knife
      $stdout.puts 'started upload_environment environment=%s, knife=%s' % [
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
      $stdout.puts 'finished upload_environment: %s' % environment
    end


    def notification e ; App.notification e end

    def self.notification entry
      return entry[:error] if entry[:error]
      event = entry[:event]

      case entry[:type]
      when 'synced', 'unsynced'
        if event.is_a? String
          event
        else
          'Synced <b>%d</b> of <b>%d</b> nodes (%s, %s elapsed)' % [
            event[:num_successes],
            event[:num_nodes],
            pluralize(event[:num_failures], 'failure'),
            humanize_seconds(event[:elapsed])
          ]
        end
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


    def generic_details e ; App.generic_details e end

    def self.generic_details event
      return if event.nil?
      %Q|
        <i>#{author(event)}</i> pushed #{push_details(event)}
      |.strip
    end


    def push_details e ; App.push_details e end

    def self.push_details event
      return if event.nil?
      %Q|
        <a href="#{gitlab_url(event)}">#{event['after']}</a> to <a href="#{repo_url(event)}">#{repo_name(event)}</a>
      |.strip
    end


    def self.author event
      event['user_name']
    end


    def self.repo_name event
      File::basename event['repository']['url'], '.git'
    end


    def self.cookbook_name event
      repo_name(event).sub /^(app|base|realm|fork)_/, 'bjn_'
    end


    def self.cookbook_repo? event
      repo_name(event) =~ /^(app|base|realm|fork)_/
    end


    def self.repo_url event
      git_daemon_style_url(event).sub(/^git/, 'http').sub(/\.git$/, '')
    end


    def self.git_daemon_style_url event
      event['repository']['url'].sub(':', '/').sub('@', '://')
    end


    def self.gitlab_url event
      url = git_daemon_style_url(event).sub(/^git/, 'http').sub(/\.git$/, '')
      "#{url}/commit/#{event['after']}"
    end


    def self.gitlab_tag_url event
      url = git_daemon_style_url(event).sub(/^git/, 'http').sub(/\.git$/, '')
      "#{url}/commits/#{tag_name(event)}"
    end


    def self.latest_commit event
      event['commits'].last['id']
    end


    def self.tagged_commit event
      event['ref'] =~ %r{/tags/(.*)$}
      return $1 # First regex capture
    end


    def self.tag_name event
      tagged_commit event
    end


    def self.commit_to_master? event
      event['ref'] == 'refs/heads/master'
    end


    def self.not_deleted? event
      event['after'] != '0000000000000000000000000000000000000000'
    end


    def self.commit_to_kitchen? event
      repo_name(event) == 'kitchen' && not_deleted?(event)
    end


    def self.tagged_commit_to_cookbook? event
      cookbook_repo?(event) &&
      event['ref'] =~ %r{/tags/} &&
      not_deleted?(event)
    end


    def self.tagged_commit_to_realm? event
      tagged_commit_to_cookbook?(event) &&
      repo_name(event) =~ /^realm_/
    end
  end
end