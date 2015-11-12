import redis
import pandas as pd
from subprocess import call
import ml_metrics as metrics
from collections import Counter

from utils import *
from main import *

if __name__ == "__main__":
    if len(sys.argv) < 2:
        dump_file = 'dump.data'
    else:
        dump_file = sys.argv[1]

    print(" [*] Dump file : %s" % dump_file)

    channels = get_channels()

    header("# of liked, disliked, recommended : %s, %s, %s" % \
            (len(channels['liked']), len(channels['disliked']), len(channels['recommended'])))

    uids = get_uids_from_channels(channels, 'liked')

    df_dict = {}
    df_dict[CHANNEL['liked']] = make_dataset_from_uids(uids, \
            channel_names=CHANNEL['liked'], check_validity = False, quite=False)
    df_dict[CHANNEL['disliked']]= make_dataset_from_uids(uids, \
            channel_names=CHANNEL['disliked'], check_validity = False, quite=False)

    channel_ids = get_channel_ids_from_df(df_dict[CHANNEL['liked']], CHANNEL['liked'])
    channel_ids.extend(get_channel_ids_from_df(df_dict[CHANNEL['disliked']], CHANNEL['disliked']))

    channel_id_counter = Counter(channel_ids)

    header("Dump dataset")

    with open(dump_file, 'w') as f:
        lines = []

        user_dict = {}
        for df_name in df_dict.keys():
            df = df_dict[df_name]

            if df_name == CHANNEL['liked']:
                score = 1
            elif df_name == CHANNEL['disliked']:
                score = -1
            else:
                raise("Wrong df_name : %s" % df_name)

            pbar = get_progressbar("dump %s" % df_name, len(df))
            for pidx, (index, row) in enumerate(df.iterrows()):
                pbar.update(pidx + 1)
                for channel in row[df_name]:
                    lines.append("%s,%s,%s\n" % (index, channel, score))

                    try:
                        user_dict[index][channel] = score
                    except:
                        user_dict[index] = {}
                        user_dict[index][channel] = score
            pbar.finish()

        ADD_ALL = False
        if ADD_ALL:
            pbar = get_progressbar("make missing data", len(user_dict))
            score = 0

            for pidx, (index, channel_dict) in enumerate(user_dict.items()):
                pbar.update(pidx + 1)

                unchecked_channel_ids = channel_id_counter - Counter(channel_dict.keys())
                for channel in unchecked_channel_ids:
                    lines.append("%s,%s,%s\n" % (index, channel, score))

        f.writelines(lines)
