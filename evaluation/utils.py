from __future__ import print_function

import json
import numpy as np

with open('names.json') as f:
    name_dict = json.loads(f.read())

def header(s, size=60):
    print("\n"+"="*size)
    print("  %s" % s)
    print("="*size)

def get_progressbar(name, size):
    from progressbar import ProgressBar, ETA, Percentage, Bar, SimpleProgress
    widgets = [
        "[", name, "] ",
        Percentage(),
        ' (', SimpleProgress(), ') ',
        Bar(), ' ',
        ETA(),
    ]
    pbar = ProgressBar(widgets=widgets, max_value=size).start()

    return pbar

def make_train_test(*arrays,  **options):
    from sklearn import cross_validation
    return cross_validation.train_test_split(*arrays,  **options)

def common_percentage(X, Y):
    from collections import Counter
    scores = []
    for x, y in zip(X, Y):
        try:
            scores.append(len(Counter(x) & Counter(y))/float(len(x)))
            #import ipdb;ipdb.set_trace()
        except:
            pass
    return np.mean(scores)

def print_name(ids):
    names = []
    for id in ids:
        try:
            names.append(name_dict[id])
        except:
            pass
    print(",".join(names))
