#!/usr/bin/env bash
set -x -euo pipefail

cd "$(
    dirname "$(
        realpath "$0"
    )"
)"

docker compose down --remove-orphans
docker compose up --build -d --remove-orphans
