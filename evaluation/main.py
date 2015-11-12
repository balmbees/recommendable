import redis
import random
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

def make_dataset_from_uids(uids, channel_names=CHANNEL['liked'], check_validity = False, quite=False):
    if type(channel_names) != list:
        channel_names = [channel_names]

    if not quite:
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

def make_x_y_len_y(true_df, train_k):
    true_df['x'] = true_df[CHANNEL['liked']].map(lambda x: x[:train_k])
    true_df['y'] = true_df[CHANNEL['liked']].map(lambda x: x[train_k:])
    true_df['len_y'] = true_df[CHANNEL['liked']].map(lambda x: len(x[train_k:]))

def get_uids_from_channels(channels, channel_name):
    return [query.split(':')[2] for query in channels[channel_name] if 'train' not in query and 'test' not in query]

def get_channel_ids_from_df(df, channel_names):
    if type(channel_names) != list:
        channel_names = [channel_names]

    channel_ids = []
    for channel_name in channel_names:
        pbar = get_progressbar('channel_id in "%s"' % channel_name, len(df))
        for pidx, (index, row) in enumerate(df.iterrows()):
            pbar.update(pidx + 1)
            channel_ids.extend(row[channel_name])
        pbar.finish()

    header("# of unique channel_id in %s : %s" % (channel_names, len(channel_ids)))
    return list(set(channel_ids))

if __name__ == '__main__':
    #######################################
    # Get data from recommendable-redis
    #######################################

    channels = get_channels()

    header("# of liked, disliked, recommended : %s, %s, %s" % \
            (len(channels['liked']), len(channels['disliked']), len(channels['recommended'])))

    #uids = [query.split(':')[2] for query in channels['liked']]
    uids = get_uids_from_channels(channels, 'recommended')

    true_df = make_dataset_from_uids(uids, CHANNEL['liked'])
    pred_df = make_dataset_from_uids(uids, CHANNEL['recommended'])

    channel_ids = get_channel_ids_from_df(true_df, CHANNEL['liked'])

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
    make_x_y_len_y(true_df, TRAIN_K)

    df = true_df[true_df['len_y'] > 0]

    Xs, ys, uids = {}, {}, {}

    Xs['train'], Xs['test'], ys['train'], ys['test'], uids['train'], uids['test'] = make_train_test(df['x'].values, df['y'].values, df.index, test_size=0.3, random_state=0)

    for mode in ['train', 'test']:
        uids[mode] = ["%s_%s" % (mode, uid) for uid in uids[mode]]

    for mode in ['train', 'test']:
        if len(r.smembers("%s:%s:%s" % (BASE_QUERY, uids[mode][0], CHANNEL['liked']))):
            print(" [*] Skip to make %s data" % mode)
            continue

        pbar = get_progressbar("make %s data" % mode, len(uids[mode]))
        for idx, uid in enumerate(uids[mode]):
            pbar.update(idx+1)
            make_user_into_redis(uid, Xs['train'][idx], 'liked', True)
        pbar.finish()

    EVAL_MODE = True
    if EVAL_MODE:
        #######################################
        # Evaluate train and test data
        #######################################

        for mode in ['train', 'test']:
            header('Evaluate recommendable for "%s" data' % mode)

            batches = np.array_split(uids[mode], 100)
            pbar = get_progressbar("eval %s data" % mode, len(batches))
            for idx, batch in enumerate(batches):
                if len(r.zrange("%s:%s:%s" % (BASE_QUERY, batch[-1], CHANNEL['recommended']), 0, -1)):
                    print(" [*] Skip to make %s data" % mode)
                    continue

                pbar.update(idx+1)
                command = ["ruby", "dummy/update.rb"]
                command.extend(batch)
                call(command)
            pbar.finish()

    ##############################################
    # Check performance for train and test data
    ##############################################

    CHECK_COUNT = 4
    for mode in ['train']:
        batches = np.array_split(uids[mode], 100)
        for idx, batch in enumerate(batches[:CHECK_COUNT]):
            true_df = make_dataset_from_uids([uid.split('_')[1] for uid in batch], CHANNEL['liked'], quite=True)
            pred_df = make_dataset_from_uids(batch, CHANNEL['recommended'], quite=True)

            make_x_y_len_y(true_df, TRAIN_K)

            assert sum(true_df.index != pred_df.index.map(lambda x: x.split('_')[1])) == 0, \
                    "index of true_df and pred_df is not same" 

            x, true, pred = true_df['x'].values, true_df['y'].values, pred_df[CHANNEL['recommended']].values
            header("Recommendable : %s" %  metrics.mapk(true, pred), short=True)

            TOP_K = 20
            pred = pred_df[CHANNEL['recommended']].map(lambda x: x[:TOP_K]).values
            header("Recommendable of top %s : %.6f (%.6f%%)" % \
                    (TOP_K, metrics.mapk(true, pred), common_percentage(true, pred)), short=True)

            for x, t, p in random.sample(zip(x, true, pred),2):
                print_name(x, "X  : ")
                print_name(t, "Y  : ")
                print_name(p, "Y_ : ")
                print

    save_df_to_csv(true_df)

