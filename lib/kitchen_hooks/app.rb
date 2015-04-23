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

    def self.db! path=@@db_path
      if defined? @@db
        @@db.flush
        @@db.close
      end
      @@db_path = path
      @@db = Daybreak::DB.new path
    end

    def self.tmp! dir ; @@tmp = dir end

    def self.close!
      @@sync_worker.kill
      @@backlog_worker.kill
      @@db.flush
      @@db.close
    end

    def self.backlog!
      @@backlog = Queue.new
      @@backlog_worker = Thread.new do
        loop do
          event = @@backlog.shift
          App.process event
        end
      end
    end

    def self.sync!
      @@sync_worker = Thread.new do
        loop do
          process_sync
          sleep @@sync_interval
        end
      end
    end


    def self.config! config
      @@config = config
      @@hipchat = nil
      if config['hipchat']
        @@hipchat = HipChat::Client.new config['hipchat']['token']
        @@hipchat_nick = config['hipchat']['nick'] || raise('No HipChat "nick" provided')
        @@hipchat_room = config['hipchat']['room'] || raise('No HipChat "room" provided')
      end
      @@knives = config['knives'].map do |_, knife|
        Pathname.new(knife).expand_path.realpath.to_s
      end
      @@sync_interval = config.fetch 'sync_interval', 3600 # Hourly
    end

    get '/backlog' do
      content_type :json
      JSON.pretty_generate \
        backlog: @@backlog.inspect,
        length: @@backlog.length
    end

    get '/' do
      App.process_release
      db_entries = {}
      @@db.each do |k, v|
        db_entries[k] = v unless k =~ /^meta/
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
      @@backlog.push event
    end



  private
    def self.db ; @@db end

    def self.tmp ; @@tmp ||= '/tmp' end

    def self.knives ; @@knives ||= [] end

    def self.hipchat message, color
      return if @@hipchat.nil?
      @@hipchat[@@hipchat_room].send @@hipchat_nick, message, \
        color: color, notify: false, message_format: 'html'
    end


    def self.notify entry
      color = case entry[:type]
      when 'failure' ; 'red'
      when 'release' ; 'purple'
      when 'unsynced' ; 'yellow'
      else ; 'green'
      end
      hipchat notification(entry), color
    end


    # error == nil   => success
    # error == true  => success
    # error == false => nop
    # otherwise      => failure
    def self.mark event, type, error=nil
      return if error == false
      error = nil if error == true
      entry = { type: type, event: event }
      entry.merge!(error: error, type: 'failure') if error
      db.lock do
        db[Time.now.to_f] = entry
      end
      db.flush
      notify entry
    end


    def self.process_release version=KitchenHooks::VERSION
      return if db['meta_version'] == version
      db.lock do
        db.set! 'meta_version', version
      end
      mark version, 'release'
    end


    def self.process_sync
      cached_nodes = db['meta_cached_nodes']
      cached_nodes ||= {}
      sync_servers = SyncServers.new knives, cached_nodes
      db.lock do
        db.set! 'meta_cached_nodes', sync_servers.cached_nodes
      end
      sync = sync_servers.status
      puts 'Sync completed'
      db!
      sync_tag = sync[:num_failures].zero? ? 'synced' : 'unsynced'
      mark sync, sync_tag
      db!
    end


    def self.process event
      if event.nil? # JSON parse failed
        mark event, 'failure', 'Could not parse WebHook payload'
        return
      end

      if commit_to_kitchen?(event)
        possible_error = begin
          perform_kitchen_upload event, knives
        rescue Exception => e
          report_error e, 'Could not perform kitchen upload: <i>%s</i>' % e.message.lines.first
        end
        mark event, 'kitchen upload', possible_error
      end

      if tagged_commit_to_cookbook?(event) &&
         tag_name(event) =~ /^v\d+/ # Cookbooks tagged with a version
        possible_error = begin
          perform_cookbook_upload event, knives
        rescue Exception => e
          report_error e, 'Could not perform cookbook upload: <i>%s</i>' % e.message.lines.first
        end
        mark event, 'cookbook upload', possible_error
      end

      if tagged_commit_to_realm?(event) &&
         tag_name(event) =~ /^bjn_/ # Realms tagged with an environment
        possible_error = begin
          perform_constraint_application event, knives
        rescue Exception => e
          report_error e, 'Could not apply constraints: <i>%s</i>' % e.message.lines.first
        end
        mark event, 'constraint application', possible_error
      end
    end
  end
end