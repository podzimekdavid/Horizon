# ADR-0006: Supabase records, Kotlin commands, React renders

Status: proposed

## Context

Auth, RLS, and the event log are platform features. Drafting an ADR and filling a research view are model workflows. The browser must not become a second backend or hold the service role.

## Decision

- `supabase/` — Postgres, Auth, RLS, the event log, folds. Queues, cron, and pgvector only when a package needs them.
- `services/agent/` — Kotlin, Ktor, Koog. Every command that branches, calls a model, or touches more than one stream. CI command lives here and is invoked by GitHub Actions. It also pulls pull requests from GitHub on an interval (ADR-0008); GitHub does not call it.
- `apps/web/` — Vite, React, TypeScript. Renders projections and the catalog. Sends user-authorized commands.

Custom logic does not go in Edge Functions. The web app does not import an LLM SDK or Koog. The service role is not in the web bundle and is not a runtime event writer. `horizon_writer` and `horizon_ci` insert events. Research reads use the user JWT.

## Rejected alternatives

- Edge Functions for the agent and CI. Rejected so model workflows stay in one service with one set of tests.
- The browser folds projections. Rejected by ADR-0001.

## Consequences

WP-00 writes this split into the Cursor rules. A package that needs a new runtime has to supersede this ADR first.

## Governs

`supabase/**`, `services/agent/**`, `apps/web/**`
