-- Local only, after Auth has migrated auth.users.
-- One organization, one human member. Agent and CI use horizon_writer / horizon_ci, not a membership role.

insert into auth.users (
  instance_id,
  id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at,
  confirmation_token,
  email_change,
  email_change_token_new,
  recovery_token
)
values (
  '00000000-0000-0000-0000-000000000000',
  '00000000-0000-4000-8000-000000000003',
  'authenticated',
  'authenticated',
  'member@horizon.local',
  extensions.crypt('horizon-local-dev', extensions.gen_salt('bf')),
  now(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{}'::jsonb,
  now(),
  now(),
  '',
  '',
  '',
  ''
);

insert into auth.identities (
  provider_id,
  user_id,
  identity_data,
  provider,
  last_sign_in_at,
  created_at,
  updated_at
)
values (
  '00000000-0000-4000-8000-000000000003',
  '00000000-0000-4000-8000-000000000003',
  '{"sub":"00000000-0000-4000-8000-000000000003","email":"member@horizon.local"}'::jsonb,
  'email',
  now(),
  now(),
  now()
);

select set_config('horizon.actor_id', '00000000-0000-4000-8000-000000000003', false);

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
values
  (
    '00000000-0000-4000-8000-000000000001',
    '00000000-0000-4000-8000-000000000001',
    'organization',
    1,
    'OrganizationCreated',
    1,
    '{"name":"Horizon"}'::jsonb,
    '00000000-0000-4000-8000-000000000000',
    '2026-01-01T00:00:00Z'
  ),
  (
    '00000000-0000-4000-8000-000000000001',
    '00000000-0000-4000-8000-000000000013',
    'membership',
    1,
    'MemberAdded',
    1,
    '{"user_id":"00000000-0000-4000-8000-000000000003"}'::jsonb,
    '00000000-0000-4000-8000-000000000000',
    '2026-01-01T00:00:01Z'
  );
