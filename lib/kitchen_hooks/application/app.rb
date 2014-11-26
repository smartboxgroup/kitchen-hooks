
module KitchenHooks

  class App
    @@config = {}

    def self.config
      return @@config
    end

    def self.run(config_path)
      File.open(config_path) do |config_file|
        @@config = JSON.parse(config_file.read)
      end
      puts @@config
      KitchenHooksApp.run!
      puts "done!"
    end
  end


end

