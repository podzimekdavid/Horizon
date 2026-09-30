# Technical design

Binding for phase 1. Phase 2 and 3 packages extend it. They do not replace the event envelope.

## Topology

```
apps/web  --user JWT-->  supabase projections (select)
apps/web  --user JWT-->  approve_proposal / reject_proposal / DiscussionNoted
apps/web  --user JWT-->  services/agent
services/agent  --horizon_writer-->  supabase.events
GitHub Action --> CI command --horizon_ci-->  CheckRecorded
```

`apps/web` is a Vite + React + TypeScript SPA. It reads projections with the user JWT. It inserts only the event types granted to a member (`ResearchSessionOpened`, `DiscussionNoted`). Approval goes through `approve_proposal` or `reject_proposal`. Research rendering, ADR drafts, and any multi-stream command go to `services/agent`.

`services/agent` is Kotlin, JDK 17+, Ktor, Koog 1.0.x stable. Koog stores checkpoints only. Runtime writes use `horizon_writer` or `horizon_ci`. The service role is not a runtime writer. The research read forwards the user JWT and uses `security invoker`, so RLS cuts the tenant. `org_id` is not a client-chosen filter that can see another organization.

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

create table public.event_type_grants (
  role_name text not null,
  event_type text not null,
  primary key (role_name, event_type)
);
```

Insert-only for clients. No `UPDATE` or `DELETE` policy on `events` or on projection tables. A `BEFORE INSERT` trigger on `events`:

- sets `actor_id` from `auth.uid()` for a user JWT
- sets `actor_id` from the role session setting for `horizon_writer` and `horizon_ci`
- ignores any `actor_id` in the payload
- rejects an `event_type` that `event_type_grants` does not grant to the current role

The service role is not granted runtime inserts. A security-definer fold, owned outside the exposed API schema, rebuilds projections. Application code does not update them.

WP-01 creates the trigger and the grants table. Later packages insert rows into `event_type_grants`. They do not edit the trigger.

Event names are past-tense PascalCase. `schema_version` starts at 1.

### Grants

| Role | Event types |
|---|---|
| member (`authenticated`) | `ResearchSessionOpened`, `DiscussionNoted` |
| `horizon_writer` | `ProposalCreated`, `ProposalVerified`, `DecisionProposed`, `PullRequestReceived` |
| `horizon_ci` | `CheckRecorded`, `ProposalCreated` of kind `review_violations` only |
| `approve_proposal` / `reject_proposal` | `ProposalApproved` or `ProposalRejected`, plus the one domain event the kind names |

`OrganizationCreated` and `MemberAdded` are seed and admin writes, not member inserts.

## Streams

| stream_type | Events in phase 1 |
|---|---|
| `organization` | `OrganizationCreated` |
| `membership` | `MemberAdded` |
| `proposal` | `ProposalCreated`, `ProposalVerified`, `ProposalApproved`, `ProposalRejected` |
| `decision` | `DecisionProposed`, `DecisionAccepted`, `DecisionRejected`, `DecisionSuperseded` |
| `check` | `CheckRecorded` |
| `pull_request` | `PullRequestReceived` |
| `research_session` | `ResearchSessionOpened`, `DiscussionNoted` |
| `harness` | `HarnessCompiled` |

A proposal payload has a `kind`: `accept_decision`, `reject_decision`, `supersede`, `compile_harness`, or `review_violations`.

`approve_proposal(proposal_id)` runs as the calling member, in one transaction:

- kind `accept_decision` appends `ProposalApproved` and `DecisionAccepted`
- kind `reject_decision` is not approved; `reject_proposal` appends `ProposalRejected` and `DecisionRejected`
- kind `supersede` appends `ProposalApproved`, `DecisionSuperseded` on the old stream, and `DecisionAccepted` on the new stream
- kind `compile_harness` appends `ProposalApproved` and `HarnessCompiled` copied from the candidate already stored on the proposal. The function does not run a model or a compiler

`reject_proposal` appends `ProposalRejected` and, for a decision draft, `DecisionRejected`.

A direct insert of `ProposalApproved`, `DecisionAccepted`, `DecisionRejected`, `DecisionSuperseded`, or `HarnessCompiled` from the browser fails the trigger.

## Pull request stream identity

One `pull_request` stream per `(org_id, repository, pull_request)`, written only by the GitHub webhook receiver through `append_pull_request_received`. Its `stream_id` is a UUIDv3 of a name that starts with the stream type, so it never equals the check stream's UUIDv5 for the same pull request. The function reads the next version under a per-stream lock, dedupes on `payload.delivery_id`, and refuses a stream id that belongs to another stream type.

## Check identity

One check stream per `(org_id, repository, pull_request)`. `stream_id` is the UUIDv5 of those three fields. Callers do not invent it.

```json
{
  "repository": "podzimekdavid/horizon",
  "pull_request": 481,
  "sha": "abc",
  "adr_id": "ADR-012",
  "relation": "violated"
}
```

`adr_id` is one id. One event per decision per relation. A run that applies, cites, and violates one ADR appends three events on that stream, versions in order. `sensor` is present on `applies` when the value is `"missing"`.

## Projections

Rebuilt only by the fold.

| Projection | Key | Source |
|---|---|---|
| `decisions` | decision stream id | decision events. Governing globs exist only after `DecisionAccepted`. |
| `proposals` | proposal stream id | proposal events. Status `proposed`, `verified`, `approved`, `rejected`. Kind is kept. |
| `checks` | check event id | `CheckRecorded`. Never collapsed into a single "used" flag. Keyed with `repository`. |
| `harness_artifacts` | harness stream id | `HarnessCompiled`, with `decision_id`. |
| `discussions` | research session id + version | `DiscussionNoted`. |

Gaps are queries, not stored truth: an accepted decision with an empty glob list; a `violated` check whose decision is not accepted; two accepted decisions whose globs overlap. Overlap is not a `conflict` relation.

## Commands

| Command | Who may call | Appends | Must refuse |
|---|---|---|---|
| Ingest ADR | human via agent service, `horizon_writer` | `ProposalCreated`, `DecisionProposed` | `DecisionAccepted` |
| `approve_proposal` | human member | `ProposalApproved` and the domain event for the kind | writer role, browser insert, service role |
| `reject_proposal` | human member | `ProposalRejected` and `DecisionRejected` when the target is a decision | writer role |
| Verify proposal | `horizon_writer` | `ProposalVerified` | a model call |
| Record check | `horizon_ci` | `CheckRecorded`, and at most one open `review_violations` proposal | `DecisionSuperseded`, a second open proposal for the same repository and ADR |
| Open research | human via web | `ResearchSessionOpened` | the agent opening one unprompted |
| Note discussion | human member | `DiscussionNoted` | treating it as approval |
| Fill view | `horizon_writer` | catalog JSON in the HTTP response; `ProposalCreated` only when the user asks to draft | `ProposalApproved` |
| Compile harness | `horizon_writer`, onto a proposal | candidate sensor on the proposal payload | `HarnessCompiled` before approval; an artifact with no decision id |

Optimistic concurrency uses `version`. On unique conflict, reread and retry the command. Do not update the row.

## CI command

Input is the pull request the job is running for: repository, number, SHA, changed paths, and the pull request body plus any agent-output text the workflow passes in. The command does not list the repository's other pull requests.

1. Load accepted decisions whose globs match a changed path.
2. For each match, append `CheckRecorded` with `applies` and that one `adr_id` on the check stream for `(org, repository, pull_request)`.
3. If the body or the agent text matches that ADR id on a token boundary, append `cited`. `ADR-012` does not match `ADR-0120`.
4. If `HarnessCompiled` exists, run that mechanical sensor against the diff. On failure, append `violated` and set the process exit code to non-zero. If no sensor exists, set `sensor: "missing"` on the `applies` event, do not append `violated`, and leave the exit code 0.
5. If a `violated` row already exists for this repository and ADR and no open `review_violations` proposal exists, append one `ProposalCreated`. Further red SHAs append `CheckRecorded` only. Do not append a decision event.

WP-04 ships a fixture `Sensor` for one decision id. WP-08 adds the implementation behind the same interface. WP-04 does not edit the harness package.

## Research read

`GET` on the agent service. The user JWT is forwarded. The query runs as `security invoker`. The organization is the caller's membership, not a service-role filter in Kotlin.

Response:

```json
{
  "area": "payments",
  "decisions": [{ "id": "ADR-012", "status": "accepted", "event_id": "…", "globs": ["src/payments/**"] }],
  "lineage": [{ "from": "ADR-004", "to": "ADR-012", "event_id": "…" }],
  "checks": [{ "repository": "podzimekdavid/horizon", "pull_request": 481, "relation": "violated", "adr_id": "ADR-012", "event_id": "…" }],
  "gaps": [{ "kind": "decision_without_glob", "adr_id": "ADR-004", "event_id": "…" }],
  "proposals": [{ "id": "…", "status": "proposed", "kind": "accept_decision", "event_id": "…" }]
}
```

Panels cite those `event_id` values only. The model is not on this path.

## Catalog

The agent service returns this. The web app renders it. Unknown component names are dropped. A panel whose `citations` are not event ids from this response is dropped.

```json
{
  "question": "What has CI recorded for payments?",
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

`ProposalCard` data includes the proposal id. Approve calls `approve_proposal`. Reject calls `reject_proposal`. No component inserts `ProposalApproved`.

## Authority

| Actor | ProposalCreated | ProposalVerified | ProposalApproved | CheckRecorded | DecisionAccepted |
|---|---|---|---|---|---|
| Human member, direct insert | no | no | no | no | no |
| `approve_proposal` as that member | no | no | yes, with the domain event | no | yes, when the kind says so |
| `horizon_writer` | yes | yes | no | no | no |
| `horizon_ci` | only `review_violations`, once per open slot | no | no | yes | no |
| Service role at runtime | no | no | no | no | no |

## Layout

```
supabase/                         WP-01: envelope, trigger, grants table, fold
supabase/migrations/*proposal*    WP-02: grant rows and proposal fold only
supabase/migrations/*decision*    WP-03
supabase/migrations/*check*       WP-04
supabase/migrations/*harness*     WP-08
services/agent/.../proposal/      WP-02
services/agent/.../decision/      WP-03
services/agent/.../sensor/        WP-03: the Sensor interface
services/agent/.../ci/            WP-04
services/agent/.../harness/       WP-08
services/agent/.../research/      WP-05
services/agent/.../view/          WP-07
apps/web/                         WP-06
.github/workflows/                WP-04
.cursor/rules/                    WP-00
docs/spec/                        this assignment, read-only during implementation
```

A package edits only its directories. It inserts grant rows. It does not edit the trigger or another package's directory.

## Not in phase 1

Full GitHub ingestion, A2UI on the wire, MCP retrieval, eval replay, Jira, Slack, a graph database, a model as judge, client `UPDATE` of any projection, runtime use of the service role.
