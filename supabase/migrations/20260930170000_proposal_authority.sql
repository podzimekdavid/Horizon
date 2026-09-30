-- WP-02: proposal grants, the proposal fold, and member approval.
-- The WP-01 trigger is not edited. A second BEFORE INSERT trigger folds proposal
-- and decision-status events. approve_proposal and reject_proposal append the
-- approval event and the domain event; they do not update projections.

insert into public.event_type_grants (role_name, event_type)
values
  ('horizon_writer', 'ProposalCreated'),
  ('horizon_writer', 'ProposalVerified'),
  ('horizon_writer', 'DecisionProposed'),
  ('approve_proposal', 'ProposalApproved'),
  ('approve_proposal', 'DecisionAccepted'),
  ('approve_proposal', 'DecisionSuperseded'),
  ('approve_proposal', 'HarnessCompiled'),
  ('reject_proposal', 'ProposalRejected'),
  ('reject_proposal', 'DecisionRejected');

-- Status only. WP-03 adds the constraint, rejected alternatives, and globs.
create table public.decisions (
  id uuid primary key,
  org_id uuid not null,
  status text not null,
  created_at timestamptz not null,
  constraint decisions_org_id_fkey
    foreign key (org_id) references public.organizations (id)
    deferrable initially immediate,
  constraint decisions_status_check
    check (status in ('proposed', 'accepted', 'rejected', 'superseded'))
);

create index decisions_org_id_idx on public.decisions (org_id);

create table public.proposals (
  id uuid primary key,
  org_id uuid not null,
  kind text not null,
  status text not null,
  verdict text,
  decision_id uuid,
  supersedes uuid,
  candidate jsonb,
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

-- Strictly after every stored event, so a replay ordered by occurred_at matches
-- the order the transaction appended.
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

create or replace function private.assert_stream_type(p_stream_id uuid, p_stream_type text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1
    from public.events as e
    where e.stream_id = p_stream_id
      and e.stream_type <> p_stream_type
  ) then
    raise exception 'stream % is not a % stream', p_stream_id, p_stream_type
      using errcode = '22023';
  end if;
end;
$$;

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
  decision_id uuid;
  supersedes uuid;
  candidate jsonb;
begin
  if p_event_type = 'DecisionProposed' then
    if p_stream_type <> 'decision' then
      raise exception 'DecisionProposed requires stream_type decision' using errcode = '22023';
    end if;
    insert into public.decisions (id, org_id, status, created_at)
    values (p_stream_id, p_org_id, 'proposed', p_occurred_at);
  elsif p_event_type = 'DecisionAccepted' then
    update public.decisions
    set status = 'accepted'
    where id = p_stream_id
      and org_id = p_org_id
      and status = 'proposed';
    if not found then
      raise exception 'DecisionAccepted requires a proposed decision' using errcode = '22023';
    end if;
  elsif p_event_type = 'DecisionRejected' then
    update public.decisions
    set status = 'rejected'
    where id = p_stream_id
      and org_id = p_org_id
      and status = 'proposed';
    if not found then
      raise exception 'DecisionRejected requires a proposed decision' using errcode = '22023';
    end if;
  elsif p_event_type = 'DecisionSuperseded' then
    update public.decisions
    set status = 'superseded'
    where id = p_stream_id
      and org_id = p_org_id
      and status = 'accepted';
    if not found then
      raise exception 'DecisionSuperseded requires an accepted decision' using errcode = '22023';
    end if;
  elsif p_event_type = 'ProposalCreated' then
    if p_stream_type <> 'proposal' then
      raise exception 'ProposalCreated requires stream_type proposal' using errcode = '22023';
    end if;
    kind := p_payload ->> 'kind';
    if kind is null or kind not in (
      'accept_decision', 'reject_decision', 'supersede', 'compile_harness', 'review_violations'
    ) then
      raise exception 'ProposalCreated requires a known kind' using errcode = '22023';
    end if;
    decision_id := nullif(p_payload ->> 'decision_id', '')::uuid;
    supersedes := nullif(p_payload ->> 'supersedes', '')::uuid;
    candidate := p_payload -> 'candidate';
    if jsonb_typeof(candidate) is distinct from 'object' then
      candidate := null;
    end if;
    insert into public.proposals (
      id, org_id, kind, status, decision_id, supersedes, candidate, created_at
    )
    values (
      p_stream_id, p_org_id, kind, 'proposed', decision_id, supersedes, candidate, p_occurred_at
    );
  elsif p_event_type = 'ProposalVerified' then
    if nullif(p_payload ->> 'verdict', '') is null then
      raise exception 'ProposalVerified requires payload.verdict' using errcode = '22023';
    end if;
    update public.proposals
    set status = 'verified',
        verdict = p_payload ->> 'verdict'
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
    new.org_id,
    new.stream_id,
    new.stream_type,
    new.event_type,
    new.payload,
    new.occurred_at
  );
  return new;
end;
$$;

create trigger events_fold_proposal
  before insert on public.events
  for each row
  execute function private.fold_proposal_event();

-- Replay must rebuild the projections this package added. The grant trigger
-- itself is unchanged.
create or replace function private.rebuild_projections()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  rec public.events;
begin
  execute 'set constraints public.events_org_id_fkey, public.proposals_org_id_fkey, public.decisions_org_id_fkey deferred';
  delete from public.proposals;
  delete from public.decisions;
  delete from public.memberships;
  delete from public.organizations;

  for rec in
    select *
    from public.events
    order by occurred_at, id
  loop
    perform private.apply_event(
      rec.org_id,
      rec.stream_id,
      rec.stream_type,
      rec.event_type,
      rec.payload,
      rec.occurred_at
    );
    perform private.apply_proposal_event(
      rec.org_id,
      rec.stream_id,
      rec.stream_type,
      rec.event_type,
      rec.payload,
      rec.occurred_at
    );
  end loop;
end;
$$;

create or replace function private.append_granted_event(
  p_org_id uuid,
  p_stream_id uuid,
  p_stream_type text,
  p_event_type text,
  p_payload jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  next_version integer;
begin
  if jsonb_typeof(p_payload) is distinct from 'object' then
    raise exception 'payload must be a JSON object' using errcode = '22023';
  end if;
  perform private.assert_stream_type(p_stream_id, p_stream_type);
  next_version := private.next_event_version(p_stream_id);
  insert into public.events (
    org_id, stream_id, stream_type, version, event_type, schema_version, payload, actor_id, occurred_at
  )
  values (
    p_org_id, p_stream_id, p_stream_type, next_version,
    p_event_type, 1, p_payload, '00000000-0000-4000-8000-000000000000',
    private.next_occurred_at()
  );
end;
$$;

create or replace function private.lock_streams(p_ids uuid[])
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  locked uuid;
begin
  for locked in
    select t.stream_id
    from unnest(p_ids) as t(stream_id)
    where t.stream_id is not null
    order by t.stream_id
  loop
    perform pg_advisory_xact_lock(hashtextextended(locked::text, 0));
  end loop;
end;
$$;

create or replace function private.proposal_for_member(p_proposal_id uuid)
returns public.proposals
language plpgsql
security definer
set search_path = ''
as $$
declare
  prop public.proposals;
  uid uuid;
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
  return prop;
end;
$$;

-- horizon_writer appends a draft, a verification, or DecisionProposed.
-- Approval event types are refused here and by the grant trigger.
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
  kind text;
  decision_id uuid;
  supersedes uuid;
  candidate jsonb;
  decision_status text;
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
  if jsonb_typeof(p_payload) is distinct from 'object' then
    raise exception 'payload must be a JSON object' using errcode = '22023';
  end if;
  if p_event_type not in ('ProposalCreated', 'ProposalVerified', 'DecisionProposed') then
    raise exception 'event type % is not granted to horizon_writer', p_event_type
      using errcode = '42501';
  end if;

  perform private.lock_streams(array[p_stream_id]);
  perform private.assert_stream_type(p_stream_id, p_stream_type);

  if p_event_type = 'DecisionProposed' then
    if p_stream_type <> 'decision' then
      raise exception 'DecisionProposed requires stream_type decision' using errcode = '22023';
    end if;
    if exists (select 1 from public.decisions as d where d.id = p_stream_id) then
      raise exception 'decision % already exists', p_stream_id using errcode = '22023';
    end if;
  elsif p_event_type = 'ProposalCreated' then
    if p_stream_type <> 'proposal' then
      raise exception 'ProposalCreated requires stream_type proposal' using errcode = '22023';
    end if;
    if exists (select 1 from public.proposals as p where p.id = p_stream_id) then
      raise exception 'proposal % already exists', p_stream_id using errcode = '22023';
    end if;
    kind := p_payload ->> 'kind';
    if kind is null or kind not in (
      'accept_decision', 'reject_decision', 'supersede', 'compile_harness', 'review_violations'
    ) then
      raise exception 'ProposalCreated requires a known kind' using errcode = '22023';
    end if;
    if kind <> 'review_violations' then
      begin
        decision_id := nullif(p_payload ->> 'decision_id', '')::uuid;
      exception
        when invalid_text_representation then
          raise exception 'payload.decision_id must be a uuid' using errcode = '22023';
      end;
      if decision_id is null then
        raise exception 'payload.decision_id is required' using errcode = '22023';
      end if;
      select d.status
      into decision_status
      from public.decisions as d
      where d.id = decision_id
        and d.org_id = p_org_id;
      if not found then
        raise exception 'decision % is not in this organization', decision_id
          using errcode = '22023';
      end if;
      if kind = 'compile_harness' then
        if decision_status <> 'accepted' then
          raise exception 'compile_harness requires an accepted decision' using errcode = '22023';
        end if;
        candidate := p_payload -> 'candidate';
        if jsonb_typeof(candidate) is distinct from 'object' then
          raise exception 'compile_harness requires payload.candidate' using errcode = '22023';
        end if;
        if nullif(candidate ->> 'stream_id', '') is null
          or nullif(candidate ->> 'decision_id', '') is null then
          raise exception 'candidate requires stream_id and decision_id' using errcode = '22023';
        end if;
        if (candidate ->> 'decision_id')::uuid is distinct from decision_id then
          raise exception 'candidate.decision_id must match payload.decision_id'
            using errcode = '22023';
        end if;
      elsif decision_status <> 'proposed' then
        raise exception 'the decision is not a draft' using errcode = '22023';
      end if;
      if kind = 'supersede' then
        begin
          supersedes := nullif(p_payload ->> 'supersedes', '')::uuid;
        exception
          when invalid_text_representation then
            raise exception 'payload.supersedes must be a uuid' using errcode = '22023';
        end;
        if supersedes is null or supersedes = decision_id then
          raise exception 'supersede requires a different payload.supersedes' using errcode = '22023';
        end if;
        select d.status
        into decision_status
        from public.decisions as d
        where d.id = supersedes
          and d.org_id = p_org_id;
        if decision_status is distinct from 'accepted' then
          raise exception 'supersede requires an accepted decision' using errcode = '22023';
        end if;
      end if;
    end if;
  elsif p_event_type = 'ProposalVerified' then
    if p_stream_type <> 'proposal' then
      raise exception 'ProposalVerified requires stream_type proposal' using errcode = '22023';
    end if;
    if nullif(p_payload ->> 'verdict', '') is null then
      raise exception 'ProposalVerified requires payload.verdict' using errcode = '22023';
    end if;
    if not exists (
      select 1
      from public.proposals as p
      where p.id = p_stream_id
        and p.org_id = p_org_id
        and p.status = 'proposed'
    ) then
      raise exception 'ProposalVerified requires a proposed proposal' using errcode = '22023';
    end if;
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
  candidate jsonb;
  harness_id uuid;
begin
  perform private.lock_streams(array[p_proposal_id]);
  prop := private.proposal_for_member(p_proposal_id);
  perform private.lock_streams(array[p_proposal_id, prop.decision_id, prop.supersedes]);
  prop := private.proposal_for_member(p_proposal_id);

  if prop.status <> 'verified' then
    raise exception 'proposal is not verified' using errcode = '22023';
  end if;
  if prop.kind in ('reject_decision', 'review_violations') then
    raise exception 'kind % is not approved by approve_proposal', prop.kind
      using errcode = '22023';
  end if;

  uid := (select auth.uid());
  perform set_config('horizon.grant_role', 'approve_proposal', true);
  perform set_config('horizon.actor_id', uid::text, true);

  perform private.append_granted_event(
    prop.org_id, prop.id, 'proposal', 'ProposalApproved',
    jsonb_build_object('kind', prop.kind)
  );

  if prop.kind = 'accept_decision' then
    select e.payload
    into draft
    from public.events as e
    where e.stream_id = prop.decision_id
      and e.event_type = 'DecisionProposed'
    order by e.version desc
    limit 1;
    perform private.append_granted_event(
      prop.org_id, prop.decision_id, 'decision', 'DecisionAccepted', coalesce(draft, '{}'::jsonb)
    );
  elsif prop.kind = 'supersede' then
    perform private.append_granted_event(
      prop.org_id, prop.supersedes, 'decision', 'DecisionSuperseded',
      jsonb_build_object('superseded_by', prop.decision_id)
    );
    select e.payload
    into draft
    from public.events as e
    where e.stream_id = prop.decision_id
      and e.event_type = 'DecisionProposed'
    order by e.version desc
    limit 1;
    perform private.append_granted_event(
      prop.org_id, prop.decision_id, 'decision', 'DecisionAccepted', coalesce(draft, '{}'::jsonb)
    );
  elsif prop.kind = 'compile_harness' then
    candidate := prop.candidate;
    harness_id := (candidate ->> 'stream_id')::uuid;
    perform private.append_granted_event(
      prop.org_id, harness_id, 'harness', 'HarnessCompiled', candidate
    );
  else
    raise exception 'unknown proposal kind %', prop.kind using errcode = '22023';
  end if;

  perform set_config('horizon.grant_role', '', true);
end;
$$;

create or replace function public.reject_proposal(p_proposal_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  prop public.proposals;
  uid uuid;
begin
  perform private.lock_streams(array[p_proposal_id]);
  prop := private.proposal_for_member(p_proposal_id);
  perform private.lock_streams(array[p_proposal_id, prop.decision_id]);
  prop := private.proposal_for_member(p_proposal_id);

  if prop.status <> 'verified' then
    raise exception 'proposal is not verified' using errcode = '22023';
  end if;

  uid := (select auth.uid());
  perform set_config('horizon.grant_role', 'reject_proposal', true);
  perform set_config('horizon.actor_id', uid::text, true);

  perform private.append_granted_event(
    prop.org_id, prop.id, 'proposal', 'ProposalRejected',
    jsonb_build_object('kind', prop.kind)
  );

  if prop.kind in ('accept_decision', 'reject_decision', 'supersede') then
    perform private.append_granted_event(
      prop.org_id, prop.decision_id, 'decision', 'DecisionRejected',
      jsonb_build_object('decision_id', prop.decision_id)
    );
  end if;

  perform set_config('horizon.grant_role', '', true);
end;
$$;

revoke all on function private.next_event_version(uuid) from public;
revoke all on function private.next_occurred_at() from public;
revoke all on function private.assert_stream_type(uuid, text) from public;
revoke all on function private.apply_proposal_event(uuid, uuid, text, text, jsonb, timestamptz) from public;
revoke all on function private.fold_proposal_event() from public;
revoke all on function private.append_granted_event(uuid, uuid, text, text, jsonb) from public;
revoke all on function private.lock_streams(uuid[]) from public;
revoke all on function private.proposal_for_member(uuid) from public;

revoke all on function public.append_writer_event(uuid, uuid, text, text, jsonb)
  from public, anon, authenticated, service_role;
grant execute on function public.append_writer_event(uuid, uuid, text, text, jsonb)
  to horizon_writer;

revoke all on function public.approve_proposal(uuid)
  from public, anon, service_role, horizon_writer, horizon_ci;
grant execute on function public.approve_proposal(uuid) to authenticated;

revoke all on function public.reject_proposal(uuid)
  from public, anon, service_role, horizon_writer, horizon_ci;
grant execute on function public.reject_proposal(uuid) to authenticated;

alter table public.decisions enable row level security;
alter table public.proposals enable row level security;

revoke all on table public.decisions from anon, authenticated, service_role, horizon_writer, horizon_ci;
revoke all on table public.proposals from anon, authenticated, service_role, horizon_writer, horizon_ci;

grant select on table public.decisions to authenticated;
grant select on table public.proposals to authenticated;

create policy decisions_select_member
  on public.decisions
  for select
  to authenticated
  using (private.is_member(org_id));

create policy proposals_select_member
  on public.proposals
  for select
  to authenticated
  using (private.is_member(org_id));
