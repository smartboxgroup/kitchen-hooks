require 'logger'

require 'thor'

require_relative 'app'
require_relative 'metadata'


module KitchenHooks
  class Main < Thor
    desc 'version', 'Show application version'
    def version
      puts VERSION
    end


    desc 'art', 'Show application art'
    def art
      w = ART.lines.map(&:length).sort.last
      w += 1 if w % 2 != 0
      puts
      puts 'kitchen_hooks'.center(w)
      puts VERSION.center(w)
      puts
      puts SUMMARY.center(w)
      puts "\n\n\n"
      puts ART
      puts "\n\n\n"
    end


    desc 'server', 'Start application web server'
    option :port, \
      type: :numeric,
      aliases: %w[ -p ],
      desc: 'Set Sinatra port',
      default: 4567
    option :environment, \
      type: :string,
      aliases: %w[ -e ],
      desc: 'Set Sinatra environment',
      default: 'development'
    option :bind, \
      type: :string,
      aliases: %w[ -b ],
      desc: 'Set Sinatra interface',
      default: '0.0.0.0'
    option :config, \
      type: :string,
      aliases: %w[ -c ],
      desc: 'Configuration file to use',
      default: '/etc/kitchen_hooks/config.json'
    option :database, \
      type: :string,
      aliases: %w[ -d ],
      desc: 'Location of application database',
      default: '/etc/kitchen_hooks/app.db'
    option :tmpdir, \
      type: :string,
      aliases: %w[ -t ],
      desc: 'Location of temporary directory',
      default: '/tmp'
    def server
      App.config! JSON::parse(File.read(options.config))
      App.backlog!
      App.db! options.database
      App.tmp! options.tmpdir
      App.sync!
      App.set :environment, options.environment
      App.set :port, options.port
      App.set :bind, options.bind
      App.set :raise_errors, true
      App.set :dump_errors, true
      App.set :show_exceptions, true
      App.set :logging, ::Logger::DEBUG
      App.run!

      at_exit do
        App.close!
      end
    end
  end
end