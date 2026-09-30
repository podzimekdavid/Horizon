---
theme: seriph
title: Horizon
info: |
  One minute. The architect asks what the system decided, sees it in the code and the pull request, and accepts the ADR in the same view.
layout: none
class: hz title
drawings:
  persist: false
transition: fade
duration: 1min
---

<div class="kicker">Horizon</div>

# Ask what the system decided

<p class="lede">See it in the code and in the open pull request. Accept or supersede the ADR in the same view.</p>

<!--
About twelve seconds. Horizon is the place an architect looks up a decision, sees where it lives, and accepts the next ADR without leaving the view. Do not mention the stack.
-->

---
layout: none
class: hz gap
---

<div class="kicker">The work already happens</div>

# Four tabs. No shared record.

<div class="tiles">
  <div class="tile">
    <strong>Research</strong>
    <span>What did we decide, and what did we reject?</span>
  </div>
  <div class="tile">
    <strong>The ADR</strong>
    <span>Written beside the decision, then abandoned.</span>
  </div>
  <div class="tile">
    <strong>Overview</strong>
    <span>Paths, pull requests, and the gaps.</span>
  </div>
  <div class="tile">
    <strong>Execution</strong>
    <span>The decision stays prose. The agent can ignore it.</span>
  </div>
</div>

<p class="punch">A decision has to compile into a sensor, or it is only a request.</p>

<!--
About fifteen seconds. Name the four tabs, then land on the last line. The etalon is a short guardrail or a mechanical sensor, not a pack of best-practice prose.
-->

---
layout: none
class: hz loops
---

<div class="kicker">One log</div>

# Two loops

<div class="loop">
  <div class="node">
    <span>Architect</span>
    <strong>You lead</strong>
    <em>the question</em>
  </div>
  <div class="arr">→</div>
  <div class="node">
    <span>Architect</span>
    <strong>The view</strong>
    <em>only what it can cite</em>
  </div>
  <div class="arr">→</div>
  <div class="node hot">
    <span>Architect</span>
    <strong>You approve</strong>
    <em>a human member</em>
  </div>

  <div></div>
  <div></div>
  <div class="arr">↑</div>
  <div></div>
  <div class="arr">↓</div>

  <div></div>
  <div></div>
  <div class="node">
    <span>Harness</span>
    <strong>CI</strong>
    <div class="rels">
      <b>applies</b>
      <b>cited</b>
      <b class="fail">violated</b>
    </div>
  </div>
  <div class="arr">←</div>
  <div class="node">
    <span>Harness</span>
    <strong>Sensor</strong>
    <em>compiled from the decision</em>
  </div>
</div>

<p class="footnote"><em>violated</em> fails the job. It does not change the decision.</p>

<!--
About twenty-five seconds. Walk the top row, then the bottom. applies, cited, and violated are three relations. A path intersection is not a citation. A failure does not supersede the ADR. The model drafts. It does not approve, and it does not judge.
-->

---
layout: none
class: hz close
---

<div class="kicker">Payments</div>

# The next pull request fails on that ADR.

<p class="lede">You accepted the supersession. The decision stayed.</p>

<!--
About eight seconds. Close on the demo. A human accepts. CI fails violated. The record does not move by itself.
-->
