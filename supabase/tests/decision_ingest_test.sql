begin;
select plan(9);

grant usage on schema extensions to horizon_writer, horizon_ci;

insert into auth.users (id, email)
values ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee2', 'ingest-member@horizon.local');

select set_config('horizon.actor_id', 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee2', true);
select set_config('horizon.grant_role', 'postgres', true);

insert into public.events (
  org_id, stream_id, stream_type, version, event_type, schema_version, payload, actor_id, occurred_at
)
values
  (
    'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee1',
    'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee1',
    'organization', 1, 'OrganizationCreated', 1,
    '{"name":"Ingest Org"}'::jsonb,
    'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee2',
    '2026-01-02T00:00:00Z'
  ),
  (
    'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee1',
    'eeeeeeee-eeee-4eee-8eee-eeeeeeeeee10',
    'membership', 1, 'MemberAdded', 1,
    '{"user_id":"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee2"}'::jsonb,
    'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee2',
    '2026-01-02T00:00:01Z'
  );

set local role horizon_writer;
set local request.jwt.claims = '{"role":"horizon_writer","sub":"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee4"}';

select public.append_writer_event(
  'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee1',
  'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee5',
  'decision', 'DecisionProposed',
  '{"adr_id":"ADR-0012","title":"Payments stay in the payments module","constraint":"Payments code lives under src/payments.","rejected_alternatives":["A shared billing helper."],"globs":["src/payments/**","src/checkout/**"]}'::jsonb
);
select public.append_writer_event(
  'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee1',
  'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee6',
  'proposal', 'ProposalCreated',
  '{"kind":"accept_decision","decision_id":"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee5"}'::jsonb
);
select public.append_writer_event(
  'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee1',
  'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee6',
  'proposal', 'ProposalVerified',
  '{"verdict":"NotConfigured"}'::jsonb
);

set local role authenticated;
set local request.jwt.claim.sub = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee2';
set local request.jwt.claims = '{"sub":"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee2"}';

select results_eq(
  $$select status, globs::text from public.decisions
    where id = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee5'$$,
  $$values ('proposed'::text, '[]'::text)$$,
  'a draft keeps the suggested globs off the governing projection'
);
select is_empty(
  $$select glob from public.governing_globs
    where decision_id = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee5'$$,
  'CI read returns no glob for a proposed decision'
);

set local role horizon_ci;
select is_empty(
  $$select id from public.decisions
    where id = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee5'$$,
  'CI cannot read a still-proposed decision'
);

set local role authenticated;
set local request.jwt.claim.sub = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee2';
set local request.jwt.claims = '{"sub":"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee2"}';

select lives_ok(
  $$select public.approve_proposal('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee6')$$,
  'a member approves the draft'
);
select results_eq(
  $$select event_type from public.events
    where stream_id = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee5'
    order by version$$,
  array['DecisionProposed', 'DecisionAccepted'],
  'approval appends DecisionAccepted on the decision stream'
);
select results_eq(
  $$select status, globs from public.decisions
    where id = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee5'$$,
  $$values ('accepted'::text, '["src/payments/**","src/checkout/**"]'::jsonb)$$,
  'the projection shows the globs as governing'
);

set local role horizon_writer;
set local request.jwt.claims = '{"role":"horizon_writer","sub":"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee4"}';
select public.append_writer_event(
  'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee1',
  'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee7',
  'decision', 'DecisionProposed',
  '{"adr_id":"ADR-0013","title":"Checkout calls payments","globs":["src/checkout/**"]}'::jsonb
);
select public.append_writer_event(
  'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee1',
  'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee8',
  'proposal', 'ProposalCreated',
  '{"kind":"supersede","decision_id":"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee7","supersedes":"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee5"}'::jsonb
);
select public.append_writer_event(
  'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee1',
  'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee8',
  'proposal', 'ProposalVerified', '{"verdict":"NotConfigured"}'::jsonb
);

set local role authenticated;
set local request.jwt.claim.sub = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee2';
set local request.jwt.claims = '{"sub":"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee2"}';
select lives_ok(
  $$select public.approve_proposal('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee8')$$,
  'a member approves the supersede proposal'
);
select results_eq(
  $$select status, adr_id from public.decisions
    where id = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee5'$$,
  $$values ('superseded'::text, 'ADR-0012'::text)$$,
  'supersession leaves the old decision readable'
);
select is_empty(
  $$select glob from public.governing_globs
    where decision_id = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee5'$$,
  'a superseded decision contributes no governing glob'
);

select * from finish();
rollback;
