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
  automationExisting: "019f0000-0000-7000-8000-000000000006",
  automationOtherMachine: "019f0000-0000-7000-8000-000000000007",
  automationPrefix: "019f0000-0000-7000-8000-000000000008",
  divergent: "019f0000-0000-7000-8000-000000000009",
};

function rolloutRows(id, title, options = {}) {
  const sessionId = options.sessionId ?? id;
  const threadSource = options.threadSource ?? "user";
  const sessionPayload = {
    session_id: sessionId,
    timestamp: "2026-07-21T00:00:00.000Z",
    cwd: "C:\\work",
    source: "vscode",
    thread_source: threadSource,
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
  ];
  if (options.automationId) {
    rows.push({
      timestamp: "2026-07-21T00:00:01.500Z",
      type: "response_item",
      payload: {
        type: "message",
        role: "developer",
        content: [{ type: "input_text", text: `Automation ID: ${options.automationId}` }],
      },
    });
  }
  rows.push({
    timestamp: "2026-07-21T00:00:02.000Z",
    type: "response_item",
    payload: { type: "message", role: "user", content: [{ type: "input_text", text: title }] },
  });
  return rows.concat(options.extraRows ?? []);
}

function writeRollout(root, id, title, options = {}) {
  const suffix = options.suffix ?? "";
  const file = path.join(root, `rollout-2026-07-21T00-00-00-${id}${suffix}.jsonl`);
  const rows = rolloutRows(id, title, options);
  fs.writeFileSync(file, `${rows.map((row) => JSON.stringify(row)).join("\n")}\n`, "utf8");
  return file;
}

function writeIndex(rows) {
  fs.writeFileSync(index, `${rows.map((row) => JSON.stringify(row)).join("\n")}\n`, "utf8");
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
      history_mode TEXT NOT NULL DEFAULT 'legacy',
      thread_source TEXT
    );
  `);
  const insertExisting = database.prepare(`
    INSERT INTO threads
      (id, rollout_path, created_at, updated_at, source, model_provider, cwd, title, sandbox_policy, approval_mode, thread_source)
    VALUES (?, ?, 1, 1, 'test', 'openai', 'C:\\work', ?, '{}', 'on-request', ?)
  `);
  insertExisting.run(ids.existing, "existing.jsonl", "existing", "user");
  insertExisting.run(
    ids.automationExisting,
    "C:\\old-machine\\CodexKit\\session-data\\sessions\\stale.jsonl",
    "existing automation",
    "automation",
  );
  database.close();

  writeRollout(active, ids.existing, "Existing title");
  writeRollout(active, ids.active, "Active first message");
  writeRollout(archived, ids.archived, "Archived first message");
  writeRollout(active, ids.alias, "Alias first message", { sessionId: ids.existing });
  const existingAutomationPath = writeRollout(active, ids.automationExisting, "Run from machine A", {
    threadSource: "automation",
    automationId: "shared-monitor",
  });
  writeRollout(active, ids.automationOtherMachine, "Independent run from machine B", {
    threadSource: "automation",
    automationId: "shared-monitor",
  });
  const prefixRows = rolloutRows(ids.automationPrefix, "Earlier machine copy", {
    threadSource: "automation",
    automationId: "weekly-radar",
  });
  fs.writeFileSync(
    path.join(archived, `rollout-2026-07-21T00-00-00-${ids.automationPrefix}-old.jsonl`),
    `${prefixRows.map((row) => JSON.stringify(row)).join("\n")}\n`,
    "utf8",
  );
  writeRollout(active, ids.automationPrefix, "Earlier machine copy", {
    threadSource: "automation",
    automationId: "weekly-radar",
    suffix: "-new",
    extraRows: [{
      timestamp: "2026-07-21T00:00:03.000Z",
      type: "event_msg",
      payload: { type: "task_complete" },
    }],
  });
  fs.writeFileSync(
    path.join(archived, `rollout-2026-07-21T00-00-00-${ids.automationPrefix}-corrupt.jsonl`),
    Buffer.alloc(20000),
  );

  const baseIndexRows = [
    { id: ids.existing, thread_name: "Existing custom title", updated_at: "2026-07-21T00:00:00Z" },
    { id: ids.active, thread_name: "Active custom title", updated_at: "2026-07-21T00:00:00Z" },
    { id: ids.archived, thread_name: "Archived custom title", updated_at: "2026-07-21T00:00:00Z" },
    { id: ids.alias, thread_name: "Alias custom title", updated_at: "2026-07-21T00:00:00Z" },
    { id: ids.automationExisting, thread_name: "Machine A run", updated_at: "2026-07-21T00:00:00Z" },
    { id: ids.automationOtherMachine, thread_name: "Machine B run", updated_at: "2026-07-21T00:00:00Z" },
    { id: ids.automationPrefix, thread_name: "Extended run", updated_at: "2026-07-21T00:00:00Z" },
  ];
  writeIndex(baseIndexRows);

  run();
  let check = new DatabaseSync(databasePath, { readOnly: true });
  assert.equal(check.prepare("SELECT count(*) AS n FROM threads").get().n, 6);
  assert.equal(check.prepare("SELECT title FROM threads WHERE id=?").get(ids.active).title, "Active custom title");
  assert.equal(check.prepare("SELECT archived FROM threads WHERE id=?").get(ids.archived).archived, 1);
  assert.equal(check.prepare("SELECT title FROM threads WHERE id=?").get(ids.existing).title, "existing");
  assert.equal(
    path.resolve(check.prepare("SELECT rollout_path FROM threads WHERE id=?").get(ids.automationExisting).rollout_path),
    path.resolve(existingAutomationPath),
  );
  assert.equal(
    check.prepare("SELECT thread_source FROM threads WHERE id=?").get(ids.automationOtherMachine).thread_source,
    "automation",
  );
  check.close();

  let result = JSON.parse(fs.readFileSync(report, "utf8"));
  assert.equal(result.inserted_count, 4);
  assert.equal(result.ignored_alias_count, 1);
  assert.equal(result.rollout_duplicate_groups, 1);
  assert.equal(result.rollout_prefix_extensions, 1);
  assert.equal(result.corrupt_rollout_copy_count, 1);
  assert.equal(result.rollout_conflict_count, 0);
  assert.equal(result.automation_history_rollouts, 3);
  assert.equal(result.automation_history_cataloged, 3);
  assert.equal(result.automation_history_inserted_count, 2);
  assert.equal(result.automation_history_path_repaired_count, 1);
  assert.equal(result.automation_history_unresolved_count, 0);
  assert.deepEqual(
    result.automation_histories.map((entry) => [entry.automation_id, entry.rollout_count]),
    [["shared-monitor", 2], ["weekly-radar", 1]],
  );

  run();
  result = JSON.parse(fs.readFileSync(report, "utf8"));
  assert.equal(result.inserted_count, 0);
  assert.equal(result.automation_history_path_repaired_count, 0);

  fs.writeFileSync(path.join(active, `rollout-${ids.broken}.jsonl`), "{}\n", "utf8");
  writeIndex(baseIndexRows.concat({ id: ids.broken, thread_name: "Broken" }));
  run(true);
  check = new DatabaseSync(databasePath, { readOnly: true });
  assert.equal(check.prepare("SELECT count(*) AS n FROM threads WHERE id=?").get(ids.broken).n, 0);
  check.close();

  fs.rmSync(path.join(active, `rollout-${ids.broken}.jsonl`));
  writeRollout(active, ids.divergent, "Machine A divergent copy", {
    threadSource: "automation",
    automationId: "shared-monitor",
    suffix: "-machine-a",
  });
  writeRollout(archived, ids.divergent, "Machine B divergent copy", {
    threadSource: "automation",
    automationId: "shared-monitor",
    suffix: "-machine-b",
  });
  writeIndex(baseIndexRows.concat({ id: ids.divergent, thread_name: "Divergent" }));
  run(true);
  result = JSON.parse(fs.readFileSync(report, "utf8"));
  assert.equal(result.status, "rollout-conflict");
  assert.equal(result.rollout_conflict_count, 1);
  check = new DatabaseSync(databasePath, { readOnly: true });
  assert.equal(check.prepare("SELECT count(*) AS n FROM threads WHERE id=?").get(ids.divergent).n, 0);
  check.close();

  console.log("Repair-CodexThreadCatalog tests passed");
} finally {
  fs.rmSync(work, { recursive: true, force: true });
}
