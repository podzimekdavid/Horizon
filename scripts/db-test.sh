#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root/docker"

for test_file in "$root"/supabase/tests/*_test.sql; do
  echo "== $(basename "$test_file")"
  {
    echo "create extension if not exists pgtap with schema extensions;"
    echo "set search_path = public, extensions;"
    cat "$test_file"
  } | docker compose exec -T db psql -U postgres -v ON_ERROR_STOP=1
done
