module Recommendable
  module Helpers
    module Calculations
      class << self
        # Calculate a numeric similarity value that can fall between -1.0 and 1.0.
        # A value of 1.0 indicates that both users have rated the same items in
        # the same ways. A value of -1.0 indicates that both users have rated the
        # same items in opposite ways.
        #
        # @param [Fixnum, String] user_id the ID of the first user
        # @param [Fixnum, String] other_user_id the ID of another user
        # @return [Float] the numeric similarity between this user and the passed user
        # @note Similarity values are asymmetrical. `Calculations.similarity_between(user_id, other_user_id)` will not necessarily equal `Calculations.similarity_between(other_user_id, user_id)`
        def similarity_between_(user_id, other_user_id)
          user_id = user_id.to_s
          other_user_id = other_user_id.to_s

          similarity = liked_count = disliked_count = 0
          in_common = Recommendable.config.ratable_classes.each do |klass|
            liked_set = Recommendable::Helpers::RedisKeyMapper.liked_set_for(klass, user_id)
            other_liked_set = Recommendable::Helpers::RedisKeyMapper.liked_set_for(klass, other_user_id)
            disliked_set = Recommendable::Helpers::RedisKeyMapper.disliked_set_for(klass, user_id)
            other_disliked_set = Recommendable::Helpers::RedisKeyMapper.disliked_set_for(klass, other_user_id)

            temp0_set = Recommendable::Helpers::RedisKeyMapper.temp0_set_for(klass, user_id, other_user_id)
            temp1_set = Recommendable::Helpers::RedisKeyMapper.temp1_set_for(klass, user_id, other_user_id)
            temp2_set = Recommendable::Helpers::RedisKeyMapper.temp2_set_for(klass, user_id, other_user_id)
            temp3_set = Recommendable::Helpers::RedisKeyMapper.temp3_set_for(klass, user_id, other_user_id)

            results = Recommendable.redis.pipelined do
              # Agreements
              Recommendable.redis.sinterstore(temp0_set, liked_set, other_liked_set)
              Recommendable.redis.sinterstore(temp1_set, disliked_set, other_disliked_set)

              # Disagreements
              Recommendable.redis.sinterstore(temp2_set, liked_set, other_disliked_set)
              Recommendable.redis.sinterstore(temp3_set, disliked_set, other_liked_set)

              Recommendable.redis.scard(liked_set)
              Recommendable.redis.scard(disliked_set)

              Recommendable.redis.del(temp0_set)
              Recommendable.redis.del(temp1_set)
              Recommendable.redis.del(temp2_set)
              Recommendable.redis.del(temp3_set)
            end

            # Agreements
            similarity += results[0]
            similarity += results[1]

            # Disagreements
            similarity -= results[2]
            similarity -= results[3]

            liked_count += results[4]
            disliked_count += results[5]
          end

          similarity / (liked_count + disliked_count).to_f
        end

        # Used internally to update the similarity values between this user and all
        # other users. This is called by the background worker.
        def update_similarities_for_(user_id)
          user_id = user_id.to_s # For comparison. Redis returns all set members as strings.
          similarity_set = Recommendable::Helpers::RedisKeyMapper.similarity_set_for(user_id)

          # Only calculate similarities for users who have rated the items that
          # this user has rated
          relevant_user_ids = Recommendable.config.ratable_classes.inject([]) do |memo, klass|
            liked_set = Recommendable::Helpers::RedisKeyMapper.liked_set_for(klass, user_id)
            disliked_set = Recommendable::Helpers::RedisKeyMapper.disliked_set_for(klass, user_id)

            item_ids = Recommendable.redis.sunion(liked_set, disliked_set)

            unless item_ids.empty?
              sets = item_ids.map do |id|
                liked_by_set = Recommendable::Helpers::RedisKeyMapper.liked_by_set_for(klass, id)
                disliked_by_set = Recommendable::Helpers::RedisKeyMapper.disliked_by_set_for(klass, id)

                [liked_by_set, disliked_by_set]
              end

              memo | Recommendable.redis.sunion(*sets.flatten)
            else
              memo
            end
          end

          similarity_values = relevant_user_ids.map { |id| similarity_between_(user_id, id) }
          Recommendable.redis.pipelined do
            relevant_user_ids.zip(similarity_values).each do |id, similarity_value|
              next if id == user_id # Skip comparing with self.
              Recommendable.redis.zadd(similarity_set, similarity_value, id)
            end
          end

          if knn = Recommendable.config.nearest_neighbors
            length = Recommendable.redis.zcard(similarity_set)
            kfn = Recommendable.config.furthest_neighbors || 0

            Recommendable.redis.zremrangebyrank(similarity_set, kfn, length - knn - 1)
          end

          true
        end

        def similarity_between_lua_func
          <<-LUA
          local function similarity_between(klasses, user_id, other_user_id, similarity_set, redis_namespace, user_namespace)
            local similarity = 0
            local liked_count = 0
            local disliked_count = 0

            for i=1, #klasses do
              local klass = klasses[i]

              local liked_set          = table.concat({redis_namespace, user_namespace, user_id, 'liked_'..klass}, ':')
              local other_liked_set    = table.concat({redis_namespace, user_namespace, other_user_id, 'liked_'..klass}, ':')
              local disliked_set       = table.concat({redis_namespace, user_namespace, user_id, 'disliked_'..klass}, ':')
              local other_disliked_set = table.concat({redis_namespace, user_namespace, other_user_id, 'disliked_'..klass}, ':')

              local temp0_set = table.concat({redis_namespace, klass, user_id, other_user_id, 'temp0'}, ':')

              local similarity0 = redis.call('SINTERSTORE', temp0_set, liked_set, other_liked_set)
              local similarity1 = redis.call('SINTERSTORE', temp0_set, disliked_set, other_disliked_set)
              local similarity2 = redis.call('SINTERSTORE', temp0_set, liked_set, other_disliked_set)
              local similarity3 = redis.call('SINTERSTORE', temp0_set, disliked_set, other_liked_set)

              similarity = similarity + similarity0 + similarity1 - similarity2 - similarity3

              redis.call('DEL', temp0_set)

              liked_count = liked_count + redis.call('SCARD', liked_set)
              disliked_count = disliked_count + redis.call('SCARD', disliked_set)
            end

            return ((liked_count + disliked_count) > 0) and similarity / (liked_count + disliked_count) or 0.0
          end
          LUA
        end

        def similarity_between_lua
          <<-LUA
          #{similarity_between_lua_func}

          return tostring(similarity_between(ARGV, unpack(KEYS)))
          LUA
        end

        def similarity_between_multi_zadd_lua
          <<-LUA
          #{similarity_between_lua_func}

          local user_id = KEYS[1]
          local other_user_ids = redis.call('SMEMBERS', KEYS[2])
          local similarity_set = KEYS[3]

          for i=1, #other_user_ids do
            if user_id ~= other_user_ids[i] then
              local other_user_id = other_user_ids[i]
              redis.call('ZADD',
                similarity_set,
                similarity_between(ARGV, user_id, other_user_id, similarity_set, KEYS[4], KEYS[5]),
                other_user_id)
            end
          end
          LUA
        end

        def similarity_between(user_id, other_user_id)
          similarity_set  = Recommendable::Helpers::RedisKeyMapper.similarity_set_for(user_id)
          Recommendable.redis.eval(similarity_between_lua,
            [ user_id, other_user_id, similarity_set,
              Recommendable.config.redis_namespace,
              Recommendable.config.user_class.to_s.tableize ],
            Recommendable.config.ratable_classes.map { |klass| klass.to_s.tableize }).to_f
        end

        def update_similarities_for(user_id)
          user_id = user_id.to_s # For comparison. Redis returns all set members as strings.
          similarity_set = Recommendable::Helpers::RedisKeyMapper.similarity_set_for(user_id)

          # Only calculate similarities for users who have rated the items that
          # this user has rated
          temp_set = Recommendable::Helpers::RedisKeyMapper.temp_set_for(Recommendable.config.user_class, user_id)
          Recommendable.config.ratable_classes.each do |klass|
            liked_set = Recommendable::Helpers::RedisKeyMapper.liked_set_for(klass, user_id)
            disliked_set = Recommendable::Helpers::RedisKeyMapper.disliked_set_for(klass, user_id)
            temp_klass_set = Recommendable::Helpers::RedisKeyMapper.temp_set_for(klass, user_id)
            item_count = Recommendable.redis.sunionstore(temp_klass_set, liked_set, disliked_set)

            if item_count > 0
              Recommendable.redis.eval(sunion_sets_lua,
                                      [temp_set],
                                      [temp_klass_set, Recommendable.config.redis_namespace, klass.to_s.tableize])
            end
          end

          Recommendable.redis.pipelined do
            Recommendable.config.ratable_classes.each do |klass|
              Recommendable.redis.del Recommendable::Helpers::RedisKeyMapper.temp_set_for(klass, user_id)
            end
          end

          temp_sub_set = Recommendable::Helpers::RedisKeyMapper.temp_sub_set_for(Recommendable.config.user_class, user_id)
          similarity_set = Recommendable::Helpers::RedisKeyMapper.similarity_set_for(user_id)
          klasses = Recommendable.config.ratable_classes.map { |klass| klass.to_s.tableize }
          scan_slice(user_id, temp_set, temp_sub_set, count: 300) do
            Recommendable.redis.eval(similarity_between_multi_zadd_lua,
              [ user_id, temp_sub_set, similarity_set,
                Recommendable.config.redis_namespace,
                Recommendable.config.user_class.to_s.tableize ],
              klasses)
          end

          Recommendable.redis.del temp_set

          if knn = Recommendable.config.nearest_neighbors
            length = Recommendable.redis.zcard(similarity_set)
            kfn = Recommendable.config.furthest_neighbors || 0

            Recommendable.redis.zremrangebyrank(similarity_set, kfn, length - knn - 1)
          end

          true
        end

        def scan_slice(user_id, set, sub_set, options={})
          cursor = 0
          loop do
            cursor, keys = Recommendable.redis.sscan(set, cursor, options)
            unless keys.empty?
              Recommendable.redis.sadd(sub_set, keys)
              yield
              Recommendable.redis.del sub_set
            end
            break if cursor == '0'
          end
        end

        def sunion_sets_lua
          <<-LUA
          local item_ids = redis.call('SMEMBERS', ARGV[1])

          local sets = {}
          for i=1, #item_ids do
            table.insert(sets, table.concat({ARGV[2], ARGV[3], item_ids[i], 'liked_by'}, ':'))
            table.insert(sets, table.concat({ARGV[2], ARGV[3], item_ids[i], 'disliked_by'}, ':'))
          end

          redis.call('SUNIONSTORE', KEYS[1], KEYS[1], unpack(sets))
          LUA
        end

        # Used internally to update this user's prediction values across all
        # recommendable types. This is called by the background worker.
        #
        # @private
        def update_recommendations_for(user_id)
          user_id = user_id.to_s

          nearest_neighbors = Recommendable.config.nearest_neighbors || Recommendable.config.user_class.count
          Recommendable.config.ratable_classes.each do |klass|
            rated_sets = [
              Recommendable::Helpers::RedisKeyMapper.liked_set_for(klass, user_id),
              Recommendable::Helpers::RedisKeyMapper.disliked_set_for(klass, user_id),
              Recommendable::Helpers::RedisKeyMapper.hidden_set_for(klass, user_id),
              Recommendable::Helpers::RedisKeyMapper.bookmarked_set_for(klass, user_id)
            ]
            temp_set = Recommendable::Helpers::RedisKeyMapper.temp_set_for(Recommendable.config.user_class, user_id)
            similarity_set  = Recommendable::Helpers::RedisKeyMapper.similarity_set_for(user_id)
            recommended_set = Recommendable::Helpers::RedisKeyMapper.recommended_set_for(klass, user_id)
            most_similar_user_ids, least_similar_user_ids = Recommendable.redis.pipelined do
              Recommendable.redis.zrevrange(similarity_set, 0, nearest_neighbors - 1)
              Recommendable.redis.zrange(similarity_set, 0, nearest_neighbors - 1)
            end

            # Get likes from the most similar users
            sets_to_union = most_similar_user_ids.inject([]) do |sets, id|
              sets << Recommendable::Helpers::RedisKeyMapper.liked_set_for(klass, id)
            end

            # Get dislikes from the least similar users
            sets_to_union = least_similar_user_ids.inject(sets_to_union) do |sets, id|
              sets << Recommendable::Helpers::RedisKeyMapper.disliked_set_for(klass, id)
            end

            return if sets_to_union.empty?

            # SDIFF rated items so they aren't recommended
            Recommendable.redis.sunionstore(temp_set, *sets_to_union)
            item_ids = Recommendable.redis.sdiff(temp_set, *rated_sets)

            item_ids.each do |id|
              Recommendable.redis.eval(predict_for_lua('((liked_by_count + disliked_by_count) > 0) and similarity_sum / (liked_by_count + disliked_by_count) or 0'),
                [ temp_set, recommended_set ],
                [ user_id, id,
                  Recommendable.config.redis_namespace,
                  Recommendable.config.user_class.to_s.tableize,
                  klass.to_s.tableize ])
            end

            Recommendable.redis.del(temp_set)

            if number_recommendations = Recommendable.config.recommendations_to_store
              length = Recommendable.redis.zcard(recommended_set)
              Recommendable.redis.zremrangebyrank(recommended_set, 0, length - number_recommendations - 1)
            end
          end

          true
        end

        def predict_for_lua(predict_function)
          <<-LUA
          #{similarity_total_for_lua_func}

          local temp_set = KEYS[1]
          local recommended_set = KEYS[2]

          local user_id = ARGV[1]
          local item_id = ARGV[2]
          local redis_namespace = ARGV[3]
          local user_namespace = ARGV[4]
          local klass = ARGV[5]

          local liked_by_set = table.concat({redis_namespace, klass, item_id, 'liked_by'}, ':')
          local disliked_by_set = table.concat({redis_namespace, klass, item_id, 'disliked_by'}, ':')
          local similarity_set = table.concat({redis_namespace, user_namespace, user_id, 'similarities'}, ':')
          local similarity_sum = 0.0

          similarity_sum = similarity_sum + similarity_total_for(liked_by_set, similarity_set)
          similarity_sum = similarity_sum - similarity_total_for(disliked_by_set, similarity_set)

          local liked_by_count = redis.call('SCARD', liked_by_set)
          local disliked_by_count = redis.call('SCARD', disliked_by_set)

          local prediction = #{predict_function}

          redis.call('ZADD', recommended_set, prediction, item_id)
          return prediction
          LUA
        end

        def update_other_recommendations_for(user_id, total_user_count)
          user_id = user_id.to_s

          nearest_neighbors = Recommendable.config.nearest_neighbors || Recommendable.config.user_class.count
          Recommendable.config.ratable_classes.each do |klass|
            rated_sets = [
              Recommendable::Helpers::RedisKeyMapper.liked_set_for(klass, user_id)
            ]
            temp_set = Recommendable::Helpers::RedisKeyMapper.temp_set_for(Recommendable.config.user_class, user_id)
            similarity_set  = Recommendable::Helpers::RedisKeyMapper.similarity_set_for(user_id)
            recommended_2_set = Recommendable::Helpers::RedisKeyMapper.recommended_2_set_for(klass, user_id)
            recommended_3_set = Recommendable::Helpers::RedisKeyMapper.recommended_3_set_for(klass, user_id)
            recommended_4_set = Recommendable::Helpers::RedisKeyMapper.recommended_4_set_for(klass, user_id)
            most_similar_user_ids, least_similar_user_ids = Recommendable.redis.pipelined do
              Recommendable.redis.zrevrange(similarity_set, 0, nearest_neighbors - 1)
              Recommendable.redis.zrange(similarity_set, 0, nearest_neighbors - 1)
            end

            # Get likes from the most similar users
            sets_to_union = most_similar_user_ids.inject([]) do |sets, id|
              sets << Recommendable::Helpers::RedisKeyMapper.liked_set_for(klass, id)
            end

            # Get dislikes from the least similar users
            sets_to_union = least_similar_user_ids.inject(sets_to_union) do |sets, id|
              sets << Recommendable::Helpers::RedisKeyMapper.disliked_set_for(klass, id)
            end

            return if sets_to_union.empty?

            # SDIFF rated items so they aren't recommended
            Recommendable.redis.sunionstore(temp_set, *sets_to_union)
            item_ids = Recommendable.redis.sdiff(temp_set, *rated_sets)

            item_ids.each do |id|
              Recommendable.redis.eval(predict_for_lua('similarity_sum'),
                [ temp_set, recommended_2_set ],
                [ user_id, id,
                  Recommendable.config.redis_namespace,
                  Recommendable.config.user_class.to_s.tableize,
                  klass.to_s.tableize ])
              Recommendable.redis.eval(predict_for_lua("similarity_sum * (similarity_sum / #{nearest_neighbors} - liked_by_count / #{total_user_count})"),
                [ temp_set, recommended_3_set ],
                [ user_id, id,
                  Recommendable.config.redis_namespace,
                  Recommendable.config.user_class.to_s.tableize,
                  klass.to_s.tableize ])
            end

            Recommendable.redis.del(temp_set)

            if number_recommendations = Recommendable.config.recommendations_to_store
              length = Recommendable.redis.zcard(recommended_2_set)
              Recommendable.redis.zremrangebyrank(recommended_2_set, 0, length - number_recommendations - 1)
              length = Recommendable.redis.zcard(recommended_3_set)
              Recommendable.redis.zremrangebyrank(recommended_3_set, 0, length - number_recommendations - 1)
            end
          end

          true
        end

        def update_4_recommendations_for(user_id)
          user_id = user_id.to_s

          nearest_neighbors = Recommendable.config.nearest_neighbors || Recommendable.config.user_class.count
          Recommendable.config.ratable_classes.each do |klass|
            rated_sets = [
              Recommendable::Helpers::RedisKeyMapper.liked_set_for(klass, user_id)
            ]
            temp_set = Recommendable::Helpers::RedisKeyMapper.temp_set_for(Recommendable.config.user_class, user_id)
            similarity_set  = Recommendable::Helpers::RedisKeyMapper.similarity_set_for(user_id)
            recommended_4_set = Recommendable::Helpers::RedisKeyMapper.recommended_4_set_for(klass, user_id)
            most_similar_user_ids, least_similar_user_ids = Recommendable.redis.pipelined do
              Recommendable.redis.zrevrange(similarity_set, 0, nearest_neighbors - 1)
              Recommendable.redis.zrange(similarity_set, 0, nearest_neighbors - 1)
            end

            # Get likes from the most similar users
            sets_to_union = most_similar_user_ids.inject([]) do |sets, id|
              sets << Recommendable::Helpers::RedisKeyMapper.liked_set_for(klass, id)
            end

            # Get dislikes from the least similar users
            sets_to_union = least_similar_user_ids.inject(sets_to_union) do |sets, id|
              sets << Recommendable::Helpers::RedisKeyMapper.disliked_set_for(klass, id)
            end

            return if sets_to_union.empty?

            # SDIFF rated items so they aren't recommended
            Recommendable.redis.sunionstore(temp_set, *sets_to_union)
            item_ids = Recommendable.redis.sdiff(temp_set, *rated_sets)

            item_ids.each do |id|
              Recommendable.redis.eval(predict_for_lua('(liked_by_count > 0) and (((similarity_sum/liked_by_count) + (1.9208/liked_by_count) - 1.96 * math.sqrt((((similarity_sum/liked_by_count) * (1-(similarity_sum/liked_by_count)) + 0.9604)) / liked_by_count)) / (1+3.8416 / liked_by_count)) or 0'),
                [ temp_set, recommended_4_set ],
                [ user_id, id,
                  Recommendable.config.redis_namespace,
                  Recommendable.config.user_class.to_s.tableize,
                  klass.to_s.tableize ])
            end

            Recommendable.redis.del(temp_set)

            if number_recommendations = Recommendable.config.recommendations_to_store
              length = Recommendable.redis.zcard(recommended_4_set)
              Recommendable.redis.zremrangebyrank(recommended_4_set, 0, length - number_recommendations - 1)
            end
          end

          true
        end

        # Predict how likely it is that a user will like an item. This probability
        # is not based on percentage. 0.0 indicates that the user will neither like
        # nor dislike the item. Values that approach Infinity indicate a rising
        # likelihood of liking the item while values approaching -Infinity
        # indicate a rising probability of disliking the item.
        #
        # @param [Fixnum, String] user_id the user's ID
        # @param [Class] klass the item's class
        # @param [Fixnum, String] item_id the item's ID
        # @return [Float] the probability that the user will like the item
        def predict_for(user_id, klass, item_id)
          user_id = user_id.to_s
          item_id = item_id.to_s

          liked_by_set = Recommendable::Helpers::RedisKeyMapper.liked_by_set_for(klass, item_id)
          disliked_by_set = Recommendable::Helpers::RedisKeyMapper.disliked_by_set_for(klass, item_id)
          similarity_set = Recommendable::Helpers::RedisKeyMapper.similarity_set_for(user_id)
          similarity_sum = 0.0

          similarity_sum += Recommendable.redis.eval(similarity_total_for_lua, keys: [liked_by_set, similarity_set]).to_f
          similarity_sum -= Recommendable.redis.eval(similarity_total_for_lua, keys: [disliked_by_set, similarity_set]).to_f

          liked_by_count, disliked_by_count = Recommendable.redis.pipelined do
            Recommendable.redis.scard(liked_by_set)
            Recommendable.redis.scard(disliked_by_set)
          end
          prediction = similarity_sum / (liked_by_count + disliked_by_count).to_f
          prediction.finite? ? prediction : 0.0
        end

        def similarity_total_for_lua_func
        #   <<-LUA
        #   local function similarity_total_for(set, similarity_set)
        #     local sum=0.0
        #     local z=redis.call('ZRANGE', similarity_set, 0, -1, 'WITHSCORES')
        #
        #     for i=1, #z, 2 do
        #       if redis.call('SISMEMBER', set, z[i]) == 1 then
        #         sum=sum+z[i+1]
        #       end
        #     end
        #
        #     return sum
        #   end
        #   LUA
          <<-LUA
          local function similarity_total_for(set, similarity_set)
            local sum=0.0
            local ids = redis.call('SMEMBERS', set)
            local similarity_values = {}
            for i=1, #ids do
              sum = sum + (tonumber(redis.call('ZSCORE', similarity_set, ids[i])) or 0)
            end

            return sum
          end
          LUA
        end

        def similarity_total_for_lua
          <<-LUA
          #{similarity_total_for_lua_func}
          return tostring(similarity_total_for(unpack(KEYS)))
          LUA
        end

        def similarity_total_for(user_id, set)
          similarity_set = Recommendable::Helpers::RedisKeyMapper.similarity_set_for(user_id)

          Recommendable.redis.eval(similarity_total_for_lua, keys: [set, similarity_set]).to_f
        end

        def update_score_for(klass, id)
          score_set = Recommendable::Helpers::RedisKeyMapper.score_set_for(klass)
          liked_by_set = Recommendable::Helpers::RedisKeyMapper.liked_by_set_for(klass, id)
          disliked_by_set = Recommendable::Helpers::RedisKeyMapper.disliked_by_set_for(klass, id)
          liked_by_count, disliked_by_count = Recommendable.redis.pipelined do
            Recommendable.redis.scard(liked_by_set)
            Recommendable.redis.scard(disliked_by_set)
          end

          return 0.0 unless liked_by_count + disliked_by_count > 0

          z = 1.96
          n = liked_by_count + disliked_by_count
          phat = liked_by_count / n.to_f

          begin
            score = (phat + z*z/(2*n) - z * Math.sqrt((phat*(1-phat)+z*z/(4*n))/n))/(1+z*z/n)
          rescue Math::DomainError
            score = 0
          end

          Recommendable.redis.zadd(score_set, score, id)
          true
        end
      end
    end
  end
end
