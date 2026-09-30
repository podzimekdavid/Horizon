#!/usr/bin/env bash
# Apply the committed Supabase config and migrations to one hosted project.
# Seed data is not included. Set the variables for the target environment:
#   SUPABASE_ACCESS_TOKEN
#   SUPABASE_DB_PASSWORD
#   SUPABASE_PROJECT_ID
#   HORIZON_AUTH_SITE_URL
#   HORIZON_AUTH_ADDITIONAL_REDIRECT_URL
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

: "${SUPABASE_ACCESS_TOKEN:?Set SUPABASE_ACCESS_TOKEN for the target project}"
: "${SUPABASE_DB_PASSWORD:?Set SUPABASE_DB_PASSWORD for the target project}"
: "${SUPABASE_PROJECT_ID:?Set SUPABASE_PROJECT_ID for the target project}"
: "${HORIZON_AUTH_SITE_URL:?Set HORIZON_AUTH_SITE_URL for the target environment}"
: "${HORIZON_AUTH_ADDITIONAL_REDIRECT_URL:?Set HORIZON_AUTH_ADDITIONAL_REDIRECT_URL for the target environment}"

npx supabase link --project-ref "$SUPABASE_PROJECT_ID" --yes
npx supabase db push --linked --yes
npx supabase config push --project-ref "$SUPABASE_PROJECT_ID" --yes
