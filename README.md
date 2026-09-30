# Horizon

Event-sourced engineering memory. Architects research the system, write ADRs, and see them against the pull requests CI has recorded. An accepted decision compiles into a sensor that agents run. **AI proposes, a human approves.**

## How it works

```mermaid
flowchart LR
    Web["apps/web<br/>React"] -->|member events| Log[("events<br/>append-only")]
    GH["GitHub PR"] -->|webhook| Agent["services/agent<br/>Kotlin · Koog"]
    CI["CI check"] -->|CheckRecorded| Log
    Agent -->|"ProposalCreated<br/>DecisionProposed"| Log

    Log -->|Postgres fold| Proj["projections<br/>decisions · checks · harness"]
    Proj --> Web

    Web -->|"approve_proposal"| Log
```

- **Events are the only record.** Projections are rebuilt from them.
- **The agent only proposes.** It cannot approve, reject, or accept a decision.
- **Approval is one function.** `approve_proposal` writes the approval and the domain event in one transaction.
- **Verdicts are mechanical.** Schema, lint, hook, or test. Never a model.

## Lifecycle

```mermaid
flowchart LR
    A[ProposalCreated] --> B[ProposalVerified]
    B --> C{Human}
    C -->|approve_proposal| D[DecisionAccepted<br/>or HarnessCompiled]
    C -->|reject_proposal| E[ProposalRejected]
```

## Layout

| Path | What |
|---|---|
| `supabase/` | Migrations, seed, config |
| `services/agent/` | Kotlin, Ktor, Koog: commands, AI, GitHub webhook |
| `apps/web/` | Vite, React, TypeScript (planned) |
| `cli/` | `horizon append` / `horizon list` |
| `docker/` | Local Supabase stack via compose |
| `docs/spec/` | Requirements, work packages, design, ADRs |

## Run locally

```sh
npm install
npm run db:start   # local Supabase + migrations
npm test           # db tests + CLI smoke test
```

## Docs

- [`idea.md`](idea.md): product narrative
- [`docs/spec/`](docs/spec/README.md): the assignment; wins over `idea.md` on conflict
