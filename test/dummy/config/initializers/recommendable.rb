require 'recommendable'
require 'redis'

Recommendable.configure do |config|
  config.redis_arr = [Redis.new(host: 'localhost', port: 6379, db: 15),Redis.new(host: 'localhost', port: 6379, db: 15)]
  config.user_class = User
end
