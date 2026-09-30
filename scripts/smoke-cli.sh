#!/usr/bin/env bash
# Append one event through the Compose API and confirm the agent role cannot approve.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

set -a
# shellcheck disable=SC1091
source docker/.env
set +a

export HORIZON_SUPABASE_URL="${SUPABASE_PUBLIC_URL:?}"
export HORIZON_SUPABASE_PUBLISHABLE_KEY="${SUPABASE_PUBLISHABLE_KEY:-${ANON_KEY:?}}"
export HORIZON_EMAIL="${HORIZON_EMAIL:-member@horizon.local}"
export HORIZON_PASSWORD="${HORIZON_PASSWORD:-horizon-local-dev}"
export HORIZON_ORG_ID="${HORIZON_ORG_ID:-00000000-0000-4000-8000-000000000001}"

stream_id="00000000-0000-4000-8000-00000000c11a"
node cli/horizon.mjs append \
  --stream-id "$stream_id" \
  --stream-type research_session \
  --event-type DiscussionNoted \
  --version 1 \
  --payload '{"body":"capture"}'

node cli/horizon.mjs list --stream-id "$stream_id" | grep -q DiscussionNoted

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
