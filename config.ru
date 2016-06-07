require './server'

Thread.new { require './lunchbot' }

run Sinatra::Application
