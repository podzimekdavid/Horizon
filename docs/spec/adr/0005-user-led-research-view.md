# ADR-0005: The user leads the research view

Status: proposed

## Context

A fixed dashboard of five panels is not the workspace. An agent that chooses the question and invents panels will present architecture the log does not support. The team still needs a place to discuss a result without that discussion counting as approval.

## Decision

The user opens a research session and states the question. The agent does not open one on its own and does not decide.

The agent returns a catalog document (`DecisionMap`, `ImplementationList`, `PullRequestLibrary`, `GapList`, `ProposalCard`) bound to citation ids from the deterministic read. A panel whose citations do not resolve is invalid and is not shown. The web app renders the catalog. It does not speak the A2UI wire protocol in phase 1.

The catalog is a render payload. It is not a second record. Facts remain the events the panels cite.

Discussion appends `DiscussionNoted` on the research session. Approval is only `ProposalApproved` from a human member, from the proposal card.

The underlying projections stay readable when the agent service is stopped.

## Rejected alternatives

- The five panels are the product, and the agent only sorts them. Rejected. The product is the generated view of the investigation the user is running.
- The model writes the architecture summary into a table the UI treats as truth. Rejected by ADR-0001.

## Consequences

WP-05 is the read with no model. WP-06 renders and drops uncited panels. WP-07 fills the catalog and may create a proposal. WP-07 must not approve.

## Governs

`apps/web/**`, `services/agent/**` research workflow
