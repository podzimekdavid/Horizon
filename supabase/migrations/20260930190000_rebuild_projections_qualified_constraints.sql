-- private.rebuild_projections() runs with search_path = '', and SET CONSTRAINTS resolves an
-- unqualified name through the search path, so the rebuild failed with:
--   ERROR: constraint "events_org_id_fkey" does not exist
-- 20260930170000 qualified the names, 20260930180000 replaced the function with the unqualified
-- form again. Qualify them here. The rebuild itself is unchanged.

create or replace function private.rebuild_projections()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  rec public.events;
begin
  execute 'set constraints public.events_org_id_fkey, public.proposals_org_id_fkey, public.decisions_org_id_fkey, public.harness_artifacts_org_id_fkey, public.harness_artifacts_decision_id_fkey deferred';
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
