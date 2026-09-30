-- PullRequestReceived: the GitHub webhook receiver (services/agent) appends one
-- event per pull_request delivery on stream_type 'pull_request'.
-- Grant row only. The WP-01 trigger is not edited.

insert into public.event_type_grants (role_name, event_type)
values ('horizon_writer', 'PullRequestReceived');

-- One stored event per X-GitHub-Delivery per organization. This is the durable
-- dedupe; the receiver keeps no authoritative in-memory state.
create unique index events_pull_request_delivery_key
  on public.events (org_id, (payload ->> 'delivery_id'))
  where event_type = 'PullRequestReceived';

-- PostgREST connects as `authenticator` and switches to the JWT role.
-- It needs membership in horizon_writer to do that.
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticator') then
    grant horizon_writer to authenticator;
  end if;
end
$$;

-- The receiver's only write path. horizon_writer has INSERT on events and no
-- SELECT, so it cannot read the next version itself. This function runs as its
-- owner, reads the next version under a per-stream lock, sets the session
-- settings the trigger reads, and inserts. The trigger still resolves the actor
-- and checks the grant; the payload is never trusted for either.
--
-- The actor is the `sub` claim of the writer JWT.
-- Returns 'appended', or 'duplicate' when the delivery is already stored.
create or replace function public.append_pull_request_received(
  p_org_id uuid,
  p_stream_id uuid,
  p_payload jsonb
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  claims jsonb;
  actor uuid;
  delivery text;
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
  delivery := nullif(p_payload ->> 'delivery_id', '');
  if delivery is null then
    raise exception 'payload.delivery_id is required' using errcode = '22023';
  end if;

  -- Serializes appends to one stream, so a concurrent delivery reads the
  -- version after ours instead of colliding on (stream_id, version).
  perform pg_advisory_xact_lock(hashtextextended(p_stream_id::text, 0));

  if exists (
    select 1
    from public.events as e
    where e.org_id = p_org_id
      and e.event_type = 'PullRequestReceived'
      and e.payload ->> 'delivery_id' = delivery
  ) then
    return 'duplicate';
  end if;

  -- A stream id shared with another stream type (for example the check stream)
  -- is a bug in the caller, not something to append onto.
  if exists (
    select 1
    from public.events as e
    where e.stream_id = p_stream_id
      and e.stream_type <> 'pull_request'
  ) then
    raise exception 'stream % is not a pull_request stream', p_stream_id
      using errcode = '22023';
  end if;

  select coalesce(max(e.version), 0) + 1
  into next_version
  from public.events as e
  where e.stream_id = p_stream_id;

  perform set_config('horizon.grant_role', 'horizon_writer', true);
  perform set_config('horizon.actor_id', actor::text, true);

  insert into public.events (
    org_id, stream_id, stream_type, version, event_type, schema_version, payload, actor_id
  )
  values (
    p_org_id, p_stream_id, 'pull_request', next_version,
    'PullRequestReceived', 1, p_payload, actor
  );

  return 'appended';
end;
$$;

revoke all on function public.append_pull_request_received(uuid, uuid, jsonb)
  from public, anon, authenticated, service_role;
grant execute on function public.append_pull_request_received(uuid, uuid, jsonb)
  to horizon_writer;
