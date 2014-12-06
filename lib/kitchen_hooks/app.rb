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
      event = JSON::parse request.body.read rescue nil
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

    def notify entry
      hipchat notification(entry)
    end

    # error == nil   => success
    # error == false => nop
    # otherwise      => failure
    def mark event, type, error=nil
      return if error == false
      entry = { type: type, event: event }
      entry.merge!(error: error, type: 'failure') if error
      db.synchronize do
        db[Time.now.to_f] = entry
      end
      db.flush
      notify entry
    end

    def process event
      if event.nil? # JSON parse failed
        mark event, 'failure', 'Could not parse WebHook payload'        
        return
      end

      if commit_to_kitchen?(event)
        possible_error = perform_kitchen_upload(event, knives) \
          rescue 'Unable to perform kitchen upload'
        mark event, 'kitchen upload', possible_error
      end

      if tagged_commit_to_cookbook?(event) &&
         tag_name(event) =~ /^v\d+/ # Cookbooks tagged with a version
        possible_error = perform_cookbook_upload(event, knives) \
          rescue 'Unable to perform cookbook upload'
        mark event, 'cookbook upload', possible_error
      end

      if tagged_commit_to_realm?(event) &&
         tag_name(event) =~ /^bjn_/ # Realms tagged with an environment
        possible_error = perform_constraint_application(event, knives) \
          rescue 'Unable to apply constraints'
        mark event, 'constraint application', possible_error
      end
    end
  end
end