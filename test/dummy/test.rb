user_id = 1317871
Recommendable::Helpers::Calculations.update_similarities_for(user_id)

similarity_set = Recommendable::Helpers::RedisKeyMapper.similarity_set_for(user_id)
Recommendable.redis.zunionstore similarity_set, ['1', similarity_set]

Recommendable::Helpers::Calculations.update_4_recommendations_for(user_id)

Recommendable.config.ratable_classes.each do |klass|
  recommended_4_set = Recommendable::Helpers::RedisKeyMapper.recommended_4_set_for(klass, user_id)
  Recommendable.redis.zunionstore recommended_4_set, ['1', recommended_4_set]
end
