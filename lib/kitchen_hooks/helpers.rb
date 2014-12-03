require 'ridley'
require 'json'

module KitchenHooks
  module Helpers
    def upload_environment environment_file, knife_file=File::join(ENV['HOME'], '.chef', 'knife.rb')
      # Load the local environment from a JSON file
      local_environment = JSON::parse File.read(environment_file)
      local_environment.delete 'chef_type'
      local_environment.delete 'json_class'
      local_environment.delete 'cookbook_versions'

      # Load existing environment object on Chef server
      Celluloid.logger = nil
      ridley = Ridley.from_chef_config knife_file
      chef_environment = ridley.environment.find(local_environment['name'])

      # Create environment object if it doesn't exist
      if chef_environment.nil?
        chef_environment = ridley.environment.create(local_environment)
      end

      # Merge the local environment into the existing object
      local_environment.each do |k, v|
        chef_environment.send "#{k}=".to_sym, v
      end

      # Make it so!
      chef_environment.save
    end
  end
end