# ADR-0003: Compliance verdicts are mechanical

Status: proposed

## Context

Auto-generated checkers that ask a model whether a rule was followed miss violations often enough to be the wrong judge. The product's risk is a stale or flattering verdict.

## Decision

A verdict is a schema check, a lint, a hook, or a test. `ProposalVerifier` records that result on `ProposalVerified`, or `NotConfigured` when no check exists. The port must not call a model.

Phase 1 ships `NotConfigured`. A human may still approve. The gap stays visible on the proposal.

The CI sensor is the same kind of check for a decision against a diff. It does not call a model.

## Rejected alternatives

- LLM-as-judge for `ProposalVerified` and for CI. Rejected as the default. A later ADR would have to supersede this one to allow it.
- Blocking all approvals until Jev is configured. Rejected for phase 1 because it hides the missing check by stopping the product.

## Consequences

WP-02's verifier has no model client. WP-04 and WP-08 share the sensor interface: input is a diff and a decision, output is pass or fail with a file and line. No prose score.

## Governs

`services/agent/**`
