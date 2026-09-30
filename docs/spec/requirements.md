# Requirements

Two sides. Architect requirements are what a person does in the workspace. Agent and CI requirements are what makes a decision binding without a person in the loop. Ids are stable. Work packages cite them. Do not renumber.

## Architect side

### Research

- **FR-RES-1.** The user chooses the question and the area. The agent must not open an investigation by itself.
- **FR-RES-2.** Retrieval of decisions, supersession lineage, governed paths, and `CheckRecorded` rows is deterministic. That module must not call a model.
- **FR-RES-3.** The generated view is a catalog document. Each panel names a component and citation ids.
- **FR-RES-4.** A citation is an event id. A path is cited by the `DecisionAccepted` event that carries the glob. A pull request is cited by the `CheckRecorded` event. A panel is dropped when any citation is not an event in the caller's organization. The server drops it. The client drops it again if the event is missing.
- **FR-RES-5.** In phase 1 the view shows decision lineage, citations, gaps, and open proposals. Overlapping governed globs are a gap query, not a stored conflict relation. Eval labels are shown only after `FR-EVL-1` has recorded them.
- **FR-RES-6.** Discussion is `DiscussionNoted` on a research session. It is not approval.
- **FR-RES-7.** The proposal card is the only control that calls `approve_proposal` or `reject_proposal`. It does not insert `ProposalApproved`.

### Decisions

- **FR-DEC-1.** A decision has status `proposed`, `accepted`, `rejected`, or `superseded`. A superseded row stays readable, including rejected alternatives.
- **FR-DEC-2.** `approve_proposal` appends `ProposalApproved` and `DecisionAccepted` in one transaction when the proposal kind is `accept_decision`. A direct insert of either event from the browser fails.
- **FR-DEC-6.** `reject_proposal` appends `ProposalRejected` and, when the target is a decision draft, `DecisionRejected`. `approve_proposal` for kind `supersede` appends `DecisionSuperseded` on the old stream and `DecisionAccepted` on the new stream in the same transaction. No other command appends those event types.
- **FR-DEC-3.** An accepted decision carries the constraint, the rejected alternatives, and the path globs it governs.
- **FR-DEC-4.** Supersession and consolidation are proposals. The proposal shows both constraints. Acceptance does not delete the older decision.
- **FR-DEC-5.** Ingest may parse ADR markdown into a proposal. Parsed path globs are not governing until a human accepts them. CI ignores unaccepted globs.

### Workspace

- **FR-UI-1.** `apps/web` renders the catalog. It must not import an LLM SDK, Koog, or a service-role client.
- **FR-UI-2.** Decision, path, and check facts are readable from projections with the agent service stopped.
- **FR-UI-3.** Phase-1 catalog components are `DecisionMap`, `ImplementationList`, `PullRequestLibrary`, `GapList`, and `ProposalCard`.
- **FR-UI-4.** The A2UI wire protocol is out of scope for phase 1. The catalog JSON in [design.md](design.md) is the contract.

## Agent and CI side

### Authority

- **FR-AUTH-1.** Model output is a proposal.
- **FR-AUTH-2.** `horizon_writer` may append `ProposalCreated`, `ProposalVerified`, and `DecisionProposed`. It must not append `ProposalApproved`, `ProposalRejected`, `DecisionAccepted`, `DecisionSuperseded`, `HarnessCompiled`, or `CheckRecorded`.
- **FR-AUTH-3.** Only `approve_proposal` and `reject_proposal`, running as a human member, append approval or rejection. The browser cannot insert those event types.
- **FR-AUTH-4.** Approval does not update a projection. The domain event is appended in the same transaction as `ProposalApproved`.
- **FR-AUTH-5.** `ProposalVerified` records a mechanical verdict or `NotConfigured`. `ProposalVerifier` must not call a model. While the port returns `NotConfigured`, a human may still approve. That gap is recorded, not hidden.

### CI library

- **FR-CI-1.** The CI command receives the repository (`owner/name`), the pull request number, the SHA, and the changed paths of the job it is running in.
- **FR-CI-2.** It selects accepted decisions whose governed globs match those paths.
- **FR-CI-3.** When `HarnessCompiled` exists for a selected decision, the command runs that mechanical sensor. The model does not produce the verdict. When no sensor exists, the command records `applies` with `sensor: "missing"`, does not record `violated`, and does not fail the job.
- **FR-CI-4.** One `CheckRecorded` event per decision per relation. The payload has `repository`, `pull_request`, `sha`, one `adr_id`, and exactly one of `applies`, `cited`, `violated`. `stream_id` is the UUIDv5 of `(org_id, repository, pull_request)`.
- **FR-CI-5.** `applies` is recorded when the scope matches, including when the sensor later fails or is missing.
- **FR-CI-6.** `cited` is recorded only when the pull request body or the agent output matches that ADR id on a token boundary. `ADR-012` does not match `ADR-0120`. A path intersection is not `cited`.
- **FR-CI-7.** `violated` fails the job. A missing sensor does not.
- **FR-CI-8.** A further `violated` check appends `CheckRecorded` only. `ProposalCreated` of kind `review_violations` is appended only when no open proposal of that kind exists for `(repository, adr_id)`. It must not append `DecisionAccepted` or `DecisionSuperseded`.

### Harness

- **FR-HAR-1.** An accepted decision with a negative constraint compiles one mechanical sensor. The path-scoped rule file is phase 2 (`FR-HAR-4`).
- **FR-HAR-2.** `HarnessCompiled` links that artifact to the decision.
- **FR-HAR-3.** The compiler rejects an artifact that does not cite a decision.
- **FR-HAR-4.** Phase 1 stops at that one sensor. Writing `AGENTS.md`, eval labels, and MCP retrieval are phase 2.

### Retrieval for coding agents (phase 2)

- **FR-AGT-1.** A coding agent retrieves decisions for the paths in play. The corpus is not pasted into the prompt.
- **FR-AGT-2.** The read tools are `search_decisions`, `get_constraints_for_paths`, and `get_rejected_alternatives`.

### Eval (phase 2)

- **FR-EVL-1.** An eval run prints the token spend and waits for confirmation before it starts. It then records `helpful`, `harmful`, or `inert` on the artifact.
- **FR-EVL-2.** A harmful result appends `ProposalCreated`. It does not edit the artifact.

## Record

- **FR-LOG-1.** The event table is insert-only. There is no client `UPDATE` or `DELETE` policy on `events` or on projection tables.
- **FR-LOG-2.** Each event has `org_id`, `stream_id`, `stream_type`, `version`, `event_type`, `schema_version`, `payload`, `actor_id`, `occurred_at`.
- **FR-LOG-3.** `(stream_id, version)` is unique. A version conflict is retried by the command, not patched.
- **FR-LOG-4.** A Postgres function folds events into projections. Application code does not `UPDATE` a projection.
- **FR-LOG-5.** Replaying the log without a model reproduces the projections.
- **FR-LOG-6.** A `BEFORE INSERT` trigger sets `actor_id` from `auth.uid()` for a user JWT, or from the role session setting for `horizon_writer` and `horizon_ci`. A payload `actor_id` is ignored. The trigger rejects an `event_type` that `event_type_grants` does not grant to that role. The service role is not a runtime writer.

## Tenancy and language

- **FR-TEN-1.** Every tenant-owned row has `org_id`.
- **FR-TEN-2.** RLS authorizes from organization membership and `auth.uid()`. It must not read `user_metadata`.
- **FR-TEN-3.** A user outside the organization cannot read the row.
- **NFR-1.** Identifiers, schema names, comments, and commits are English.
- **NFR-2.** Local seed is one organization. The schema stays multi-tenant.
- **NFR-3.** Koog persistence stores agent checkpoints only. It must not store decisions, rules, checks, or proposals.
- **NFR-4.** The Supabase service role is for migrations and admin only. Runtime event writes use `horizon_writer` or `horizon_ci`. Research reads use the user JWT and `security invoker`. The service role is never committed and never placed in a `VITE_` variable.
