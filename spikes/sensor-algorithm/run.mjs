#!/usr/bin/env node
// Spike. Semgrep finds locations. Jev scores each hunk.
// violated only when a match exists and noul >= threshold.
// A file with no match does not call Jev. No API key records jev_unavailable and does not fail the job.

import { createHash } from "node:crypto";
import { appendFileSync, readFileSync } from "node:fs";
import { dirname, isAbsolute, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const root = dirname(fileURLToPath(import.meta.url));
const repo = resolve(root, "../..");
const rulePath = join(root, "rule.yaml");
const decisionId = "ADR-0006";
const threshold = Number(process.env.SENSOR_THRESHOLD ?? "0.8");
const model = process.env.SENSOR_MODEL ?? "jev-1.13.0";

const question = {
  type: "noul",
  instructions:
    "This hunk imports or invokes an LLM SDK from web application code, which the decision forbids.",
  criteria: {
    true: "Executable code imports or calls an LLM SDK.",
    false: "A comment, a doc string, or code that only mentions the ban.",
  },
};

const questionHash = createHash("sha256")
  .update(JSON.stringify(question))
  .digest("hex")
  .slice(0, 16);

const rule = readFileSync(rulePath, "utf8");
if (!rule.includes(`decision_id: ${decisionId}`)) {
  console.error(`refused: rule does not cite ${decisionId}`);
  process.exit(2);
}

const files = targetFiles();
if (files.length === 0) {
  writeSummary("No code files to scan.");
  process.exit(0);
}

const report = scan(files);
const matches = report.results ?? [];
const matched = new Set();
const findings = [];

for (const match of matches) {
  const file = repoRelative(match.path);
  const line = match.start.line;
  matched.add(file);
  const scored = await score(hunkAt(resolve(repo, file), line));
  findings.push({
    file,
    line,
    decision_id: decisionId,
    model: scored.model,
    noul: scored.noul,
    question_hash: questionHash,
    outcome: outcome(scored),
  });
}

for (const file of files.map((file) => repoRelative(file))) {
  if (!matched.has(file)) {
    findings.push({
      file,
      line: null,
      decision_id: decisionId,
      model: null,
      noul: null,
      question_hash: questionHash,
      outcome: "pass",
    });
  }
}

console.log(JSON.stringify({ threshold, findings }, null, 2));
writeSummary(render(findings));

if (findings.some((finding) => finding.outcome === "violated")) {
  process.exit(1);
}

function targetFiles() {
  const listFlag = process.argv.indexOf("--list");
  if (listFlag !== -1) {
    return readFileSync(process.argv[listFlag + 1], "utf8")
      .split("\n")
      .map((line) => line.trim())
      .filter(Boolean)
      .map((file) => resolve(repo, file));
  }
  const args = process.argv.slice(2).filter((arg) => !arg.startsWith("--"));
  if (args.length > 0) return args.map((file) => resolve(repo, file));
  return ["violating/checkout.ts", "mention/policy.ts", "clean/map.ts"].map((file) =>
    join(root, "fixtures", file),
  );
}

function scan(paths) {
  const useDocker = process.env.SEMGREP_DOCKER === "1" || spawnSync("semgrep", ["--version"], { encoding: "utf8" }).status !== 0;
  const scan = useDocker ? dockerScan(paths) : localScan(paths);
  if (scan.error) {
    console.error(scan.error.message);
    process.exit(1);
  }
  if (!scan.stdout.trim()) {
    console.error(scan.stderr);
    process.exit(scan.status || 1);
  }
  return JSON.parse(scan.stdout);
}

function localScan(paths) {
  return spawnSync(
    "semgrep",
    ["scan", "--config", rulePath, "--json", "--metrics", "off", "--quiet", ...paths],
    { encoding: "utf8" },
  );
}

function dockerScan(paths) {
  const inside = paths.map((file) => `/src/${repoRelative(file)}`);
  return spawnSync(
    "docker",
    [
      "run",
      "--rm",
      "-v",
      `${repo}:/src`,
      "semgrep/semgrep",
      "semgrep",
      "scan",
      "--config",
      "/src/spikes/sensor-algorithm/rule.yaml",
      "--json",
      "--metrics",
      "off",
      "--quiet",
      ...inside,
    ],
    { encoding: "utf8" },
  );
}

function outcome(scored) {
  if (scored.noul === null) return "jev_unavailable";
  return scored.noul >= threshold ? "violated" : "acquitted";
}

function hunkAt(path, line) {
  const lines = readFileSync(path, "utf8").split("\n");
  const from = Math.max(0, line - 3);
  const to = Math.min(lines.length, line + 2);
  return lines.slice(from, to).join("\n");
}

function repoRelative(file) {
  const normalized = file.replaceAll("\\", "/");
  if (normalized.startsWith("/src/")) return normalized.slice("/src/".length);
  const absolute = isAbsolute(file) ? file : resolve(repo, file);
  return relative(repo, absolute).replaceAll("\\", "/");
}

async function score(hunk) {
  const key = process.env.TYPESAFE_API_KEY;
  if (!key) return { model: null, noul: null };

  const response = await fetch("https://api.typesafe.ai/v1/systemone", {
    method: "POST",
    headers: {
      authorization: `Bearer ${key}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({
      state: hunk,
      model,
      questions: { violates: question },
    }),
    signal: AbortSignal.timeout(20000),
  });

  const body = await response.json();
  if (!response.ok) {
    console.error(`jev ${response.status}: ${JSON.stringify(body)}`);
    return { model: null, noul: null };
  }
  return { model: body.model, noul: body.answers.violates.noul };
}

function render(findings) {
  const lines = [
    `Threshold ${threshold}. A semgrep match fails the job only when noul is at or above it.`,
    "",
    "| File | Line | noul | Outcome |",
    "|---|---|---|---|",
    ...findings.map((finding) => {
      const noul = finding.noul === null ? "—" : finding.noul;
      const line = finding.line ?? "—";
      return `| \`${finding.file}\` | ${line} | ${noul} | ${finding.outcome} |`;
    }),
  ];
  return lines.join("\n");
}

function writeSummary(markdown) {
  if (!process.env.GITHUB_STEP_SUMMARY) return;
  appendFileSync(process.env.GITHUB_STEP_SUMMARY, `${markdown}\n`);
}
