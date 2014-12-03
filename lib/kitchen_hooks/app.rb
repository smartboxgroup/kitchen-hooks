require 'shellwords'
require 'json'

require 'git'
require 'sinatra/base'

require_relative 'helpers'
require_relative 'metadata'


module KitchenHooks
  class App < Sinatra::Application
    include KitchenHooks::Helpers

    def self.config! config ; @@config = config end
    def config ; @@config ||= {} end


    get '/' do
      content_type :text
      KitchenHooks::VERSION
    end


    post '/' do
      content_type :text
      request.body.rewind
      event = JSON::parse request.body.read

      repo_url      = event['repository']['url']
      event['name'] = File::basename repo_url, '.git'
      event['path'] = repo_url.split(':', 2).last
      event['url']  = 'git://git.bluejeansnet.com/%s' % event['path']

      perform_kitchen_upload event if commit_to_kitchen? event
      perform_realm_upload event if tagged_commit_to_realm? event
    end



  private
    def debug o
      $stderr.puts JSON::pretty_generate(o || {})
    end

    def perform_kitchen_upload event
      Dir.mktmpdir event['name'] do |dir|
        repo = Git.clone(event['url'], dir, log: $stdout)
        repo.checkout last_commit_for(event)

        Dir.chdir dir do
          puts 'Uploading data_bags'
          `knife upload data_bags --chef-repo-path . 2>&1`

          puts 'Uploading roles'
          `knife upload roles --chef-repo-path . 2>&1`

          puts 'Uploading environments'
          Dir['environments/*'].each do |e|
            upload_environment e
          end
        end
      end
    end

    def perform_realm_upload event
      Dir.mktmpdir event['name'] do |dir|
        repo = Git.clone(event['url'], dir, log: $stdout)
        repo.checkout tag_for(event)

        Dir.chdir dir do
          puts 'Uploading realm'
          `berks upload`
        end
      end
    end

    def last_commit_for event
      event['commits'].last['id']
    end

    def tag_for event
      event['ref'] =~ %r{/tags/(.*)$}
      return $1
    end

    def commit_to_kitchen? event
      event['after'] != '0000000000000000000000000000000000000000' &&
      event['repository']['name'] == 'kitchen'
    end

    def tagged_commit_to_realm? event
      event['after'] != '0000000000000000000000000000000000000000' &&
      event['repository']['name'] =~ /^realm_/ && \
      event['ref'] =~ %r{/tags/}
    end
  end
end