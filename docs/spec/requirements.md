# Requirements

Two sides. Architect requirements are what a person does in the workspace. Agent and CI requirements are what makes a decision binding without a person in the loop. Ids are stable. Work packages cite them. Do not renumber.

## Architect side

### Research

- **FR-RES-1.** The user chooses the question and the area. The agent must not open an investigation by itself.
- **FR-RES-2.** Retrieval of decisions, supersession lineage, governed paths, and `CheckRecorded` rows is deterministic. That module must not call a model.
- **FR-RES-3.** The generated view is a catalog document. Each panel names a component and citation ids.
- **FR-RES-4.** A panel is dropped when a citation does not resolve to an event, a path on an accepted decision, or a `CheckRecorded` pull request. The server drops it. The client drops it again if the citation is missing.
- **FR-RES-5.** The view can show decision lineage, citations, conflicts, eval labels, and open proposals. Eval labels may be empty until phase 2.
- **FR-RES-6.** Discussion is `DiscussionNoted` on a research session. It is not approval.
- **FR-RES-7.** The proposal card is the only control that appends `ProposalApproved` or `ProposalRejected`.

### Decisions

- **FR-DEC-1.** A decision has status `proposed`, `accepted`, `rejected`, or `superseded`. A superseded row stays readable, including rejected alternatives.
- **FR-DEC-2.** `DecisionAccepted` is appended only after a human member has appended `ProposalApproved` for that draft.
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
- **FR-AUTH-2.** The agent service account may append `ProposalCreated` and `ProposalVerified`. It must refuse `ProposalApproved` and `ProposalRejected`.
- **FR-AUTH-3.** Only a human organization member appends approval or rejection.
- **FR-AUTH-4.** Approval does not update a projection. The accepted change is a separate domain event.
- **FR-AUTH-5.** `ProposalVerified` records a mechanical verdict or `NotConfigured`. `ProposalVerifier` must not call a model. While the port returns `NotConfigured`, a human may still approve. That gap is recorded, not hidden.

### CI library

- **FR-CI-1.** The CI command receives the pull request number, the SHA, and the changed paths of the job it is running in.
- **FR-CI-2.** It selects accepted decisions whose governed globs match those paths.
- **FR-CI-3.** It runs the mechanical sensor compiled from each selected decision. The model does not produce the verdict.
- **FR-CI-4.** It appends one `CheckRecorded` event per relation. The payload has the pull request, the SHA, the ADR ids, and exactly one of `applies`, `cited`, `violated`.
- **FR-CI-5.** `applies` is recorded when the scope matches, including when the sensor later fails.
- **FR-CI-6.** `cited` is recorded only when the pull request body or the agent output names that ADR id. A path intersection is not `cited`.
- **FR-CI-7.** `violated` fails the job.
- **FR-CI-8.** Repeated `violated` checks may append `ProposalCreated`. They must not append `DecisionAccepted` or `DecisionSuperseded`.

### Harness

- **FR-HAR-1.** An accepted decision with a negative constraint compiles one path-scoped rule and one mechanical sensor.
- **FR-HAR-2.** `HarnessCompiled` links that artifact to the decision.
- **FR-HAR-3.** The compiler rejects an artifact that does not cite a decision.
- **FR-HAR-4.** Phase 1 stops at that one sensor. Writing `AGENTS.md`, eval labels, and MCP retrieval are phase 2.

### Retrieval for coding agents (phase 2)

- **FR-AGT-1.** A coding agent retrieves decisions for the paths in play. The corpus is not pasted into the prompt.
- **FR-AGT-2.** The read tools are `search_decisions`, `get_constraints_for_paths`, and `get_rejected_alternatives`.

## Record

- **FR-LOG-1.** The event table is insert-only. There is no client `UPDATE` or `DELETE` policy on `events` or on projection tables.
- **FR-LOG-2.** Each event has `org_id`, `stream_id`, `stream_type`, `version`, `event_type`, `schema_version`, `payload`, `actor_id`, `occurred_at`.
- **FR-LOG-3.** `(stream_id, version)` is unique. A version conflict is retried by the command, not patched.
- **FR-LOG-4.** A Postgres function folds events into projections. Application code does not `UPDATE` a projection.
- **FR-LOG-5.** Replaying the log without a model reproduces the projections.

## Tenancy and language

- **FR-TEN-1.** Every tenant-owned row has `org_id`.
- **FR-TEN-2.** RLS authorizes from organization membership and `auth.uid()`. It must not read `user_metadata`.
- **FR-TEN-3.** A user outside the organization cannot read the row.
- **NFR-1.** Identifiers, schema names, comments, and commits are English.
- **NFR-2.** Local seed is one organization. The schema stays multi-tenant.
- **NFR-3.** Koog persistence stores agent checkpoints only. It must not store decisions, rules, checks, or proposals.
- **NFR-4.** The Supabase service role stays in `services/agent`. It is never committed and never placed in a `VITE_` variable.
