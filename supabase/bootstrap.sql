-- One-shot data for a hosted environment. Not a migration and not the local seed.
-- Create the Auth users in that project first, then run as the database owner:
--
--   psql "$DATABASE_URL" \
--     -v org_id='<organization uuid>' \
--     -v org_name='Horizon' \
--     -v owner_id='<auth.users id of the human owner>' \
--     -v owner_stream_id='<new uuid>' \
--     -v agent_id='<auth.users id of the agent or CI user>' \
--     -v agent_stream_id='<new uuid>' \
--     -f supabase/bootstrap.sql
--
-- Re-running is safe: each insert is skipped when that stream version already exists.

insert into public.events (
  org_id,
  stream_id,
  stream_type,
  version,
  event_type,
  schema_version,
  payload,
  actor_id,
  occurred_at
)
select
  :'org_id'::uuid,
  :'org_id'::uuid,
  'organization',
  1,
  'OrganizationCreated',
  1,
  jsonb_build_object('name', :'org_name'),
  :'owner_id'::uuid,
  timestamptz '2026-01-01 00:00:00+00'
where not exists (
  select 1
  from public.events
  where stream_id = :'org_id'::uuid
    and version = 1
);

insert into public.events (
  org_id,
  stream_id,
  stream_type,
  version,
  event_type,
  schema_version,
  payload,
  actor_id,
  occurred_at
)
select
  :'org_id'::uuid,
  :'owner_stream_id'::uuid,
  'membership',
  1,
  'MembershipGranted',
  1,
  jsonb_build_object('user_id', :'owner_id', 'role', 'owner'),
  :'owner_id'::uuid,
  timestamptz '2026-01-01 00:00:01+00'
where not exists (
  select 1
  from public.events
  where stream_id = :'owner_stream_id'::uuid
    and version = 1
);

insert into public.events (
  org_id,
  stream_id,
  stream_type,
  version,
  event_type,
  schema_version,
  payload,
  actor_id,
  occurred_at
)
select
  :'org_id'::uuid,
  :'agent_stream_id'::uuid,
  'membership',
  1,
  'MembershipGranted',
  1,
  jsonb_build_object('user_id', :'agent_id', 'role', 'agent'),
  :'owner_id'::uuid,
  timestamptz '2026-01-01 00:00:02+00'
where not exists (
  select 1
  from public.events
  where stream_id = :'agent_stream_id'::uuid
    and version = 1
);
