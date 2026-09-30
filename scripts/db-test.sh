#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root/docker"

{
  echo "create extension if not exists pgtap with schema extensions;"
  echo "set search_path = public, extensions;"
  cat "$root/supabase/tests/events_rls_test.sql"
} | docker compose exec -T db psql -U postgres -v ON_ERROR_STOP=1
