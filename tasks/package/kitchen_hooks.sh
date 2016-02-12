#!/bin/bash
set -e
KITCHEN_HOOKS_RUBY="${KITCHEN_HOOKS_RUBY:-/usr/bin/ruby2.2}"
KITCHEN_HOOKS_ROOT="${KITCHEN_HOOKS_ROOT:-/opt/kitchen_hooks}"
export BUNDLE_GEMFILE="$KITCHEN_HOOKS_ROOT/Gemfile"
unset BUNDLE_IGNORE_CONFIG
exec "$KITCHEN_HOOKS_RUBY" -rbundler/setup "$KITCHEN_HOOKS_ROOT/bin/kitchen_hooks" $@