require File.expand_path('../config/boot',__FILE__)
require File.expand_path('../config/environment',__FILE__)
require 'rails/all'
Bundler.require(*Rails.groups(:assets => %w(development test)))

require 'recommendable'
require 'redis'

if ARGV.length < 1
  raise 'user_id needed'
else
  user_ids = ARGV
end

Recommendable.configure do |config|
  ENV["RECOMMENDABLE_REDIS_URL"] ||= "redis://127.0.0.1:6379/"
  redis_urls = ENV["RECOMMENDABLE_REDIS_URL"].split(",")
  config.redis_arr = redis_urls.map do |redis_url|
    uri = URI.parse(redis_url)
    Redis.new host: uri.host, port: uri.port, password: uri.password, driver: :hiredis, connect_timeout: 1
  end

  config.redis_namespace = :recommendable
  config.auto_enqueue = false

  config.nearest_neighbors = ENV["RECOMMENDABLE_NEAREST_NEIGHBORS"] || 1000
  config.furthest_neighbors = nil
  config.recommendations_to_store = ENV["RECOMMENDABLE_RECOMMENDATIONS_TO_STORE"] || 100
end

config = Recommendable.config
user = User.first

ARGV.each do |user_id|
  Recommendable::Helpers::Calculations.update_similarities_for(user_id)

  similarity_set = Recommendable::Helpers::RedisKeyMapper.similarity_set_for(user_id)
  Recommendable.redis.zunionstore similarity_set, ['1', similarity_set]

  Recommendable::Helpers::Calculations.update_4_recommendations_for(user_id)

  Recommendable.config.ratable_classes.each do |klass|
    recommended_4_set = Recommendable::Helpers::RedisKeyMapper.recommended_4_set_for(klass, user_id)
    Recommendable.redis.zunionstore recommended_4_set, ['1', recommended_4_set]
  end
end
