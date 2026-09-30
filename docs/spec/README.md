# Horizon specification

This folder is the assignment. `idea.md` is the product narrative. When they disagree, this folder wins.

Give one agent one work package. Pass that package, the ADRs it lists, and the design sections it lists. Do not pass the whole folder unless the task is a cross-cutting review.

## How to assign an agent

1. Pick a package in [work-packages.md](work-packages.md) whose dependencies are done.
2. Point the agent at that section, the requirement ids, and the ADR files named there.
3. The agent may edit only the paths under **Owns**.
4. **Done when** is the acceptance check. A package is not done because the code compiles.

## Map

| Doc | What an agent uses it for |
|---|---|
| [requirements.md](requirements.md) | Functional requirements, ids `FR-*` and `NFR-*` |
| [work-packages.md](work-packages.md) | The units of work. One package per agent. |
| [design.md](design.md) | Event envelope, projections, commands, CI, catalog JSON |
| [adr/](adr/) | Draft decisions for this product. Implementation follows them until a human supersedes them. That is not the decision status `proposed`, which means CI ignores the decision. |

## Order

Phase 1, in dependency order: WP-00, WP-01, WP-02, WP-03, then WP-04 and WP-08 in parallel, then WP-05, WP-06, WP-07.

Phase 2: WP-09, WP-10. Phase 3: WP-11. Do not start those inside a phase-1 package.

## Rules that every package inherits

- The event table is the only record. Projections are rebuilt from events.
- A model may draft. A human member approves by calling `approve_proposal` or `reject_proposal`. Those functions write the approval and the domain event in one transaction. The browser cannot insert `ProposalApproved`.
- Runtime event writes use `horizon_writer` or `horizon_ci`. The service role is not a runtime writer. `actor_id` comes from the session, not the payload.
- A compliance verdict is a schema check, a lint, a hook, or a test. A model must not judge compliance.
- `applies`, `cited`, and `violated` are three relations. A path intersection is not a citation. A violation does not change the decision.
- The user leads a research session. The agent renders a view. An uncited panel is invalid.
- Identifiers, schema names, comments, and commits are English.
- Every tenant-owned row has `org_id`. RLS uses membership and `auth.uid()`, never `user_metadata`.
