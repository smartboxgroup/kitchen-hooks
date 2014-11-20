require 'sinatra'
require 'json'

set :bind, '0.0.0.0'

post '/hook' do
  request.body.rewind
  git_event =  JSON.parse request.body.read
  puts git_event
end
