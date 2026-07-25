import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { DatabaseSync } from "node:sqlite";

const helper = path.resolve(import.meta.dirname, "..", "Repair-CodexThreadCatalog.mjs");
const work = fs.mkdtempSync(path.join(os.tmpdir(), "codexkit-thread-catalog-test-"));
const active = path.join(work, "sessions");
const archived = path.join(work, "archived_sessions");
const index = path.join(work, "session_index.jsonl");
const databasePath = path.join(work, "state_5.sqlite");
const report = path.join(work, "report.json");
fs.mkdirSync(active, { recursive: true });
fs.mkdirSync(archived, { recursive: true });

const ids = {
  existing: "019f0000-0000-7000-8000-000000000001",
  active: "019f0000-0000-7000-8000-000000000002",
  archived: "019f0000-0000-7000-8000-000000000003",
  broken: "019f0000-0000-7000-8000-000000000004",
  alias: "019f0000-0000-7000-8000-000000000005",
};

function rollout(root, id, title, sessionId = id) {
  const file = path.join(root, `rollout-2026-07-21T00-00-00-${id}.jsonl`);
  const sessionPayload = {
    session_id: sessionId,
    timestamp: "2026-07-21T00:00:00.000Z",
    cwd: "C:\\work",
    source: "vscode",
    thread_source: "user",
    model_provider: "openai",
    cli_version: "test",
  };
  if (sessionId === id) sessionPayload.id = id;
  const rows = [
    {
      timestamp: "2026-07-21T00:00:00.000Z",
      type: "session_meta",
      payload: sessionPayload,
    },
    {
      timestamp: "2026-07-21T00:00:01.000Z",
      type: "turn_context",
      payload: { approval_policy: "on-request", sandbox_policy: { type: "read-only" }, model: "test-model" },
    },
    {
      timestamp: "2026-07-21T00:00:02.000Z",
      type: "response_item",
      payload: { type: "message", role: "user", content: [{ type: "input_text", text: title }] },
    },
  ];
  fs.writeFileSync(file, `${rows.map((row) => JSON.stringify(row)).join("\n")}\n`, "utf8");
  return file;
}

function run(expectFailure = false) {
  const args = [
    helper,
    "--database", databasePath,
    "--sessions-root", active,
    "--archived-root", archived,
    "--session-index", index,
    "--report-output", report,
  ];
  if (expectFailure) {
    assert.throws(() => execFileSync(process.execPath, args, { stdio: "pipe" }));
  } else {
    execFileSync(process.execPath, args, { stdio: "pipe" });
  }
}

try {
  const database = new DatabaseSync(databasePath);
  database.exec(`
    CREATE TABLE threads (
      id TEXT PRIMARY KEY,
      rollout_path TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      source TEXT NOT NULL,
      model_provider TEXT NOT NULL,
      cwd TEXT NOT NULL,
      title TEXT NOT NULL,
      sandbox_policy TEXT NOT NULL,
      approval_mode TEXT NOT NULL,
      tokens_used INTEGER NOT NULL DEFAULT 0,
      has_user_event INTEGER NOT NULL DEFAULT 0,
      archived INTEGER NOT NULL DEFAULT 0,
      archived_at INTEGER,
      cli_version TEXT NOT NULL DEFAULT '',
      first_user_message TEXT NOT NULL DEFAULT '',
      memory_mode TEXT NOT NULL DEFAULT 'enabled',
      preview TEXT NOT NULL DEFAULT '',
      recency_at INTEGER NOT NULL DEFAULT 0,
      history_mode TEXT NOT NULL DEFAULT 'legacy'
    );
  `);
  database.prepare(`
    INSERT INTO threads
      (id, rollout_path, created_at, updated_at, source, model_provider, cwd, title, sandbox_policy, approval_mode)
    VALUES (?, ?, 1, 1, 'test', 'openai', 'C:\\work', 'existing', '{}', 'on-request')
  `).run(ids.existing, "existing.jsonl");
  database.close();

  rollout(active, ids.existing, "Existing title");
  rollout(active, ids.active, "Active first message");
  rollout(archived, ids.archived, "Archived first message");
  rollout(active, ids.alias, "Alias first message", ids.existing);
  fs.writeFileSync(index, [
    { id: ids.existing, thread_name: "Existing custom title", updated_at: "2026-07-21T00:00:00Z" },
    { id: ids.active, thread_name: "Active custom title", updated_at: "2026-07-21T00:00:00Z" },
    { id: ids.archived, thread_name: "Archived custom title", updated_at: "2026-07-21T00:00:00Z" },
    { id: ids.alias, thread_name: "Alias custom title", updated_at: "2026-07-21T00:00:00Z" },
  ].map((row) => JSON.stringify(row)).join("\n") + "\n", "utf8");

  run();
  let check = new DatabaseSync(databasePath, { readOnly: true });
  assert.equal(check.prepare("SELECT count(*) AS n FROM threads").get().n, 3);
  assert.equal(check.prepare("SELECT title FROM threads WHERE id=?").get(ids.active).title, "Active custom title");
  assert.equal(check.prepare("SELECT archived FROM threads WHERE id=?").get(ids.archived).archived, 1);
  assert.equal(check.prepare("SELECT title FROM threads WHERE id=?").get(ids.existing).title, "existing");
  check.close();
  assert.equal(JSON.parse(fs.readFileSync(report, "utf8")).inserted_count, 2);
  assert.equal(JSON.parse(fs.readFileSync(report, "utf8")).ignored_alias_count, 1);

  run();
  assert.equal(JSON.parse(fs.readFileSync(report, "utf8")).inserted_count, 0);

  fs.writeFileSync(path.join(active, `rollout-${ids.broken}.jsonl`), "{}\n", "utf8");
  fs.appendFileSync(index, `${JSON.stringify({ id: ids.broken, thread_name: "Broken" })}\n`, "utf8");
  run(true);
  check = new DatabaseSync(databasePath, { readOnly: true });
  assert.equal(check.prepare("SELECT count(*) AS n FROM threads WHERE id=?").get(ids.broken).n, 0);
  check.close();

  console.log("Repair-CodexThreadCatalog tests passed");
} finally {
  fs.rmSync(work, { recursive: true, force: true });
}
