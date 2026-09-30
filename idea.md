# Horizon

Horizon is the workspace where an architect researches the system, writes and evolves ADRs, and sees those decisions against the code and the pull requests that implement them. An accepted decision is compiled into the harness coding agents run. When the code, a review, or an eval shows drift, Horizon proposes the next change. A human approves it.

Pitch:

> The architect asks what the system decided, sees where that decision lives in the code and in open pull requests, and accepts or supersedes the ADR in the same view. Agents then run the harness compiled from that decision, and the next pull request shows up on it.

This draft restores the architect workspace as the product. The harness loop is how a decision stays executable. The Cursor rules on `cursor/horizon-agent-rules` still fence phase 1 to harness streams only (no decisions, no pull requests, no graph). That fence is narrower than this draft. Update those rules before implementation follows this spec.

## Problem

Architects already do this work. The tools split it into tabs that do not share a record.

- **Research.** "What did we decide about payments, what did we reject, and which service actually does it?" The answer is spread across ADRs, old pull requests, and chat. Most architectural choices never become an ADR at all.
- **ADR development.** Writing the record sits beside the decision. Teams abandon the practice within weeks or months. Dedup, if it happens, is a person noticing two files that sound alike.
- **Overview.** A lead engineer cannot open one view of the architecture: accepted decisions, the paths they govern, the pull requests touching those paths, and the gaps (a decision with no implementation, an implementation with no decision). Current ADR tools are per-repo TUI or markdown.
- **Execution.** Even a good ADR is context, not a constraint. Agents violate it unless a harness sensor fires. Reviews and pull requests are not linked back onto the decision they confirm or break.

Harness engineering names the last gap. Guides (`AGENTS.md`, skills) and sensors (linters, types, tests) are scattered across delivery. ([Harness engineering for coding agent users](https://martinfowler.com/articles/harness-engineering.html), April 2026.) A 2026 study of 679 rule files found that random rules raise task success about as much as expert-written ones, negative constraints help, and positive directives tend to hurt. ([Guardrails Beat Guidance](https://arxiv.org/html/2604.11088)) The architect's etalon is a decision compiled into a short guardrail or a mechanical sensor, not a pack of best-practice prose.

## What already exists

| Layer | Who is there | What they stop at |
|---|---|---|
| Decision records for agents | [adrkit](https://adrkit.dev/), [adr-kit](https://github.com/rvdbreemen/adr-kit), [adr-warden](https://libraries.io/npm/adr-warden) | Typed ADRs, path scope, read-only MCP, regex or rubric checks, staleness. Per repository. The architect's UI is a terminal, a Mermaid map, or a CI comment. |
| Team knowledge from ADR, Slack, and review | [Harbor](https://gethrbr.com/blog/architecture-decision-records-for-ai-agents) | Facts and supersession proposed to an owner. |
| Format sync | Rulesync and similar compilers | One markdown file written out for several agents. |
| Rule eval | [optirule](https://github.com/BaconMan1168/optirule) | Whether a rule file changed behaviour. Single-player CLI. |
| Agent-driven UI | [A2UI](https://a2ui.org/) | A declarative catalog the agent fills and the client renders. No architecture product on top. |

Nobody gives the architect one workspace that researches the current system, develops the ADR, shows implementation and pull-request links, and compiles the accepted decision into the agent harness.

## Product

Two loops, one log.

**Architect loop.** Research the area, draft or supersede the ADR, see paths and pull requests, approve.

**Harness loop.** Compile the accepted decision into rules, skills, and sensors. Eval whether they earn their tokens. Propose an edit when they do not.

The graph is a projection of the event log. It is not the source of truth. The model may draft a brief, an ADR, or a link interpretation. It does not accept a decision, and it does not judge compliance. Schema, lint, hooks, and tests produce verdicts.

### A session

1. The architect opens "payments boundary" and leads the investigation: which decision, which paths, which pull request.
2. The agent does not choose the question and does not decide. It renders a generated view the team discusses: the lineage of ADR-012, citations, a conflict, eval labels, and open proposals. Every panel cites an event, a path, or a pull request. A panel without a citation is invalid.
3. The team discusses that view. Discussion does not approve anything.
4. A proposal card offers a superseding ADR. A human member records `ProposalApproved`. The harness recompiles the constraint.
5. CI on the next pull request selects the decisions whose scope covers the changed files, runs the mechanical sensor, and fails the job if one is violated. The same run appends which ADRs applied, which were cited, and which were violated. The research view reads that library. The decision itself does not change.

### Architect workspace

#### Research engine

The engine answers questions about this system. It is not a web search box and not a chat that invents architecture.

It must answer:

- What is currently decided about this area, and which alternatives were rejected?
- Which modules and paths implement it?
- Which pull requests has CI recorded as `applies`, `cited`, or `violated` for this decision?
- Where does the code diverge from the decision?
- Which existing decisions overlap or conflict with the draft I am about to write?
- What is missing: a governed path with no decision, or a decision with no path?

Two passes:

1. **Retrieval is deterministic.** Status, supersession chain, path match, and the CI library (`applies`, `cited`, `violated`) come from the projection. No model in this pass.
2. **The brief is written by the model, and every sentence cites a decision, a path, or a pull request.** Uncited sentences are dropped. The brief is attached to a proposal. It is not a second source of truth.

The same engine runs before a new ADR is drafted, so a duplicate or a conflict shows up while the architect is still researching.

#### Research session

The user conducts the investigation in the UI. The agent does not lead it and does not decide. It renders the result as a generated view the team discusses.

That view shows decision lineage, citations, conflicts, eval labels, and open proposals. Every claim cites an event, a path, or a pull request. An uncited panel is invalid and is not shown.

Discussion is its own step on that surface. The proposal card stays the approval control. Approval remains `ProposalApproved`, recorded by a human member.

The five-component catalog below is the first renderer for that view. The product requirement is the generated research view, not only a rearrangement of those five panels.

#### ADR development

The record is written from the research brief, or from a gap the overview already shows (a pull request that decided something, a boundary with no ADR).

The agent drafts context, the decision, rejected alternatives, consequences, and the paths it should govern. The architect edits and accepts. Acceptance is `DecisionAccepted`. A later change is a supersession or a consolidation proposal ("ADR-007 and ADR-012 cover the same topic and differ in one constraint"), shown as a structured diff with both constraints visible. History stays. Dedup does not delete the older record.

Status is `proposed`, `accepted`, `rejected`, or `superseded`. Superseded records stay readable, including the alternatives they rejected.

#### Agentic overview

The research view is a surface the agent fills and the team discusses. The web app renders it from a fixed catalog. The agent picks components and binds them to cited facts. It does not generate UI code, and it does not decide. That is the A2UI shape: declarative, catalog-limited, client-rendered ([A2UI](https://a2ui.org/), production spec v0.9.1, v1.0 still a candidate). Phase 1 renders the catalog in the React app. Speaking the A2UI wire protocol waits until the same surface is worth opening in another client.

The catalog is the first renderer. A research view may compose these components around the question the user is investigating. An uncited panel is invalid.

| Component | What it shows |
|---|---|
| Decision map | Lineage for the area: accepted, proposed, and superseded |
| Implementation list | Paths and modules the decision governs |
| Pull request list | For each pull request, which ADRs `applies`, `cited`, and `violated` |
| Gap list | Decision with no path, path or pull request with no decision, repeated violations |
| Proposal card | The draft ADR or harness edit. This is the only approval control |

The projection underneath is readable without a model call, because that is what the panels cite. CI is the source of the pull-request facts. The generated view is where the team discusses them.

#### Links to implementations and pull requests

Links are edges, not a paragraph inside the ADR.

| Edge | Meaning | How it is recorded |
|---|---|---|
| `governs` | Decision → path glob or module | On the decision, confirmed by the architect |
| `applies` | The decision scope covers files in this pull request | CI event. `touches` is only the path intersection inside this relation |
| `cited` | The pull request or the agent referenced the ADR | CI event |
| `violated` | The mechanical sensor for that decision failed | CI event. Fails the job |
| `compiled_to` | Decision → rule, skill, prompt, or sensor | Written when the harness is compiled |
| `learned_from` | Evidence → the proposal it triggered | Written with the proposal |

`applies`, `cited`, and `violated` are three relations, not one fact. `touches` only says the diff intersects a governed path. It does not record that CI checked the decision, and it does not record that the ADR was cited. A sensor failure is `violated` on that pull request and SHA. It is not, by itself, the library of which ADRs were used where.

"This pull request implements the decision" stays a claim. CI does not write it. A human can still propose it. The library the research view reads is `applies` / `cited` / `violated`.

### CI module

CI makes an accepted decision binding on a pull request, and it writes the ADR library for that pull request.

On the changed paths the command selects the decisions whose scope applies, runs the mechanical sensor compiled from each decision, and fails the check when one is violated. The model does not produce that verdict.

The same run records the three relations above. Smallest version: a CI command that fails the job and appends one event per relation, carrying the pull request, the SHA, and the ADR ids. The command only knows the pull request it is running on. Other GitHub activity arrives later, on the webhook path in GitHub ingestion.

Repeated violations may open a proposal. They do not change the decision by themselves.

The research view reads this projection. CI is the source of the facts. The generated view is where the team discusses them.

### Harness loop

An accepted decision compiles the surfaces that should carry it: a path-scoped negative rule, a short skill, a prompt fragment, or the CI sensor above. A rule that cites no decision is debt. A decision with no sensor is a request the agent can ignore.

Eval replays tasks from git history and labels an artifact `helpful`, `harmful`, or `inert`, with token cost. A harmful rule becomes a proposal to drop or edit it. The architect approves. The projection rebuilds from the new event.

Coding agents read the current decision through retrieval (`search_decisions`, `get_constraints_for_paths`, `get_rejected_alternatives`), scoped to the paths in play. The corpus is not pasted into every prompt.

### Event log

Append-only. Schema-validated. Replayable without a model.

| Event | Who records it | What follows |
|---|---|---|
| `DecisionProposed` | Agent or architect | A draft attached to a research brief |
| `DecisionAccepted` | A human | The current constraint, rejected alternatives, and governed paths |
| `DecisionSuperseded` | A human, via a proposal | The old record stays, the new one governs |
| `CheckRecorded` | The CI command | Pull request, SHA, ADR ids, and one relation: `applies`, `cited`, or `violated` |
| `HarnessCompiled` | The compiler | A rule, skill, prompt, or sensor linked to the decision |
| `EvalCompleted` | Replay from git history | `helpful`, `harmful`, or `inert`, plus token cost |
| `ProposalApproved` / `ProposalRejected` | A human member | The accepted change is a separate event |

`CheckRecorded` is the ADR library. A `violated` record fails the job. It does not supersede the decision. Opening a proposal from repeated violations is a separate `ProposalCreated`.

Proposal sequence for anything the model drafts: `ProposalCreated` → `ProposalVerified` → `ProposalApproved` or `ProposalRejected`. The agent service may record `ProposalCreated` and `ProposalVerified`. It must not record approval. Approval does not edit a projection by itself.

The Cursor rules still close streams at `organization`, `membership`, `rule`, `skill`, `prompt`, `evaluation`, `proposal`. This draft adds `decision` and `CheckRecorded`. Those rules already require a mechanical verdict on `ProposalVerified` through a `ProposalVerifier` port, and they ship that port as `NotConfigured`. A model must not judge compliance.

### Who it is for

Architects and lead engineers are the primary users. They research an area, develop the ADR, and read the overview of decisions, implementations, and pull requests.

Coding agents are the second user. They retrieve the current decision and run the compiled harness.

A team shares one log across repositories. One person can run the same loop in a single repo. Rollout of an etalon across repos is a staged proposal.

### Stack already chosen

- `supabase/` — Postgres, Auth, RLS, Storage. The event table is the system of record. Projection tables, including the ADR library on pull requests, are rebuilt from events. Full GitHub ingestion is not required for that library.
- `services/agent/` — Kotlin, Ktor, Koog. Renders the research view, drafts ADRs, compiles the harness, and makes every model call. Koog memory stores agent checkpoints only. The agent does not lead the investigation.
- `apps/web/` — Vite, React, TypeScript. The user conducts research here. The app renders the generated view and sends commands a member is allowed to record. Discussion happens on that view. Approval is only the proposal card.
- Every tenant-owned row has `org_id`.
- Jev is a `ProposalVerifier` port. It checks a proposal, not a decision. The first slice returns `NotConfigured` and records that on `ProposalVerified`. When a check exists, the port reports only a mechanical verdict: schema, lint, hook, or test. It must not call a model. The CI sensor is that kind of check for a decision on a pull request.

### GitHub ingestion

A GitHub App on the organization sends HTTPS webhooks to `services/agent` on Render. The service checks `X-Hub-Signature-256`, treats `X-GitHub-Delivery` as idempotent, keeps the subscribed event types, and appends to `events`. Supabase is the log. GitHub does not call Supabase.

A push is one delivery. The body lists at most 20 commits. A larger push is completed with the compare API before the append. A merged pull request delivers `pull_request` with action `closed` and `merged: true`, and a `push` to the base branch. A pull request closed without a merge delivers only `pull_request`.

`CheckRecorded` is still appended by the CI command for that pull request, through the same append function. The webhook does not record `applies`, `cited`, or `violated`.

A one-time poll through that function loads history already on GitHub. The live feed is the webhook. Phase 1 appends `CheckRecorded` from CI and does not run the receiver. Phase 3 turns the receiver on.

## Phases

Each phase is a demo by itself. The first demo is one an architect recognizes.

### Phase 1 — Architect workspace on one repository

1. Event log and human approval of proposals. Discussion on the research view is not approval.
2. Ingest existing ADRs into a decision stream: status, rejected alternatives, path globs.
3. CI command on the pull request under test. It selects applicable decisions, runs the mechanical sensor, fails the job on `violated`, and appends `CheckRecorded` with the pull request, the SHA, the ADR ids, and `applies`, `cited`, or `violated`. The webhook receiver waits until phase 3.
4. Research session the user leads. Deterministic retrieval, then a generated view. Every panel cites an event, a path, or a pull request. An uncited panel is invalid.
5. The team discusses that view. An ADR draft is a proposal card on it. A human member accepts or rejects it.
6. The React catalog is the first renderer of that view: decision map, implementation list, pull request library, gap list, proposal card.
7. One accepted decision compiles one path-scoped negative rule, and that rule is the sensor CI runs.

Demo line: the architect leads a payments investigation, the team discusses the generated view, a human accepts a supersession, and the next pull request fails CI with `violated` on that ADR while the library records that the ADR applied.

Day-one value, before any model spend: ingest the ADR directory, run the CI command on one pull request, and show which ADRs applied and which were violated. The generated view is empty until those facts exist to cite.

### Phase 2 — Harness loop on those decisions

Bootstrap (`AGENTS.md`, `.cursor/rules`, skill), verify (dead references, contradictions, token budget, drift), and eval (`helpful` / `harmful` / `inert`). Harmful artifacts come back to the same proposal card. Retrieval tools for coding agents: `search_decisions`, `get_constraints_for_paths`, `get_rejected_alternatives`.

### Phase 3 — Wider evidence

The GitHub App webhook on `services/agent` appends the selected events. Review findings and `learned_from`. A human-confirmed "implements" claim, kept separate from `applies` / `cited` / `violated`. Cross-repo etalon rollout. A real Jev adapter for the proposals that need a mechanical check. Jira, Slack, and further agent runtimes are new event types when a team asks.

## Out of scope

- A compiler whose main job is writing one instruction file into ten vendor formats.
- A model as the judge of whether a rule was followed, or as the author of an accepted decision.
- Curated packs of positive "write the code like this" prose.
- Pasting the ADR corpus into every agent prompt.
- The A2UI wire protocol before the React catalog renders the research view.
- Full GitHub ingestion before the CI command records `applies`, `cited`, and `violated` for the pull request it is running on.
- Treating `touches`, a sensor failure, or a model verdict as the ADR library.

## Risks

- **Cold start.** The first screen ingests ADRs and open pull requests that already exist. An empty log is not the demo.
- **A stale overview.** `applies`, `cited`, and `violated` stay labeled as those three relations. A path intersection is not shown as a citation, and a violation is not shown as a changed decision.
- **False ADR merges.** Two decisions that sound alike and constrain different things. The proposal shows both constraints side by side.
- **Overview scope.** The catalog renders the research view. A panel without a citation is invalid. The agent does not invent a page, and it does not lead the investigation.
- **Research drift.** The view cites events, paths, and pull requests. An uncited panel is dropped.
- **The rules lag this draft.** Implementing phase 1 against the current Cursor rules would refuse the decision stream and the pull-request links. Update the rules first.
- **Eval cost.** Phase 2 shows the spend before a replay starts.

## Open questions

- Phase 1 path links: parsed from ADR text, or confirmed by the architect on ingest?
- Does the research brief live only on the proposal payload, or is the generated view its own stream?
- Are comments in the discussion step events, or are they outside the log until someone turns one into a proposal?
- When Jev gets a real adapter, which proposals must pass that mechanical check before a human can approve: ADR acceptance, harness compile, or both?

## Sources

- Böckeler, *Harness engineering for coding agent users*, martinfowler.com, April 2026.
- *Guardrails Beat Guidance*, arXiv 2604.11088.
- [A2UI](https://a2ui.org/), v0.9.1 current, v1.0 candidate as of June 2026.
- adrkit, adr-kit, adr-warden, Harbor, optirule — as linked above.
