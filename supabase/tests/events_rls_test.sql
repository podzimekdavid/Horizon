begin;
select plan(24);

insert into auth.users (id, email)
values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1', 'agent-test@horizon.local'),
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2', 'owner-test@horizon.local'),
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa3', 'outsider-test@horizon.local');

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
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2',
    '2026-01-02T00:00:00Z'
  ),
  (
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4',
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa6',
    'membership',
    1,
    'MembershipGranted',
    1,
    '{"user_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2","role":"owner"}'::jsonb,
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2',
    '2026-01-02T00:00:01Z'
  ),
  (
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4',
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa7',
    'membership',
    1,
    'MembershipGranted',
    1,
    '{"user_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1","role":"agent"}'::jsonb,
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2',
    '2026-01-02T00:00:02Z'
  );

select ok(
  not has_table_privilege('anon', 'public.events', 'select,insert,update,delete'),
  'anon has no grant on events'
);
select ok(
  not has_table_privilege('authenticated', 'public.events', 'update,delete'),
  'authenticated cannot update or delete events'
);
select ok(
  has_table_privilege('authenticated', 'public.events', 'select,insert'),
  'authenticated can read and append events'
);
select ok(
  not has_table_privilege('anon', 'public.organizations', 'select,insert,update,delete'),
  'anon has no grant on organizations'
);
select ok(
  not has_table_privilege('authenticated', 'public.organizations', 'insert,update,delete'),
  'authenticated cannot write organizations'
);
select ok(
  not has_table_privilege('anon', 'public.memberships', 'select,insert,update,delete'),
  'anon has no grant on memberships'
);
select ok(
  not has_table_privilege('authenticated', 'public.memberships', 'insert,update,delete'),
  'authenticated cannot write memberships'
);

set local role anon;
select throws_ok(
  $$select * from public.events$$,
  '42501',
  null,
  'anon cannot read events'
);

set local role authenticated;
set local request.jwt.claim.sub = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1';

select results_eq(
  $$insert into public.events (
      org_id, stream_id, stream_type, version, event_type, schema_version, payload, actor_id
    ) values (
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4',
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa5',
      'rule',
      1,
      'RuleCreated',
      1,
      '{"body":"capture"}'::jsonb,
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'
    )
    returning event_type$$,
  array['RuleCreated'],
  'agent appends a rule event'
);

select results_eq(
  $$select event_type from public.events
    where stream_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa5'$$,
  array['RuleCreated'],
  'agent reads the event it appended'
);

select throws_ok(
  $$insert into public.events (
      org_id, stream_id, stream_type, version, event_type, schema_version, payload, actor_id
    ) values (
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4',
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa8',
      'proposal',
      1,
      'ProposalApproved',
      1,
      '{}'::jsonb,
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'
    )$$,
  '42501',
  null,
  'agent cannot record ProposalApproved'
);

select is_empty(
  $$select event_type from public.events
    where stream_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa8'$$,
  'rejected approval left no event'
);

select throws_ok(
  $$insert into public.events (
      org_id, stream_id, stream_type, version, event_type, schema_version, payload, actor_id
    ) values (
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4',
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa5',
      'rule',
      1,
      'RuleCreated',
      1,
      '{}'::jsonb,
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'
    )$$,
  '23505',
  null,
  'the same stream version conflicts'
);

select throws_ok(
  $$insert into public.events (
      org_id, stream_id, stream_type, version, event_type, schema_version, payload, actor_id
    ) values (
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4',
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa9',
      'rule',
      1,
      'RuleCreated',
      1,
      '{}'::jsonb,
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2'
    )$$,
  '42501',
  null,
  'agent cannot append as another actor'
);

select throws_ok(
  $$update public.events set event_type = 'RuleCreated'$$,
  '42501',
  null,
  'agent cannot update events'
);
select throws_ok(
  $$delete from public.events$$,
  '42501',
  null,
  'agent cannot delete events'
);
select throws_ok(
  $$update public.organizations set name = 'changed'$$,
  '42501',
  null,
  'agent cannot update the organization projection'
);

set local request.jwt.claim.sub = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa3';

select is_empty(
  $$select * from public.events$$,
  'a user outside the organization reads no events'
);
select is_empty(
  $$select * from public.organizations$$,
  'a user outside the organization reads no organizations'
);
select throws_ok(
  $$insert into public.events (
      org_id, stream_id, stream_type, version, event_type, schema_version, payload, actor_id
    ) values (
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4',
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaab',
      'rule',
      1,
      'RuleCreated',
      1,
      '{}'::jsonb,
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa3'
    )$$,
  '42501',
  null,
  'a user outside the organization cannot append'
);

set local request.jwt.claim.sub = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1';
select results_eq(
  $$select event_type from public.events
    where stream_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa5'$$,
  array['RuleCreated'],
  'the denied writes left the rule event intact'
);

set local request.jwt.claim.sub = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2';
select results_eq(
  $$insert into public.events (
      org_id, stream_id, stream_type, version, event_type, schema_version, payload, actor_id
    ) values (
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4',
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa8',
      'proposal',
      1,
      'ProposalApproved',
      1,
      '{}'::jsonb,
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2'
    )
    returning event_type$$,
  array['ProposalApproved'],
  'owner records ProposalApproved'
);

select throws_ok(
  $$select private.rebuild_projections()$$,
  '42501',
  null,
  'a member cannot rebuild projections'
);

reset role;
select private.rebuild_projections();
select results_eq(
  $$select name from public.organizations
    where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4'$$,
  array['Test Org'],
  'rebuilding projections restores the organization from events'
);

select * from finish();
rollback;
