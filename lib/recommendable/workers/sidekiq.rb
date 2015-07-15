module Recommendable
  module Workers
    class Sidekiq
      if defined?(::Sidekiq)
        include ::Sidekiq::Worker
        sidekiq_options :unique => true, :queue => :recommendable, :retry => false
      end

      def perform(user_id, options={})
        Recommendable::Helpers::Calculations.update_similarities_for(user_id)
        Recommendable::Helpers::Calculations.update_4_recommendations_for(user_id)
      end
    end
  end
end
