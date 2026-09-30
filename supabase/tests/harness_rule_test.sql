begin;
select plan(11);

insert into auth.users (id, email)
values
  ('dddddddd-dddd-4ddd-8ddd-ddddddddddd2', 'rule-member@horizon.local'),
  ('dddddddd-dddd-4ddd-8ddd-ddddddddddd3', 'rule-outsider@horizon.local');

select set_config('horizon.actor_id', 'dddddddd-dddd-4ddd-8ddd-ddddddddddd2', true);
select set_config('horizon.grant_role', '', true);

insert into public.events (
  org_id, stream_id, stream_type, version, event_type, schema_version, payload, actor_id, occurred_at
)
values
  (
    'dddddddd-dddd-4ddd-8ddd-ddddddddddd1',
    'dddddddd-dddd-4ddd-8ddd-ddddddddddd1',
    'organization', 1, 'OrganizationCreated', 1,
    '{"name":"Rule Org"}'::jsonb,
    'dddddddd-dddd-4ddd-8ddd-ddddddddddd2',
    '2026-01-03T00:00:00Z'
  ),
  (
    'dddddddd-dddd-4ddd-8ddd-ddddddddddd1',
    'dddddddd-dddd-4ddd-8ddd-dddddddddd10',
    'membership', 1, 'MemberAdded', 1,
    '{"user_id":"dddddddd-dddd-4ddd-8ddd-ddddddddddd2"}'::jsonb,
    'dddddddd-dddd-4ddd-8ddd-ddddddddddd2',
    '2026-01-03T00:00:01Z'
  );

set local role horizon_writer;
set local request.jwt.claims = '{"role":"horizon_writer","sub":"dddddddd-dddd-4ddd-8ddd-ddddddddddd4"}';

select public.append_writer_event(
  'dddddddd-dddd-4ddd-8ddd-ddddddddddd1',
  'dddddddd-dddd-4ddd-8ddd-ddddddddddd5',
  'decision', 'DecisionProposed', '{"adr_id":"ADR-0006"}'::jsonb
);
select public.append_writer_event(
  'dddddddd-dddd-4ddd-8ddd-ddddddddddd1',
  'dddddddd-dddd-4ddd-8ddd-ddddddddddd6',
  'proposal', 'ProposalCreated',
  '{"kind":"accept_decision","decision_id":"dddddddd-dddd-4ddd-8ddd-ddddddddddd5"}'::jsonb
);
select public.append_writer_event(
  'dddddddd-dddd-4ddd-8ddd-ddddddddddd1',
  'dddddddd-dddd-4ddd-8ddd-ddddddddddd6',
  'proposal', 'ProposalVerified', '{"verdict":"NotConfigured"}'::jsonb
);

set local role authenticated;
set local request.jwt.claim.sub = 'dddddddd-dddd-4ddd-8ddd-ddddddddddd2';
set local request.jwt.claims = '{"sub":"dddddddd-dddd-4ddd-8ddd-ddddddddddd2"}';
select public.approve_proposal('dddddddd-dddd-4ddd-8ddd-ddddddddddd6');

set local role horizon_writer;
set local request.jwt.claims = '{"role":"horizon_writer","sub":"dddddddd-dddd-4ddd-8ddd-ddddddddddd4"}';
select public.append_writer_event(
  'dddddddd-dddd-4ddd-8ddd-ddddddddddd1',
  'dddddddd-dddd-4ddd-8ddd-ddddddddddd8',
  'proposal', 'ProposalCreated',
  jsonb_build_object(
    'kind', 'compile_harness',
    'decision_id', 'dddddddd-dddd-4ddd-8ddd-ddddddddddd5',
    'candidate', jsonb_build_object(
      'stream_id', 'dddddddd-dddd-4ddd-8ddd-ddddddddddd7',
      'decision_id', 'dddddddd-dddd-4ddd-8ddd-ddddddddddd5',
      'adr_id', 'ADR-0006',
      'surface', 'cursor_rule',
      'globs', jsonb_build_array('apps/web/**'),
      'body', $body$---
description: "ADR-0006 — The web app does not import an LLM SDK or Koog."
globs: apps/web/**
alwaysApply: false

The web app does not import an LLM SDK or Koog.

Cites ADR-0006.
$body$
    )
  )
);
select public.append_writer_event(
  'dddddddd-dddd-4ddd-8ddd-ddddddddddd1',
  'dddddddd-dddd-4ddd-8ddd-ddddddddddd8',
  'proposal', 'ProposalVerified', '{"verdict":"NotConfigured"}'::jsonb
);

set local role authenticated;
set local request.jwt.claim.sub = 'dddddddd-dddd-4ddd-8ddd-ddddddddddd2';
set local request.jwt.claims = '{"sub":"dddddddd-dddd-4ddd-8ddd-ddddddddddd2"}';
select public.approve_proposal('dddddddd-dddd-4ddd-8ddd-ddddddddddd8');

select is(
  (select decision_id::text from public.harness_artifacts where id = 'dddddddd-dddd-4ddd-8ddd-ddddddddddd7'),
  'dddddddd-dddd-4ddd-8ddd-ddddddddddd5',
  'the compiled rule is linked to the decision'
);
select is(
  (select adr_id from public.harness_artifacts where id = 'dddddddd-dddd-4ddd-8ddd-ddddddddddd7'),
  'ADR-0006',
  'the projection keeps the ADR id'
);
select is(
  (select surface from public.harness_artifacts where id = 'dddddddd-dddd-4ddd-8ddd-ddddddddddd7'),
  'cursor_rule',
  'the artifact is a cursor rule'
);
select is(
  (select globs::text from public.harness_artifacts where id = 'dddddddd-dddd-4ddd-8ddd-ddddddddddd7'),
  '{apps/web/**}',
  'the rule is path scoped'
);
select is(
  (select body from public.harness_artifacts where id = 'dddddddd-dddd-4ddd-8ddd-ddddddddddd7'),
  $body$---
description: "ADR-0006 — The web app does not import an LLM SDK or Koog."
globs: apps/web/**
alwaysApply: false

The web app does not import an LLM SDK or Koog.

Cites ADR-0006.
$body$,
  'the projection stores the rule text'
);
select throws_ok(
  $$update public.harness_artifacts set body = 'rewritten'$$,
  '42501',
  null,
  'a member cannot update the harness projection'
);

set local request.jwt.claim.sub = 'dddddddd-dddd-4ddd-8ddd-ddddddddddd3';
set local request.jwt.claims = '{"sub":"dddddddd-dddd-4ddd-8ddd-ddddddddddd3"}';
select is_empty(
  $$select * from public.harness_artifacts$$,
  'a user outside the organization reads no rules'
);

set local role horizon_writer;
set local request.jwt.claims = '{"role":"horizon_writer","sub":"dddddddd-dddd-4ddd-8ddd-ddddddddddd4"}';
select public.append_writer_event(
  'dddddddd-dddd-4ddd-8ddd-ddddddddddd1',
  'dddddddd-dddd-4ddd-8ddd-ddddddddddd9',
  'proposal', 'ProposalCreated',
  jsonb_build_object(
    'kind', 'compile_harness',
    'decision_id', 'dddddddd-dddd-4ddd-8ddd-ddddddddddd5',
    'candidate', jsonb_build_object(
      'stream_id', 'dddddddd-dddd-4ddd-8ddd-ddddddddddda',
      'decision_id', 'dddddddd-dddd-4ddd-8ddd-ddddddddddd5',
      'adr_id', 'ADR-0006',
      'surface', 'cursor_rule',
      'globs', jsonb_build_array('apps/web/**'),
      'body', 'Cites ADR-00060.'
    )
  )
);
select public.append_writer_event(
  'dddddddd-dddd-4ddd-8ddd-ddddddddddd1',
  'dddddddd-dddd-4ddd-8ddd-ddddddddddd9',
  'proposal', 'ProposalVerified', '{"verdict":"NotConfigured"}'::jsonb
);

set local role authenticated;
set local request.jwt.claim.sub = 'dddddddd-dddd-4ddd-8ddd-ddddddddddd2';
set local request.jwt.claims = '{"sub":"dddddddd-dddd-4ddd-8ddd-ddddddddddd2"}';
select throws_ok(
  $$select public.approve_proposal('dddddddd-dddd-4ddd-8ddd-ddddddddddd9')$$,
  '22023',
  null,
  'a rule that only mentions ADR-00060 does not cite ADR-0006'
);
select is(
  (select status from public.proposals where id = 'dddddddd-dddd-4ddd-8ddd-ddddddddddd9'),
  'verified',
  'a refused compile leaves the proposal verified'
);

reset role;
select set_config('horizon.grant_role', 'approve_proposal', true);
select set_config('horizon.actor_id', 'dddddddd-dddd-4ddd-8ddd-ddddddddddd2', true);
select throws_ok(
  $$insert into public.events (
    org_id, stream_id, stream_type, version, event_type, schema_version, payload
  ) values (
    'dddddddd-dddd-4ddd-8ddd-ddddddddddd1',
    'dddddddd-dddd-4ddd-8ddd-dddddddddddb',
    'harness', 1, 'HarnessCompiled', 1,
    '{"stream_id":"dddddddd-dddd-4ddd-8ddd-dddddddddddb"}'::jsonb
  )$$,
  '22023',
  null,
  'HarnessCompiled without a decision id is refused'
);

select private.rebuild_projections();
select private.rebuild_projections();
select results_eq(
  $$select id::text, adr_id, surface from public.harness_artifacts
    where org_id = 'dddddddd-dddd-4ddd-8ddd-ddddddddddd1'
    order by id$$,
  $$values ('dddddddd-dddd-4ddd-8ddd-ddddddddddd7', 'ADR-0006', 'cursor_rule')$$,
  'folding the same events twice yields the same rule'
);

select * from finish();
rollback;
