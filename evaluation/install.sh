#!/bin/bash

sudo apt-get update

sudo apt-get install -y tree tmux git ctags zsh vim build-essential python-pip curl screen
sudo apt-get install -y git-core curl zlib1g-dev build-essential libssl-dev libreadline-dev libyaml-dev libsqlite3-dev sqlite3 libxml2-dev libxslt1-dev libcurl4-openssl-dev python-software-properties libffi-dev python-setuptools postgresql postgresql-contrib libpq-dev libqtwebkit-dev qt4-qmake nodejs
sudo apt-get install build-essential autoconf libtool pkg-config python-opengl python-imaging python-pyrex python-pyside.qtopengl idle-python2.7 qt4-dev-tools qt4-designer libqtgui4 libqtcore4 libqt4-xml libqt4-test libqt4-script libqt4-network libqt4-dbus python-qt4 python-qt4-gl libgle3 python-dev
sudo apt-get install python-numpy python-scipy python-matplotlib ipython ipython-notebook python-pandas python-sympy python-nose
sudo apt-get install libblas-dev liblapack-dev libatlas-base-dev gfortran


sudo easy_install green let
sudo easy_install gevent

sudo pip install scipy
sudo pip install -U scikit-learn

git clone git://github.com/kennethreitz/autoenv.git ~/.autoenv

# oh-my-zsh
sh -c "$(curl -fsSL https://raw.github.com/robbyrussell/oh-my-zsh/master/tools/install.sh)"

# dotfiles
git clone https://github.com/carpedm20/dotfiles.git
cd dotfiles
./makesymlinks.sh

# make dir
mkdir ~/git; cd ~/git

# ssh-key generate
ssh-keygen -t rsa -b 4096 -C "carpedm20@gmail.com"
ssh-add ~/.ssh/id_rsa

# git
git config user.name "Taehoon Kim"
git config user.email "carpedm20@gmail.com" 

# python
sudo pip install awscli requests ipython

# ruby
cd
git clone git://github.com/sstephenson/rbenv.git .rbenv
echo 'export PATH="$HOME/.rbenv/bin:$PATH"' >> ~/.bashrc
echo 'eval "$(rbenv init -)"' >> ~/.bashrc
exec $SHELL

git clone git://github.com/sstephenson/ruby-build.git ~/.rbenv/plugins/ruby-build
echo 'export PATH="$HOME/.rbenv/plugins/ruby-build/bin:$PATH"' >> ~/.bashrc
exec $SHELL

git clone https://github.com/sstephenson/rbenv-gem-rehash.git ~/.rbenv/plugins/rbenv-gem-rehash

rbenv install 2.2.3
rbenv global 2.2.3
ruby -v

# redis
wget http://download.redis.io/redis-stable.tar.gz
tar xvzf redis-stable.tar.gz
cd ~/git/redis-stable
make

# recommendable
cd ~/git
git clone git@github.com:balmbees/recommendable.git

# balmbees
cd ~/git
git clone git@github.com:balmbees/balmbees.git
cd ~/git/balmbees
rbenv install
gem install eventmachine -v '1.0.8'  -- --with-cppflags=-I/usr/local/opt/openssl/include
bundle config local.recommendable ~/git/recommendable
vi Gemfile
# edit recommendable gem to => gem 'recommendable', github: 'balmbees/recommendable', branch: 'evaluation'
bundle install --jobs 5
cp config/database_sample.yml config/database.yml
rake db:create
rake db:migrate
rake db:test:prepare

# redis dump
mkdir ~/data
cd ~/data
aws s3 cp s3://vingle-rediss3/redis-recommend1/dump-6380.rdb_2015-11-06-01 ./dump1.rdb
aws s3 cp s3://vingle-rediss3/redis-recommend2/dump-6380.rdb_2015-11-06-01 ./dump2.rdb
aws s3 cp s3://vingle-rediss3/redis-recommend3/dump-6380.rdb_2015-11-06-01 ./dump3.rdb
aws s3 cp s3://vingle-rediss3/redis-recommend4/dump-6380.rdb_2015-11-06-01 ./dump4.rdb
aws s3 cp s3://vingle-rediss3/redis-recommend5/dump-6380.rdb_2015-11-06-01 ./dump5.rdb
aws s3 cp s3://vingle-rediss3/redis-recommend6/dump-6380.rdb_2015-11-06-01 ./dump6.rdb

# ssh-key publish
echo "[[ ~/.ssh/id_rsa.pub ]]"
cat ~/.ssh/id_rsa.pub
echo

echo "[[ hostname : `hostname` ]]"
echo
