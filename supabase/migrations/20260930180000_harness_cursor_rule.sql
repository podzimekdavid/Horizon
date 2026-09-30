-- A cursor rule compiled from an accepted decision.
-- The WP-01 grant trigger is not edited. approve_proposal already appends
-- HarnessCompiled; this fold projects that event.

create table public.harness_artifacts (
  id uuid primary key,
  org_id uuid not null,
  decision_id uuid not null,
  adr_id text,
  surface text,
  globs text[],
  body text,
  created_at timestamptz not null,
  constraint harness_artifacts_org_id_fkey
    foreign key (org_id) references public.organizations (id)
    deferrable initially immediate,
  constraint harness_artifacts_decision_id_fkey
    foreign key (decision_id) references public.decisions (id)
    deferrable initially immediate,
  constraint harness_artifacts_cursor_rule_check
    check (
      surface is distinct from 'cursor_rule'
      or (
        adr_id is not null
        and body is not null
        and globs is not null
        and cardinality(globs) > 0
      )
    )
);

create index harness_artifacts_org_id_idx on public.harness_artifacts (org_id);
create index harness_artifacts_decision_id_idx on public.harness_artifacts (decision_id);

create or replace function private.apply_harness_event(
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
  decision_id uuid;
  adr_id text;
  surface text;
  body text;
  globs text[];
begin
  if p_event_type is distinct from 'HarnessCompiled' then
    return;
  end if;
  if p_stream_type <> 'harness' then
    raise exception 'HarnessCompiled requires stream_type harness' using errcode = '22023';
  end if;

  begin
    decision_id := nullif(p_payload ->> 'decision_id', '')::uuid;
  exception
    when invalid_text_representation then
      raise exception 'payload.decision_id must be a uuid' using errcode = '22023';
  end;
  if decision_id is null then
    raise exception 'HarnessCompiled requires decision_id' using errcode = '22023';
  end if;

  surface := nullif(p_payload ->> 'surface', '');
  if surface is null then
    insert into public.harness_artifacts (id, org_id, decision_id, created_at)
    values (p_stream_id, p_org_id, decision_id, p_occurred_at);
    return;
  end if;
  if surface <> 'cursor_rule' then
    raise exception 'unknown harness surface %', surface using errcode = '22023';
  end if;

  adr_id := nullif(p_payload ->> 'adr_id', '');
  body := p_payload ->> 'body';
  if adr_id is null or adr_id !~ '^ADR-[0-9]+$' then
    raise exception 'cursor_rule requires an ADR id' using errcode = '22023';
  end if;
  if nullif(body, '') is null then
    raise exception 'cursor_rule requires a body' using errcode = '22023';
  end if;
  if body !~ ('(^|[^A-Za-z0-9])' || adr_id || '([^A-Za-z0-9]|$)') then
    raise exception 'cursor_rule must cite %', adr_id using errcode = '22023';
  end if;
  if jsonb_typeof(p_payload -> 'globs') is distinct from 'array'
    or jsonb_array_length(p_payload -> 'globs') < 1 then
    raise exception 'cursor_rule requires globs' using errcode = '22023';
  end if;

  select coalesce(array_agg(item order by ord), '{}')
  into globs
  from jsonb_array_elements_text(p_payload -> 'globs') with ordinality as listed(item, ord);
  if cardinality(globs) < 1
    or exists (
      select 1
      from unnest(globs) as glob
      where btrim(glob) = ''
        or glob <> btrim(glob)
        or position(',' in glob) > 0
    ) then
    raise exception 'cursor_rule globs must be non-empty path patterns' using errcode = '22023';
  end if;

  insert into public.harness_artifacts (
    id, org_id, decision_id, adr_id, surface, globs, body, created_at
  )
  values (
    p_stream_id, p_org_id, decision_id, adr_id, surface, globs, body, p_occurred_at
  );
end;
$$;

create or replace function private.fold_harness_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.apply_harness_event(
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

create trigger events_fold_harness
  before insert on public.events
  for each row
  execute function private.fold_harness_event();

-- Replay must rebuild this projection too. The grant trigger stays unchanged.
create or replace function private.rebuild_projections()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  rec public.events;
begin
  execute 'set constraints events_org_id_fkey, proposals_org_id_fkey, decisions_org_id_fkey, harness_artifacts_org_id_fkey, harness_artifacts_decision_id_fkey deferred';
  delete from public.harness_artifacts;
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
    perform private.apply_harness_event(
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

revoke all on function private.apply_harness_event(uuid, uuid, text, text, jsonb, timestamptz) from public;
revoke all on function private.fold_harness_event() from public;

alter table public.harness_artifacts enable row level security;

revoke all on table public.harness_artifacts from anon, authenticated, service_role, horizon_writer, horizon_ci;

grant select on table public.harness_artifacts to authenticated;

create policy harness_artifacts_select_member
  on public.harness_artifacts
  for select
  to authenticated
  using (private.is_member(org_id));
