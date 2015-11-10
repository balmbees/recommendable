import redis
import pandas as pd
import ml_metrics as metrics

from utils import *

r = redis.StrictRedis(host='localhost', port=6379, db=0)

TOP_K = 20

BASE_KEY = 'recommendable'
USER_KEY = 'users'
BASE_QUERY = '%s:%s' % (BASE_KEY, USER_KEY)

TOTAL_DATA_FILE = 'total.csv'

def get_ith_key(query, idx):
    try:
        return query.split(':')[idx]
    except:
        pass

def make_dataset_from_uids(uids, channel_names=['liked_channels'], check_validity = False):
    if type(channel_names) != list:
        channel_names = [channel_names]
    header("Make dataset from %s (#%s)" % (channel_names, len(uids)))

    queries = ['%s:%s:%s' % (BASE_QUERY, uid, channel_names) for uid in uids]

    data = {}
    for channel_name in channel_names:
        if channel_name == 'liked_channels':
            data.update({channel_name: [list(r.smembers(query)) for query in queries]})
        elif channel_name == 'recommended_4_channels':
            data.update({channel_name: [list(r.zrange(query, 0, -1, withscores=False, desc=True)) for query in queries]})
        else:
            raise("Undefined channel name : %s" % channel_names)

    df = pd.DataFrame(index=uids, data=data)

    if check_validity:
        pbar = get_progressbar("check", len(df))
        for pidx, (index, row) in enumerate(df.iterrows()):
            pbar.update(pidx + 1)
            compare1 = r.smembers('%s:%s:%s' % (BASE_QUERY, index, channel_names))
            compare2 = row['channels']
            assert compare1 == compare2, "Wrong channels for %s" % index
        pbar.finish()

    return df

if __name__ == '__main__':
    total_uids = list(set([get_ith_key(query, 2) for query in r.keys('*')]))
    total_actions = list(set([get_ith_key(query, 3) for query in r.keys('*')]))

    header("# of uids : %s, # of actions : %s" % (len(total_uids), len(total_actions)))

    for idx, action in enumerate(total_actions):
        print " %s) %s" % (idx+1, action)

    total_uids.sort()

    liked_channels = r.keys('%s:*:liked_channels' % BASE_QUERY)
    disliked_channels = r.keys('%s:*:disliked_channels' % BASE_QUERY)
    recommended_channels = r.keys('%s:*:recommended_4_channels' % BASE_QUERY)

    liked_channels.sort()
    disliked_channels.sort()
    recommended_channels.sort()

    header("# of liked, disliked, recommended : %s, %s, %s" % \
            (len(liked_channels), len(disliked_channels), len(recommended_channels)))

    #uids = [query.split(':')[2] for query in liked_channels]
    uids = [query.split(':')[2] for query in recommended_channels]

    true_df = make_dataset_from_uids(uids, 'liked_channels')
    pred_df = make_dataset_from_uids(uids, 'recommended_4_channels')

    assert sum(true_df.index != pred_df.index) == 0, "index of true_df and pred_df is not same" 

    true_channel_name = 'liked_channels'
    pred_channel_name = 'recommended_4_channels'

    true, pred = true_df[true_channel_name].values, pred_df[pred_channel_name].values
    header("Recommendable : %s" %  metrics.mapk(true, pred))

    TOP_K = 20
    pred = pred_df[pred_channel_name].map(lambda x: x[:TOP_K]).values
    header("Recommendable of top %s : %.6f (%.6f%%)" % \
            (TOP_K, metrics.mapk(true, pred), common_percentage(true, pred)))

    tmp_df = true_df.copy()
    tmp_df[true_channel_name] = tmp_df[true_channel_name].map(lambda x: " ".join(x))
    tmp_df.to_csv(TOTAL_DATA_FILE)

    X_train, X_test, y_train, y_test = make_train_test(true_df[true_channel_name].values, true_df.index, 0.3, 0)

