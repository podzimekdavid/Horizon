---
theme: seriph
title: Horizon
info: |
  Two minutes. Coding agents ignore architecture decisions written as prose. Horizon turns an accepted decision into a check on every pull request and shows the architect where it holds and where it breaks.
layout: none
class: hz title
drawings:
  persist: false
transition: fade
duration: 2min
---

<div class="kicker">Horizon</div>

# Decisions your agents can't ignore

<p class="lede">Horizon turns an accepted architecture decision into a check on every pull request, and shows you where it holds and where it breaks.</p>

<!--
About ten seconds. Say the one sentence and stop. Do not mention the stack, events, or ADR mechanics yet.
-->

---
layout: none
class: hz gap
---

<div class="kicker">The problem</div>

# Your coding agents don't read your ADRs.

<div class="tiles three">
  <div class="tile">
    <strong>Decisions live in prose</strong>
    <span>An ADR is context. Nothing stops a pull request that breaks it.</span>
  </div>
  <div class="tile">
    <strong>Agents outpace review</strong>
    <span>Every agent-written pull request can cross a boundary nobody checks.</span>
  </div>
  <div class="tile">
    <strong>Drift surfaces late</strong>
    <span>As rework, an incident, or an audit question nobody can answer.</span>
  </div>
</div>

<p class="punch">A decision that nothing checks is only a request.</p>

<!--
About twenty seconds. The pain is not scattered tools. It is that decisions do not bind the code, and agents now write a large share of it. Ask the room: when did you last find out a boundary was broken, and how long after the merge?
-->

---
layout: none
class: hz gap
---

<div class="kicker">Who it helps</div>

# Three people pay for that drift.

<div class="tiles three">
  <div class="tile">
    <strong>The architect</strong>
    <span>Can't review every pull request. Gets a decision that enforces itself and one view of where it holds.</span>
  </div>
  <div class="tile">
    <strong>Engineering leadership</strong>
    <span>Wants the speed of coding agents without losing the architecture. Gets fewer rewrites.</span>
  </div>
  <div class="tile">
    <strong>Compliance and audit</strong>
    <span>Has to prove who decided what and that it is followed. Gets a record nobody can edit.</span>
  </div>
</div>

<!--
About twenty seconds. The architect uses it. Leadership buys it. In regulated teams, compliance is the reason it gets approved. Pick the tile that matches the room and spend your time there.
-->

---
layout: none
class: hz loops
---

<div class="kicker">How it works</div>

# Decide. Enforce. See.

<div class="loop">
  <div class="node">
    <span>Decide</span>
    <strong>A person accepts</strong>
    <em>AI can draft the decision. It never approves it.</em>
  </div>
  <div class="arr">→</div>
  <div class="node hot">
    <span>Enforce</span>
    <strong>CI checks it</strong>
    <em>The decision becomes a check. A pull request that breaks it fails.</em>
  </div>
  <div class="arr">→</div>
  <div class="node">
    <span>See</span>
    <strong>One view</strong>
    <em>Which decisions each pull request touched, referenced, or broke.</em>
  </div>
</div>

<p class="footnote">The verdict comes from a <em>deterministic check</em>, not from another model.</p>

<!--
About twenty seconds. Three steps, left to right. The trust argument is the footnote: we do not ask AI to judge AI. A lint, a test, or a hook decides. A failed check does not rewrite the decision; a person changes a decision.
-->

---
layout: none
class: hz gap
---

<div class="kicker">Payments, in practice</div>

# An agent calls the card provider from checkout.

<div class="tiles">
  <div class="tile">
    <strong>The decision</strong>
    <span>ADR-012: only the payments gateway talks to the card provider.</span>
  </div>
  <div class="tile">
    <strong>The pull request</strong>
    <span>A coding agent adds a direct provider call in the checkout service.</span>
  </div>
  <div class="tile">
    <strong>CI</strong>
    <span>The check fails and names ADR-012 as the decision it broke.</span>
  </div>
  <div class="tile">
    <strong>The architect</strong>
    <span>Sees it in the payments view, beside every pull request that kept the rule.</span>
  </div>
</div>

<p class="punch">Caught before merge. Not in the post-mortem.</p>

<!--
About twenty-five seconds. This is the demo. Tell it as a story, top left to bottom right. If you run it live, show the failing check first, then the view.
-->

---
layout: none
class: hz gap
---

<div class="kicker">Why Horizon</div>

# ADR tools document. Horizon enforces.

<div class="tiles">
  <div class="tile">
    <strong>Enforced, not suggested</strong>
    <span>An accepted decision compiles into a check CI runs on every pull request.</span>
  </div>
  <div class="tile">
    <strong>A person decides, a check verifies</strong>
    <span>AI drafts. A team member signs off. No model judges compliance.</span>
  </div>
  <div class="tile">
    <strong>A full audit trail</strong>
    <span>Who decided what, when, and which pull requests kept it. Nothing is overwritten.</span>
  </div>
  <div class="tile">
    <strong>Guardrails beat guidance</strong>
    <span>A 2026 study of 679 rule files: short negative constraints help agents. Best-practice prose tends to hurt.</span>
  </div>
</div>

<!--
About fifteen seconds. Existing ADR tools stop at a typed file, a terminal, or a CI comment in one repository. Horizon makes the decision binding and gives the architect the view. Source for the last tile: Guardrails Beat Guidance, arXiv 2604.11088.
-->

---
layout: none
class: hz close
---

<div class="kicker">Start in a day</div>

# Point it at your ADR folder and one repository.

<p class="lede">Your next pull request shows which decisions it touched and which it broke, before any AI spend.</p>

<!--
About ten seconds. The ask: one repository, the ADRs they already have, one pull request through CI. If they have no ADRs, offer to write the first one with them from a boundary they already care about.
-->
