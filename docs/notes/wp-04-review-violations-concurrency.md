# WP-04 design note: one open review_violations proposal under concurrency

Status: design proposal for WP-04. No code yet. Written ahead of the package so the mechanism is decided before an agent implements `services/agent/**/ci/`.

## Problem

FR-CI-8: a `violated` check appends `ProposalCreated` of kind `review_violations` only when no open proposal of that kind exists for `(repository, adr_id)`. "Open" is projection state. Two CI runs for the same pull request — two pushes seconds apart, or a re-run next to a running job — can both read "no open proposal" and both append `ProposalCreated`. The library then shows two open proposals for one violation.

Stream versioning does not help: each proposal is a new stream, so the two inserts never conflict on `(stream_id, version)`.

## Constraints from the spec

- `horizon_ci` appends `CheckRecorded` and at most one open `review_violations` proposal (design.md, Authority).
- The event table is insert-only; projections are written only by the fold (ADR-0001).
- A version conflict is retried by the command, not patched (FR-LOG-3).
- WP-04 owns `services/agent/**/ci/` and the check projection migration. It does not edit the WP-01 trigger.

## Options

### A. Deterministic proposal stream id

Derive the proposal stream id as the UUIDv5 of `(org_id, repository, adr_id, 'review_violations')` — the same pattern the spec uses for check stream identity. The second concurrent insert hits `unique (stream_id, version)` at version 1, gets `23505`, retries, sees the open proposal, and appends `CheckRecorded` only.

- \+ Reuses the spec's own optimistic-concurrency mechanism. No new machinery.
- \− Re-open semantics: after the proposal is rejected, a later violation must open a fresh proposal, but the stream already exists. A second `ProposalCreated` at a later version would have to mean "re-open", which the proposal fold does not define. The proposal lifecycle (`proposed` → `verified` → `approved`/`rejected`) gets muddy.

Rejected: it trades a concurrency fix for ambiguous proposal semantics.

### B. Advisory lock in a command function

A security-definer function takes `pg_advisory_xact_lock(hashtext(org_id, repository, adr_id, 'review_violations'))`, re-reads the open-proposal projection inside the lock, and conditionally appends `ProposalCreated`. The second run blocks on the lock, then sees the proposal and skips it.

- \+ Atomic check-and-act. No fold changes.
- \− Correct only while the projection is updated synchronously with the insert. With an asynchronous fold the projection lags and the re-read inside the lock still sees "no open proposal".
- \− Moves part of the CI command into a Postgres function, while ADR-0006 keeps command logic in Kotlin.

Viable fallback when the fold is synchronous and the team prefers one function over a fold side table.

### C. Fold-enforced uniqueness (recommended)

The check projection migration adds a side table `review_violations_open (org_id, repository, adr_id)` with a unique constraint. The fold maintains it like any other projection: a `review_violations` `ProposalCreated` inserts the row; `ProposalApproved` or `ProposalRejected` on that proposal stream deletes it.

With the synchronous trigger fold (as in PR #4), the fold runs in the same transaction as the event insert. A racing second `ProposalCreated` makes its fold step hit the unique violation; the whole transaction — `CheckRecorded` and `ProposalCreated` — rolls back. The command retries, re-reads, sees the open proposal, and appends `CheckRecorded` only.

- \+ The invariant is enforced mechanically at write time. No locks, no TOCTOU window.
- \+ Each proposal keeps its own stream and a clean lifecycle. Re-opening after a rejection is a fresh stream.
- \+ The side table is derived data; `rebuild_projections` rebuilds it like any projection.
- \− An event append can now fail because of derived state, not only because of grants. That matches the spec's existing trigger-rejects-ungranted-type approach, but it couples ingest to fold content.
- \− Requires the synchronous fold. If the WP-01 rework makes the fold asynchronous, fall back to option B.

## Recommendation

Option C, with B as the documented fallback. WP-04's "Done when" already contains the acceptance test — "a second red SHA appends `CheckRecorded` and does not open a second `review_violations` proposal". Implement it as two *concurrent* commands, not two sequential ones, or the race stays untested.

## Open dependencies on the WP-01 rework

1. **Fold timing.** This design assumes the fold runs synchronously in the insert transaction (PR #4's trigger fold). If the rework changes that, WP-04 falls back to option B.
2. **Fold extensibility.** WP-01 owns the trigger and later packages must not edit it, yet each package adds projections. The rework should leave an extension point — one trigger dispatching to per-package fold functions, or per-package `AFTER INSERT` triggers — so WP-04 can add the check projection and the side table in its own migration.
