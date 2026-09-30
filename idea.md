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

1. The architect opens "payments boundary".
2. The overview shows ADR-012 (accepted), the rejected alternative "shared database", the modules under `src/payments`, three open pull requests whose diffs touch those paths, and a gap: ADR-004 governs no path.
3. They ask whether pull request 481 contradicts ADR-012.
4. Research returns a brief. Every claim cites a decision, a path, or a pull request. The agent proposes a superseding ADR or a review note.
5. The architect accepts the ADR. The harness recompiles the constraint. Pull request 481 stays on the decision as an observed touch until someone confirms that it implements or conflicts.

### Architect workspace

#### Research engine

The engine answers questions about this system. It is not a web search box and not a chat that invents architecture.

It must answer:

- What is currently decided about this area, and which alternatives were rejected?
- Which modules and paths implement it?
- Which open and merged pull requests touch those paths?
- Where does the code diverge from the decision?
- Which existing decisions overlap or conflict with the draft I am about to write?
- What is missing: a governed path with no decision, or a decision with no path?

Two passes:

1. **Retrieval is deterministic.** Status, supersession chain, path match, and pull-request intersection come from the projection. No model in this pass.
2. **The brief is written by the model, and every sentence cites a decision, a path, or a pull request.** Uncited sentences are dropped. The brief is attached to a proposal. It is not a second source of truth.

The same engine runs before a new ADR is drafted, so a duplicate or a conflict shows up while the architect is still researching.

#### ADR development

The record is written from the research brief, or from a gap the overview already shows (a pull request that decided something, a boundary with no ADR).

The agent drafts context, the decision, rejected alternatives, consequences, and the paths it should govern. The architect edits and accepts. Acceptance is `DecisionAccepted`. A later change is a supersession or a consolidation proposal ("ADR-007 and ADR-012 cover the same topic and differ in one constraint"), shown as a structured diff with both constraints visible. History stays. Dedup does not delete the older record.

Status is `proposed`, `accepted`, `rejected`, or `superseded`. Superseded records stay readable, including the alternatives they rejected.

#### Agentic overview

The overview is a surface the agent fills. The web app renders it from a fixed catalog. The agent picks components and data from that catalog. It does not generate UI code. That is the A2UI shape: declarative, catalog-limited, client-rendered ([A2UI](https://a2ui.org/), production spec v0.9.1, v1.0 still a candidate). Phase 1 renders the catalog in the React app. Speaking the A2UI wire protocol waits until the same surface is worth opening in another client.

Catalog for the first overview:

| Component | What it shows |
|---|---|
| Decision map | Accepted, proposed, and superseded decisions for the area |
| Implementation list | Paths and modules the decision governs |
| Pull request list | Open and merged pull requests, each marked `touches`, `implements`, or `conflicts` |
| Gap list | Decision with no path, path or pull request with no decision |
| Proposal card | The draft ADR or harness edit, with approve and reject |

The same projection is visible without a model call. The agent rearranges and explains it. The chat is how the architect asks. The overview is where they work.

#### Links to implementations and pull requests

Links are edges, not a paragraph inside the ADR.

| Edge | Meaning | How it is recorded |
|---|---|---|
| `governs` | Decision → path glob or module | On the decision, confirmed by the architect |
| `touches` | Pull request diff intersects a governed path | Observed. Recomputed from GitHub. No model |
| `implements` / `conflicts` | The pull request carries or breaks the decision | Interpretation. A proposal until a human confirms |
| `compiled_to` | Decision → rule, skill, prompt, or sensor | Written when the harness is compiled |
| `learned_from` | Evidence → the proposal it triggered | Written with the proposal |

"This pull request changed a governed path" is a fact. "This pull request implements the decision" is a claim.

### Harness loop

An accepted decision compiles the surfaces that should carry it: a path-scoped negative rule, a short skill, a prompt fragment, or a CI sensor. A rule that cites no decision is debt. A decision with no sensor is a request the agent can ignore.

Eval replays tasks from git history and labels an artifact `helpful`, `harmful`, or `inert`, with token cost. A harmful rule becomes a proposal to drop or edit it. The architect approves. The projection rebuilds from the new event.

Coding agents read the current decision through retrieval (`search_decisions`, `get_constraints_for_paths`, `get_rejected_alternatives`), scoped to the paths in play. The corpus is not pasted into every prompt.

### Event log

Append-only. Schema-validated. Replayable without a model.

| Event | Who records it | What follows |
|---|---|---|
| `DecisionProposed` | Agent or architect | A draft attached to a research brief |
| `DecisionAccepted` | A human | The current constraint, rejected alternatives, and governed paths |
| `DecisionSuperseded` | A human, via a proposal | The old record stays, the new one governs |
| `LinkConfirmed` | A human | `implements` or `conflicts` on a pull request |
| `HarnessCompiled` | The compiler | A rule, skill, prompt, or sensor linked to the decision |
| `ViolationDetected` | CI, a hook, or a review | Evidence the decision or the harness failed |
| `EvalCompleted` | Replay from git history | `helpful`, `harmful`, or `inert`, plus token cost |
| `ProposalApproved` / `ProposalRejected` | A human member | The accepted change is a separate event |

`touches` is not an event. It is a projection of path globs against pull request diffs.

Proposal sequence for anything the model drafts: `ProposalCreated` → `ProposalVerified` → `ProposalApproved` or `ProposalRejected`. The agent service may record `ProposalCreated` and `ProposalVerified`. It must not record approval. Approval does not edit a projection by itself.

The Cursor rules still close streams at `organization`, `membership`, `rule`, `skill`, `prompt`, `evaluation`, `proposal`. This draft adds `decision` and confirmed links. Observed pull requests can stay outside the log, as a projection fed by GitHub.

### Who it is for

Architects and lead engineers are the primary users. They research an area, develop the ADR, and read the overview of decisions, implementations, and pull requests.

Coding agents are the second user. They retrieve the current decision and run the compiled harness.

A team shares one log across repositories. One person can run the same loop in a single repo. Rollout of an etalon across repos is a staged proposal.

### Stack already chosen

- `supabase/` — Postgres, Auth, RLS, Storage. The event table is the system of record. Projection tables, including observed pull-request coverage, are rebuilt from events and from GitHub.
- `services/agent/` — Kotlin, Ktor, Koog. Research briefs, ADR drafts, harness compilation, and every model call. Koog memory stores agent checkpoints only.
- `apps/web/` — Vite, React, TypeScript. Renders the architect catalog and sends commands a member is allowed to record.
- Every tenant-owned row has `org_id`.
- Jev (typesafe verification) is a port. The first slice ships `NotConfigured` and records that outcome on `ProposalVerified`.

## Phases

Each phase is a demo by itself. The first demo is one an architect recognizes.

### Phase 1 — Architect workspace on one repository

1. Event log and human approval of proposals.
2. Ingest existing ADRs into a decision stream: status, rejected alternatives, path globs.
3. Observed `touches`: open pull requests whose diffs intersect those paths.
4. Research query. Deterministic retrieval, then a cited brief.
5. ADR draft from that brief. The architect accepts or rejects it in the proposal card.
6. Overview catalog: decision map, implementation list, pull request list, gap list, proposal card. The React app renders it. The agent fills it.
7. One accepted decision compiles one path-scoped negative rule, so the harness side of the log exists.

Demo line: the architect asks what governs payments, sees the ADR, the paths, and the open pull requests, accepts a supersession, and the compiled rule cites the new decision.

Day-one value, before any model spend: ingest the ADR directory and open pull requests, and show decisions with no path and pull requests that touch a governed path.

### Phase 2 — Harness loop on those decisions

Bootstrap (`AGENTS.md`, `.cursor/rules`, skill), verify (dead references, contradictions, token budget, drift), and eval (`helpful` / `harmful` / `inert`). Harmful artifacts come back to the same proposal card. Retrieval tools for coding agents: `search_decisions`, `get_constraints_for_paths`, `get_rejected_alternatives`.

### Phase 3 — Confirmed evidence

Review findings, CI violations, and `learned_from`. Confirmed `implements` / `conflicts` beyond observed `touches`. Cross-repo etalon rollout. A real Jev adapter for the proposals that need it. Jira, Slack, and further agent runtimes are new event types when a team asks.

## Out of scope

- A compiler whose main job is writing one instruction file into ten vendor formats.
- A model as the judge of whether a rule was followed, or as the author of an accepted decision.
- Curated packs of positive "write the code like this" prose.
- Pasting the ADR corpus into every agent prompt.
- The A2UI wire protocol before the React catalog is the overview architects actually use.
- Integrations beyond one Git host's pull requests, until phase 1 links are real.

## Risks

- **Cold start.** The first screen ingests ADRs and open pull requests that already exist. An empty log is not the demo.
- **A stale overview.** A decision with no path, and a pull request that only `touches`, are shown as such. Observed touch is not labeled "implements".
- **False ADR merges.** Two decisions that sound alike and constrain different things. The proposal shows both constraints side by side.
- **Overview scope.** The catalog is five components. A new panel is a new component in that list, not a generated page.
- **Research drift.** The brief cites the log. A sentence without a citation is dropped.
- **The rules lag this draft.** Implementing phase 1 against the current Cursor rules would refuse the decision stream and the pull-request links. Update the rules first.
- **Eval cost.** Phase 2 shows the spend before a replay starts.

## Open questions

- Phase 1 path links: parsed from ADR text, or confirmed by the architect on ingest?
- Does the research brief live only on the proposal payload?
- First overview: agent-filled catalog only, or the static projection beside it from the start? This draft says both, with the static projection always available.
- When Jev gets a real adapter, which proposals must pass it before a human can approve: ADR acceptance, harness compile, or both?

## Sources

- Böckeler, *Harness engineering for coding agent users*, martinfowler.com, April 2026.
- *Guardrails Beat Guidance*, arXiv 2604.11088.
- [A2UI](https://a2ui.org/), v0.9.1 current, v1.0 candidate as of June 2026.
- adrkit, adr-kit, adr-warden, Harbor, optirule — as linked above.
