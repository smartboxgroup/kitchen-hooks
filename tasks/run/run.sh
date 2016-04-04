#!/usr/bin/env bash
set -x
set -e

project="$(basename `pwd`)"
dockerfile="${2:-tasks/run/Dockerfile}"
task_name="${3:-$project-run-$(date +%s)}"
base_image="$(grep '^FROM' "$dockerfile" | awk '{ print $2 }')"

cleanup() {
  docker stop "$task_name"
  docker rm "$task_name"
  docker rmi "$task_name"
}

trap cleanup EXIT

docker pull "$base_image"
docker build -t "$task_name" -f "$dockerfile" .
docker run --name "$task_name" -t "$task_name"
