#!/bin/sh
set -eu

escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

url=$(escape "${SUPABASE_URL:-}")
key=$(escape "${SUPABASE_ANON_KEY:-}")
printf 'window.__HORIZON__ = { supabaseUrl: "%s", supabaseAnonKey: "%s" };\n' "$url" "$key" \
  > /usr/share/nginx/html/config.js

exec "$@"
