#!/bin/sh
# Apply supabase/migrations, then the local seed when HORIZON_SEED=true.
set -eu

until pg_isready -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" >/dev/null 2>&1; do
  sleep 1
done

psql -v ON_ERROR_STOP=1 <<'SQL'
create schema if not exists supabase_migrations;
create table if not exists supabase_migrations.schema_migrations (
  version text primary key,
  name text not null,
  applied_at timestamptz not null default now()
);
SQL

for file in /migrations/*.sql; do
  [ -f "$file" ] || continue
  base=$(basename "$file")
  version=${base%%_*}
  name=${base#*_}
  name=${name%.sql}
  applied=$(psql -tAc "select 1 from supabase_migrations.schema_migrations where version = '${version}'" | tr -d '[:space:]')
  if [ "$applied" = "1" ]; then
    continue
  fi
  psql -v ON_ERROR_STOP=1 -f "$file"
  psql -v ON_ERROR_STOP=1 -c "insert into supabase_migrations.schema_migrations (version, name) values ('${version}', '${name}')"
done

if [ "${HORIZON_SEED:-false}" = "true" ]; then
  seeded=$(psql -tAc "select 1 from public.organizations where id = '00000000-0000-4000-8000-000000000001'" | tr -d '[:space:]')
  if [ "$seeded" != "1" ]; then
    psql -v ON_ERROR_STOP=1 -f /seed.sql
  fi
fi
