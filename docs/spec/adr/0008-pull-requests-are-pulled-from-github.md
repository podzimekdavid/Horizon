# ADR-0008: The agent pulls pull requests from GitHub

Status: proposed

## Context

Horizon needs the pull requests of a repository in the log next to the `CheckRecorded` facts that CI writes (ADR-0004). The first design pushed them: a GitHub App sent `pull_request` webhooks to `services/agent`. That needs a public inbound route, a signing secret, and a GitHub App configured to point at the service. It also ties correctness to delivery: a webhook sent while the service is down is lost once GitHub stops retrying, and the service has to keep a delivery id to survive redelivery.

Reading is simpler. The service asks GitHub what it needs, when it wants it, with a read-only token.

## Decision

`services/agent` pulls pull requests from GitHub. GitHub does not call the service, and the service exposes no route for GitHub.

- The poller reads `GET /repos/{owner}/{repo}/pulls?state=all&sort=updated&direction=desc` for each repository named in `GITHUB_REPOSITORIES`, on an interval (`GITHUB_POLL_INTERVAL_SECONDS`, default 60).
- The credential is `GITHUB_TOKEN`: a fine-grained token or a GitHub App installation token with read-only "Pull requests" access. It is used only against the GitHub API and is never logged.
- A pull request produces one `PullRequestReceived` on its `pull_request` stream when its `(head SHA, state)` pair is new. `state` is `open`, `closed`, or `merged`. A comment, label, or review request changes `updated_at` only and stores nothing.
- The idempotency key is `{repository}#{number}@{head_sha}:{state}`, stored in `payload.idempotency_key` and enforced by `append_pull_request_received` and its unique index. The database is the dedupe. The poller's cursor (the newest `updated_at` seen per repository) lives in memory and only shortens the next read. After a restart the first poll re-reads what GitHub lists and stores nothing twice.
- The cursor advances only after every pull request of that poll for that repository is stored. A failed append or a failed GitHub call leaves the cursor where it was, so the next poll reads the same window. One failing repository does not stop the others.
- The first poll has no cursor and loads the history GitHub still lists, bounded by `GITHUB_POLL_MAX_PAGES` pages of 100.
- Only pull requests of the listed repositories are read. This is not full GitHub ingestion (ADR-0004).
- Writes still go through `append_pull_request_received` as `horizon_writer`. The poller does not append `CheckRecorded` and does not record `applies`, `cited`, or `violated`.

## Rejected alternatives

- Keep the GitHub App webhook. Rejected: it needs a public route and a shared secret, and a webhook missed while the service is down is not recoverable from the receiver. A poll reads the current state whenever the service runs.
- Poll from Supabase (`pg_cron` calling out, or an Edge Function). Rejected by ADR-0006: custom logic stays in `services/agent`.
- Have CI report every pull request. Rejected by ADR-0004: CI only knows the pull request it runs on, and it does not run on pull requests that never trigger the workflow.
- Poll every event type on the repository. Rejected: pull requests are the only GitHub fact phase 1 needs.

## Consequences

- A pull request appears in the log up to one poll interval after it changes. Two changes between polls (a push and a merge) yield one event for the final state, not two.
- A pull request that is closed and reopened at the same head SHA repeats an already stored key, so the reopen is not recorded. Adding a state-change timestamp to the key would fix this; it is not needed for phase 1.
- Polling spends GitHub API rate limit (one request per repository per poll when nothing changed). A rate-limited or failing call is logged and retried on the next interval.
- The event payload has `state` and `merged` where the earlier webhook payload had `action`, and `idempotency_key` where it had `delivery_id`. The database was not yet initialized when this changed, so the original migration was edited instead of adding a new one.
- No webhook secret, no `X-Hub-Signature-256` check, and no `X-GitHub-Delivery` header exist in the service. The Render service still binds `0.0.0.0:$PORT` for `/health`.
- A stopped service falls behind and catches up when it starts again. A host that spins the service down when idle also stops the polling.

## Governs

`services/agent/**` GitHub pull request reads, `append_pull_request_received` callers
