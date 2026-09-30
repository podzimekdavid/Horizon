# Horizon

Horizon is a team system that compiles an architectural decision into the harness a coding agent actually runs, then proposes a change when code, review, or an eval shows that harness no longer holds.

Pitch:

> Log4brains tells a human which decision was made. Rulesync copies that markdown into every tool. Horizon compiles the decision into the harness the agent runs, and proposes an update when the code or a review shows the harness has drifted.

This is the first product draft. It records the idea, the wedge, and the order in which to build it. Phase 1 below matches the implementation boundary already drafted in `.cursor/rules/` on `cursor/horizon-agent-rules`.

## Problem

Three piles of files are supposed to steer coding agents, and none of them stays true:

- **Decisions** (ADRs) say what the team chose and what it rejected. Most architectural choices never become an ADR. They happen in a chat and disappear. Teams that do write ADRs usually abandon them within weeks or months, because authoring sits outside the work of shipping.
- **Harness** (rules, skills, prompts, hooks) is how an agent is told to behave. `CLAUDE.md` and `.cursorrules` are context, not enforced configuration. Adherence drops as a session gets longer. A 2026 study of 679 rule files and 5 000+ Claude Code runs found that random rules raise task success about as much as expert-written ones (+13.8 pp). Negative constraints help. Positive directives ("follow the code style") tend to hurt. Context files often raise cost by more than 20 % without a better result. ([Guardrails Beat Guidance](https://arxiv.org/html/2604.11088))
- **Evidence** (pull requests, review comments, CI, agent sessions) is what actually happened. It is not linked back to the decision or the rule that was supposed to govern it.

Harness engineering already has a name. Birgitta Böckeler describes guides (feedforward: `AGENTS.md`, skills, conventions) and sensors (feedback: linters, types, tests) and notes that they are scattered across delivery, with room for tooling that configures, syncs, and reasons about them as one system. ([Harness engineering for coding agent users](https://martinfowler.com/articles/harness-engineering.html), April 2026)

An etalon of "best practice" prose is the wrong object to curate. The object is a decision compiled into a short guardrail or a mechanical sensor, plus a measurement of whether that artifact still earns its tokens.

## What already exists

The space around each pile is occupied. The joint organism is not.

| Layer | Who is there | What they stop at |
|---|---|---|
| Decision records for agents | [adrkit](https://adrkit.dev/), [adr-kit](https://github.com/rvdbreemen/adr-kit), [adr-warden](https://libraries.io/npm/adr-warden) | Typed ADRs, path scope, read-only MCP, regex or rubric checks, staleness. Per repository. |
| Team knowledge from ADR, Slack, and review | [Harbor](https://gethrbr.com/blog/architecture-decision-records-for-ai-agents) | Facts, supersession proposed to an owner, citation counts. |
| Format sync | Rulesync and similar compilers | One markdown file written out as Cursor, Claude, Codex, Copilot files. |
| Rule eval | [optirule](https://github.com/BaconMan1168/optirule) | A/B replay from git history, leave-one-out, single-player CLI. |
| Agent output eval | Promptfoo, Braintrust, Langfuse | The agent's answer, not the harness artifact. |
| Enterprise agent governance | Credo AI, HiddenLayer, and others | Security and policy for a CISO buyer. |

adr-kit already compiles a decision into a mechanical check inside one repo. optirule already measures whether a rule file changed behaviour. Nobody keeps the decision, the compiled harness, and the evidence in one log, then proposes the next decision from that evidence across a team's repositories.

## Product

A human accepts a decision. Horizon compiles the harness surfaces that should carry it: a path-scoped negative rule, a short skill, a prompt fragment, or a CI sensor. Usage, review, and eval write evidence back. When evidence says the decision is stale, two decisions collide, or a rule is harmful, Horizon proposes a supersession or a harness edit. A human approves. The accepted change is a new event. Projections rebuild from the log.

The graph is a projection. It is not the source of truth.

### Three kinds of knowledge

- **Decision.** Why it holds, what was rejected, which paths it governs. A decision with no sensor is a request. History is kept. Dedup means a supersession link or a consolidation proposal ("ADR-007 and ADR-012 cover the same topic and differ in one constraint"), with a structured diff and citations. It does not mean deleting the older record.
- **Harness artifact.** Rule, skill, prompt, or hook. Each one cites the decision it was compiled from. A rule that cites no decision is debt.
- **Evidence.** A pull request, a review finding, a CI result, an eval. A `learned_from` edge records which evidence triggered a proposed change.

### Event log

Append-only. Schema-validated. Replayable without a model. The model may author a candidate. It does not approve one, and it does not judge correctness. Deterministic checks (schema, lint, hook, test) produce verdicts. Auto-generated rule checkers miss violations often enough that a model must not be the compliance judge.

Illustrative events:

| Event | Who records it | What follows |
|---|---|---|
| `DecisionAccepted` | A human, after an agent draft | A constraint, including rejected alternatives |
| `HarnessCompiled` | The compiler | A rule, skill, prompt, or CI sensor linked to that decision |
| `ViolationDetected` | CI, a hook, or a review | Evidence the harness or the decision failed |
| `EvalCompleted` | Replay of tasks from git history | `helpful`, `harmful`, or `inert`, plus token cost |
| `ChangeProposed` | Drift detector or a model | Supersession, merge, or a harness edit |
| `ChangeApproved` | A human | A new decision version and a recompiled harness |

Names in the table are the product language. Phase 1 uses the closed stream set in the event-log rule (`organization`, `membership`, `rule`, `skill`, `prompt`, `evaluation`, `proposal`) and the proposal sequence `ProposalCreated` → `ProposalVerified` → `ProposalApproved` or `ProposalRejected`.

### Who it is for

A team already running coding agents across more than one repo, with someone who currently checks by hand whether `AGENTS.md` still matches the decisions. One person uses the same loop inside a single repo: bootstrap from an etalon, verify, eval. The team layer adds a shared etalon, rollout, and an approval inbox across repositories.

Architects and lead engineers work in a web explorer and an inbox, approving proposals the way they approve a pull request. An agent-rendered UI (A2UI) can show a drift dashboard later. It is not the product.

### Stack already chosen

- `supabase/` — Postgres, Auth, RLS, Storage. The event table is the system of record. Projection tables are rebuilt from events.
- `services/agent/` — Kotlin, Ktor, Koog. Custom commands and every model workflow. Koog memory stores agent checkpoints only.
- `apps/web/` — Vite, React, TypeScript. Renders projections and sends commands a member is allowed to record.
- Every tenant-owned row has `org_id`.
- Jev (typesafe verification) is a port. Phase 1 ships `NotConfigured` and records that outcome on `ProposalVerified`.

## Phases

Each phase is a demo by itself.

### Phase 1 — Harness loop

In scope: rules, skills, prompts, evaluations, proposals. Decisions, pull requests, review findings, incidents, and a knowledge-graph product stay out. If a task needs one of them, stop and ask.

1. Event schema and append-only log. Projections rebuild from events.
2. One etalon. A TypeScript/Node service pack: one path-scoped negative rule, one short skill, one prompt fragment. The rule's rationale names the constraint it enforces. The decision stream itself is not built yet.
3. `horizon init` writes `AGENTS.md`, `.cursor/rules`, and the skill.
4. Verify: dead references, contradictions, token budget, drift against the repo.
5. Eval on a handful of tasks from git history. Label each artifact `helpful`, `harmful`, or `inert`.
6. Approval inbox. A proposal to drop or edit a harmful rule. A human approves. The agent service account cannot append approval.

Demo line: a rule entered the log, an eval said it does not earn its tokens, a human approved the removal, the projection updated from the new event.

Day-one value on an existing repo, before any eval spend: ingest current rules and skills and report which cite nothing, which contradict each other, and which blow the token budget.

### Phase 2 — Decisions compile the harness

Add a decision stream. `DecisionAccepted` compiles `HarnessCompiled`. Read-only retrieval for agents: `search_decisions`, `get_constraints_for_paths`, `get_rejected_alternatives`.

Demo line: the same task without the harness violates the decision; with the harness the agent cites it and the sensor catches a slip.

Consolidation and supersession proposals land in the same inbox. A false merge of two similar decisions with different constraints is the failure mode to design against: the proposal shows both constraints side by side.

### Phase 3 — Evidence from the lifecycle

Link the software development lifecycle as an evidence spine. Three sources are enough: GitHub pull requests, CI, and agent sessions. That covers decision, harness, and what the agent did. Jira, Slack, and every agent runtime are further event types, added when a team asks for them.

`ViolationDetected` and `learned_from` close the loop. Rollout of an etalon across repos is a staged proposal, not a silent push.

## Out of scope for the product

- A compiler whose main job is writing one instruction file into ten vendor formats. `AGENTS.md` is becoming the shared file. Sync is a commodity.
- A model as the judge of whether a rule was followed.
- Curated packs of positive "write the code like this" prose. Those packs are priming. The etalon holds constraints and sensors tied to a named decision.
- An integration of every system in the lifecycle before the three sources above work.
- Loading an entire ADR corpus into every agent prompt. Retrieval is path-scoped. Trust comes from the sensor, not from a longer prompt.

## Risks

- **Cold start.** An empty log has no value. Horizon starts from artifacts that already exist: ADRs in the repo, `AGENTS.md`, pull requests, CI. Writing a record beside the work is how earlier ADR tools died.
- **A stale projection.** A decision nobody cites, and a rule with no eval, are shown as debt. They are not served as quiet truth.
- **Platform absorption.** Cursor team rules, skills.sh benchmarks, and adr-kit's guardian can each close part of the loop inside one vendor or one repo. Horizon's position is cross-tool, and it is the only place the decision, the harness, and the evidence co-evolve.
- **Eval cost and noise.** An agent run is slow and paid. Repeats and a real comparison (paired tests, confidence intervals) are part of the eval design. Phase 1 can demo the pipeline on a few tasks. It should show the spend before it starts.
- **Scope.** Phase 1 is the harness loop. The decision compiler and the lifecycle evidence wait until that loop approves a real change from a real event.

## Open questions

- Which single etalon is the hackathon story: TypeScript service, or a stack this team already has?
- Does phase 1 store the constraint text inside the rule payload, or only a free-text rationale, until the decision stream exists?
- What is the smallest eval that is honest: optirule-style replay, or a scripted pair of runs with the cost printed up front?
- When Jev gets a real adapter, which proposals must pass it before a human can approve?

## Sources

- Böckeler, *Harness engineering for coding agent users*, martinfowler.com, April 2026.
- *Guardrails Beat Guidance*, arXiv 2604.11088.
- adrkit, adr-kit, adr-warden, Harbor, optirule — as linked above.
