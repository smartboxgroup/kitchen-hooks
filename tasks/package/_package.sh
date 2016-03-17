#!/usr/bin/env bash
set -x
set -e

ARTIFACTS="${1:-artifacts}"

ruby=ruby2.2
version="$(cat VERSION)-${BUILD_NUMBER:-1}+$(git rev-parse --short HEAD)"

rm -rf doc
rm -rf etc
rm -rf tmp
rm -rf .bundle
rm -rf .vagrant
rm -rf vendor
rm -rf pkg
mkdir -p pkg

bundle update
bundle package --all

bundle exec fpm -n kitchen_hooks \
  --after-install tasks/package/post-install.sh \
  --after-upgrade tasks/package/post-install.sh \
  -d "$ruby" -d "$ruby-dev" -d git \
  -s dir -t deb -v "$version" \
  tasks/package/kitchen_hooks.sh=/usr/local/bin/kitchen_hooks \
  ./=/opt/kitchen_hooks

# gem uninstall -aIx
# dpkg -i *.deb
# ls -la /opt/kitchen_hooks
# kitchen_hooks art

mkdir -p $ARTIFACTS
mv *.deb $ARTIFACTS