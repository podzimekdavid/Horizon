# Technical design

Binding for phase 1. Phase 2 and 3 packages extend it. They do not replace the event envelope.

## Topology

```
apps/web  --user JWT-->  supabase.events (insert) and projections (select)
apps/web  --user JWT-->  services/agent  --service role-->  supabase.events
GitHub Action --------->  CI command in services/agent  --append CheckRecorded-->
```

`apps/web` is a Vite + React + TypeScript SPA. It reads projections and appends an event only when RLS can authorize that insert alone. Research rendering, ADR drafts, and any multi-stream command go to `services/agent`.

`services/agent` is Kotlin, JDK 17+, Ktor, Koog 1.0.x stable. Koog stores checkpoints only.

`supabase/` is Postgres, Auth, RLS. The event table is the record.

## Event envelope

```sql
create table public.events (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  stream_id uuid not null,
  stream_type text not null,
  version int not null,
  event_type text not null,
  schema_version int not null,
  payload jsonb not null,
  actor_id uuid not null,
  occurred_at timestamptz not null default now(),
  unique (stream_id, version)
);
```

Insert-only for clients. No `UPDATE` or `DELETE` policy on `events` or on projection tables. A security-definer function owned outside the exposed API schema folds projections. Application code does not update them.

Event names are past-tense PascalCase. `schema_version` starts at 1.

## Streams

| stream_type | Events in phase 1 |
|---|---|
| `organization` | `OrganizationCreated` |
| `membership` | `MemberAdded` |
| `proposal` | `ProposalCreated`, `ProposalVerified`, `ProposalApproved`, `ProposalRejected` |
| `decision` | `DecisionProposed`, `DecisionAccepted`, `DecisionRejected`, `DecisionSuperseded` |
| `check` | `CheckRecorded` |
| `research_session` | `ResearchSessionOpened`, `DiscussionNoted` |
| `harness` | `HarnessCompiled` |

`ProposalCreated` payload names the target stream and carries the draft. `ProposalApproved` does not copy the draft into a projection by itself. The command that observes approval appends the domain event (`DecisionAccepted`, `HarnessCompiled`).

`CheckRecorded` payload:

```json
{
  "pull_request": 481,
  "sha": "abc",
  "adr_ids": ["ADR-012"],
  "relation": "violated"
}
```

`relation` is exactly one of `applies`, `cited`, `violated`. One event per relation. A single CI run may append three events on the same check stream, versions in order.

## Projections

Rebuilt only by the fold.

| Projection | Key | Source |
|---|---|---|
| `decisions` | decision stream id | decision events. Governing globs exist only after `DecisionAccepted`. |
| `proposals` | proposal stream id | proposal events. Status `proposed`, `verified`, `approved`, `rejected`. |
| `checks` | check event id | `CheckRecorded`. Never collapsed into a single "used" flag. |
| `harness_artifacts` | harness stream id | `HarnessCompiled`, with `decision_id`. |
| `discussions` | research session id + version | `DiscussionNoted`. |

Gaps are queries, not stored truth: an accepted decision with an empty glob list; a `violated` check whose decision is not accepted.

## Commands

| Command | Who may call | Appends | Must refuse |
|---|---|---|---|
| Ingest ADR | human via agent service | `ProposalCreated`, `DecisionProposed` | `DecisionAccepted` |
| Accept proposal | human member, RLS | `ProposalApproved`, then the domain event | service account |
| Verify proposal | agent service | `ProposalVerified` | a model call |
| Record check | CI command, service account | `CheckRecorded`, maybe `ProposalCreated` | `DecisionSuperseded` |
| Open research | human via web | `ResearchSessionOpened` | the agent opening one unprompted |
| Note discussion | human member | `DiscussionNoted` | treating it as approval |
| Fill view | agent service | catalog JSON in the HTTP response; `ProposalCreated` only when the user asks to draft | `ProposalApproved` |
| Compile harness | agent service after acceptance | `HarnessCompiled` | an artifact with no decision id |

Optimistic concurrency uses `version`. On unique conflict, reread and retry the command. Do not update the row.

## CI command

Input is the pull request the job is running for: number, SHA, changed paths, and the pull request body plus any agent-output text the workflow passes in. The command does not list the repository's other pull requests.

1. Load accepted decisions whose globs match a changed path.
2. For each match, append `CheckRecorded` with `applies`.
3. If the body or the agent text contains that ADR id, append `cited`.
4. Run the mechanical sensor for that decision against the diff. On failure, append `violated` and set the process exit code to non-zero.
5. If this decision already has a `violated` check on an older SHA, append `ProposalCreated` asking a human to look. Do not append a decision event.

No sensor compiled yet: WP-04 ships a fixture sensor for one decision id. WP-08's output replaces it. Absence of a sensor for a matched decision records `ProposalVerified`-style honesty as a check payload field `sensor: "missing"` and does not pretend the decision was enforced. It still records `applies`. It does not record `violated`.

## Research read

`GET` on the agent service, user JWT forwarded, org taken from membership.

Response:

```json
{
  "area": "payments",
  "decisions": [{ "id": "ADR-012", "status": "accepted", "event_id": "…", "globs": ["src/payments/**"] }],
  "lineage": [{ "from": "ADR-004", "to": "ADR-012", "event_id": "…" }],
  "checks": [{ "pull_request": 481, "relation": "violated", "adr_ids": ["ADR-012"], "event_id": "…" }],
  "gaps": [{ "kind": "decision_without_glob", "adr_id": "ADR-004", "event_id": "…" }],
  "proposals": [{ "id": "…", "status": "proposed", "event_id": "…" }]
}
```

This payload is what panels cite. The model is not on this path.

## Catalog

The agent service returns this. The web app renders it. Unknown component names are dropped.

```json
{
  "question": "Does PR 481 contradict ADR-012?",
  "panels": [
    {
      "component": "DecisionMap",
      "citations": ["event-id"],
      "data": {}
    }
  ]
}
```

Components: `DecisionMap`, `ImplementationList`, `PullRequestLibrary`, `GapList`, `ProposalCard`.

`ProposalCard` data includes the proposal id. Approve and reject call the accept command. No other component appends `ProposalApproved`.

## Authority

| Actor | ProposalCreated | ProposalVerified | ProposalApproved | CheckRecorded | DecisionAccepted |
|---|---|---|---|---|---|
| Human member | yes | no | yes | no | via the accept command |
| Agent service | yes | yes | no | yes, from CI | no |
| Browser, direct | only if RLS allows a single insert | no | yes, if member | no | no |

## Layout

```
supabase/          WP-01, plus projection SQL the later packages add
services/agent/    WP-02, WP-03, WP-04, WP-05, WP-07, WP-08
apps/web/          WP-06
.github/workflows/ WP-04
.cursor/rules/     WP-00
docs/spec/         this assignment, read-only during implementation
```

## Not in phase 1

Full GitHub ingestion, A2UI on the wire, MCP retrieval, eval replay, Jira, Slack, a graph database, a model as judge, client `UPDATE` of any projection.
