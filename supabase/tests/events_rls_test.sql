begin;
select plan(14);

insert into auth.users (id, email)
values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1', 'member-test@horizon.local'),
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa3', 'outsider-test@horizon.local');

select set_config('horizon.actor_id', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1', true);

insert into public.events (
  org_id, stream_id, stream_type, version, event_type, schema_version, payload, actor_id, occurred_at
)
values
  (
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4',
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4',
    'organization',
    1,
    'OrganizationCreated',
    1,
    '{"name":"Test Org"}'::jsonb,
    '00000000-0000-4000-8000-000000000000',
    '2026-01-02T00:00:00Z'
  ),
  (
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4',
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa7',
    'membership',
    1,
    'MemberAdded',
    1,
    '{"user_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1"}'::jsonb,
    '00000000-0000-4000-8000-000000000000',
    '2026-01-02T00:00:01Z'
  );

select ok(
  not has_table_privilege('anon', 'public.events', 'select,insert,update,delete'),
  'anon has no grant on events'
);
select ok(
  not has_table_privilege('service_role', 'public.events', 'insert'),
  'service role has no runtime insert'
);
select ok(
  not has_table_privilege('authenticated', 'public.events', 'update,delete'),
  'authenticated cannot update or delete events'
);
select ok(
  not has_table_privilege('authenticated', 'public.organizations', 'insert,update,delete'),
  'authenticated cannot write the organization projection'
);

set local role authenticated;
set local request.jwt.claim.sub = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1';

select results_eq(
  $$insert into public.events (
      org_id, stream_id, stream_type, version, event_type, schema_version, payload, actor_id
    ) values (
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4',
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa5',
      'research_session',
      1,
      'DiscussionNoted',
      1,
      '{"body":"note"}'::jsonb,
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa3'
    )
    returning actor_id::text$$,
  array['aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'],
  'a member notes discussion and the stored actor is auth.uid()'
);

select throws_ok(
  $$insert into public.events (
      org_id, stream_id, stream_type, version, event_type, schema_version, payload, actor_id
    ) values (
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4',
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa8',
      'proposal', 1, 'ProposalApproved', 1, '{}'::jsonb,
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'
    )$$,
  '42501',
  null,
  'a member cannot insert ProposalApproved'
);
select throws_ok(
  $$insert into public.events (
      org_id, stream_id, stream_type, version, event_type, schema_version, payload, actor_id
    ) values (
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4',
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa8',
      'decision', 1, 'DecisionAccepted', 1, '{}'::jsonb,
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'
    )$$,
  '42501',
  null,
  'a member cannot insert DecisionAccepted'
);
select throws_ok(
  $$insert into public.events (
      org_id, stream_id, stream_type, version, event_type, schema_version, payload, actor_id
    ) values (
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4',
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa9',
      'check', 1, 'CheckRecorded', 1, '{}'::jsonb,
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'
    )$$,
  '42501',
  null,
  'a member cannot insert CheckRecorded'
);
select throws_ok(
  $$insert into public.events (
      org_id, stream_id, stream_type, version, event_type, schema_version, payload, actor_id
    ) values (
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4',
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaab',
      'harness', 1, 'HarnessCompiled', 1, '{}'::jsonb,
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'
    )$$,
  '42501',
  null,
  'a member cannot insert HarnessCompiled'
);
select throws_ok(
  $$insert into public.events (
      org_id, stream_id, stream_type, version, event_type, schema_version, payload, actor_id
    ) values (
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4',
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaac',
      'proposal', 1, 'ProposalVerified', 1, '{}'::jsonb,
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'
    )$$,
  '42501',
  null,
  'a member cannot insert ProposalVerified'
);
select throws_ok(
  $$update public.organizations set name = 'changed'$$,
  '42501',
  null,
  'a member cannot update a projection'
);

set local request.jwt.claim.sub = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa3';
select is_empty(
  $$select * from public.events$$,
  'a user outside the organization reads no events'
);

reset role;
grant usage on schema extensions to horizon_writer;
set local role horizon_writer;
set local search_path = public, extensions;
select set_config('horizon.actor_id', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1', true);
select throws_ok(
  $$insert into public.events (
      org_id, stream_id, stream_type, version, event_type, schema_version, payload, actor_id
    ) values (
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4',
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaad',
      'proposal', 1, 'ProposalApproved', 1, '{}'::jsonb,
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'
    )$$,
  '42501',
  null,
  'horizon_writer cannot insert ProposalApproved'
);

reset role;
select private.rebuild_projections();
select private.rebuild_projections();
select results_eq(
  $$select name from public.organizations
    where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4'$$,
  array['Test Org'],
  'folding the same events twice yields the same organization'
);

select * from finish();
rollback;
