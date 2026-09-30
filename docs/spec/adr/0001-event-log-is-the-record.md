# ADR-0001: The event log is the only record

Status: proposed

## Context

Horizon stores decisions, proposals, CI results, and harness artifacts. Those rows will be wrong if any client can edit them in place. Agents will treat a projection update as a fact.

## Decision

`public.events` is the system of record. Insert-only. Unique `(stream_id, version)`. Projections are rebuilt by a Postgres fold. Application code does not `UPDATE` or `DELETE` events or projections. There is no client `UPDATE` or `DELETE` policy on those tables.

A research view, a chat transcript, and Koog's checkpoint store are not records of product facts.

## Rejected alternatives

- The graph is the source of truth. Rejected because a model write would be hard to replay and easy to corrupt.
- Supabase as a general document store, with the events table as an audit copy. Rejected because two writable models drift.

## Consequences

WP-01 builds the envelope. Every later package adds events, not column updates. Replay without a model must reproduce the projections.

## Governs

`supabase/**`, `services/agent/**`, `apps/web/**`
