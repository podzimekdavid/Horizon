#!/usr/bin/env bash
# Start or reset the local stack. Auth URLs default for this machine.
# A deploy does not use this script; see scripts/supabase-deploy.sh.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

export HORIZON_AUTH_SITE_URL="${HORIZON_AUTH_SITE_URL:-http://127.0.0.1:3000}"
export HORIZON_AUTH_ADDITIONAL_REDIRECT_URL="${HORIZON_AUTH_ADDITIONAL_REDIRECT_URL:-http://127.0.0.1:3000}"

if [[ "${1:-}" == "reset" ]]; then
  exec npx supabase db reset
fi

exec npx supabase start
