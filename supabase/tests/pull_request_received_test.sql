begin;
select plan(10);

select set_config('horizon.actor_id', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1', true);

insert into public.events (
  org_id, stream_id, stream_type, version, event_type, schema_version, payload, actor_id, occurred_at
)
values (
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb4',
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb4',
  'organization', 1, 'OrganizationCreated', 1,
  '{"name":"PR Org"}'::jsonb,
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
  '2026-01-02T00:00:00Z'
);

-- A stream of another type, to show the function refuses to append onto it.
select set_config('horizon.grant_role', 'authenticated', true);
insert into public.events (
  org_id, stream_id, stream_type, version, event_type, schema_version, payload, actor_id
)
values (
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb4',
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb9',
  'research_session', 1, 'DiscussionNoted', 1,
  '{"body":"note"}'::jsonb,
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1'
);
select set_config('horizon.grant_role', '', true);

select ok(
  exists (
    select 1 from public.event_type_grants
    where role_name = 'horizon_writer' and event_type = 'PullRequestReceived'
  ),
  'horizon_writer is granted PullRequestReceived'
);
select ok(
  not has_function_privilege(
    'authenticated', 'public.append_pull_request_received(uuid, uuid, jsonb)', 'execute'
  ),
  'a member cannot call the append function'
);
select ok(
  has_function_privilege(
    'horizon_writer', 'public.append_pull_request_received(uuid, uuid, jsonb)', 'execute'
  ),
  'horizon_writer can call the append function'
);

set local role horizon_writer;
set local request.jwt.claims = '{"role":"horizon_writer","sub":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2"}';

select is(
  public.append_pull_request_received(
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb4',
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb5',
    '{"delivery_id":"d-1","action":"opened","actor_id":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb3"}'::jsonb
  ),
  'appended',
  'a first delivery appends'
);
select is(
  public.append_pull_request_received(
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb4',
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb5',
    '{"delivery_id":"d-2","action":"synchronize"}'::jsonb
  ),
  'appended',
  'a second delivery on the stream appends'
);
select is(
  public.append_pull_request_received(
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb4',
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb5',
    '{"delivery_id":"d-2","action":"synchronize"}'::jsonb
  ),
  'duplicate',
  'a repeated X-GitHub-Delivery is reported as a duplicate'
);
select throws_ok(
  $$select public.append_pull_request_received(
      'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb4',
      'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb9',
      '{"delivery_id":"d-3","action":"opened"}'::jsonb
    )$$,
  '22023',
  null,
  'the function refuses a stream that belongs to another stream type'
);

set local request.jwt.claims = '{"role":"horizon_writer"}';
select throws_ok(
  $$select public.append_pull_request_received(
      'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb4',
      'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb6',
      '{"delivery_id":"d-4","action":"opened"}'::jsonb
    )$$,
  '42501',
  null,
  'a writer JWT without a sub cannot append'
);

reset role;

select results_eq(
  $$select version, actor_id::text
    from public.events
    where stream_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb5'
    order by version$$,
  $$values (1, 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2'),
           (2, 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2')$$,
  'versions are 1 and 2, and the actor is the JWT sub, not the payload'
);
select is(
  (select count(*)::int from public.events where event_type = 'PullRequestReceived'),
  2,
  'the duplicate and the refused deliveries stored nothing'
);

select * from finish();
rollback;
