# ADR-0002: A human member approves

Status: proposed

## Context

The product drafts ADRs, harness edits, and consolidation proposals with a model. If the service account can also approve them, the draft and the decision are the same write.

## Decision

Model output is a proposal. The sequence is `ProposalCreated`, then `ProposalVerified`, then `ProposalApproved` or `ProposalRejected`.

`horizon_writer` may append `ProposalCreated`, `ProposalVerified`, and `DecisionProposed`. It must not append approval, rejection, `DecisionAccepted`, `DecisionSuperseded`, `HarnessCompiled`, or `CheckRecorded`. The service role is not a runtime writer, so a ban that lives only in RLS would not hold.

A human member approves by calling `approve_proposal` or `reject_proposal`. Each function appends the approval event and the domain event (`DecisionAccepted`, `DecisionRejected`, `DecisionSuperseded`, or `HarnessCompiled`) in one transaction. The browser cannot insert `ProposalApproved`. A `BEFORE INSERT` trigger reads `actor_id` from the session and rejects event types the role is not granted.

`DiscussionNoted` is not approval.

## Rejected alternatives

- The agent accepts when the verifier passes. Rejected because a mechanical pass is not a decision to change the architecture.
- Approval updates the projection row directly. Rejected by ADR-0001.

## Consequences

WP-01 ships the trigger and the grants table. WP-02 ships the two functions and the writer-role grants. WP-06's proposal card calls those functions and does not insert the approval event.

## Governs

`services/agent/**`, `apps/web/**`, `supabase/**`
