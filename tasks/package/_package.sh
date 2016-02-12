#!/usr/bin/env bash
set -x
set -e

ruby=ruby2.2
version=$(cat VERSION)

rm -rf etc
rm -rf tmp
rm -rf .bundle
rm -rf .vagrant

bundle update
bundle package --all

bundle exec fpm -n kitchen_hooks \
  --after-install tasks/package/post-install.sh \
  --after-upgrade tasks/package/post-install.sh \
  -d "$ruby" -d "$ruby-dev" -d git \
  -s dir -t deb -v "$version" \
  tasks/package/kitchen_hooks.sh=/usr/local/bin/kitchen_hooks \
  ./=/opt/kitchen_hooks

dpkg -i *.deb
ls -la /opt/kitchen_hooks
kitchen_hooks art

mkdir -p /package
mv *.deb /package