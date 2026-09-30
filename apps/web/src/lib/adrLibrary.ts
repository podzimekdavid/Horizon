export type CheckRelation = "applies" | "cited" | "violated";

export type CheckRow = {
  adr_id: string;
  repository: string;
  pull_request: number;
  sha: string;
  relation: CheckRelation;
};

export type DecisionRow = {
  adr_id: string;
  title: string | null;
};

export type PullRequestRef = {
  repository: string;
  pull_request: number;
  sha: string;
  note?: string;
};

export type LogEvent = {
  event_type: string;
  payload: Record<string, unknown>;
};

export type AdrCard = {
  adr_id: string;
  title: string;
  violated: PullRequestRef[];
  follows: PullRequestRef[];
  cited: PullRequestRef[];
};

export type LibraryProjection = {
  missing: boolean;
  rows: Record<string, unknown>[];
  error: string | null;
};

export type AdrLibrary = {
  sample: boolean;
  cards: AdrCard[];
};

const repository = "podzimekdavid/Horizon";

const sampleTitles: Record<string, string> = {
  "ADR-0001": "The event log is the only record",
  "ADR-0003": "Compliance verdicts are mechanical",
  "ADR-0004": "CI writes the ADR library as three relations",
  "ADR-0006": "Supabase records, Kotlin commands, React renders",
  "ADR-0007": "Everything runs in a container unless there is a good reason",
  "ADR-0008": "The agent pulls pull requests from GitHub",
};

function sampleCheck(adrId: string, pullRequest: number, sha: string, relation: CheckRelation): CheckRow {
  return { adr_id: adrId, repository, pull_request: pullRequest, sha, relation };
}

/**
 * Shown while `checks` is empty. Pull request 10 is the spike: the SDK import
 * violates ADR-0006, and the same pull request also applies.
 */
const sampleChecks: CheckRow[] = [
  sampleCheck("ADR-0001", 4, "4add9f6", "applies"),
  sampleCheck("ADR-0001", 9, "6bf40a1", "applies"),
  sampleCheck("ADR-0001", 11, "95ec137", "cited"),

  sampleCheck("ADR-0003", 10, "65d5ee5", "applies"),
  sampleCheck("ADR-0003", 13, "472975a", "applies"),
  sampleCheck("ADR-0003", 9, "6bf40a1", "cited"),

  sampleCheck("ADR-0004", 10, "65d5ee5", "violated"),
  sampleCheck("ADR-0004", 10, "65d5ee5", "applies"),
  sampleCheck("ADR-0004", 11, "95ec137", "applies"),
  sampleCheck("ADR-0004", 7, "05cb4c5", "cited"),

  sampleCheck("ADR-0006", 10, "65d5ee5", "violated"),
  sampleCheck("ADR-0006", 10, "65d5ee5", "applies"),
  sampleCheck("ADR-0006", 9, "6bf40a1", "applies"),
  sampleCheck("ADR-0006", 11, "95ec137", "applies"),
  sampleCheck("ADR-0006", 4, "4add9f6", "cited"),

  sampleCheck("ADR-0007", 8, "6a539db", "applies"),
  sampleCheck("ADR-0007", 11, "95ec137", "applies"),
  sampleCheck("ADR-0007", 9, "6bf40a1", "cited"),

  sampleCheck("ADR-0008", 7, "05cb4c5", "violated"),
  sampleCheck("ADR-0008", 7, "05cb4c5", "applies"),
  sampleCheck("ADR-0008", 13, "472975a", "applies"),
  sampleCheck("ADR-0008", 9, "6bf40a1", "cited"),
];

const sampleFindings: LogEvent[] = [
  {
    event_type: "CheckRecorded",
    payload: {
      adr_id: "ADR-0004",
      repository,
      pull_request: 10,
      relation: "violated",
      findings: [{ file: "spikes/sensor-algorithm/run.mjs", line: 1 }],
    },
  },
  {
    event_type: "CheckRecorded",
    payload: {
      adr_id: "ADR-0006",
      repository,
      pull_request: 10,
      relation: "violated",
      findings: [{ file: "spikes/sensor-algorithm/fixtures/violating/checkout.ts", line: 1 }],
    },
  },
  {
    event_type: "CheckRecorded",
    payload: {
      adr_id: "ADR-0008",
      repository,
      pull_request: 7,
      relation: "violated",
      findings: [{ file: "services/agent/src/main/kotlin/horizon/agent/webhook/GithubWebhook.kt", line: 1 }],
    },
  },
];

const relations = new Set<CheckRelation>(["applies", "cited", "violated"]);

export function adrLibrary(
  checks: LibraryProjection,
  decisions: LibraryProjection,
  events: LogEvent[] = [],
): AdrLibrary {
  const titles = decisionTitles(decisions.error ? [] : decisions.rows);
  const sample = checks.error !== null || checks.missing || checks.rows.length === 0;
  const rows = sample ? sampleChecks : recordedChecks(checks.rows);
  return { sample, cards: cardsFrom(rows, titles, sample, sample ? sampleFindings : events) };
}

function decisionTitles(rows: Record<string, unknown>[]): Map<string, string> {
  const titles = new Map<string, string>();
  for (const row of rows) {
    const adrId = text(row.adr_id);
    const title = text(row.title);
    if (adrId && title) titles.set(adrId, title);
  }
  return titles;
}

function recordedChecks(rows: Record<string, unknown>[]): CheckRow[] {
  const checks: CheckRow[] = [];
  for (const row of rows) {
    const adrId = text(row.adr_id);
    const repository = text(row.repository);
    const sha = text(row.sha);
    const relation = text(row.relation);
    const pullRequest = row.pull_request;
    if (!adrId || !repository || !sha || !relation || !relations.has(relation as CheckRelation)) continue;
    if (typeof pullRequest !== "number") continue;
    checks.push({
      adr_id: adrId,
      repository,
      pull_request: pullRequest,
      sha,
      relation: relation as CheckRelation,
    });
  }
  return checks;
}

function cardsFrom(
  checks: CheckRow[],
  titles: Map<string, string>,
  sample: boolean,
  events: LogEvent[],
): AdrCard[] {
  const byAdr = new Map<string, CheckRow[]>();
  for (const check of checks) {
    const group = byAdr.get(check.adr_id) ?? [];
    group.push(check);
    byAdr.set(check.adr_id, group);
  }

  return [...byAdr.entries()]
    .sort(([left], [right]) => left.localeCompare(right))
    .map(([adrId, group]) => {
      const violatedKeys = new Set(
        group.filter((check) => check.relation === "violated").map(pullKey),
      );
      return {
        adr_id: adrId,
        title: titles.get(adrId) ?? (sample ? sampleTitles[adrId] : undefined) ?? adrId,
        violated: withFindings(
          uniquePulls(group.filter((check) => check.relation === "violated")),
          adrId,
          events,
        ),
        follows: uniquePulls(
          group.filter((check) => check.relation === "applies" && !violatedKeys.has(pullKey(check))),
        ),
        cited: uniquePulls(group.filter((check) => check.relation === "cited")),
      };
    });
}

function withFindings(pulls: PullRequestRef[], adrId: string, events: LogEvent[]): PullRequestRef[] {
  return pulls.map((pull) => {
    const note = findingNote(events, adrId, pull);
    return note ? { ...pull, note } : pull;
  });
}

function findingNote(events: LogEvent[], adrId: string, pull: PullRequestRef): string | null {
  const notes: string[] = [];
  for (const event of events) {
    if (event.event_type !== "CheckRecorded") continue;
    const payload = event.payload;
    if (payload.relation !== "violated" || payload.adr_id !== adrId) continue;
    if (payload.repository !== pull.repository || payload.pull_request !== pull.pull_request) continue;
    if (!Array.isArray(payload.findings)) continue;
    for (const finding of payload.findings) {
      if (!finding || typeof finding !== "object") continue;
      const file = text((finding as { file?: unknown }).file);
      const line = (finding as { line?: unknown }).line;
      if (!file) continue;
      notes.push(typeof line === "number" ? `${file}:${line}` : file);
    }
  }
  return notes.length > 0 ? notes.join(", ") : null;
}

function uniquePulls(checks: CheckRow[]): PullRequestRef[] {
  const seen = new Set<string>();
  const pulls: PullRequestRef[] = [];
  for (const check of checks) {
    const key = pullKey(check);
    if (seen.has(key)) continue;
    seen.add(key);
    pulls.push({
      repository: check.repository,
      pull_request: check.pull_request,
      sha: check.sha,
    });
  }
  return pulls.sort((left, right) => left.pull_request - right.pull_request);
}

function pullKey(check: CheckRow): string {
  return `${check.repository}#${check.pull_request}`;
}

function text(value: unknown): string | null {
  return typeof value === "string" && value.trim().length > 0 ? value : null;
}
