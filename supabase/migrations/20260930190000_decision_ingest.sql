-- WP-03 on the decision projection that is already on main.
-- DecisionProposed keeps globs empty. DecisionAccepted, appended by approve_proposal,
-- is what stores governing globs. The grant trigger is not edited.

insert into public.event_type_grants (role_name, event_type)
values
  ('horizon_writer', 'ProposalCreated'),
  ('horizon_writer', 'ProposalVerified'),
  ('approve_proposal', 'ProposalApproved'),
  ('approve_proposal', 'DecisionAccepted'),
  ('approve_proposal', 'DecisionSuperseded'),
  ('reject_proposal', 'ProposalRejected'),
  ('reject_proposal', 'DecisionRejected');

create table public.proposals (
  id uuid primary key,
  org_id uuid not null,
  kind text not null,
  status text not null,
  verdict text,
  decision_id uuid,
  supersedes uuid,
  created_at timestamptz not null,
  constraint proposals_org_id_fkey
    foreign key (org_id) references public.organizations (id)
    deferrable initially immediate,
  constraint proposals_kind_check
    check (kind in (
      'accept_decision', 'reject_decision', 'supersede', 'compile_harness', 'review_violations'
    )),
  constraint proposals_status_check
    check (status in ('proposed', 'verified', 'approved', 'rejected'))
);

create index proposals_org_id_idx on public.proposals (org_id);

create or replace function private.apply_proposal_event(
  p_org_id uuid,
  p_stream_id uuid,
  p_stream_type text,
  p_event_type text,
  p_payload jsonb,
  p_occurred_at timestamptz
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  kind text;
begin
  if p_event_type = 'ProposalCreated' then
    if p_stream_type <> 'proposal' then
      raise exception 'ProposalCreated requires stream_type proposal' using errcode = '22023';
    end if;
    kind := p_payload ->> 'kind';
    if kind is null or kind not in (
      'accept_decision', 'reject_decision', 'supersede', 'compile_harness', 'review_violations'
    ) then
      raise exception 'ProposalCreated requires a known kind' using errcode = '22023';
    end if;
    insert into public.proposals (id, org_id, kind, status, decision_id, supersedes, created_at)
    values (
      p_stream_id,
      p_org_id,
      kind,
      'proposed',
      nullif(p_payload ->> 'decision_id', '')::uuid,
      nullif(p_payload ->> 'supersedes', '')::uuid,
      p_occurred_at
    );
  elsif p_event_type = 'ProposalVerified' then
    update public.proposals
    set status = 'verified',
        verdict = nullif(p_payload ->> 'verdict', '')
    where id = p_stream_id
      and org_id = p_org_id
      and status = 'proposed';
    if not found then
      raise exception 'ProposalVerified requires a proposed proposal' using errcode = '22023';
    end if;
  elsif p_event_type = 'ProposalApproved' then
    update public.proposals
    set status = 'approved'
    where id = p_stream_id
      and org_id = p_org_id
      and status = 'verified';
    if not found then
      raise exception 'ProposalApproved requires a verified proposal' using errcode = '22023';
    end if;
  elsif p_event_type = 'ProposalRejected' then
    update public.proposals
    set status = 'rejected'
    where id = p_stream_id
      and org_id = p_org_id
      and status = 'verified';
    if not found then
      raise exception 'ProposalRejected requires a verified proposal' using errcode = '22023';
    end if;
  end if;
end;
$$;

create or replace function private.fold_proposal_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.apply_proposal_event(
    new.org_id, new.stream_id, new.stream_type, new.event_type, new.payload, new.occurred_at
  );
  return new;
end;
$$;

create trigger events_fold_proposal
  before insert on public.events
  for each row
  execute function private.fold_proposal_event();

create or replace function private.rebuild_projections()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  rec public.events;
begin
  execute 'set constraints public.events_org_id_fkey, public.proposals_org_id_fkey deferred';
  delete from public.proposals;
  delete from public.checks;
  delete from public.decisions;
  delete from public.memberships;
  delete from public.organizations;

  for rec in
    select *
    from public.events
    order by occurred_at, id
  loop
    perform private.apply_event(
      rec.org_id, rec.stream_id, rec.stream_type, rec.event_type, rec.payload, rec.occurred_at, rec.id
    );
    perform private.apply_proposal_event(
      rec.org_id, rec.stream_id, rec.stream_type, rec.event_type, rec.payload, rec.occurred_at
    );
  end loop;
end;
$$;

create or replace function private.next_event_version(p_stream_id uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  next_version integer;
begin
  perform pg_advisory_xact_lock(hashtextextended(p_stream_id::text, 0));
  select coalesce(max(e.version), 0) + 1
  into next_version
  from public.events as e
  where e.stream_id = p_stream_id;
  return next_version;
end;
$$;

create or replace function private.next_occurred_at()
returns timestamptz
language sql
volatile
security definer
set search_path = ''
as $$
  select greatest(
    clock_timestamp(),
    coalesce((select max(e.occurred_at) from public.events as e), '-infinity'::timestamptz)
      + interval '1 microsecond'
  );
$$;

create or replace function public.append_writer_event(
  p_org_id uuid,
  p_stream_id uuid,
  p_stream_type text,
  p_event_type text,
  p_payload jsonb
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  claims jsonb;
  actor uuid;
  next_version integer;
begin
  begin
    claims := nullif(current_setting('request.jwt.claims', true), '')::jsonb;
    actor := nullif(claims ->> 'sub', '')::uuid;
  exception
    when invalid_text_representation or invalid_parameter_value then
      actor := null;
  end;
  if actor is null then
    raise exception 'writer JWT has no usable sub claim' using errcode = '42501';
  end if;
  if p_event_type not in ('ProposalCreated', 'ProposalVerified', 'DecisionProposed') then
    raise exception 'event type % is not granted to horizon_writer', p_event_type
      using errcode = '42501';
  end if;
  if jsonb_typeof(p_payload) is distinct from 'object' then
    raise exception 'payload must be a JSON object' using errcode = '22023';
  end if;

  perform set_config('horizon.grant_role', 'horizon_writer', true);
  perform set_config('horizon.actor_id', actor::text, true);
  next_version := private.next_event_version(p_stream_id);
  insert into public.events (
    org_id, stream_id, stream_type, version, event_type, schema_version, payload, actor_id, occurred_at
  )
  values (
    p_org_id, p_stream_id, p_stream_type, next_version,
    p_event_type, 1, p_payload, actor, private.next_occurred_at()
  );
  perform set_config('horizon.grant_role', '', true);
  return next_version;
end;
$$;

create or replace function public.approve_proposal(p_proposal_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  prop public.proposals;
  uid uuid;
  draft jsonb;
  old_adr text;
begin
  uid := (select auth.uid());
  if uid is null then
    raise exception 'caller has no member session' using errcode = '42501';
  end if;

  select *
  into prop
  from public.proposals
  where id = p_proposal_id;
  if not found then
    raise exception 'proposal % not found', p_proposal_id using errcode = 'P0002';
  end if;
  if not private.is_member(prop.org_id) then
    raise exception 'caller is not a member of the organization' using errcode = '42501';
  end if;
  if prop.status <> 'verified' then
    raise exception 'proposal is not verified' using errcode = '22023';
  end if;
  if prop.kind not in ('accept_decision', 'supersede') then
    raise exception 'kind % is not approved by approve_proposal', prop.kind using errcode = '22023';
  end if;

  select e.payload
  into draft
  from public.events as e
  where e.stream_id = prop.decision_id
    and e.event_type = 'DecisionProposed'
  order by e.version desc
  limit 1;
  if draft is null or nullif(draft ->> 'adr_id', '') is null then
    raise exception 'the decision draft has no adr_id' using errcode = '22023';
  end if;

  perform set_config('horizon.grant_role', 'approve_proposal', true);
  perform set_config('horizon.actor_id', uid::text, true);
  perform pg_advisory_xact_lock(hashtextextended(prop.id::text, 0));

  insert into public.events (
    org_id, stream_id, stream_type, version, event_type, schema_version, payload, actor_id, occurred_at
  )
  values (
    prop.org_id, prop.id, 'proposal', private.next_event_version(prop.id),
    'ProposalApproved', 1, jsonb_build_object('kind', prop.kind),
    uid, private.next_occurred_at()
  );

  if prop.kind = 'supersede' then
    select d.adr_id into old_adr
    from public.decisions as d
    where d.id = prop.supersedes
      and d.status = 'accepted';
    if old_adr is null then
      raise exception 'supersede requires an accepted decision' using errcode = '22023';
    end if;
    insert into public.events (
      org_id, stream_id, stream_type, version, event_type, schema_version, payload, actor_id, occurred_at
    )
    values (
      prop.org_id, prop.supersedes, 'decision', private.next_event_version(prop.supersedes),
      'DecisionSuperseded', 1, jsonb_build_object('adr_id', old_adr),
      uid, private.next_occurred_at()
    );
  end if;

  insert into public.events (
    org_id, stream_id, stream_type, version, event_type, schema_version, payload, actor_id, occurred_at
  )
  values (
    prop.org_id, prop.decision_id, 'decision', private.next_event_version(prop.decision_id),
    'DecisionAccepted', 1, draft,
    uid, private.next_occurred_at()
  );

  perform set_config('horizon.grant_role', '', true);
end;
$$;

create view public.governing_globs
with (security_invoker = true) as
select
  d.id as decision_id,
  d.org_id,
  d.adr_id,
  g.glob
from public.decisions as d
cross join lateral jsonb_array_elements_text(d.globs) as g(glob)
where d.status = 'accepted';

revoke all on function private.apply_proposal_event(uuid, uuid, text, text, jsonb, timestamptz) from public;
revoke all on function private.fold_proposal_event() from public;
revoke all on function private.next_event_version(uuid) from public;
revoke all on function private.next_occurred_at() from public;

revoke all on function public.append_writer_event(uuid, uuid, text, text, jsonb)
  from public, anon, authenticated, service_role;
grant execute on function public.append_writer_event(uuid, uuid, text, text, jsonb) to horizon_writer;

revoke all on function public.approve_proposal(uuid)
  from public, anon, service_role, horizon_writer, horizon_ci;
grant execute on function public.approve_proposal(uuid) to authenticated;

alter table public.proposals enable row level security;
revoke all on table public.proposals from anon, authenticated, service_role, horizon_writer, horizon_ci;
grant select on table public.proposals to authenticated;

create policy proposals_select_member
  on public.proposals
  for select
  to authenticated
  using (private.is_member(org_id));

revoke all on table public.governing_globs from public, anon, service_role;
grant select on table public.governing_globs to authenticated, horizon_ci;

grant select on table public.decisions to horizon_ci;

create policy decisions_select_ci
  on public.decisions
  for select
  to horizon_ci
  using (status = 'accepted');
