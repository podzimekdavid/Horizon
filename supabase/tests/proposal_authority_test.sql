begin;
select plan(34);

-- pgTAP lives in extensions. horizon_writer has no USAGE on that schema, so
-- assertions after SET ROLE would not resolve. The grant rolls back with the test.
grant usage on schema extensions to horizon_writer;

insert into auth.users (id, email)
values
  ('cccccccc-cccc-4ccc-8ccc-ccccccccccc2', 'proposal-member@horizon.local'),
  ('cccccccc-cccc-4ccc-8ccc-ccccccccccc3', 'proposal-outsider@horizon.local');

select set_config('horizon.actor_id', 'cccccccc-cccc-4ccc-8ccc-ccccccccccc2', true);
select set_config('horizon.grant_role', '', true);

insert into public.events (
  org_id, stream_id, stream_type, version, event_type, schema_version, payload, actor_id, occurred_at
)
values
  (
    'cccccccc-cccc-4ccc-8ccc-ccccccccccc1',
    'cccccccc-cccc-4ccc-8ccc-ccccccccccc1',
    'organization', 1, 'OrganizationCreated', 1,
    '{"name":"Proposal Org"}'::jsonb,
    'cccccccc-cccc-4ccc-8ccc-ccccccccccc2',
    '2026-01-02T00:00:00Z'
  ),
  (
    'cccccccc-cccc-4ccc-8ccc-ccccccccccc1',
    'cccccccc-cccc-4ccc-8ccc-cccccccccc10',
    'membership', 1, 'MemberAdded', 1,
    '{"user_id":"cccccccc-cccc-4ccc-8ccc-ccccccccccc2"}'::jsonb,
    'cccccccc-cccc-4ccc-8ccc-ccccccccccc2',
    '2026-01-02T00:00:01Z'
  );

select ok(
  exists (
    select 1 from public.event_type_grants
    where role_name = 'horizon_writer' and event_type = 'ProposalCreated'
  )
  and exists (
    select 1 from public.event_type_grants
    where role_name = 'horizon_writer' and event_type = 'ProposalVerified'
  )
  and exists (
    select 1 from public.event_type_grants
    where role_name = 'horizon_writer' and event_type = 'DecisionProposed'
  ),
  'horizon_writer is granted ProposalCreated, ProposalVerified, and DecisionProposed'
);
select ok(
  not exists (
    select 1 from public.event_type_grants
    where role_name = 'horizon_writer'
      and event_type in (
        'ProposalApproved', 'ProposalRejected', 'DecisionAccepted',
        'DecisionSuperseded', 'HarnessCompiled', 'CheckRecorded'
      )
  ),
  'horizon_writer is not granted approval or domain events'
);
select ok(
  exists (
    select 1 from public.event_type_grants
    where role_name = 'approve_proposal' and event_type = 'ProposalApproved'
  )
  and exists (
    select 1 from public.event_type_grants
    where role_name = 'approve_proposal' and event_type = 'DecisionAccepted'
  ),
  'approve_proposal is granted ProposalApproved and DecisionAccepted'
);
select ok(
  has_function_privilege('horizon_writer', 'public.append_writer_event(uuid, uuid, text, text, jsonb)', 'execute')
  and not has_function_privilege('authenticated', 'public.append_writer_event(uuid, uuid, text, text, jsonb)', 'execute')
  and has_function_privilege('authenticated', 'public.approve_proposal(uuid)', 'execute')
  and has_function_privilege('authenticated', 'public.reject_proposal(uuid)', 'execute')
  and not has_function_privilege('horizon_writer', 'public.approve_proposal(uuid)', 'execute')
  and not has_function_privilege('service_role', 'public.approve_proposal(uuid)', 'execute')
  and not has_function_privilege('service_role', 'public.reject_proposal(uuid)', 'execute'),
  'only a member calls approve_proposal and reject_proposal, and only the writer appends drafts'
);

set local role horizon_writer;
set local request.jwt.claims = '{"role":"horizon_writer","sub":"cccccccc-cccc-4ccc-8ccc-ccccccccccc4"}';

select is(
  public.append_writer_event(
    'cccccccc-cccc-4ccc-8ccc-ccccccccccc1',
    'cccccccc-cccc-4ccc-8ccc-ccccccccccc5',
    'decision',
    'DecisionProposed',
    '{"adr_id":"ADR-001","constraint":"no client update","actor_id":"cccccccc-cccc-4ccc-8ccc-ccccccccccc3"}'::jsonb
  )::text,
  '1'::text,
  'horizon_writer appends DecisionProposed'::text
);
select is(
  public.append_writer_event(
    'cccccccc-cccc-4ccc-8ccc-ccccccccccc1',
    'cccccccc-cccc-4ccc-8ccc-ccccccccccc6',
    'proposal',
    'ProposalCreated',
    '{"kind":"accept_decision","decision_id":"cccccccc-cccc-4ccc-8ccc-ccccccccccc5"}'::jsonb
  )::text,
  '1'::text,
  'horizon_writer appends ProposalCreated'::text
);
select is(
  public.append_writer_event(
    'cccccccc-cccc-4ccc-8ccc-ccccccccccc1',
    'cccccccc-cccc-4ccc-8ccc-ccccccccccc6',
    'proposal',
    'ProposalVerified',
    '{"verdict":"NotConfigured"}'::jsonb
  )::text,
  '2'::text,
  'horizon_writer appends ProposalVerified'::text
);
select throws_ok(
  $$select public.append_writer_event(
      'cccccccc-cccc-4ccc-8ccc-ccccccccccc1',
      'cccccccc-cccc-4ccc-8ccc-ccccccccccc6',
      'proposal', 'ProposalApproved', '{"kind":"accept_decision"}'::jsonb
    )$$,
  '42501',
  null,
  'the writer function refuses ProposalApproved'
);
select throws_ok(
  $$insert into public.events (
      org_id, stream_id, stream_type, version, event_type, schema_version, payload, actor_id
    ) values (
      'cccccccc-cccc-4ccc-8ccc-ccccccccccc1',
      'cccccccc-cccc-4ccc-8ccc-ccccccccccc6',
      'proposal', 9, 'ProposalApproved', 1, '{}'::jsonb,
      'cccccccc-cccc-4ccc-8ccc-ccccccccccc4'
    )$$,
  '42501',
  null,
  'horizon_writer cannot insert ProposalApproved'
);
select throws_ok(
  $$insert into public.events (
      org_id, stream_id, stream_type, version, event_type, schema_version, payload, actor_id
    ) values (
      'cccccccc-cccc-4ccc-8ccc-ccccccccccc1',
      'cccccccc-cccc-4ccc-8ccc-ccccccccccc5',
      'decision', 9, 'DecisionAccepted', 1, '{}'::jsonb,
      'cccccccc-cccc-4ccc-8ccc-ccccccccccc4'
    )$$,
  '42501',
  null,
  'horizon_writer cannot insert DecisionAccepted'
);

set local role authenticated;
set local request.jwt.claim.sub = 'cccccccc-cccc-4ccc-8ccc-ccccccccccc2';
set local request.jwt.claims = '{"sub":"cccccccc-cccc-4ccc-8ccc-ccccccccccc2"}';

select results_eq(
  $$select status, verdict from public.proposals
    where id = 'cccccccc-cccc-4ccc-8ccc-ccccccccccc6'$$,
  $$values ('verified'::text, 'NotConfigured'::text)$$,
  'verification records NotConfigured on the proposal'
);
select is(
  (select status from public.decisions where id = 'cccccccc-cccc-4ccc-8ccc-ccccccccccc5'),
  'proposed'::text,
  'a draft stays proposed until a member approves'::text
);
select is(
  (select actor_id::text from public.events
    where stream_id = 'cccccccc-cccc-4ccc-8ccc-ccccccccccc5' and event_type = 'DecisionProposed'),
  'cccccccc-cccc-4ccc-8ccc-ccccccccccc4'::text,
  'the stored actor is the writer JWT sub, not the payload'::text
);
select throws_ok(
  $$insert into public.events (
      org_id, stream_id, stream_type, version, event_type, schema_version, payload, actor_id
    ) values (
      'cccccccc-cccc-4ccc-8ccc-ccccccccccc1',
      'cccccccc-cccc-4ccc-8ccc-ccccccccccc6',
      'proposal', 9, 'ProposalApproved', 1, '{}'::jsonb,
      'cccccccc-cccc-4ccc-8ccc-ccccccccccc2'
    )$$,
  '42501',
  null,
  'a member cannot insert ProposalApproved'
);

select lives_ok(
  $$select public.approve_proposal('cccccccc-cccc-4ccc-8ccc-ccccccccccc6')$$,
  'a member approves a verified accept_decision proposal'
);
select results_eq(
  $$select event_type, actor_id::text
    from public.events
    where stream_id = 'cccccccc-cccc-4ccc-8ccc-ccccccccccc6'
    order by version$$,
  $$values
    ('ProposalCreated', 'cccccccc-cccc-4ccc-8ccc-ccccccccccc4'),
    ('ProposalVerified', 'cccccccc-cccc-4ccc-8ccc-ccccccccccc4'),
    ('ProposalApproved', 'cccccccc-cccc-4ccc-8ccc-ccccccccccc2')$$,
  'approval appends ProposalApproved as the member'
);
select results_eq(
  $$select event_type from public.events
    where stream_id = 'cccccccc-cccc-4ccc-8ccc-ccccccccccc5'
    order by version$$,
  array['DecisionProposed', 'DecisionAccepted'],
  'approval appends DecisionAccepted on the decision stream'
);
select is(
  (select status from public.decisions where id = 'cccccccc-cccc-4ccc-8ccc-ccccccccccc5'),
  'accepted'::text,
  'the decision projection status becomes accepted'::text
);
select is(
  (select verdict from public.proposals where id = 'cccccccc-cccc-4ccc-8ccc-ccccccccccc6'),
  'NotConfigured'::text,
  'approval leaves the NotConfigured gap visible'::text
);
select throws_ok(
  $$update public.decisions set status = 'proposed'$$,
  '42501',
  null,
  'a member cannot update the decision projection'
);
select throws_ok(
  $$select public.approve_proposal('cccccccc-cccc-4ccc-8ccc-ccccccccccc6')$$,
  '22023',
  null,
  'a second approval is refused'
);

set local request.jwt.claim.sub = 'cccccccc-cccc-4ccc-8ccc-ccccccccccc3';
set local request.jwt.claims = '{"sub":"cccccccc-cccc-4ccc-8ccc-ccccccccccc3"}';
select is_empty(
  $$select * from public.decisions$$,
  'a user outside the organization reads no decisions'
);
select throws_ok(
  $$select public.approve_proposal('cccccccc-cccc-4ccc-8ccc-ccccccccccc6')$$,
  '42501',
  null,
  'an outsider cannot approve'
);

-- A second draft is rejected.
set local role horizon_writer;
set local request.jwt.claims = '{"role":"horizon_writer","sub":"cccccccc-cccc-4ccc-8ccc-ccccccccccc4"}';
select public.append_writer_event(
  'cccccccc-cccc-4ccc-8ccc-ccccccccccc1',
  'cccccccc-cccc-4ccc-8ccc-ccccccccccc7',
  'decision', 'DecisionProposed', '{"adr_id":"ADR-002"}'::jsonb
);
select public.append_writer_event(
  'cccccccc-cccc-4ccc-8ccc-ccccccccccc1',
  'cccccccc-cccc-4ccc-8ccc-ccccccccccc8',
  'proposal', 'ProposalCreated',
  '{"kind":"accept_decision","decision_id":"cccccccc-cccc-4ccc-8ccc-ccccccccccc7"}'::jsonb
);
select public.append_writer_event(
  'cccccccc-cccc-4ccc-8ccc-ccccccccccc1',
  'cccccccc-cccc-4ccc-8ccc-ccccccccccc8',
  'proposal', 'ProposalVerified', '{"verdict":"NotConfigured"}'::jsonb
);

set local role authenticated;
set local request.jwt.claim.sub = 'cccccccc-cccc-4ccc-8ccc-ccccccccccc2';
set local request.jwt.claims = '{"sub":"cccccccc-cccc-4ccc-8ccc-ccccccccccc2"}';
select lives_ok(
  $$select public.reject_proposal('cccccccc-cccc-4ccc-8ccc-ccccccccccc8')$$,
  'reject_proposal rejects a decision draft'
);
select results_eq(
  $$select event_type from public.events
    where stream_id in (
      'cccccccc-cccc-4ccc-8ccc-ccccccccccc8',
      'cccccccc-cccc-4ccc-8ccc-ccccccccccc7'
    )
    and event_type in ('ProposalRejected', 'DecisionRejected')
    order by event_type$$,
  array['DecisionRejected', 'ProposalRejected'],
  'rejection appends ProposalRejected and DecisionRejected'
);
select is(
  (select status from public.decisions where id = 'cccccccc-cccc-4ccc-8ccc-ccccccccccc7'),
  'rejected'::text,
  'the decision projection status becomes rejected'::text
);

-- Supersede the accepted decision.
set local role horizon_writer;
select public.append_writer_event(
  'cccccccc-cccc-4ccc-8ccc-ccccccccccc1',
  'cccccccc-cccc-4ccc-8ccc-ccccccccccc9',
  'decision', 'DecisionProposed', '{"adr_id":"ADR-003"}'::jsonb
);
select public.append_writer_event(
  'cccccccc-cccc-4ccc-8ccc-ccccccccccc1',
  'cccccccc-cccc-4ccc-8ccc-ccccccccccca',
  'proposal', 'ProposalCreated',
  '{"kind":"supersede","decision_id":"cccccccc-cccc-4ccc-8ccc-ccccccccccc9","supersedes":"cccccccc-cccc-4ccc-8ccc-ccccccccccc5"}'::jsonb
);
select public.append_writer_event(
  'cccccccc-cccc-4ccc-8ccc-ccccccccccc1',
  'cccccccc-cccc-4ccc-8ccc-ccccccccccca',
  'proposal', 'ProposalVerified', '{"verdict":"NotConfigured"}'::jsonb
);

set local role authenticated;
set local request.jwt.claim.sub = 'cccccccc-cccc-4ccc-8ccc-ccccccccccc2';
set local request.jwt.claims = '{"sub":"cccccccc-cccc-4ccc-8ccc-ccccccccccc2"}';
select lives_ok(
  $$select public.approve_proposal('cccccccc-cccc-4ccc-8ccc-ccccccccccca')$$,
  'a member approves a supersede proposal'
);
select results_eq(
  $$select id::text, status from public.decisions
    where id in (
      'cccccccc-cccc-4ccc-8ccc-ccccccccccc5',
      'cccccccc-cccc-4ccc-8ccc-ccccccccccc9'
    )
    order by id$$,
  $$values
    ('cccccccc-cccc-4ccc-8ccc-ccccccccccc5', 'superseded'),
    ('cccccccc-cccc-4ccc-8ccc-ccccccccccc9', 'accepted')$$,
  'supersede marks the old decision superseded and the new one accepted'
);

-- Compiling copies the candidate. A harness stream that is the decision stream rolls back.
set local role horizon_writer;
select public.append_writer_event(
  'cccccccc-cccc-4ccc-8ccc-ccccccccccc1',
  'cccccccc-cccc-4ccc-8ccc-cccccccccccd',
  'proposal', 'ProposalCreated',
  '{"kind":"compile_harness","decision_id":"cccccccc-cccc-4ccc-8ccc-ccccccccccc9","candidate":{"stream_id":"cccccccc-cccc-4ccc-8ccc-ccccccccccc9","decision_id":"cccccccc-cccc-4ccc-8ccc-ccccccccccc9"}}'::jsonb
);
select public.append_writer_event(
  'cccccccc-cccc-4ccc-8ccc-ccccccccccc1',
  'cccccccc-cccc-4ccc-8ccc-cccccccccccd',
  'proposal', 'ProposalVerified', '{"verdict":"NotConfigured"}'::jsonb
);
set local role authenticated;
set local request.jwt.claim.sub = 'cccccccc-cccc-4ccc-8ccc-ccccccccccc2';
set local request.jwt.claims = '{"sub":"cccccccc-cccc-4ccc-8ccc-ccccccccccc2"}';
select throws_ok(
  $$select public.approve_proposal('cccccccc-cccc-4ccc-8ccc-cccccccccccd')$$,
  '22023',
  null,
  'approval refuses a harness stream that already belongs to the decision'
);
select is(
  (select status from public.proposals where id = 'cccccccc-cccc-4ccc-8ccc-cccccccccccd'),
  'verified'::text,
  'a failed approval rolls back and leaves the proposal verified'::text
);

set local role horizon_writer;
select public.append_writer_event(
  'cccccccc-cccc-4ccc-8ccc-ccccccccccc1',
  'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
  'proposal', 'ProposalCreated',
  '{"kind":"compile_harness","decision_id":"cccccccc-cccc-4ccc-8ccc-ccccccccccc9","candidate":{"stream_id":"cccccccc-cccc-4ccc-8ccc-cccccccccccb","decision_id":"cccccccc-cccc-4ccc-8ccc-ccccccccccc9"}}'::jsonb
);
select public.append_writer_event(
  'cccccccc-cccc-4ccc-8ccc-ccccccccccc1',
  'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
  'proposal', 'ProposalVerified', '{"verdict":"NotConfigured"}'::jsonb
);
set local role authenticated;
set local request.jwt.claim.sub = 'cccccccc-cccc-4ccc-8ccc-ccccccccccc2';
set local request.jwt.claims = '{"sub":"cccccccc-cccc-4ccc-8ccc-ccccccccccc2"}';
select lives_ok(
  $$select public.approve_proposal('cccccccc-cccc-4ccc-8ccc-cccccccccccc')$$,
  'a member approves compile_harness'
);
select is(
  (select payload ->> 'decision_id' from public.events where event_type = 'HarnessCompiled'),
  'cccccccc-cccc-4ccc-8ccc-ccccccccccc9'::text,
  'HarnessCompiled copies the candidate already stored on the proposal'::text
);
select is(
  (select status from public.decisions where id = 'cccccccc-cccc-4ccc-8ccc-ccccccccccc9'),
  'accepted'::text,
  'compiling the harness does not change the decision'::text
);

reset role;
select private.rebuild_projections();
select private.rebuild_projections();
select results_eq(
  $$select id::text, status from public.decisions
    where org_id = 'cccccccc-cccc-4ccc-8ccc-ccccccccccc1'
    order by id$$,
  $$values
    ('cccccccc-cccc-4ccc-8ccc-ccccccccccc5', 'superseded'),
    ('cccccccc-cccc-4ccc-8ccc-ccccccccccc7', 'rejected'),
    ('cccccccc-cccc-4ccc-8ccc-ccccccccccc9', 'accepted')$$,
  'folding the same events twice yields the same decision rows'
);

select * from finish();
rollback;
