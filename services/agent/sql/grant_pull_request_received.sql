-- Follow-up after PR #4 (origin/dp/supabase event_log migration).
-- Do not apply to a live database from this POC alone.
-- The agent posts PullRequestReceived as horizon_writer; without this grant the
-- enforce_event_grant trigger rejects the insert. Do not edit that trigger.

insert into public.event_type_grants (role_name, event_type)
values ('horizon_writer', 'PullRequestReceived');
