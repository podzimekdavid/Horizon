-- Append-only event log. Projections are rebuilt from events.
-- The same migration deploys locally and to every hosted environment.

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
  role text not null,
  constraint memberships_role_check check (role in ('owner', 'member', 'agent')),
  primary key (org_id, user_id)
);

create index memberships_user_id_idx on public.memberships (user_id);

create table public.events (
  id bigint generated always as identity primary key,
  org_id uuid not null,
  stream_id uuid not null,
  stream_type text not null,
  version integer not null,
  event_type text not null,
  schema_version integer not null,
  payload jsonb not null,
  actor_id uuid not null references auth.users (id),
  occurred_at timestamptz not null default now(),
  constraint events_stream_version_key unique (stream_id, version),
  constraint events_org_id_fkey
    foreign key (org_id) references public.organizations (id)
    deferrable initially immediate,
  constraint events_stream_type_check check (
    stream_type in (
      'organization',
      'membership',
      'rule',
      'skill',
      'prompt',
      'evaluation',
      'proposal'
    )
  ),
  constraint events_version_check check (version >= 1),
  constraint events_schema_version_check check (schema_version >= 1),
  constraint events_event_type_check check (event_type ~ '^[A-Z][A-Za-z0-9]+$'),
  constraint events_payload_object_check check (jsonb_typeof(payload) = 'object')
);

create index events_org_id_occurred_at_idx on public.events (org_id, occurred_at);

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
  granted_user uuid;
  granted_role text;
  org_name text;
begin
  if p_event_type = 'OrganizationCreated' then
    if p_stream_type <> 'organization' then
      raise exception 'OrganizationCreated requires stream_type organization';
    end if;
    if p_stream_id is distinct from p_org_id then
      raise exception 'OrganizationCreated requires stream_id = org_id';
    end if;

    org_name := nullif(btrim(p_payload ->> 'name'), '');
    if org_name is null then
      raise exception 'OrganizationCreated requires payload.name';
    end if;

    insert into public.organizations (id, name, created_at)
    values (p_stream_id, org_name, p_occurred_at);
  elsif p_event_type = 'MembershipGranted' then
    if p_stream_type <> 'membership' then
      raise exception 'MembershipGranted requires stream_type membership';
    end if;
    if p_payload ->> 'user_id' is null or p_payload ->> 'role' is null then
      raise exception 'MembershipGranted requires payload.user_id and payload.role';
    end if;

    granted_user := (p_payload ->> 'user_id')::uuid;
    granted_role := p_payload ->> 'role';
    if granted_role not in ('owner', 'member', 'agent') then
      raise exception 'MembershipGranted role must be owner, member, or agent';
    end if;

    insert into public.memberships (org_id, user_id, role)
    values (p_org_id, granted_user, granted_role);
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
    order by id
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

create or replace function private.membership_role(target_org uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select m.role
  from public.memberships as m
  where m.org_id = target_org
    and m.user_id = (select auth.uid());
$$;

revoke all on function private.apply_event(uuid, uuid, text, text, jsonb, timestamptz) from public;
revoke all on function private.fold_event() from public;
revoke all on function private.rebuild_projections() from public;
revoke all on function private.is_member(uuid) from public;
revoke all on function private.membership_role(uuid) from public;

grant usage on schema private to authenticated;
grant execute on function private.is_member(uuid) to authenticated;
grant execute on function private.membership_role(uuid) to authenticated;

alter table public.organizations enable row level security;
alter table public.memberships enable row level security;
alter table public.events enable row level security;

revoke all on table public.organizations from anon, authenticated;
revoke all on table public.memberships from anon, authenticated;
revoke all on table public.events from anon, authenticated;

grant select on table public.organizations to authenticated;
grant select on table public.memberships to authenticated;
grant select, insert on table public.events to authenticated;

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
  with check (
    actor_id = (select auth.uid())
    and private.is_member(org_id)
    and event_type <> 'OrganizationCreated'
    and (
      event_type <> 'MembershipGranted'
      or private.membership_role(org_id) = 'owner'
    )
    and (
      event_type not in ('ProposalApproved', 'ProposalRejected')
      or private.membership_role(org_id) in ('owner', 'member')
    )
  );
