# ADR-0002: A human member approves

Status: proposed

## Context

The product drafts ADRs, harness edits, and consolidation proposals with a model. If the service account can also approve them, the draft and the decision are the same write.

## Decision

Model output is a proposal. The sequence is `ProposalCreated`, then `ProposalVerified`, then `ProposalApproved` or `ProposalRejected`.

The agent service account may append `ProposalCreated` and `ProposalVerified`. It must not append `ProposalApproved` or `ProposalRejected`. Only a human organization member may approve or reject.

Approval does not edit a projection. The accept command appends a separate domain event (`DecisionAccepted`, `HarnessCompiled`).

`DiscussionNoted` is not approval.

## Rejected alternatives

- The agent accepts when the verifier passes. Rejected because a mechanical pass is not a decision to change the architecture.
- Approval updates the projection row directly. Rejected by ADR-0001.

## Consequences

WP-02 enforces the service-account ban in the command and in RLS. WP-06's proposal card is the only UI control that requests approval.

## Governs

`services/agent/**`, `apps/web/**`, `supabase/**`
