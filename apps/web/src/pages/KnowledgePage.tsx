import { useEffect, useState } from "react";
import { Link, Navigate } from "react-router-dom";
import { useSession } from "../hooks/useSession";
import { adrLibrary, type PullRequestRef } from "../lib/adrLibrary";
import { visibleForRepository, type HorizonEvent } from "../lib/events";
import { readRepository } from "../lib/repository";
import { getSupabase } from "../lib/supabase";

type Organization = {
  id: string;
  name: string;
};

type ProjectionState = {
  missing: boolean;
  rows: Record<string, unknown>[];
  error: string | null;
};

const emptyProjection: ProjectionState = { missing: false, rows: [], error: null };

function isMissingRelation(code: string | undefined, message: string): boolean {
  return code === "PGRST205" || code === "42P01" || /does not exist|schema cache/i.test(message);
}

export function KnowledgePage() {
  const { session } = useSession();
  const userId = session?.user.id ?? "";
  const repository = userId ? readRepository(userId) : null;
  const [organizations, setOrganizations] = useState<Organization[] | null>(null);
  const [member, setMember] = useState<boolean | null>(null);
  const [events, setEvents] = useState<HorizonEvent[] | null>(null);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [decisions, setDecisions] = useState<ProjectionState>(emptyProjection);
  const [checks, setChecks] = useState<ProjectionState>(emptyProjection);
  const [projectionsReady, setProjectionsReady] = useState(false);

  useEffect(() => {
    const supabase = getSupabase();
    if (!supabase || !session || !repository) return;
    let active = true;

    async function load() {
      const client = getSupabase();
      if (!client) return;
      const membership = await client.from("memberships").select("org_id");
      if (!active) return;
      if (membership.error) {
        setLoadError(membership.error.message);
        return;
      }
      const orgIds = membership.data ?? [];
      setMember(orgIds.length > 0);
      if (orgIds.length === 0) return;

      const [orgs, eventRows, decisionRows, checkRows] = await Promise.all([
        client.from("organizations").select("id, name"),
        client
          .from("events")
          .select("id, stream_type, stream_id, version, event_type, payload, occurred_at")
          .order("occurred_at", { ascending: false }),
        client.from("decisions").select("*").limit(50),
        client.from("checks").select("*").limit(50),
      ]);
      if (!active) return;
      if (orgs.error) setLoadError(orgs.error.message);
      else setOrganizations(orgs.data ?? []);
      if (eventRows.error) setLoadError(eventRows.error.message);
      else setEvents((eventRows.data ?? []) as HorizonEvent[]);
      setDecisions(readProjection(decisionRows.error, decisionRows.data));
      setChecks(readProjection(checkRows.error, checkRows.data));
      setProjectionsReady(true);
    }

    void load();
    return () => {
      active = false;
    };
  }, [session, repository]);

  if (!repository) return <Navigate to="/onboarding" replace />;

  async function signOut() {
    await getSupabase()?.auth.signOut();
  }

  const visible = (events ?? []).filter((event) => visibleForRepository(event, repository));

  return (
    <main className="sheet">
      <header className="top">
        <p className="kicker">Knowledge</p>
        <button className="text-link" type="button" onClick={signOut}>
          Sign out
        </button>
      </header>
      <h1>{organizations?.[0]?.name ?? "Organization"}</h1>
      <p>
        Repository <strong>{repository}</strong>.{" "}
        <Link to="/onboarding">Change</Link>
      </p>

      {member === false ? (
        <p>This account is not in an organization yet. Membership is granted by seed or an admin.</p>
      ) : null}
      {loadError ? <p className="error">{loadError}</p> : null}

      <AdrBoard checks={checks} decisions={decisions} events={events} ready={projectionsReady} />

      <section>
        <h2>Events</h2>
        {events === null && !loadError ? <p className="status">Loading the log.</p> : null}
        {events && visible.length === 0 ? <p>No events for this membership yet.</p> : null}
        <ul className="event-list">
          {visible.map((event) => (
            <li key={event.id}>
              <span className="kicker">{event.event_type}</span>
              <strong>
                {event.stream_type} · v{event.version}
              </strong>
              <time dateTime={event.occurred_at}>{new Date(event.occurred_at).toLocaleString()}</time>
              <EventPayload event={event} />
            </li>
          ))}
        </ul>
      </section>

    </main>
  );
}

function AdrBoard({
  checks,
  decisions,
  events,
  ready,
}: {
  checks: ProjectionState;
  decisions: ProjectionState;
  events: HorizonEvent[] | null;
  ready: boolean;
}) {
  const library = adrLibrary(checks, decisions, events ?? []);
  return (
    <section className="adr-board">
      <h2>Decisions</h2>
      {!ready ? <p className="status">Loading decisions.</p> : null}
      {checks.error ? <p className="error">{checks.error}</p> : null}
      {decisions.error ? <p className="error">{decisions.error}</p> : null}
      {ready
        ? library.cards.map((card) => (
        <article className="tile adr-card" key={card.adr_id}>
          <p className="kicker">{card.adr_id}</p>
          <h3>{card.title}</h3>
          <div className="tiles">
            <PullColumn title="Violated" pulls={card.violated} />
            <PullColumn title="Follows" pulls={card.follows} />
          </div>
          {card.cited.length > 0 ? <PullColumn title="Cited" pulls={card.cited} /> : null}
        </article>
      ))
        : null}
    </section>
  );
}

function PullColumn({ title, pulls }: { title: string; pulls: PullRequestRef[] }) {
  return (
    <div>
      <p className="kicker">{title}</p>
      {pulls.length === 0 ? <p>None</p> : null}
      <ul className="pull-list">
        {pulls.map((pull) => (
          <li key={`${pull.repository}#${pull.pull_request}`}>
            <strong>
              {pull.repository} #{pull.pull_request}
            </strong>
            <span>{pull.sha.slice(0, 7)}</span>
            {pull.note ? <span className="pull-note">{pull.note}</span> : null}
          </li>
        ))}
      </ul>
    </div>
  );
}

function readProjection(
  error: { code?: string; message: string } | null,
  data: Record<string, unknown>[] | null,
): ProjectionState {
  if (error && isMissingRelation(error.code, error.message)) {
    return { missing: true, rows: [], error: null };
  }
  if (error) return { missing: false, rows: [], error: error.message };
  return { missing: false, rows: data ?? [], error: null };
}

function EventPayload({ event }: { event: HorizonEvent }) {
  if (event.event_type !== "PullRequestReceived") return null;
  const state = event.payload.state ?? event.payload.action;
  const pullRequest = event.payload.pull_request;
  const sha = event.payload.head_sha;
  return (
    <span>
      {typeof state === "string" ? state : "pull request"}
      {typeof pullRequest === "number" ? ` #${pullRequest}` : ""}
      {typeof sha === "string" ? ` · ${sha.slice(0, 7)}` : ""}
    </span>
  );
}
