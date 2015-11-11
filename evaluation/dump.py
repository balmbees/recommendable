import redis
import pandas as pd
from subprocess import call
import ml_metrics as metrics

from utils import *
from main import *

r = redis.StrictRedis(host='localhost', port=6379, db=0)

TOP_K = 20

BASE_KEY = 'recommendable'
USER_KEY = 'users'
BASE_QUERY = '%s:%s' % (BASE_KEY, USER_KEY)

CHANNEL = {}
CHANNEL['liked'] = 'liked_channels'
CHANNEL['disliked'] = 'liked_channels'
CHANNEL['recommended'] = 'recommended_4_channels'

if __name__ == "__main__":
    channels = get_channels()

    header("# of liked, disliked, recommended : %s, %s, %s" % \
            (len(channels['liked']), len(channels['disliked']), len(channels['recommended'])))

    uids = [query.split(':')[2] for query in channels['recommended']]

    df = make_dataset_from_uids(uids, channel_names=CHANNEL['liked'], check_validity = False, quite=False)
