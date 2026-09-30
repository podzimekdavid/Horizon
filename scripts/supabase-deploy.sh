#!/usr/bin/env bash
# Start the same Compose stack on a host that already has docker/.env.
# URLs and secrets in that file are the only difference between environments.
set -euo pipefail
cd "$(dirname "$0")/../docker"

if [[ ! -f .env ]]; then
  echo "docker/.env is missing. Copy docker/.env.example, set the URLs for this environment, then run utils/generate-keys.sh --update-env." >&2
  exit 1
fi

exec docker compose up -d --wait
