---
theme: seriph
title: Horizon
info: |
  Three minutes. Horizon runs the whole lifecycle of an architecture decision: research, draft, decide, enforce, learn. It reviews the system continuously and brings the architect only what needs a human call.
layout: none
class: hz title
drawings:
  persist: false
transition: fade
duration: 3min
---

<div class="kicker">Horizon</div>

# Architecture that keeps up with your agents

<p class="lede">Horizon researches your system, drafts the decisions, enforces them on every pull request, and brings you only what needs a human call.</p>

<!--
About ten seconds. One sentence, four verbs: research, draft, enforce, bring you the call. Do not mention the stack, events, or ADR mechanics yet.
-->

---
layout: none
class: hz gap
---

<div class="kicker">The problem</div>

# Architecture decisions have no lifecycle.

<div class="tiles">
  <div class="tile">
    <strong>Nobody knows what was decided</strong>
    <span>The answer is spread across old ADRs, pull requests, and chat. Most decisions never get written down.</span>
  </div>
  <div class="tile">
    <strong>Writing ADRs dies in weeks</strong>
    <span>The record sits beside the work, not inside it. Teams stop.</span>
  </div>
  <div class="tile">
    <strong>Nothing enforces them</strong>
    <span>An ADR is context. Coding agents write more of the code and ignore it.</span>
  </div>
  <div class="tile">
    <strong>Drift surfaces late</strong>
    <span>As rework, an incident, or an audit question nobody can answer.</span>
  </div>
</div>

<p class="punch">Each step lives in a different place, and none of them binds the code.</p>

<!--
About twenty seconds. Four steps of the same job: find the decision, write it, enforce it, notice drift. Today each one is a different tool, or no tool. Ask the room: when did you last find out a boundary was broken, and how long after the merge?
-->

---
layout: none
class: hz gap
---

<div class="kicker">Who it helps</div>

# Three people pay for that gap.

<div class="tiles three">
  <div class="tile">
    <strong>The architect</strong>
    <span>Can't review every pull request. Gets a reviewer that watches the system and brings back what matters.</span>
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
About fifteen seconds. The architect uses it. Leadership buys it. In regulated teams, compliance is the reason it gets approved. Pick the tile that matches the room.
-->

---
layout: none
class: hz gap
---

<div class="kicker">The whole lifecycle</div>

# From question to enforced decision, and back.

<div class="flow">
  <div class="node">
    <span>1 · Research</span>
    <strong>Ask</strong>
    <em>What did we decide, where does the code do it, which pull requests touched it?</em>
  </div>
  <div class="node">
    <span>2 · Draft</span>
    <strong>AI writes</strong>
    <em>The ADR, with rejected alternatives and the code it governs.</em>
  </div>
  <div class="node hot">
    <span>3 · Decide</span>
    <strong>You sign off</strong>
    <em>Accept, reject, or replace. Only a person can.</em>
  </div>
  <div class="node">
    <span>4 · Enforce</span>
    <strong>CI checks it</strong>
    <em>A pull request that breaks the decision fails.</em>
  </div>
  <div class="node">
    <span>5 · Learn</span>
    <strong>Drift returns</strong>
    <em>Violations and gaps come back as a proposal.</em>
  </div>
</div>

<p class="footnote">Learning feeds the next question. Every step writes to <em>one record</em>.</p>

<!--
About twenty-five seconds. This is the slide that says we are not a linter. Walk left to right, then point back from Learn to Research. Verification is step four of five.
-->

---
layout: none
class: hz gap
---

<div class="kicker">A reviewer that faces people</div>

# It reviews the system. You make the call.

<div class="split">
  <div class="tile">
    <strong>Horizon, all the time</strong>
    <ul>
      <li>Reads every pull request against your decisions</li>
      <li>Finds gaps: code with no decision, a decision with no code</li>
      <li>Flags repeated violations and ADRs that overlap</li>
      <li>Drafts the next change, with the evidence attached</li>
    </ul>
  </div>
  <div class="tile hot">
    <strong>Your team, when it matters</strong>
    <ul>
      <li>Asks the question</li>
      <li>Discusses the findings in one shared view</li>
      <li>Accepts or rejects on a single card</li>
    </ul>
  </div>
</div>

<p class="punch">Every claim links to its evidence. If it can't cite it, it doesn't show it.</p>

<!--
About twenty-five seconds. The reviewer is not a bot that argues in pull request comments. It is the colleague who prepared the brief: here is what we decided, here is where the code drifted, here is the change I propose. Discussion is not approval. Only the card approves. A panel without a citation is dropped before anyone sees it.
-->

---
layout: none
class: hz gap
---

<div class="kicker">Payments, in practice</div>

# One question, one decision, one blocked merge.

<div class="tiles">
  <div class="tile">
    <strong>The question</strong>
    <span>"What did we decide about card payments?" Horizon shows ADR-012, its code, and the pull requests that broke it.</span>
  </div>
  <div class="tile">
    <strong>The proposal</strong>
    <span>Horizon drafts a sharper replacement: only the payments gateway talks to the card provider. The team discusses it.</span>
  </div>
  <div class="tile">
    <strong>The decision</strong>
    <span>The architect accepts it. The old ADR stays readable. The new one becomes a check.</span>
  </div>
  <div class="tile">
    <strong>The next pull request</strong>
    <span>An agent calls the provider from checkout. CI fails and names the decision it broke.</span>
  </div>
</div>

<p class="punch">Caught before merge. Not in the post-mortem.</p>

<!--
About twenty-five seconds. This is the demo, told as a story from top left to bottom right. If you run it live: the research view, then the proposal card, then the failing check.
-->

---
layout: none
class: hz gap
---

<div class="kicker">Why Horizon</div>

# ADR tools document. Horizon runs the lifecycle.

<div class="tiles">
  <div class="tile">
    <strong>The whole loop, one record</strong>
    <span>Research, draft, decision, check, and drift in one place. Others stop at a file per repository.</span>
  </div>
  <div class="tile">
    <strong>Enforced, not suggested</strong>
    <span>An accepted decision compiles into a check CI runs on every pull request.</span>
  </div>
  <div class="tile">
    <strong>AI reviews, a person decides</strong>
    <span>AI drafts and flags. A team member signs off. No model judges compliance.</span>
  </div>
  <div class="tile">
    <strong>A full audit trail</strong>
    <span>Who decided what, when, and which pull requests kept it. Nothing is overwritten.</span>
  </div>
</div>

<!--
About fifteen seconds. Existing ADR tools stop at a typed file, a terminal, or a CI comment in one repository. Evidence for enforcing over advising: a 2026 study of 679 rule files found short negative constraints help agents and best-practice prose tends to hurt (Guardrails Beat Guidance, arXiv 2604.11088).
-->

---
layout: none
class: hz gap
---

<div class="kicker">Where it goes</div>

# Start with one check. Shape how your agents work.

<div class="tiles three">
  <div class="tile">
    <strong>Now: one repository</strong>
    <span>Your ADRs imported, a check on every pull request, the research view, and proposals you sign off.</span>
  </div>
  <div class="tile">
    <strong>Next: agents follow it</strong>
    <span>Decisions compiled into agent rules and looked up by coding agents. Horizon measures which rules help and proposes cutting the rest.</span>
  </div>
  <div class="tile">
    <strong>Then: the organization</strong>
    <span>GitHub-wide evidence, code review findings, and one decision rolled out across repositories.</span>
  </div>
</div>

<!--
About fifteen seconds. Be honest about the order. The first column is what we demo. The second is where Horizon earns its place in the agent workflow: it does not just check agents, it shapes what they read and measures whether that helped.
-->

---
layout: none
class: hz title
---

<div class="kicker">Horizon</div>

# Thank you

<p class="lede">Architecture that keeps up with your agents. Researched, decided by people, enforced on every pull request.</p>

<!--
About five seconds, then questions. If someone asks how to start: one repository, the ADRs they already have, one pull request through CI. That shows which decisions it touched and which it broke, before any AI spend. If they have no ADRs, offer to run the first research session with them on a boundary they already care about.
-->
