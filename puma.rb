# allow PORT env

bind 'tcp://0.0.0.0:' + (ENV['PORT'] || "9292")

rackup 'config.ru'
