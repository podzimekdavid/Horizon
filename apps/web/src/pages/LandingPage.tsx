import { Link } from "react-router-dom";
import { MissingConfig } from "../components/MissingConfig";
import { useSession } from "../hooks/useSession";
import { readRepository } from "../lib/repository";

export function LandingPage() {
  const { session, loading, configured } = useSession();
  if (!configured) return <MissingConfig />;

  const next = session
    ? readRepository(session.user.id)
      ? "/knowledge"
      : "/onboarding"
    : "/login";

  return (
    <main className="landing">
      <header className="top">
        <span className="kicker">Horizon</span>
        <Link className="text-link" to={next}>
          {loading ? "Sign in" : session ? "Open the workspace" : "Sign in"}
        </Link>
      </header>

      <section className="hero">
        <h1>Decisions your agents can&apos;t ignore</h1>
        <p className="lede">
          Horizon turns an accepted architecture decision into a check on every pull request, and
          shows you where it holds and where it breaks.
        </p>
      </section>

      <section>
        <p className="kicker">The problem</p>
        <h2>Your coding agents don&apos;t read your ADRs.</h2>
        <div className="tiles three">
          <article className="tile">
            <strong>Decisions live in prose</strong>
            <span>An ADR is context. Nothing stops a pull request that breaks it.</span>
          </article>
          <article className="tile">
            <strong>Agents outpace review</strong>
            <span>Every agent-written pull request can cross a boundary nobody checks.</span>
          </article>
          <article className="tile">
            <strong>Drift surfaces late</strong>
            <span>As rework, an incident, or an audit question nobody can answer.</span>
          </article>
        </div>
        <p className="punch">A decision that nothing checks is only a request.</p>
      </section>

      <section>
        <p className="kicker">How it works</p>
        <h2>Decide. Enforce. See.</h2>
        <div className="loop">
          <article className="node">
            <span>Decide</span>
            <strong>A person accepts</strong>
            <em>AI can draft the decision. It never approves it.</em>
          </article>
          <div className="arr" aria-hidden="true">
            →
          </div>
          <article className="node hot">
            <span>Enforce</span>
            <strong>CI checks it</strong>
            <em>The decision becomes a check. A pull request that breaks it fails.</em>
          </article>
          <div className="arr" aria-hidden="true">
            →
          </div>
          <article className="node">
            <span>See</span>
            <strong>One view</strong>
            <em>Which decisions each pull request touched, referenced, or broke.</em>
          </article>
        </div>
        <p className="footnote">
          The verdict comes from a <em>deterministic check</em>, not from another model.
        </p>
      </section>

      <section className="close">
        <p className="kicker">Start in a day</p>
        <h2>Point it at one repository.</h2>
        <p className="lede">
          Sign in, connect GitHub, and read the event log for that repository. Decisions and checks
          appear when those projections exist.
        </p>
        <Link className="button" to={next}>
          {session ? "Continue" : "Sign in"}
        </Link>
      </section>
    </main>
  );
}
