-- Event envelope, grant trigger, and the organization fold.
-- Later packages insert event_type_grants rows. They do not edit the trigger.

create schema if not exists private;

revoke all on schema private from public;

create table public.organizations (
  id uuid primary key,
  name text not null,
  created_at timestamptz not null
);

create table public.memberships (
  org_id uuid not null references public.organizations (id),
  user_id uuid not null references auth.users (id),
  primary key (org_id, user_id)
);

create index memberships_user_id_idx on public.memberships (user_id);

create table public.events (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  stream_id uuid not null,
  stream_type text not null,
  version integer not null,
  event_type text not null,
  schema_version integer not null,
  payload jsonb not null,
  actor_id uuid not null,
  occurred_at timestamptz not null default now(),
  constraint events_stream_version_key unique (stream_id, version),
  constraint events_org_id_fkey
    foreign key (org_id) references public.organizations (id)
    deferrable initially immediate,
  constraint events_version_check check (version >= 1),
  constraint events_schema_version_check check (schema_version >= 1),
  constraint events_payload_object_check check (jsonb_typeof(payload) = 'object')
);

create index events_org_id_occurred_at_idx on public.events (org_id, occurred_at);

create table public.event_type_grants (
  role_name text not null,
  event_type text not null,
  primary key (role_name, event_type)
);

insert into public.event_type_grants (role_name, event_type)
values
  ('authenticated', 'ResearchSessionOpened'),
  ('authenticated', 'DiscussionNoted'),
  ('postgres', 'OrganizationCreated'),
  ('postgres', 'MemberAdded');

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'horizon_writer') then
    create role horizon_writer nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'horizon_ci') then
    create role horizon_ci nologin;
  end if;
end
$$;

create or replace function private.apply_event(
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
  member_id uuid;
  org_name text;
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
  end if;
end;
$$;

create or replace function private.enforce_event_grant()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  grant_role text;
  actor uuid;
begin
  grant_role := current_user;

  -- Security-definer commands (approve_proposal, later) set this.
  -- A member JWT cannot assume the postgres role, so the setting is ignored for them.
  if current_user in ('postgres', 'supabase_admin')
    and coalesce(current_setting('horizon.grant_role', true), '') <> '' then
    grant_role := current_setting('horizon.grant_role', true);
  end if;

  if current_user = 'authenticated' then
    actor := auth.uid();
  elsif current_user in ('horizon_writer', 'horizon_ci', 'postgres', 'supabase_admin') then
    begin
      actor := nullif(current_setting('horizon.actor_id', true), '')::uuid;
    exception
      when invalid_text_representation then
        actor := null;
    end;
  else
    raise exception 'role % cannot append events', current_user using errcode = '42501';
  end if;

  if actor is null then
    raise exception 'actor_id could not be resolved' using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.event_type_grants as g
    where g.role_name = grant_role
      and g.event_type = new.event_type
  ) then
    raise exception 'event type % is not granted to %', new.event_type, grant_role
      using errcode = '42501';
  end if;

  new.actor_id := actor;
  return new;
end;
$$;

create trigger events_enforce_grant
  before insert on public.events
  for each row
  execute function private.enforce_event_grant();

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
    new.occurred_at
  );
  return new;
end;
$$;

create trigger events_fold
  before insert on public.events
  for each row
  execute function private.fold_event();

create or replace function private.rebuild_projections()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  rec public.events;
begin
  execute 'set constraints events_org_id_fkey deferred';
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
  end loop;
end;
$$;

create or replace function private.is_member(target_org uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.memberships as m
    where m.org_id = target_org
      and m.user_id = (select auth.uid())
  );
$$;

create or replace function private.org_exists(target_org uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.organizations as o
    where o.id = target_org
  );
$$;

revoke all on function private.apply_event(uuid, uuid, text, text, jsonb, timestamptz) from public;
revoke all on function private.enforce_event_grant() from public;
revoke all on function private.fold_event() from public;
revoke all on function private.rebuild_projections() from public;
revoke all on function private.is_member(uuid) from public;
revoke all on function private.org_exists(uuid) from public;

grant usage on schema private to authenticated, horizon_writer, horizon_ci;
grant execute on function private.is_member(uuid) to authenticated;
grant execute on function private.org_exists(uuid) to horizon_writer, horizon_ci;

alter table public.organizations enable row level security;
alter table public.memberships enable row level security;
alter table public.events enable row level security;
alter table public.event_type_grants enable row level security;

revoke all on table public.organizations from anon, authenticated, service_role;
revoke all on table public.memberships from anon, authenticated, service_role;
revoke all on table public.events from anon, authenticated, service_role;
revoke all on table public.event_type_grants from anon, authenticated, service_role, horizon_writer, horizon_ci;

grant select on table public.organizations to authenticated;
grant select on table public.memberships to authenticated;
grant select, insert on table public.events to authenticated;
grant insert on table public.events to horizon_writer, horizon_ci;

create policy organizations_select_member
  on public.organizations
  for select
  to authenticated
  using (private.is_member(id));

create policy memberships_select_member
  on public.memberships
  for select
  to authenticated
  using (private.is_member(org_id));

create policy events_select_member
  on public.events
  for select
  to authenticated
  using (private.is_member(org_id));

create policy events_insert_member
  on public.events
  for insert
  to authenticated
  with check (private.is_member(org_id));

create policy events_insert_writer
  on public.events
  for insert
  to horizon_writer, horizon_ci
  with check (private.org_exists(org_id));
