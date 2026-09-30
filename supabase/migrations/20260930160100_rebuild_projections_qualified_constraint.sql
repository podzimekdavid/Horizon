-- private.rebuild_projections() runs with search_path = '', and SET CONSTRAINTS resolves an
-- unqualified name through the search path. `events_org_id_fkey` was never found:
--   ERROR: constraint "events_org_id_fkey" does not exist
-- Qualify it. The rebuild itself is unchanged.

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
