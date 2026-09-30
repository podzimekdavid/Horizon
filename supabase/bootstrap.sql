-- One-shot for a new environment, as postgres, after the human user exists in Auth.
--
--   psql "$DATABASE_URL" \
--     -v org_id='<organization uuid>' \
--     -v org_name='Horizon' \
--     -v member_id='<auth.users id>' \
--     -v member_stream_id='<new uuid>' \
--     -c "select set_config('horizon.actor_id', :'member_id', false)" \
--     -f supabase/bootstrap.sql

select set_config('horizon.actor_id', :'member_id', false);

insert into public.events (
  org_id, stream_id, stream_type, version, event_type, schema_version, payload, actor_id, occurred_at
)
select
  :'org_id'::uuid,
  :'org_id'::uuid,
  'organization',
  1,
  'OrganizationCreated',
  1,
  jsonb_build_object('name', :'org_name'),
  :'member_id'::uuid,
  timestamptz '2026-01-01 00:00:00+00'
where not exists (
  select 1 from public.events where stream_id = :'org_id'::uuid and version = 1
);

insert into public.events (
  org_id, stream_id, stream_type, version, event_type, schema_version, payload, actor_id, occurred_at
)
select
  :'org_id'::uuid,
  :'member_stream_id'::uuid,
  'membership',
  1,
  'MemberAdded',
  1,
  jsonb_build_object('user_id', :'member_id'),
  :'member_id'::uuid,
  timestamptz '2026-01-01 00:00:01+00'
where not exists (
  select 1 from public.events where stream_id = :'member_stream_id'::uuid and version = 1
);
