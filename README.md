<p align="center">
  <img src="docs/slides/public/ambient.jpg" alt="Horizon" width="520" />
</p>

# Horizon

**Architecture that keeps up with your agents.**

Horizon researches your system, drafts the decisions (ADRs), checks every pull request against them, and brings you only what needs a human call. **AI proposes, a human approves.**

## The loop

```mermaid
flowchart LR
    R["1 · Research<br/><i>what did we decide?</i>"] --> D["2 · Draft<br/><i>AI writes the ADR</i>"]
    D --> H["3 · Decide<br/><i>a human signs off</i>"]
    H --> E["4 · Enforce<br/><i>CI checks every PR</i>"]
    E --> L["5 · Learn<br/><i>drift comes back as a proposal</i>"]
    L --> R

    classDef step fill:#e4eed6,stroke:#6fa84a,color:#0b120e;
    classDef human fill:#c6e89a,stroke:#6fa84a,stroke-width:3px,color:#0b120e;
    class R,D,E,L step;
    class H human;
```

## How it works

```mermaid
flowchart LR
    Web["apps/web<br/>React"] -->|member events| Log[("events<br/>append-only")]
    Agent["services/agent<br/>Kotlin · Koog"] -->|"polls PRs"| GH["GitHub PR"]
    CI["CI check"] -->|CheckRecorded| Log
    Agent -->|"ProposalCreated<br/>DecisionProposed"| Log

    Log -->|Postgres fold| Proj["projections<br/>decisions · checks · harness"]
    Proj --> Web
    Web -->|"approve_proposal"| Log

    classDef store fill:#c6e89a,stroke:#6fa84a,color:#0b120e;
    classDef node fill:#e4eed6,stroke:#6fa84a,color:#0b120e;
    class Log,Proj store;
    class Web,GH,Agent,CI node;
```

- **Events are the only record.** Projections are rebuilt from them.
- **The agent only proposes.** It cannot approve, reject, or accept a decision.
- **Approval is one function.** `approve_proposal` writes the approval and the domain event in one transaction.
- **Verdicts are mechanical.** Schema, lint, hook, or test. Never a model.

## Layout

| Path | What |
|---|---|
| `supabase/` | Migrations, seed, config |
| `services/agent/` | Kotlin, Ktor, Koog: commands, AI, GitHub pull request poller |
| `apps/web/` | Vite, React, TypeScript (planned) |
| `cli/` | `horizon append` / `horizon list` |
| `docker/` | Local Supabase stack via compose |
| `docs/spec/` | Requirements, work packages, design, ADRs |
| `docs/slides/` | Pitch deck (Slidev) |

## Run locally

```sh
npm install
npm run db:start   # local Supabase + migrations
npm test           # db tests + CLI smoke test
```

## Docs

- [`idea.md`](idea.md): product narrative
- [`docs/spec/`](docs/spec/README.md): the assignment; wins over `idea.md` on conflict
