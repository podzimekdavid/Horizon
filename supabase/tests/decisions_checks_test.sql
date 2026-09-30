begin;
select plan(10);

insert into auth.users (id, email)
values
  ('cccccccc-cccc-4ccc-8ccc-ccccccccccc1', 'checks-member@horizon.local'),
  ('cccccccc-cccc-4ccc-8ccc-ccccccccccc3', 'checks-outsider@horizon.local');

select set_config('horizon.actor_id', 'cccccccc-cccc-4ccc-8ccc-ccccccccccc1', true);
select set_config('horizon.grant_role', 'postgres', true);

insert into public.events (
  org_id, stream_id, stream_type, version, event_type, schema_version, payload, actor_id, occurred_at
)
values
  (
    'cccccccc-cccc-4ccc-8ccc-ccccccccccc4',
    'cccccccc-cccc-4ccc-8ccc-ccccccccccc4',
    'organization', 1, 'OrganizationCreated', 1,
    '{"name":"Checks Org"}'::jsonb,
    'cccccccc-cccc-4ccc-8ccc-ccccccccccc1',
    '2026-02-01T00:00:00Z'
  ),
  (
    'cccccccc-cccc-4ccc-8ccc-ccccccccccc4',
    'cccccccc-cccc-4ccc-8ccc-ccccccccccc7',
    'membership', 1, 'MemberAdded', 1,
    '{"user_id":"cccccccc-cccc-4ccc-8ccc-ccccccccccc1"}'::jsonb,
    'cccccccc-cccc-4ccc-8ccc-ccccccccccc1',
    '2026-02-01T00:00:01Z'
  );

select set_config('horizon.grant_role', 'horizon_writer', true);

insert into public.events (
  org_id, stream_id, stream_type, version, event_type, schema_version, payload, actor_id, occurred_at
)
values (
  'cccccccc-cccc-4ccc-8ccc-ccccccccccc4',
  'cccccccc-cccc-4ccc-8ccc-ccccccccccc8',
  'decision', 1, 'DecisionProposed', 1,
  '{"adr_id":"ADR-0006","title":"Stack split","globs":["apps/web/**"]}'::jsonb,
  'cccccccc-cccc-4ccc-8ccc-ccccccccccc1',
  '2026-02-01T00:00:02Z'
);

select results_eq(
  $$select status, globs::text from public.decisions
    where id = 'cccccccc-cccc-4ccc-8ccc-ccccccccccc8'$$,
  $$values ('proposed', '[]')$$,
  'a proposed decision does not govern globs'
);

insert into public.event_type_grants (role_name, event_type)
values ('horizon_writer', 'DecisionAccepted');

insert into public.events (
  org_id, stream_id, stream_type, version, event_type, schema_version, payload, actor_id, occurred_at
)
values (
  'cccccccc-cccc-4ccc-8ccc-ccccccccccc4',
  'cccccccc-cccc-4ccc-8ccc-ccccccccccc8',
  'decision', 2, 'DecisionAccepted', 1,
  '{"adr_id":"ADR-0006","globs":["apps/web/**"]}'::jsonb,
  'cccccccc-cccc-4ccc-8ccc-ccccccccccc1',
  '2026-02-01T00:00:03Z'
);

select results_eq(
  $$select status, globs::text from public.decisions
    where id = 'cccccccc-cccc-4ccc-8ccc-ccccccccccc8'$$,
  $$values ('accepted', '["apps/web/**"]')$$,
  'acceptance stores the governing globs'
);

select set_config('horizon.grant_role', 'horizon_ci', true);

insert into public.events (
  id, org_id, stream_id, stream_type, version, event_type, schema_version, payload, actor_id, occurred_at
)
values (
  'cccccccc-cccc-4ccc-8ccc-ccccccccccc9',
  'cccccccc-cccc-4ccc-8ccc-ccccccccccc4',
  'cccccccc-cccc-4ccc-8ccc-ccccccccccca',
  'check', 1, 'CheckRecorded', 1,
  '{"repository":"podzimekdavid/Horizon","pull_request":10,"sha":"abc","adr_id":"ADR-0006","relation":"violated"}'::jsonb,
  'cccccccc-cccc-4ccc-8ccc-ccccccccccc1',
  '2026-02-01T00:00:04Z'
);

select results_eq(
  $$select relation, pull_request from public.checks
    where id = 'cccccccc-cccc-4ccc-8ccc-ccccccccccc9'$$,
  $$values ('violated', 10)$$,
  'a CheckRecorded event folds one check row'
);

select ok(
  not has_table_privilege('authenticated', 'public.checks', 'insert,update,delete'),
  'a member cannot write the check projection'
);
select ok(
  not has_table_privilege('authenticated', 'public.decisions', 'insert,update,delete'),
  'a member cannot write the decision projection'
);
select ok(
  not exists (
    select 1
    from public.event_type_grants
    where role_name = 'authenticated'
      and event_type = 'CheckRecorded'
  ),
  'a member is not granted CheckRecorded'
);

select private.rebuild_projections();
select private.rebuild_projections();

select results_eq(
  $$select d.status, d.title, d.globs::text, c.relation
    from public.decisions as d
    join public.checks as c on c.org_id = d.org_id and c.adr_id = d.adr_id
    where d.id = 'cccccccc-cccc-4ccc-8ccc-ccccccccccc8'$$,
  $$values ('accepted', 'Stack split', '["apps/web/**"]', 'violated')$$,
  'replaying the log restores the decision and the check'
);

select set_config('horizon.grant_role', '', true);

set local role authenticated;
set local request.jwt.claim.sub = 'cccccccc-cccc-4ccc-8ccc-ccccccccccc1';

select results_eq(
  $$select adr_id from public.checks$$,
  array['ADR-0006'],
  'a member reads the check for their organization'
);

select throws_ok(
  $$insert into public.events (
      org_id, stream_id, stream_type, version, event_type, schema_version, payload, actor_id
    ) values (
      'cccccccc-cccc-4ccc-8ccc-ccccccccccc4',
      'cccccccc-cccc-4ccc-8ccc-cccccccccccb',
      'check', 1, 'CheckRecorded', 1, '{}'::jsonb,
      'cccccccc-cccc-4ccc-8ccc-ccccccccccc1'
    )$$,
  '42501',
  null,
  'a member cannot insert CheckRecorded'
);

set local request.jwt.claim.sub = 'cccccccc-cccc-4ccc-8ccc-ccccccccccc3';

select is_empty(
  $$select id from public.checks$$,
  'a user outside the organization cannot read the check'
);

select * from finish();
rollback;
