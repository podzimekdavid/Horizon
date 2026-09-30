---
theme: seriph
title: Horizon
info: |
  One minute, then the live app. Three slides: the claim, the gap, the loop. The payments story, the reviewer, and the roadmap are the demo.
layout: none
class: hz title
drawings:
  persist: false
transition: fade
duration: 1min
---

<div class="kicker">Horizon</div>

# Architecture that keeps up with your agents

<p class="lede">It researches the system, drafts the decision, and enforces it on every pull request. You only make the call.</p>

<!--
About ten seconds. Read the title, then the sentence. Four beats: research, draft, enforce, you decide. Stop. Do not explain the product yet.
-->

---
layout: none
class: hz gap
---

<div class="kicker">The problem</div>

# Decisions have no lifecycle.

<div class="tiles three">
  <div class="tile">
    <strong>Nobody can find them</strong>
    <span>Spread across old ADRs, pull requests, and chat. Most never get written down.</span>
  </div>
  <div class="tile">
    <strong>Nothing enforces them</strong>
    <span>An ADR is context. Coding agents write the code and ignore it.</span>
  </div>
  <div class="tile">
    <strong>Drift shows up late</strong>
    <span>As rework, an incident, or an audit question nobody can answer.</span>
  </div>
</div>

<p class="punch">Each step lives somewhere else. None of it binds the code.</p>

<!--
About twenty seconds. Three beats, then the punch line. Do not list tools. The next slide is the answer.
-->

---
layout: none
class: hz gap
---

<div class="kicker">The loop</div>

# One record. You sign off. CI enforces.

<div class="flow">
  <div class="node">
    <span>1</span>
    <strong>Research</strong>
  </div>
  <div class="node">
    <span>2</span>
    <strong>Draft</strong>
  </div>
  <div class="node hot">
    <span>3</span>
    <strong>You decide</strong>
  </div>
  <div class="node">
    <span>4</span>
    <strong>CI checks</strong>
  </div>
  <div class="node">
    <span>5</span>
    <strong>Drift returns</strong>
  </div>
</div>

<p class="punch">I'll show one decision, from the question to a blocked merge.</p>

<!--
About thirty seconds. Point left to right: research, draft, only a person accepts, CI fails the pull request, violations come back. Then the punch line and switch to the app. The demo is the payments question, the proposal card, and the failing check. Do not narrate it here.
-->

---
layout: none
class: hz gap
---

<div class="kicker">Pull request #10</div>

# The import failed the check.

<div class="shots">
  <img src="/pr10-check.png" alt="GitHub Actions run for pull request 10, ADR-0006 sensor failed" />
</div>

<p class="punch">The job is named ADR-0006 sensor.</p>

<!--
About ten seconds. This is the check on pull request 10. It failed, and the job name is the decision it broke.
-->

---
layout: none
class: hz gap
---

<div class="kicker">The record</div>

# The decision names the pull request.

<div class="shots">
  <img class="wide" src="/decisions.png" alt="Horizon decisions view, ADR-0004 violated by pull request 10" />
</div>

<!--
About ten seconds. The same pull request shows up on the decision. ADR-0004 lists pull request 10 and the file it broke.
-->
