# Work packages

One package per agent. Dependencies are blocking. **Owns** is the only tree the agent may edit. Shared files (`docs/spec`, `.cursor/rules` after WP-00) are read-only for later packages unless the package says otherwise.

## Phase 1

### WP-00 — Align the Cursor rules

**Depends on:** none. **Blocks:** every implementation package.

**Owns:** `.cursor/rules/`

**Read:** [adr/0001](adr/0001-event-log-is-the-record.md), [adr/0002](adr/0002-human-member-approves.md), [adr/0003](adr/0003-mechanical-verdict.md), [adr/0006](adr/0006-stack-split.md)

**Requirements:** FR-AUTH-1, FR-AUTH-2, FR-AUTH-5, FR-LOG-1, NFR-1

The rules in `.cursor/rules/` still forbid a decision stream and pull-request checks. This package opens phase 1 to `decision`, `check`, and `research_session`, and keeps the bans: no model judge, no client writes to projections, no direct browser approval, no runtime service role, no knowledge-graph product, no full GitHub ingestion, no A2UI wire protocol.

**Done when:**

- The constitution names the allowed phase-1 streams and the still-forbidden work.
- `ProposalVerifier` checks a proposal, returns `NotConfigured` in this phase, and must not call a model.
- An agent that reads only these rules will not scaffold Jira, Slack, or a graph database.

### WP-01 — Event log and tenancy

**Depends on:** WP-00.

**Owns:** `supabase/` envelope, trigger, `event_type_grants`, and the fold. Later packages insert grant rows and their own projection migrations. They do not edit this trigger.

**Read:** [design.md](design.md) sections Event envelope, Grants, Streams. [adr/0001](adr/0001-event-log-is-the-record.md), [adr/0006](adr/0006-stack-split.md)

**Requirements:** FR-LOG-1 through FR-LOG-6, FR-TEN-1 through FR-TEN-3, NFR-2, NFR-4

**Done when:**

- A member can insert `DiscussionNoted` for their organization.
- A member insert of `DecisionAccepted`, `CheckRecorded`, `HarnessCompiled`, or `ProposalVerified` fails.
- The stored `actor_id` is `auth.uid()` when the payload names someone else.
- A direct `UPDATE` of a projection fails under the member role.
- A user outside the organization cannot read the row.
- The service role is not granted a runtime insert.
- Folding the same events twice yields the same projection rows.

**Out of scope:** decision ingest, CI, the web app.

### WP-02 — Proposals and authority

**Depends on:** WP-01.

**Owns:** `services/agent/**/proposal/` and the proposal grant rows. The `ProposalVerifier` port lives here.

**Read:** [design.md](design.md) Commands, Authority. [adr/0002](adr/0002-human-member-approves.md), [adr/0003](adr/0003-mechanical-verdict.md)

**Requirements:** FR-AUTH-1 through FR-AUTH-5, FR-DEC-2, FR-DEC-6

**Done when:**

- `horizon_writer` appends `ProposalCreated` and `ProposalVerified`.
- A direct insert of `ProposalApproved` from the browser and from `horizon_writer` fails.
- `approve_proposal` as a member appends `ProposalApproved` and `DecisionAccepted` in one transaction. The decision projection status becomes `accepted`.
- `reject_proposal` appends `ProposalRejected` and `DecisionRejected` for a decision draft.
- `ProposalVerified` for this phase records `NotConfigured`.
- No model client exists on the verifier path.

### WP-03 — Decision stream and ingest

**Depends on:** WP-02.

**Owns:** `services/agent/**/decision/`, `services/agent/**/sensor/` (the interface only), and the decision projection migration.

**Read:** [design.md](design.md) Streams, Projections. [adr/0002](adr/0002-human-member-approves.md). FR-DEC-*.

**Requirements:** FR-DEC-1 through FR-DEC-5, FR-AUTH-4

**Done when:**

- A fixture ADR markdown file becomes `DecisionProposed` with suggested globs, not accepted globs.
- `approve_proposal` on that draft appends `DecisionAccepted` in the same transaction, and the projection shows the globs as governing.
- Supersession leaves the old decision readable with status `superseded`.
- CI-facing queries return no governing glob from a still-proposed decision.

### WP-04 — CI ADR library

**Depends on:** WP-03. A fixture sensor is enough. WP-08 replaces that fixture with the compiler output. Do not wait for WP-08 to prove the library.

**Owns:** `services/agent/**/ci/`, `.github/workflows/` for this command, and the check projection migration. It calls the `Sensor` interface. It does not edit `harness/`.

**Read:** [design.md](design.md) CI command. [adr/0003](adr/0003-mechanical-verdict.md), [adr/0004](adr/0004-ci-adr-library.md)

**Requirements:** FR-CI-1 through FR-CI-8

**Done when:**

- A diff inside a governed glob appends `applies` for that one `adr_id` on the stream for `(org, repository, pull_request)`, and exits 0 when the sensor passes.
- A diff the sensor rejects appends `violated`, exits non-zero, and does not append `DecisionSuperseded`.
- A matched decision with no sensor appends `applies` with `sensor: "missing"`, does not append `violated`, and exits 0.
- Text `ADR-0120` does not append `cited` for `ADR-012`.
- A second red SHA appends `CheckRecorded` and does not open a second `review_violations` proposal.

**Out of scope:** listing every open pull request on GitHub.

### WP-08 — Compile one sensor

**Depends on:** WP-03. Parallel with WP-04.

**Owns:** `services/agent/**/harness/` and the harness projection migration. It implements `Sensor`. It does not edit `ci/`.

**Read:** [adr/0003](adr/0003-mechanical-verdict.md). FR-HAR-1 through FR-HAR-3.

**Requirements:** FR-HAR-1, FR-HAR-2, FR-HAR-3

**Done when:**

- An accepted decision whose constraint is a negative check compiles one sensor candidate onto the proposal. `approve_proposal` appends `HarnessCompiled`.
- The compiler refuses an artifact with no decision id.
- The CI command loads that implementation through the `Sensor` interface, with no model call and no edit to the CI package.

**Out of scope:** `AGENTS.md` generation, skills, eval, MCP.

### WP-05 — Deterministic research read

**Depends on:** WP-03 and WP-04.

**Owns:** `services/agent/**/research/`. Reads go through the user JWT as `security invoker`. No service role. No UI.

**Read:** [design.md](design.md) Research read. FR-RES-2.

**Requirements:** FR-RES-2

**Done when:**

- A query by area returns accepted and superseded decisions, governed paths, `CheckRecorded` rows, gaps (decision with no glob, overlapping globs, check with no decision), and open proposals.
- A caller in another organization receives no rows from this organization.
- The module has no model import.
- The response cites event ids the caller can resolve.

### WP-06 — Research view in the web app

**Depends on:** WP-05.

**Owns:** `apps/web/`

**Read:** [design.md](design.md) Catalog. [adr/0005](adr/0005-user-led-research-view.md)

**Requirements:** FR-RES-1, FR-RES-4, FR-RES-6, FR-RES-7, FR-UI-1 through FR-UI-4

**Done when:**

- The user starts the session by naming an area. The page does not auto-investigate.
- A catalog panel with a missing citation is not rendered.
- Discussion posts `DiscussionNoted` and the proposal card stays `proposed`.
- With `services/agent` stopped, the projection page still lists decisions and checks.
- The app has no LLM SDK and no service-role key.

### WP-07 — Fill the view and draft an ADR

**Depends on:** WP-05 and WP-06.

**Owns:** `services/agent/**/view/`.

**Read:** [design.md](design.md) Catalog. [adr/0005](adr/0005-user-led-research-view.md)

**Requirements:** FR-RES-1, FR-RES-3, FR-RES-4, FR-RES-5, FR-DEC-4, FR-AUTH-2

**Done when:**

- Given a user question and the WP-05 payload, the workflow returns catalog JSON and drops any panel it cannot cite.
- It appends `ProposalCreated` for a draft ADR and does not append `ProposalApproved`.
- A consolidation proposal includes both constraints in the payload.

## Phase 2

### WP-09 — Bootstrap and agent retrieval

**Depends on:** WP-08.

**Owns:** bootstrap command and the three read tools.

**Requirements:** FR-AGT-1, FR-AGT-2, FR-HAR-4

**Done when:** bootstrap writes `AGENTS.md`, `.cursor/rules`, and one skill from accepted decisions, and the three tools return path-scoped decisions without the rest of the corpus.

### WP-10 — Eval labels

**Depends on:** WP-08.

**Owns:** eval command and `EvalCompleted` projection.

**Requirements:** FR-EVL-1, FR-EVL-2

**Done when:** a run prints the token spend and waits for confirmation, then records `helpful`, `harmful`, or `inert`. A harmful result is `ProposalCreated`, not a silent edit.

## Phase 3

### WP-11 — Wider evidence

**Depends on:** WP-04 and WP-07.

**Owns:** new event types only, behind the phase-3 note in the constitution.

**Requirements:** none of phase 1.

**Done when:** a review finding can be `learned_from` on a proposal, and a human can confirm an `implements` claim distinct from `applies` / `cited` / `violated`. `NotConfigured` is replaced only by an adapter that returns pass or fail from a schema or type check and does not call a model. If Jev cannot do that, this package does not add the client.

**Out of scope until a human asks:** Jira, Slack, and extra agent runtimes.
