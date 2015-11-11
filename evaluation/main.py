import redis
import pandas as pd
from subprocess import call
import ml_metrics as metrics

from utils import *

r = redis.StrictRedis(host='localhost', port=6379, db=0)

TOP_K = 20

BASE_KEY = 'recommendable'
USER_KEY = 'users'
BASE_QUERY = '%s:%s' % (BASE_KEY, USER_KEY)

CHANNEL = {}
CHANNEL['liked'] = 'liked_channels'
CHANNEL['disliked'] = 'liked_channels'
CHANNEL['recommended'] = 'recommended_4_channels'

TOTAL_DATA_FILE = 'total.csv'

def get_ith_key(query, idx):
    try:
        return query.split(':')[idx]
    except:
        pass

def make_dataset_from_uids(uids, channel_names=CHANNEL['liked'], check_validity = False):
    if type(channel_names) != list:
        channel_names = [channel_names]

    header("Make dataset from %s (#%s)" % (channel_names, len(uids)))

    data = {}
    for channel_name in channel_names:
        queries = ['%s:%s:%s' % (BASE_QUERY, uid, channel_name) for uid in uids]

        if channel_name in [CHANNEL['liked'], CHANNEL['disliked']]:
            data.update({channel_name: [list(r.smembers(query)) for query in queries]})
        elif channel_name == CHANNEL['recommended']:
            data.update({channel_name: [list(r.zrange(query, 0, -1, withscores=False, desc=True)) for query in queries]})
        else:
            raise("Undefined channel name : %s" % channel_names)

    df = pd.DataFrame(index=uids, data=data)

    if check_validity:
        pbar = get_progressbar("check", len(df))
        for pidx, (index, row) in enumerate(df.iterrows()):
            pbar.update(pidx + 1)
            for channel_name in channel_names:
                compare1 = r.smembers('%s:%s:%s' % (BASE_QUERY, index, channel_name))
                compare2 = row[channel_name]
                assert compare1 == compare2, "Wrong channels for %s" % index
        pbar.finish()

    return df

def get_channels():
    total_uids = list(set([get_ith_key(query, 2) for query in r.keys('*')]))
    total_actions = list(set([get_ith_key(query, 3) for query in r.keys('*')]))

    header("# of uids : %s, # of actions : %s" % (len(total_uids), len(total_actions)))

    for idx, action in enumerate(total_actions):
        if action:
            print " %s) %s" % (idx+1, action)

    total_uids.sort()

    channels = {}
    channels['liked'] = r.keys('%s:*:%s' % (BASE_QUERY, CHANNEL['liked']))
    channels['disliked'] = r.keys('%s:*:%s' % (BASE_QUERY, CHANNEL['disliked']))
    channels['recommended'] = r.keys('%s:*:%s' % (BASE_QUERY, CHANNEL['recommended']))

    for name in channels:
        channels[name].sort()

    return channels

def save_df_to_csv(df):
    tmp_df = df.copy()
    tmp_df[CHANNEL['liked']] = tmp_df[CHANNEL['liked']].map(lambda x: " ".join(x))
    tmp_df.to_csv(TOTAL_DATA_FILE)

def make_user_into_redis(uid, channel_ids, channel_type='liked', force_delete=True):
    query = '%s:%s:%s' % (BASE_QUERY, uid, CHANNEL[channel_type])

    if force_delete:
        r.delete(query)

    for channel_id in channel_ids:
        r.sadd(query, channel_id)

if __name__ == '__main__':
    #######################################
    # Get data from recommendable-redis
    #######################################

    channels = get_channels()

    header("# of liked, disliked, recommended : %s, %s, %s" % \
            (len(channels['liked']), len(channels['disliked']), len(channels['recommended'])))

    #uids = [query.split(':')[2] for query in channels['liked']]
    uids = [query.split(':')[2] for query in channels['recommended']]

    true_df = make_dataset_from_uids(uids, CHANNEL['liked'])
    pred_df = make_dataset_from_uids(uids, CHANNEL['recommended'])

    assert sum(true_df.index != pred_df.index) == 0, "index of true_df and pred_df is not same" 

    true, pred = true_df[CHANNEL['liked']].values, pred_df[CHANNEL['recommended']].values
    header("Recommendable : %s" %  metrics.mapk(true, pred))

    TOP_K = 20
    pred = pred_df[CHANNEL['recommended']].map(lambda x: x[:TOP_K]).values
    header("Recommendable of top %s : %.6f (%.6f%%)" % \
            (TOP_K, metrics.mapk(true, pred), common_percentage(true, pred)))

    save_df_to_csv(true_df)

    ##############################################
    # Insert train and test data for into redis
    ##############################################
    header('Insert fake data for into redis')

    TRAIN_K = 5
    true_df['x'] = true_df[CHANNEL['liked']].map(lambda x: x[:TRAIN_K])
    true_df['y'] = true_df[CHANNEL['liked']].map(lambda x: x[TRAIN_K:])
    true_df['len_y'] = true_df[CHANNEL['liked']].map(lambda x: len(x[TRAIN_K:]))

    df = true_df[true_df['len_y'] > 0]

    Xs, ys, uids = {}, {}, {}

    Xs['train'], Xs['test'], ys['train'], ys['test'], uids['train'], uids['test'] = make_train_test(df['x'].values, df['y'].values, df.index, test_size=0.3, random_state=0)

    for mode in ['train', 'test']:
        uids[mode] = ["%s_%s" % (mode, uid) for uid in uids[mode]]

    for mode in ['train', 'test']:
        pbar = get_progressbar("make user data for %s" % mode, len(uids[mode]))
        for idx, uid in enumerate(uids[mode]):
            pbar.update(idx+1)
            make_user_into_redis(uid, Xs['train'][idx], 'liked', True)
        pbar.finish()

    #######################################
    # Evaluate train and test data
    #######################################
    heaer('Evaluate train and test data')

    for mode in ['train', 'test']:
        command = ["ruby", "dummy/update.rb"]
        command.extend(uids[mode])
        call(command)
