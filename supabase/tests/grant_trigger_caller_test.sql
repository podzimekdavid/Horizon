begin;
select plan(4);

insert into auth.users (id, email)
values ('cccccccc-cccc-4ccc-8ccc-ccccccccccc1', 'caller-test@horizon.local');

select set_config('horizon.actor_id', 'cccccccc-cccc-4ccc-8ccc-ccccccccccc1', true);

insert into public.events (
  org_id, stream_id, stream_type, version, event_type, schema_version, payload, actor_id, occurred_at
)
values
  (
    'cccccccc-cccc-4ccc-8ccc-ccccccccccc4',
    'cccccccc-cccc-4ccc-8ccc-ccccccccccc4',
    'organization', 1, 'OrganizationCreated', 1,
    '{"name":"Caller Org"}'::jsonb,
    'cccccccc-cccc-4ccc-8ccc-ccccccccccc1',
    '2026-01-02T00:00:00Z'
  ),
  (
    'cccccccc-cccc-4ccc-8ccc-ccccccccccc4',
    'cccccccc-cccc-4ccc-8ccc-ccccccccccc7',
    'membership', 1, 'MemberAdded', 1,
    '{"user_id":"cccccccc-cccc-4ccc-8ccc-ccccccccccc1"}'::jsonb,
    'cccccccc-cccc-4ccc-8ccc-ccccccccccc1',
    '2026-01-02T00:00:01Z'
  );

select ok(
  not (select prosecdef from pg_proc where oid = 'private.enforce_event_grant()'::regprocedure),
  'the grant trigger runs as the inserting role, not as its owner'
);

-- postgres names the role to check, the way a definer command does.
select set_config('horizon.grant_role', 'horizon_writer', true);
select lives_ok(
  $$insert into public.events (
      org_id, stream_id, stream_type, version, event_type, schema_version, payload, actor_id
    ) values (
      'cccccccc-cccc-4ccc-8ccc-ccccccccccc4',
      'cccccccc-cccc-4ccc-8ccc-ccccccccccc5',
      'proposal', 1, 'ProposalCreated', 1, '{}'::jsonb,
      'cccccccc-cccc-4ccc-8ccc-ccccccccccc1'
    )$$,
  'postgres may check horizon.grant_role for a definer command'
);

-- A member cannot borrow another role's grants through the same setting.
set local role authenticated;
set local request.jwt.claim.sub = 'cccccccc-cccc-4ccc-8ccc-ccccccccccc1';

select throws_ok(
  $$insert into public.events (
      org_id, stream_id, stream_type, version, event_type, schema_version, payload, actor_id
    ) values (
      'cccccccc-cccc-4ccc-8ccc-ccccccccccc4',
      'cccccccc-cccc-4ccc-8ccc-ccccccccccc6',
      'proposal', 1, 'ProposalCreated', 1, '{}'::jsonb,
      'cccccccc-cccc-4ccc-8ccc-ccccccccccc1'
    )$$,
  '42501',
  null,
  'a member cannot use horizon.grant_role to act as horizon_writer'
);

select lives_ok(
  $$insert into public.events (
      org_id, stream_id, stream_type, version, event_type, schema_version, payload, actor_id
    ) values (
      'cccccccc-cccc-4ccc-8ccc-ccccccccccc4',
      'cccccccc-cccc-4ccc-8ccc-cccccccccc10',
      'research_session', 1, 'DiscussionNoted', 1, '{"body":"note"}'::jsonb,
      'cccccccc-cccc-4ccc-8ccc-ccccccccccc1'
    )$$,
  'a member can still note a discussion'
);

reset role;
select * from finish();
rollback;
