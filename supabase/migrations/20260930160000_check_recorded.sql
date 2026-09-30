-- CheckRecorded: the CI command appends one event per relation on the check stream.
-- Grant row only. The WP-01 trigger is not edited.

insert into public.event_type_grants (role_name, event_type)
values ('horizon_ci', 'CheckRecorded');

-- PostgREST connects as authenticator and switches to the JWT role.
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticator') then
    grant horizon_ci to authenticator;
  end if;
end
$$;

-- The CI command's only write path. horizon_ci has INSERT on events and no
-- SELECT, so it cannot read the next version itself. This function runs as its
-- owner, reads the next version under a per-stream lock, sets the session
-- settings the trigger reads, and inserts one CheckRecorded per payload.
-- The trigger still resolves the actor and checks the grant.
--
-- The actor is the sub claim of the horizon_ci JWT.
-- p_events is a JSON array of payloads, in version order. Each payload carries
-- its own relation: applies, cited, or violated. One of each per call.
create or replace function public.append_check_recorded(
  p_org_id uuid,
  p_stream_id uuid,
  p_events jsonb
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  claims jsonb;
  actor uuid;
  event jsonb;
  relation text;
  next_version integer;
  appended integer := 0;
begin
  begin
    claims := nullif(current_setting('request.jwt.claims', true), '')::jsonb;
    actor := nullif(claims ->> 'sub', '')::uuid;
  exception
    when invalid_text_representation or invalid_parameter_value then
      actor := null;
  end;
  if actor is null then
    raise exception 'ci JWT has no usable sub claim' using errcode = '42501';
  end if;

  if jsonb_typeof(p_events) is distinct from 'array' or jsonb_array_length(p_events) < 1 then
    raise exception 'events must be a non-empty JSON array' using errcode = '22023';
  end if;
  if exists (
    select 1
    from jsonb_array_elements(p_events) as item
    group by item ->> 'relation'
    having count(*) > 1
  ) then
    raise exception 'one event per relation' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_stream_id::text, 0));

  if exists (
    select 1
    from public.events as e
    where e.stream_id = p_stream_id
      and e.stream_type <> 'check'
  ) then
    raise exception 'stream % is not a check stream', p_stream_id
      using errcode = '22023';
  end if;

  select coalesce(max(e.version), 0)
  into next_version
  from public.events as e
  where e.stream_id = p_stream_id;

  perform set_config('horizon.grant_role', 'horizon_ci', true);
  perform set_config('horizon.actor_id', actor::text, true);

  for event in
    select item
    from jsonb_array_elements(p_events) as item
  loop
    if jsonb_typeof(event) is distinct from 'object' then
      raise exception 'each event payload must be a JSON object' using errcode = '22023';
    end if;
    relation := event ->> 'relation';
    if relation is null or relation not in ('applies', 'cited', 'violated') then
      raise exception 'relation must be applies, cited, or violated' using errcode = '22023';
    end if;
    if nullif(event ->> 'adr_id', '') is null then
      raise exception 'adr_id is required' using errcode = '22023';
    end if;

    next_version := next_version + 1;
    insert into public.events (
      org_id, stream_id, stream_type, version, event_type, schema_version, payload, actor_id
    )
    values (
      p_org_id, p_stream_id, 'check', next_version,
      'CheckRecorded', 1, event, actor
    );
    appended := appended + 1;
  end loop;

  return appended;
end;
$$;

revoke all on function public.append_check_recorded(uuid, uuid, jsonb)
  from public, anon, authenticated, service_role;
grant execute on function public.append_check_recorded(uuid, uuid, jsonb)
  to horizon_ci;
