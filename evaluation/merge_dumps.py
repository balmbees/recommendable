from glob import glob

from utils import *

lines = []
for dump_file in glob('./dump*.data'):
    with open(dump_file) as f:
        lines.extend(f.readlines())

        header(" # of lines until %s : %s" % (dump_file, len(lines)))

with open('total_dump.data', 'w') as f:
    f.writelines(lines)
