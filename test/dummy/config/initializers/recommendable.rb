require 'recommendable'
require 'redis'

Recommendable.configure do |config|
  #config.redis_arr = [Redis.new(host: 'localhost', port: 6379, db: 15),Redis.new(host: 'localhost', port: 6379, db: 15)]
  #config.user_class = User

  ENV["RECOMMENDABLE_REDIS_URL"] ||= "redis://127.0.0.1:6379/"
  redis_urls = ENV["RECOMMENDABLE_REDIS_URL"].split(",")
  config.redis_arr = redis_urls.map do |redis_url|
    uri = URI.parse(redis_url)
    Redis.new host: uri.host, port: uri.port, password: uri.password, driver: :hiredis, connect_timeout: 1
  end

  # A prefix for all keys Recommendable uses.
  #
  # Default: recommendable
  config.redis_namespace = :recommendable

  # Whether or not to automatically enqueue users to have their recommendations
  # refreshed after they like/dislike an item.
  #
  # Default: true
  config.auto_enqueue = false

  # The number of nearest neighbors (k-NN) to check when updating
  # recommendations for a user. Set to `nil` if you want to check all
  # neighbors as opposed to a subset of the nearest ones. Set this to a lower
  # number to improve Redis memory usage.
  #
  # Default: nil
  config.nearest_neighbors = ENV["RECOMMENDABLE_NEAREST_NEIGHBORS"] || 10

  # Like kNN, but also uses some number of most dissimilar users when
  # updating recommendations for a user. Because, hey, disagreements are
  # just as important as agreements, right? If `nearest_neighbors` is set to
  # `nil`, this configuration is ignored. Set this to a lower number
  # to improve Redis memory usage.
  #
  # Default: nil
  config.furthest_neighbors = nil

  # The number of recommendations to store per user. Set this to a lower
  # number to improve Redis memory usage.
  #
  # Default: 100
  config.recommendations_to_store = ENV["RECOMMENDABLE_RECOMMENDATIONS_TO_STORE"] || 35

  # config.orm = :active_record
end
