-- The grant trigger must see the role that ran the INSERT.
--
-- private.enforce_event_grant() was SECURITY DEFINER, so current_user inside it was always the
-- function owner (postgres). A member insert was checked as 'postgres' and rejected
-- ("event type DiscussionNoted is not granted to postgres"), and the authenticated branch could
-- never run.
--
-- The trigger becomes SECURITY INVOKER, so current_user is the inserting role:
--   authenticated                    -> actor is auth.uid()
--   horizon_writer, horizon_ci       -> actor is horizon.actor_id
--   postgres, supabase_admin         -> actor is horizon.actor_id, and horizon.grant_role names the
--                                       role to check (approve_proposal, append_pull_request_received)
-- Only the grants lookup needs owner rights, because event_type_grants is closed to every client
-- role. That lookup moves into a small definer helper. The trigger's decision rules are unchanged.

create or replace function private.event_type_granted(p_role text, p_event_type text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.event_type_grants as g
    where g.role_name = p_role
      and g.event_type = p_event_type
  );
$$;

revoke all on function private.event_type_granted(text, text) from public;
grant execute on function private.event_type_granted(text, text)
  to authenticated, horizon_writer, horizon_ci;

create or replace function private.enforce_event_grant()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  grant_role text;
  actor uuid;
begin
  grant_role := current_user;

  -- Security-definer commands (approve_proposal, append_pull_request_received) run as postgres and
  -- set this. A member JWT cannot assume the postgres role, so the setting is ignored for them.
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

  if not private.event_type_granted(grant_role, new.event_type) then
    raise exception 'event type % is not granted to %', new.event_type, grant_role
      using errcode = '42501';
  end if;

  new.actor_id := actor;
  return new;
end;
$$;
