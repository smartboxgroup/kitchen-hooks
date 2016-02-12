#!/usr/bin/env bash
set -x
set -e

project=$(basename `pwd`)
artifacts="${1:-tasks/package/artifacts}"
dockerfile="${2:-tasks/package/Dockerfile}"
task_name="${3:-$project-package-$(date +%s)}"

cleanup() {
  docker stop "$task_name"
  docker rm "$task_name"
}

trap cleanup EXIT

rm -rf "$artifacts"
docker build -t "$task_name" -f "$dockerfile" .
docker run --name "$task_name" -dt "$task_name"
docker cp "$task_name":/artifacts "$artifacts"
