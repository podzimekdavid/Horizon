#!/usr/bin/env bash
# Same Compose stack as a deployed environment. First local run writes docker/.env.
set -euo pipefail
cd "$(dirname "$0")/../docker"

if [[ ! -f .env ]]; then
  cp .env.example .env
  sh utils/generate-keys.sh --update-env
fi

if [[ "${1:-}" == "reset" ]]; then
  docker compose down -v --remove-orphans
  rm -rf volumes/db/data
fi

if ! docker compose up -d --wait; then
  docker compose logs migrate || true
  exit 1
fi
