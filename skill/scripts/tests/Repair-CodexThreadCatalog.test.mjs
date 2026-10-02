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
const automationDatabasePath = path.join(work, "codex-dev.db");
const automationRoot = path.join(work, "automations");
const report = path.join(work, "report.json");
const runStatusRepair = path.join(work, "automation-run-status-repair.json");
fs.mkdirSync(active, { recursive: true });
fs.mkdirSync(archived, { recursive: true });
for (const automationId of ["shared-monitor", "weekly-radar"]) {
  const definitionRoot = path.join(automationRoot, automationId);
  fs.mkdirSync(definitionRoot, { recursive: true });
  fs.writeFileSync(path.join(definitionRoot, "automation.toml"), `id = "${automationId}"\n`, "utf8");
}

const ids = {
  existing: "019f0000-0000-7000-8000-000000000001",
  active: "019f0000-0000-7000-8000-000000000002",
  post019: "01a00abf-04d9-7a22-8d81-e6dfdf12c2f7",
  archived: "019f0000-0000-7000-8000-000000000003",
  broken: "019f0000-0000-7000-8000-000000000004",
  alias: "019f0000-0000-7000-8000-000000000005",
  automationExisting: "019f0000-0000-7000-8000-000000000006",
  automationOtherMachine: "019f0000-0000-7000-8000-000000000007",
  automationPrefix: "019f0000-0000-7000-8000-000000000008",
  divergent: "019f0000-0000-7000-8000-000000000009",
  automationRetired: "019f0000-0000-7000-8000-000000000010",
  automationToolOutput: "019f0000-0000-7000-8000-000000000013",
  derivedOne: "01a02235-e87a-7ef3-9451-426ffdabb84d",
  derivedTwo: "01a02236-375b-7212-89f6-11622d5ffe3c",
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
    ...(options.historyMode ? { history_mode: options.historyMode } : {}),
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
  if (options.untrustedAutomationId) {
    rows.push({
      timestamp: "2026-07-21T00:00:01.250Z",
      type: "response_item",
      payload: {
        type: "function_call_output",
        name: "exec_command",
        namespace: "codex_app",
        output: `Automation ID: ${options.untrustedAutomationId}`,
      },
    });
  }
  if (options.automationId) {
    const payload = options.automationIdSource === "tool-output"
      ? {
          type: "function_call_output",
          name: "automation_update",
          namespace: "codex_app",
          output: `Automation: Test\nAutomation ID: ${options.automationId}\nAutomation memory: memory.md`,
        }
      : {
          type: "message",
          role: "developer",
          content: [{ type: "input_text", text: `Automation ID: ${options.automationId}` }],
        };
    rows.push({
      timestamp: "2026-07-21T00:00:01.500Z",
      type: "response_item",
      payload,
    });
  }
  rows.push({
    timestamp: "2026-07-21T00:00:02.000Z",
    type: "response_item",
    payload: { type: "message", role: "user", content: [{ type: "input_text", text: title }] },
  });
  if (options.automationId && options.completed !== false) {
    rows.push({
      timestamp: "2026-07-21T00:00:03.000Z",
      type: "event_msg",
      payload: { type: "task_complete" },
    });
  }
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
    "--automation-database", automationDatabasePath,
    "--automation-root", automationRoot,
    "--automation-run-status-repair", runStatusRepair,
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
      name TEXT,
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

  const automationDatabase = new DatabaseSync(automationDatabasePath);
  automationDatabase.exec(`
    CREATE TABLE automations (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      prompt TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'ACTIVE',
      next_run_at INTEGER,
      last_run_at INTEGER,
      cwds TEXT NOT NULL DEFAULT '[]',
      rrule TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    );
    CREATE TABLE automation_runs (
      thread_id TEXT PRIMARY KEY,
      automation_id TEXT NOT NULL,
      status TEXT NOT NULL,
      read_at INTEGER,
      thread_title TEXT,
      source_cwd TEXT,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    );
    INSERT INTO automations
      (id, name, prompt, status, next_run_at, last_run_at, cwds, rrule, created_at, updated_at)
    VALUES
      ('shared-monitor', 'Shared monitor', 'prompt', 'ACTIVE', 9999999999999, 1, '[]', 'FREQ=WEEKLY;BYDAY=MO', 1, 1),
      ('weekly-radar', 'Weekly radar', 'prompt', 'ACTIVE', 9999999999999, 1, '[]', 'FREQ=WEEKLY;BYDAY=MO', 1, 1);
  `);
  automationDatabase.prepare(`
    INSERT INTO automation_runs
      (thread_id, automation_id, status, thread_title, source_cwd, created_at, updated_at)
    VALUES (?, 'shared-monitor', 'PENDING_REVIEW', 'Legacy imported run', 'C:\\work', 1, 1)
  `).run(ids.automationExisting);
  automationDatabase.close();
  fs.writeFileSync(runStatusRepair, JSON.stringify({ thread_ids: [ids.automationExisting] }), "utf8");

  const existingPath = writeRollout(active, ids.existing, "Existing title", { historyMode: "paginated" });
  const historySetup = new DatabaseSync(databasePath);
  historySetup.prepare("UPDATE threads SET rollout_path=? WHERE id=?").run(existingPath, ids.existing);
  const existingBefore = historySetup.prepare("SELECT * FROM threads WHERE id=?").get(ids.existing);
  historySetup.close();
  writeRollout(active, ids.active, "Active first message", { historyMode: "paginated" });
  writeRollout(active, ids.post019, "Post-019 first message");
  writeRollout(active, ids.active, "Derived branch one", { suffix: `_${ids.derivedOne}` });
  writeRollout(active, ids.active, "Derived branch two", { suffix: `_${ids.derivedTwo}` });
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
  writeRollout(active, ids.automationRetired, "Run from retired automation", {
    threadSource: "automation",
    automationId: "retired-monitor",
  });
  writeRollout(active, ids.automationToolOutput, "Run using current automation metadata", {
    threadSource: "automation",
    automationId: "shared-monitor",
    automationIdSource: "tool-output",
    untrustedAutomationId: "spoofed-monitor",
  });
  fs.writeFileSync(
    path.join(archived, `rollout-2026-07-21T00-00-00-${ids.automationPrefix}-corrupt.jsonl`),
    Buffer.alloc(20000),
  );

  const baseIndexRows = [
    { id: ids.existing, thread_name: "Existing custom title", updated_at: "2026-07-21T00:00:00Z" },
    { id: ids.active, thread_name: "Active custom title", updated_at: "2026-07-21T00:00:00Z" },
    { id: ids.post019, thread_name: "Post-019 custom title", updated_at: "2026-08-16T13:24:52Z" },
    { id: ids.archived, thread_name: "Archived custom title", updated_at: "2026-07-21T00:00:00Z" },
    { id: ids.alias, thread_name: "Alias custom title", updated_at: "2026-07-21T00:00:00Z" },
    { id: ids.automationExisting, thread_name: "Machine A run", updated_at: "2026-07-21T00:00:00Z" },
    { id: ids.automationOtherMachine, thread_name: "Machine B run", updated_at: "2026-07-21T00:00:00Z" },
    { id: ids.automationPrefix, thread_name: "Extended run", updated_at: "2026-07-21T00:00:00Z" },
    { id: ids.automationRetired, thread_name: "Retired run", updated_at: "2026-07-21T00:00:00Z" },
    { id: ids.automationToolOutput, thread_name: "Tool-output run", updated_at: "2026-07-21T00:00:00Z" },
  ];
  writeIndex(baseIndexRows);

  run();
  let check = new DatabaseSync(databasePath, { readOnly: true });
  assert.equal(check.prepare("SELECT count(*) AS n FROM threads").get().n, 9);
  assert.equal(check.prepare("SELECT title FROM threads WHERE id=?").get(ids.active).title, "Active custom title");
  assert.equal(check.prepare("SELECT title FROM threads WHERE id=?").get(ids.post019).title, "Post-019 custom title");
  assert.equal(
    check.prepare("SELECT count(*) AS n FROM threads WHERE id IN (?, ?)").get(ids.derivedOne, ids.derivedTwo).n,
    0,
  );
  assert.equal(check.prepare("SELECT archived FROM threads WHERE id=?").get(ids.archived).archived, 1);
  assert.equal(check.prepare("SELECT title FROM threads WHERE id=?").get(ids.existing).title, "Existing custom title");
  assert.deepEqual(check.prepare("SELECT * FROM threads WHERE id=?").get(ids.existing),
    Object.assign(Object.create(null), existingBefore, { history_mode: "paginated", name: "Existing custom title", title: "Existing custom title" }));
  assert.equal(check.prepare("SELECT name FROM threads WHERE id=?").get(ids.active).name, "Active custom title");
  assert.equal(check.prepare("SELECT history_mode FROM threads WHERE id=?").get(ids.active).history_mode, "paginated");
  assert.equal(check.prepare("SELECT history_mode FROM threads WHERE id=?").get(ids.post019).history_mode, "legacy");
  assert.equal(
    path.resolve(check.prepare("SELECT rollout_path FROM threads WHERE id=?").get(ids.automationExisting).rollout_path),
    path.resolve(existingAutomationPath),
  );
  assert.equal(
    check.prepare("SELECT thread_source FROM threads WHERE id=?").get(ids.automationOtherMachine).thread_source,
    "automation",
  );
  check.close();
  let schedulerCheck = new DatabaseSync(automationDatabasePath, { readOnly: true });
  assert.equal(schedulerCheck.prepare("SELECT count(*) AS n FROM automation_runs").get().n, 5);
  assert.equal(
    schedulerCheck.prepare("SELECT count(*) AS n FROM automation_runs WHERE status='ARCHIVED'").get().n,
    1,
  );
  assert.equal(
    schedulerCheck.prepare("SELECT last_run_at FROM automations WHERE id='shared-monitor'").get().last_run_at,
    Date.parse("2026-07-21T00:00:00.000Z"),
  );
  assert.equal(
    schedulerCheck.prepare("SELECT next_run_at FROM automations WHERE id='shared-monitor'").get().next_run_at,
    null,
  );
  schedulerCheck.close();

  let result = JSON.parse(fs.readFileSync(report, "utf8"));
  assert.equal(result.inserted_count, 7);
  assert.equal(result.history_mode_repaired_count, 1);
  assert.equal(result.history_name_repaired_count, 1);
  const backups = fs.readdirSync(path.join(work, "thread-history-mode-backups"));
  assert.equal(backups.length, 1);
  const backupCheck = new DatabaseSync(path.join(work, "thread-history-mode-backups", backups[0]), { readOnly: true });
  assert.deepEqual(backupCheck.prepare("SELECT * FROM threads WHERE id=?").get(ids.existing), existingBefore);
  backupCheck.close();
  assert.equal(result.ignored_alias_count, 1);
  assert.equal(result.rollout_duplicate_groups, 1);
  assert.equal(result.rollout_prefix_extensions, 1);
  assert.equal(result.corrupt_rollout_copy_count, 1);
  assert.equal(result.rollout_conflict_count, 0);
  assert.equal(result.automation_history_rollouts, 5);
  assert.equal(result.automation_history_cataloged, 5);
  assert.equal(result.automation_history_inserted_count, 4);
  assert.equal(result.automation_history_path_repaired_count, 1);
  assert.equal(result.automation_history_unknown_id_count, 0);
  assert.equal(result.automation_history_unresolved_count, 0);
  assert.equal(result.automation_scheduler_status, "reconciled");
  assert.equal(result.automation_scheduler_runs, 5);
  assert.equal(result.automation_scheduler_runs_cataloged, 5);
  assert.equal(result.automation_scheduler_runs_inserted_count, 4);
  assert.equal(result.automation_scheduler_pending_repaired_count, 0);
  assert.equal(result.automation_scheduler_retention_reopened_count, 3);
  assert.equal(result.automation_scheduler_watermarks_advanced_count, 2);
  assert.equal(result.automation_scheduler_unresolved_definition_count, 0);
  assert.deepEqual(
    result.automation_histories.map((entry) => [entry.automation_id, entry.rollout_count]),
    [["retired-monitor", 1], ["shared-monitor", 3], ["weekly-radar", 1]],
  );

  run();
  result = JSON.parse(fs.readFileSync(report, "utf8"));
  assert.equal(result.inserted_count, 0);
  assert.equal(result.history_mode_repaired_count, 0);
  assert.equal(result.history_name_repaired_count, 0);
  assert.equal(result.history_path_repaired_count, 0);
  assert.equal(result.automation_history_path_repaired_count, 0);
  assert.equal(result.automation_scheduler_runs_inserted_count, 0);
  assert.equal(result.automation_scheduler_watermarks_advanced_count, 0);

  // Recent imported results replace old pending results per automation. A read
  // or updated timestamp must not promote an old run; active/error rows survive.
  const retentionSetup = new DatabaseSync(automationDatabasePath);
  retentionSetup.exec("ALTER TABLE automation_runs ADD COLUMN archived_reason TEXT");
  const retentionInsert = retentionSetup.prepare(`
    INSERT INTO automation_runs (thread_id,automation_id,status,read_at,created_at,updated_at,archived_reason)
    VALUES (?,?,?,?,?,?,?)
  `);
  for (const automationId of ['shared-monitor', 'weekly-radar']) {
    for (let i = 0; i < 7; i++) {
      retentionInsert.run(`retention-${automationId}-${i}`, automationId,
        i === 0 || i === 6 ? 'ACCEPTED' : (i < 2 ? 'PENDING_REVIEW' : 'ARCHIVED'), i === 6 ? 123 : null,
        2000000000000 + i, i === 0 ? 9999999999999 : 2000000000000 + i, 'old reason');
    }
    retentionInsert.run(`retention-${automationId}-active`, automationId, 'IN_PROGRESS', null, 9999999999999, 1, null);
    retentionInsert.run(`retention-${automationId}-error`, automationId, 'FAILED', null, 9999999999999, 1, null);
  }
  retentionSetup.close();
  run();
  let retentionCheck = new DatabaseSync(automationDatabasePath, { readOnly: true });
  for (const automationId of ['shared-monitor', 'weekly-radar']) {
    assert.equal(retentionCheck.prepare("SELECT count(*) n FROM automation_runs WHERE automation_id=? AND status IN ('PENDING_REVIEW','ACCEPTED')").get(automationId).n, 5);
    for (let i = 0; i < 7; i++) {
      const row = retentionCheck.prepare('SELECT * FROM automation_runs WHERE thread_id=?').get(`retention-${automationId}-${i}`);
      assert.equal(row.status, i < 2 ? 'ARCHIVED' : (i === 6 ? 'ACCEPTED' : 'PENDING_REVIEW'));
      if (i >= 2 && i < 6) { assert.equal(row.archived_reason, null); assert.notEqual(row.read_at, null); }
      if (i === 6) assert.equal(row.read_at, 123);
    }
    assert.equal(retentionCheck.prepare('SELECT status FROM automation_runs WHERE thread_id=?').get(`retention-${automationId}-active`).status, 'IN_PROGRESS');
    assert.equal(retentionCheck.prepare('SELECT status FROM automation_runs WHERE thread_id=?').get(`retention-${automationId}-error`).status, 'FAILED');
  }
  const retainedRows = retentionCheck.prepare('SELECT * FROM automation_runs ORDER BY thread_id').all();
  retentionCheck.close();
  const retentionBackups = fs.readdirSync(path.join(work, 'automation-retention-backups'));
  assert.ok(retentionBackups.length > 0 && retentionBackups.length <= 2);
  run();
  result = JSON.parse(fs.readFileSync(report, 'utf8'));
  assert.equal(result.automation_scheduler_retention_reopened_count, 0);
  assert.equal(result.automation_scheduler_retention_archived_count, 0);
  retentionCheck = new DatabaseSync(automationDatabasePath);
  assert.deepEqual(retentionCheck.prepare('SELECT * FROM automation_runs ORDER BY thread_id').all(), retainedRows);
  retentionCheck.exec("DELETE FROM automation_runs WHERE thread_id LIKE 'retention-%'");
  retentionCheck.close();
  run();

  // Existing names, including literal ** and Chinese characters, follow the index.
  const renamed = "**大语言模型长尾机制研究-2";
  writeIndex(baseIndexRows.map(row => row.id === ids.existing ? { ...row, thread_name: renamed } : row));
  run();
  const renamedCheck = new DatabaseSync(databasePath, { readOnly: true });
  assert.equal(renamedCheck.prepare('SELECT name FROM threads WHERE id=?').get(ids.existing).name, renamed);
  assert.equal(renamedCheck.prepare('SELECT title FROM threads WHERE id=?').get(ids.existing).title, renamed);
  renamedCheck.close();
  run();
  assert.equal(JSON.parse(fs.readFileSync(report, 'utf8')).title_updated_count, 0);
  writeIndex(baseIndexRows);
  run();

  // Another device may already have applied the initial mode-only patch.
  const nameOnlySetup = new DatabaseSync(databasePath);
  nameOnlySetup.prepare("UPDATE threads SET name=NULL, title='<recommended_plugins> injected text' WHERE id=?").run(ids.existing);
  nameOnlySetup.close();
  run();
  result = JSON.parse(fs.readFileSync(report, "utf8"));
  assert.equal(result.history_mode_repaired_count, 0);
  assert.equal(result.history_name_repaired_count, 1);
  const nameOnlyCheck = new DatabaseSync(databasePath, { readOnly: true });
  assert.equal(nameOnlyCheck.prepare("SELECT name FROM threads WHERE id=?").get(ids.existing).name, "Existing custom title");
  nameOnlyCheck.close();

  // A different Windows profile must resolve the shared file by exact ID.
  const pathSetup = new DatabaseSync(databasePath);
  pathSetup.prepare("UPDATE threads SET rollout_path='C:\\old-device\\missing.jsonl' WHERE id=?").run(ids.existing);
  pathSetup.close();
  run();
  result = JSON.parse(fs.readFileSync(report, "utf8"));
  assert.equal(result.history_path_repaired_count, 1);
  const pathCheck = new DatabaseSync(databasePath, { readOnly: true });
  assert.equal(pathCheck.prepare("SELECT rollout_path FROM threads WHERE id=?").get(ids.existing).rollout_path, path.resolve(existingPath));
  pathCheck.close();

  const customNameSetup = new DatabaseSync(databasePath);
  customNameSetup.prepare("UPDATE threads SET history_mode='legacy', name='User chosen name' WHERE id=?").run(ids.existing);
  customNameSetup.close();
  run();
  const customNameCheck = new DatabaseSync(databasePath, { readOnly: true });
  assert.equal(customNameCheck.prepare("SELECT name FROM threads WHERE id=?").get(ids.existing).name, "Existing custom title");
  customNameCheck.close();

  // A catalog pointing at another task must not borrow its name or format.
  const mismatchSetup = new DatabaseSync(databasePath);
  const wrongPath = path.join(active, `rollout-2026-07-21T00-00-00-${ids.active}.jsonl`);
  mismatchSetup.prepare("UPDATE threads SET rollout_path=?, history_mode='legacy', name=NULL WHERE id=?").run(wrongPath, ids.existing);
  mismatchSetup.close();
  run();
  const mismatchCheck = new DatabaseSync(databasePath);
  assert.equal(mismatchCheck.prepare("SELECT history_mode FROM threads WHERE id=?").get(ids.existing).history_mode, "legacy");
  assert.equal(mismatchCheck.prepare("SELECT name FROM threads WHERE id=?").get(ids.existing).name, null);
  mismatchCheck.prepare("UPDATE threads SET rollout_path=?, history_mode='paginated', name='User chosen name' WHERE id=?").run(existingPath, ids.existing);
  mismatchCheck.close();

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
  schedulerCheck = new DatabaseSync(automationDatabasePath, { readOnly: true });
  assert.equal(schedulerCheck.prepare("SELECT count(*) AS n FROM automation_runs").get().n, 5);
  schedulerCheck.close();

  console.log("Repair-CodexThreadCatalog tests passed");
} finally {
  fs.rmSync(work, { recursive: true, force: true });
}
