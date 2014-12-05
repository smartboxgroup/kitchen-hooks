require 'pathname'
require 'thread'
require 'json'

require 'daybreak'
require 'sinatra/base'

require_relative 'helpers'
require_relative 'metadata'


module KitchenHooks
  class App < Sinatra::Application
    set :root, File.join(KitchenHooks::ROOT, 'web')

    enable :sessions

    include KitchenHooks::Helpers

    def self.db! path
      @@db = Daybreak::DB.new path
    end

    def self.config! config
      @@knives = config['servers'].map do |s|
        Pathname.new(s['knife']).expand_path.realpath.to_s
      end
    end


    get '/' do
      db_entries = {}
      db.each do |k, v|
        db_entries[k] = v
      end
      erb :app, locals: {
        database: db_entries.sort_by { |stamp, _| stamp }
      }
    end

    get '/favicon.ico' do
      send_file File.join(settings.root, 'favicon.ico'), \
        :disposition => 'inline'
    end

    get %r|/app/(.*)| do |fn|
      send_file File.join(settings.root, 'app', fn), \
        :disposition => 'inline'
    end

    post '/' do
      request.body.rewind
      event = JSON::parse request.body.read
      Thread.new do
        process event
      end
    end


  private
    def knives ; @@knives ||= [] end

    def db ; @@db end

    def mark event, type
      db.synchronize do
        db[Time.now.to_f] = {
          type: type,
          event: event
        }
      end
    end

    def process event
      if commit_to_kitchen?(event)
        perform_kitchen_upload(event, knives)
        mark event, 'kitchen upload'
      end

      if tagged_commit_to_cookbook?(event) &&
         tag_name(event) =~ /^v\d+/ # Tagged with version we're releasing
        perform_cookbook_upload(event, knives)
        mark event, 'cookbok upload'
      end

      if tagged_commit_to_realm?(event) &&
         tag_name(event) =~ /^bjn_/ # Tagged with environment we're pinning
        perform_constraint_application(event, knives)
        mark event, 'constraint application'
      end

      db.flush
    end
  end
end