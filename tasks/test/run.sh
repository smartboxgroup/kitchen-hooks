#!/usr/bin/env bash
set -x
set -e

project=$(basename `pwd`)
dockerfile="${1:-tasks/test/Dockerfile}"
task_name="${2:-$project-test-$(date +%s)}"

docker pull sczizzo/trusty-tool:latest
docker build -t "$task_name" -f "$dockerfile" .
