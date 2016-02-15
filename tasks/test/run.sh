#!/usr/bin/env bash
set -x
set -e

project=$(basename `pwd`)
dockerfile="${1:-tasks/test/Dockerfile}"
task_name="${2:-$project-test-$(date +%s)}"
base_image="$(grep '^FROM' "$dockerfile" | awk '{ print $2 }')"

docker pull "$base_image"
docker build -t "$task_name" -f "$dockerfile" .
docker rmi "$task_name"