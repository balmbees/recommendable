config = Recommendable.config
u = User.first
user_id = u.id

id=1221825
Recommendable::Helpers::Calculations.update_4_recommendations_for(id)
puts Recommendable.redis.eval(predict_for_lua_return('(liked_by_count > 0) and (((similarity_sum/liked_by_count) + (1.9208/liked_by_count) - 1.96 * math.sqrt((((similarity_sum/liked_by_count) * (1-(similarity_sum/liked_by_count)) + 0.9604)) / liked_by_count)) / (1+3.8416 / liked_by_count)) or 0'),
  [ recommended_4_set ],
  [ user_id, id,
    Recommendable.config.redis_namespace,
    Recommendable.config.user_class.to_s.tableize,
    klass.to_s.tableize ])

user_id=1221825
Recommendable::Helpers::Calculations.update_similarities_for(user_id)
similarity_total_for("recommendable:channels:1221825:liked_by", "recommendable:users:1221825:similarities")
