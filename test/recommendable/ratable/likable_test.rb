$LOAD_PATH.unshift File.expand_path('../../test', __FILE__)
require 'test_helper'

class LikableTest < Minitest::Test
  def setup
    @user = Factory(:user)
    @friend = Factory(:user)
    @movie = Factory(:movie)
    Recommendable.set_shard_key(@user.id)
  end

  def test_liked_by_returns_relevant_users
    assert_empty @movie.liked_by
    @user.like(@movie)
    assert_includes @movie.liked_by, @user
    refute_includes @movie.liked_by, @friend
    @friend.like(@movie)
    assert_includes @movie.liked_by, @friend
  end

  def test_liked_by_count_returns_an_accurate_count
    assert_empty @movie.liked_by
    @user.like(@movie)
    assert_equal @movie.liked_by_count, 1
    @friend.like(@movie)
    assert_equal @movie.liked_by_count, 2
  end

  def teardown
    Recommendable.set_shard_key(nil)
    Recommendable.redis_arr.each do |redis|
      redis.flushdb
    end
  end
end
