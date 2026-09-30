begin;
grant usage on schema extensions to horizon_ci;
select plan(12);

select set_config('horizon.actor_id', 'cccccccc-cccc-4ccc-8ccc-ccccccccccc1', true);

insert into public.events (
  org_id, stream_id, stream_type, version, event_type, schema_version, payload, actor_id, occurred_at
)
values (
  'cccccccc-cccc-4ccc-8ccc-ccccccccccc4',
  'cccccccc-cccc-4ccc-8ccc-ccccccccccc4',
  'organization', 1, 'OrganizationCreated', 1,
  '{"name":"CI Org"}'::jsonb,
  'cccccccc-cccc-4ccc-8ccc-ccccccccccc1',
  '2026-01-02T00:00:00Z'
);

select set_config('horizon.grant_role', 'authenticated', true);
insert into public.events (
  org_id, stream_id, stream_type, version, event_type, schema_version, payload, actor_id
)
values (
  'cccccccc-cccc-4ccc-8ccc-ccccccccccc4',
  'cccccccc-cccc-4ccc-8ccc-ccccccccccc9',
  'research_session', 1, 'DiscussionNoted', 1,
  '{"body":"note"}'::jsonb,
  'cccccccc-cccc-4ccc-8ccc-ccccccccccc1'
);
select set_config('horizon.grant_role', '', true);

select ok(
  exists (
    select 1 from public.event_type_grants
    where role_name = 'horizon_ci' and event_type = 'CheckRecorded'
  ),
  'horizon_ci is granted CheckRecorded'
);
select ok(
  not has_function_privilege(
    'authenticated', 'public.append_check_recorded(uuid, uuid, jsonb)', 'execute'
  ),
  'a member cannot call the append function'
);
select ok(
  has_function_privilege(
    'horizon_ci', 'public.append_check_recorded(uuid, uuid, jsonb)', 'execute'
  ),
  'horizon_ci can call the append function'
);

set local role horizon_ci;
set local request.jwt.claims = '{"role":"horizon_ci","sub":"cccccccc-cccc-4ccc-8ccc-ccccccccccc2"}';

select is(
  public.append_check_recorded(
    'cccccccc-cccc-4ccc-8ccc-ccccccccccc4',
    'cccccccc-cccc-4ccc-8ccc-ccccccccccc5',
    '[
      {"repository":"acme/horizon","pull_request":9,"sha":"abc","adr_id":"ADR-0006","relation":"applies","actor_id":"cccccccc-cccc-4ccc-8ccc-ccccccccccc3"},
      {"repository":"acme/horizon","pull_request":9,"sha":"abc","adr_id":"ADR-0006","relation":"violated","findings":[{"file":"checkout.ts","line":1,"noul":0.92}]}
    ]'::jsonb
  )::text,
  '2',
  'applies and violated append on one call'
);

select throws_ok(
  $$select public.append_check_recorded(
      'cccccccc-cccc-4ccc-8ccc-ccccccccccc4',
      'cccccccc-cccc-4ccc-8ccc-ccccccccccc5',
      '[{"adr_id":"ADR-0006","relation":"violated"},{"adr_id":"ADR-0006","relation":"violated"}]'::jsonb
    )$$,
  '22023',
  null,
  'two events with the same relation are refused'
);
select throws_ok(
  $$select public.append_check_recorded(
      'cccccccc-cccc-4ccc-8ccc-ccccccccccc4',
      'cccccccc-cccc-4ccc-8ccc-ccccccccccc5',
      '[{"adr_id":"ADR-0006","relation":"acquitted"}]'::jsonb
    )$$,
  '22023',
  null,
  'acquitted is not a relation'
);
select throws_ok(
  $$select public.append_check_recorded(
      'cccccccc-cccc-4ccc-8ccc-ccccccccccc4',
      'cccccccc-cccc-4ccc-8ccc-ccccccccccc9',
      '[{"adr_id":"ADR-0006","relation":"applies"}]'::jsonb
    )$$,
  '22023',
  null,
  'the function refuses a stream that belongs to another stream type'
);

set local request.jwt.claims = '{"role":"horizon_ci"}';
select throws_ok(
  $$select public.append_check_recorded(
      'cccccccc-cccc-4ccc-8ccc-ccccccccccc4',
      'cccccccc-cccc-4ccc-8ccc-ccccccccccc6',
      '[{"adr_id":"ADR-0006","relation":"applies"}]'::jsonb
    )$$,
  '42501',
  null,
  'a ci JWT without a sub cannot append'
);

reset role;

select results_eq(
  $$select version, event_type, actor_id::text, payload ->> 'relation'
    from public.events
    where stream_id = 'cccccccc-cccc-4ccc-8ccc-ccccccccccc5'
    order by version$$,
  $$values (1, 'CheckRecorded', 'cccccccc-cccc-4ccc-8ccc-ccccccccccc2', 'applies'),
           (2, 'CheckRecorded', 'cccccccc-cccc-4ccc-8ccc-ccccccccccc2', 'violated')$$,
  'versions are 1 and 2, and the actor is the JWT sub, not the payload'
);
select is(
  (select payload -> 'findings' -> 0 ->> 'file'
     from public.events
     where stream_id = 'cccccccc-cccc-4ccc-8ccc-ccccccccccc5' and version = 2),
  'checkout.ts',
  'the violated payload keeps the semgrep file'
);
select is(
  (select count(*)::text from public.events where event_type = 'CheckRecorded'),
  '2',
  'the refused calls stored nothing'
);
select is(
  (select stream_type from public.events
    where stream_id = 'cccccccc-cccc-4ccc-8ccc-ccccccccccc5' and version = 1),
  'check',
  'the events land on the check stream'
);

select * from finish();
rollback;
