require 'pathname'
require 'thread'
require 'json'

require 'hipchat'
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
      @@hipchat = nil
      if config['hipchat']
        @@hipchat = HipChat::Client.new config['hipchat']['token']
        @@hipchat_nick = config['hipchat']['nick'] || raise('No HipChat "nick" provided')
        @@hipchat_room = config['hipchat']['room'] || raise('No HipChat "room" provided')
      end
      @@knives = config['knives'].map do |_, knife|
        Pathname.new(knife).expand_path.realpath.to_s
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

    def hipchat message, color='green', notify=false
      return if @@hipchat.nil?
      @@hipchat[@@hipchat_room].send @@hipchat_nick, message, \
        color: color, notify: notify, message_format: 'html'
    end

    def notify event, type
      hipchat notification(event, type)
    end

    def mark event, type
      db.synchronize do
        db[Time.now.to_f] = {
          type: type,
          event: event
        }
      end
      notify event, type
    end

    def process event
      if commit_to_kitchen?(event)
        perform_kitchen_upload(event, knives)
        mark event, 'kitchen upload'
      end

      if tagged_commit_to_cookbook?(event) &&
         tag_name(event) =~ /^v\d+/ # Tagged with version we're releasing
        perform_cookbook_upload(event, knives)
        mark event, 'cookbook upload'
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