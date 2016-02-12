#!/usr/bin/env bash
set -e
useradd --user-group --system -M --shell /bin/false kitchen_hooks || true
mkdir -p /etc/kitchen_hooks
cd /opt/kitchen_hooks
if ! hash bundle ; then
  echo 'Could not run `bundle`, fixing that for you...'
  gem install bundler || gem2.2 install bundler
fi
bundle install --without development:test --local
chown -R kitchen_hooks:kitchen_hooks /opt/kitchen_hooks
chown -R kitchen_hooks:kitchen_hooks /etc/kitchen_hooks