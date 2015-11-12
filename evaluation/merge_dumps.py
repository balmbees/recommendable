from glob import glob

from utils import *

mode = 'mahout'

lines = []
if mode=='mahout':
    for dump_file in glob('./dump*.data'):
        with open(dump_file) as f:
            lines.extend([l.replace(',1\n',',3\n').replace(',-1',',0').replace(',','\t') for l in f.readlines()])

            header(" # of lines until %s : %s" % (dump_file, len(lines)))
elif mode=='spark':
    for dump_file in glob('./dump*.data'):
        with open(dump_file) as f:
            lines.extend(f.readlines())

            header(" # of lines until %s : %s" % (dump_file, len(lines)))

with open('total_dump_%s.data' % mode, 'w') as f:
    f.writelines(lines)
