require 'json'

require 'sinatra/base'

require_relative 'helpers'
require_relative 'metadata'


module KitchenHooks
  class App < Sinatra::Application
    include KitchenHooks::Helpers

    def self.config! config
      @@knives = config['servers'].map { |s| s['knife'] }
    end

    def knives ; @@knives ||= [] end


    get '/' do
      content_type :text
      KitchenHooks::VERSION
    end


    post '/' do
      request.body.rewind
      event = JSON::parse request.body.read

      if commit_to_kitchen? event
        perform_kitchen_upload event, knives
      end

      if tagged_commit_to_cookbook? event && \
         tag_name(event) =~ /^v\d+/ # Tagged with version we're releasing
        perform_cookbook_upload event, knives
      end

      if tagged_commit_to_realm? event && \
         tag_name(event) =~ /^bjn_/ # Tagged with environment we're pinning
        perform_constraint_application event, knives
      end
    end
  end
end