require File.expand_path('../config/boot',__FILE__)
require File.expand_path('../config/environment',__FILE__)
require 'rails/all'
Bundler.require(*Rails.groups(:assets => %w(development test)))

require 'recommendable'
require 'redis'


module Dummy
  class Application < Rails::Application
    config.encoding = "utf-8"
    config.filter_parameters += [:password]

    config.active_support.escape_html_entities_in_json = true
    config.active_record.whitelist_attributes = true if ::ActiveRecord::VERSION::MAJOR < 4

    config.assets.enabled = true

    config.assets.version = '1.0'
  end
end

Dummy::Application.configure do
  config.cache_classes = false
  config.eager_load = false

  config.consider_all_requests_local       = true
  config.action_controller.perform_caching = false

  config.action_mailer.raise_delivery_errors = false

  config.active_support.deprecation = :log
  config.action_dispatch.best_standards_support = :builtin

  if (::ActiveRecord::VERSION::MAJOR == 3) && (::ActiveRecord::VERSION::MINOR == 2)
    config.active_record.mass_assignment_sanitizer = :strict
  end

  config.active_record.auto_explain_threshold_in_seconds = 0.5

  config.assets.compress = false

  config.assets.debug = true
end


if ARGV.length < 1
  raise 'user_id needed'
else
  user_id = ARGV[0]
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

Recommendable::Helpers::Calculations.update_similarities_for(user_id)

similarity_set = Recommendable::Helpers::RedisKeyMapper.similarity_set_for(user_id)
Recommendable.redis.zunionstore similarity_set, ['1', similarity_set]

Recommendable::Helpers::Calculations.update_4_recommendations_for(user_id)

Recommendable.config.ratable_classes.each do |klass|
  recommended_4_set = Recommendable::Helpers::RedisKeyMapper.recommended_4_set_for(klass, user_id)
  Recommendable.redis.zunionstore recommended_4_set, ['1', recommended_4_set]
end
