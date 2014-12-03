require 'json'

require 'git'
require 'mail'
require 'sinatra/base'

require_relative 'metadata'


module KitchenHooks
  class App < Sinatra::Application
    def self.config! config ; @@config = config end
    def config ; @@config ||= {} end


    get '/' do
      content_type :text
      KitchenHooks::VERSION
    end


    post '/' do
      content_type :text
      request.body.rewind
      event = JSON::parse request.body.read, symbolize_names: true

      if commit_to_kitchen? event
        perform_kitchen_upload event[:commits].last
      end

      if tagged_commit_to_cookbook? event
        perform_cookbook_upload event[:commits].last
      end
    end



  private
    def perform_kitchen_upload commit
      $stderr.puts JSON::pretty_generate(commit)
    end

    def perform_cookbook_upload commit
      $stderr.puts JSON::pretty_generate(commit)
    end

    def commit_to_kitchen? commit
      commit[:repository][:name] == 'kitchen'
    end

    def tagged_commit_to_cookbook? commit
      commit[:repository][:name] =~ /^(app|bjn|realm|base)_/ && \
      commit[:ref] =~ %r{/tags/}
    end
  end
end