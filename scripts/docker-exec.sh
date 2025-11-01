#!/bin/bash
# Helper script to execute commands in docker container

CONTAINER_NAME="${CONTAINER_NAME:-ubuntu18-dev}"
USER_ID="${USER_ID:-1000}"
WORK_DIR="${WORK_DIR:-/data/work/projects/rustdesk-ubuntu18}"

# Default to user 1000, use -r for root
if [ "$1" = "-r" ]; then
    USER_ID=0
    shift
fi

docker exec -u $USER_ID -w "$WORK_DIR" "$CONTAINER_NAME" bash -c "$@"
