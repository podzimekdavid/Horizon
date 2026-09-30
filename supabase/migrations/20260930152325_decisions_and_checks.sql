-- Decision and check projections. The WP-01 trigger is not edited.
-- This migration replaces the fold functions and adds grant rows only.

create table public.decisions (
  id uuid primary key,
  org_id uuid not null references public.organizations (id),
  adr_id text not null,
  title text,
  status text not null,
  globs jsonb not null default '[]'::jsonb,
  constraint decisions_status_check check (
    status in ('proposed', 'accepted', 'rejected', 'superseded')
  ),
  constraint decisions_globs_array_check check (jsonb_typeof(globs) = 'array')
);

create index decisions_org_id_idx on public.decisions (org_id);

create table public.checks (
  id uuid primary key,
  org_id uuid not null references public.organizations (id),
  repository text not null,
  pull_request integer not null,
  sha text not null,
  adr_id text not null,
  relation text not null,
  constraint checks_relation_check check (relation in ('applies', 'cited', 'violated')),
  constraint checks_pull_request_check check (pull_request >= 0)
);

create index checks_org_id_idx on public.checks (org_id);

insert into public.event_type_grants (role_name, event_type)
values ('horizon_writer', 'DecisionProposed');

create or replace function private.apply_event(
  p_org_id uuid,
  p_stream_id uuid,
  p_stream_type text,
  p_event_type text,
  p_payload jsonb,
  p_occurred_at timestamptz,
  p_event_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  member_id uuid;
  org_name text;
  adr_id text;
  decision_title text;
  decision_status text;
  decision_globs jsonb;
  check_repository text;
  check_sha text;
  check_relation text;
begin
  if p_event_type = 'OrganizationCreated' then
    if p_stream_type <> 'organization' or p_stream_id is distinct from p_org_id then
      raise exception 'OrganizationCreated requires stream_type organization and stream_id = org_id';
    end if;
    org_name := nullif(btrim(p_payload ->> 'name'), '');
    if org_name is null then
      raise exception 'OrganizationCreated requires payload.name';
    end if;
    insert into public.organizations (id, name, created_at)
    values (p_stream_id, org_name, p_occurred_at);
  elsif p_event_type = 'MemberAdded' then
    if p_stream_type <> 'membership' or p_payload ->> 'user_id' is null then
      raise exception 'MemberAdded requires stream_type membership and payload.user_id';
    end if;
    member_id := (p_payload ->> 'user_id')::uuid;
    insert into public.memberships (org_id, user_id)
    values (p_org_id, member_id);
  elsif p_event_type in (
    'DecisionProposed', 'DecisionAccepted', 'DecisionRejected', 'DecisionSuperseded'
  ) then
    if p_stream_type <> 'decision' then
      raise exception '% requires stream_type decision', p_event_type;
    end if;
    adr_id := nullif(btrim(p_payload ->> 'adr_id'), '');
    if adr_id is null then
      raise exception '% requires payload.adr_id', p_event_type;
    end if;
    decision_title := nullif(btrim(p_payload ->> 'title'), '');
    if p_event_type = 'DecisionProposed' then
      decision_status := 'proposed';
      decision_globs := '[]'::jsonb;
    elsif p_event_type = 'DecisionAccepted' then
      decision_status := 'accepted';
      if p_payload ? 'globs' and jsonb_typeof(p_payload -> 'globs') is distinct from 'array' then
        raise exception 'DecisionAccepted payload.globs must be an array';
      end if;
      decision_globs := coalesce(p_payload -> 'globs', '[]'::jsonb);
    elsif p_event_type = 'DecisionRejected' then
      decision_status := 'rejected';
    else
      decision_status := 'superseded';
    end if;

    insert into public.decisions (id, org_id, adr_id, title, status, globs)
    values (
      p_stream_id,
      p_org_id,
      adr_id,
      decision_title,
      decision_status,
      coalesce(decision_globs, '[]'::jsonb)
    )
    on conflict (id) do update
      set adr_id = excluded.adr_id,
          title = coalesce(excluded.title, public.decisions.title),
          status = excluded.status,
          globs = case
            when p_event_type = 'DecisionAccepted' then excluded.globs
            else public.decisions.globs
          end;
  elsif p_event_type = 'CheckRecorded' then
    if p_stream_type <> 'check' then
      raise exception 'CheckRecorded requires stream_type check';
    end if;
    if p_event_id is null then
      raise exception 'CheckRecorded requires an event id';
    end if;
    check_repository := nullif(btrim(p_payload ->> 'repository'), '');
    adr_id := nullif(btrim(p_payload ->> 'adr_id'), '');
    check_sha := nullif(btrim(p_payload ->> 'sha'), '');
    check_relation := p_payload ->> 'relation';
    if check_repository is null or adr_id is null or check_sha is null then
      raise exception 'CheckRecorded requires repository, sha, and adr_id';
    end if;
    if check_relation not in ('applies', 'cited', 'violated') then
      raise exception 'CheckRecorded relation must be applies, cited, or violated';
    end if;
    if jsonb_typeof(p_payload -> 'pull_request') is distinct from 'number' then
      raise exception 'CheckRecorded requires payload.pull_request';
    end if;
    insert into public.checks (id, org_id, repository, pull_request, sha, adr_id, relation)
    values (
      p_event_id,
      p_org_id,
      check_repository,
      (p_payload ->> 'pull_request')::integer,
      check_sha,
      adr_id,
      check_relation
    );
  end if;
end;
$$;

create or replace function private.fold_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.apply_event(
    new.org_id,
    new.stream_id,
    new.stream_type,
    new.event_type,
    new.payload,
    new.occurred_at,
    new.id
  );
  return new;
end;
$$;

create or replace function private.rebuild_projections()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  rec public.events;
begin
  execute 'set constraints public.events_org_id_fkey deferred';
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
      rec.org_id,
      rec.stream_id,
      rec.stream_type,
      rec.event_type,
      rec.payload,
      rec.occurred_at,
      rec.id
    );
  end loop;
end;
$$;

drop function private.apply_event(uuid, uuid, text, text, jsonb, timestamptz);

revoke all on function private.apply_event(uuid, uuid, text, text, jsonb, timestamptz, uuid) from public;

alter table public.decisions enable row level security;
alter table public.checks enable row level security;

revoke all on table public.decisions from anon, authenticated, service_role;
revoke all on table public.checks from anon, authenticated, service_role;

grant select on table public.decisions to authenticated;
grant select on table public.checks to authenticated;

create policy decisions_select_member
  on public.decisions
  for select
  to authenticated
  using (private.is_member(org_id));

create policy checks_select_member
  on public.checks
  for select
  to authenticated
  using (private.is_member(org_id));
