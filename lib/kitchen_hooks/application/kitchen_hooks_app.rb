require 'sinatra/base'
require 'json'
require 'git'
require 'mail'

module KitchenHooks
  class KitchenHooksApp < Sinatra::Base

    set :bind, '0.0.0.0'

    post '/hook' do
      request.body.rewind
      git_event =  JSON.parse request.body.read
      puts git_event
      match = /.*\/tags\/(.*)/.match(git_event['ref'])
      if match
        tag_name = match[1]
        puts tag_name
        results = upload_tag(git_event['repository']['name'], git_event['repository']['url'], tag_name)
        email_results(git_event, results)
      end
    end

    helpers do
      def email_results(git_event, results)
        Mail.defaults do
          delivery_method :smtp, {
                                   address: KitchenHooks::App.config['email']['server'],
                                   port: KitchenHooks::App.config['email']['port'],
                                   openssl_verify_mode: "none"
                                 }
        end
        result_body = ""
        results.each do |server, result|
          result_body << "\n#{server}\n#{result}"
        end
        Mail.deliver do
          from KitchenHooks::App.config['email']['user']
          to KitchenHooks::App.config['email']['recipient']
          subject "Chef: Uploading #{git_event['repository']['name']} #{git_event['ref']}"
          body result_body
        end
      end
  
  
      def upload_tag(name, url, tag_name)
        results = nil
        Dir.mktmpdir("cookbook_#{tag_name}") do |dir|
          puts "Tempdir at #{dir}"
          repo = Git.clone(url, "#{dir}/#{convert_name(name)}", :log => Logger.new(STDOUT))
          puts repo.log
          puts repo.dir
          repo.checkout(tag_name)
          results = do_chef_upload(convert_name(name), dir, KitchenHooks::App.config)
        end
        return results
      end
  
      def convert_name(name)
        name.gsub(/app/, 'bjn')
      end
  
      def do_chef_upload(name, dir)
        results = {}
        KitchenHooks::App.config['servers'].each do |server_config|
          knife_config = server_config['knife']
          IO.popen("knife cookbook upload #{name} -o #{dir} -c #{knife_config} --freeze", :err=>[:child, :out]) do |pipe|
            results[server_config['name']] = pipe.read
          end
        end
        return results
      end
    end
  end
end

