#!/usr/bin/env bash
set -e

project=kitchen_hooks

if ! hash bundle ; then
  echo 'Could not run `bundle`, fixing that for you...'
  gem install bundler || gem2.2 install bundler
fi

cd /opt/$project
bundle install --without development:test:spec --local --deployment

useradd --user-group --system -M --shell /bin/false $project || true

for d in /opt/$project /etc/$project /var/log/$project /var/data/$project ; do
  mkdir -p $d
  chown -R $project:$project $d
done