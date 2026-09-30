# ADR-0004: CI writes the ADR library as three relations

Status: proposed

## Context

Architects need to know which ADRs were in force on a pull request, which were cited, and which were broken. A path intersection (`touches`) does not say CI ran. A single `violated` flag does not say the ADR was used. Ingesting every pull request from GitHub is a larger product than the first library.

## Decision

The CI command, running inside the pull request job, selects accepted decisions whose globs match the changed paths, runs the mechanical sensor, and fails the job on a violation.

It appends `CheckRecorded` on the one stream for `(org_id, repository, pull_request)`. The payload has `repository`, the pull request, the SHA, one `adr_id`, and one relation:

- `applies` — the scope covers files in the pull request
- `cited` — the pull request body or the agent output matches the ADR id on a token boundary
- `violated` — the sensor failed

These are three facts. `touches` is only the path test inside `applies`. It is not stored as its own relation. `ADR-012` does not match `ADR-0120`.

A missing sensor records `applies` with `sensor: "missing"`, does not record `violated`, and does not fail the job.

The first repeated violation may open one `ProposalCreated` of kind `review_violations` for that repository and ADR. Later red SHAs append `CheckRecorded` only. They must not change the decision.

The command knows only the pull request it is running on. Full GitHub ingestion is a later package.

## Rejected alternatives

- Recompute `touches` by listing open pull requests. Rejected for phase 1. It does not record `cited` or that CI ran.
- One event with a boolean `violated`. Rejected because the library then cannot show that an ADR applied and was not cited.

## Consequences

WP-04 builds the command and the workflow. The research view reads the `checks` projection. It must not relabel `applies` as "implements".

## Governs

`.github/workflows/**`, `services/agent/**` CI command
