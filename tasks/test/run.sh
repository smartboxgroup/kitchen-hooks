#!/usr/bin/env bash
set -x
set -e

dockerfile="${1:-tasks/test/Dockerfile}"
task_name="${2:-franz-test-$(date +%s)}"

docker build -t "$task_name" -f "$dockerfile" .
