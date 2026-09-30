#!/usr/bin/env bash
# Append one event through the local API and confirm the agent role cannot approve.
set -euo pipefail
cd "$(dirname "$0")/.."

status="$(npx supabase status -o env)"
set -a
# shellcheck disable=SC1090
eval "$status"
set +a

key="${PUBLISHABLE_KEY:-${ANON_KEY:-}}"
url="${API_URL:-}"
if [[ -z "$key" || -z "$url" ]]; then
  echo "supabase status did not report API_URL and a publishable key" >&2
  exit 1
fi

export HORIZON_SUPABASE_URL="$url"
export HORIZON_SUPABASE_PUBLISHABLE_KEY="$key"
export HORIZON_EMAIL="${HORIZON_EMAIL:-agent@horizon.local}"
export HORIZON_PASSWORD="${HORIZON_PASSWORD:-horizon-local-dev}"
export HORIZON_ORG_ID="${HORIZON_ORG_ID:-00000000-0000-4000-8000-000000000001}"

stream_id="00000000-0000-4000-8000-00000000c11a"
node cli/horizon.mjs append \
  --stream-id "$stream_id" \
  --stream-type rule \
  --event-type RuleCreated \
  --version 1 \
  --payload '{"body":"capture"}'

node cli/horizon.mjs list --stream-id "$stream_id" | grep -q RuleCreated

if node cli/horizon.mjs append \
  --stream-id "00000000-0000-4000-8000-00000000c11b" \
  --stream-type proposal \
  --event-type ProposalApproved \
  --version 1 \
  --payload '{}'
then
  echo "agent recorded ProposalApproved" >&2
  exit 1
fi
