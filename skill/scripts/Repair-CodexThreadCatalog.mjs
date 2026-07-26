import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import readline from "node:readline";
import { DatabaseSync } from "node:sqlite";

function parseArgs(argv) {
  const args = {};
  for (let i = 2; i < argv.length; i += 2) {
    const key = argv[i];
    const value = argv[i + 1];
    if (!key?.startsWith("--") || value === undefined) {
      throw new Error(`Invalid argument near ${key ?? "<end>"}`);
    }
    args[key.slice(2)] = value;
  }
  for (const required of ["database", "sessions-root", "archived-root", "session-index", "report-output"]) {
    if (!args[required]) throw new Error(`Missing --${required}`);
  }
  return args;
}

function asText(value, fallback = "") {
  if (typeof value === "string") return value;
  if (value === null || value === undefined) return fallback;
  return JSON.stringify(value);
}

function parseTime(value, fallbackMs) {
  const parsed = Date.parse(value ?? "");
  return Number.isFinite(parsed) ? parsed : fallbackMs;
}

function writeReport(reportPath, report) {
  fs.mkdirSync(path.dirname(reportPath), { recursive: true });
  fs.writeFileSync(reportPath, `${JSON.stringify(report, null, 2)}\n`, "utf8");
}

async function loadTitleIndex(indexPath) {
  const latest = new Map();
  if (!fs.existsSync(indexPath)) return latest;
  const input = fs.createReadStream(indexPath, { encoding: "utf8" });
  const lines = readline.createInterface({ input, crlfDelay: Infinity });
  let rowNumber = 0;
  for await (const line of lines) {
    rowNumber += 1;
    if (!line.trim()) continue;
    let row;
    try {
      row = JSON.parse(line);
    } catch (error) {
      throw new Error(`Invalid JSON in session index at row ${rowNumber}: ${error.message}`);
    }
    if (typeof row.id !== "string" || !row.id) continue;
    const id = row.id.toLowerCase();
    const stamp = parseTime(row.updated_at, 0);
    const previous = latest.get(id);
    if (!previous || stamp >= previous.stamp) {
      latest.set(id, { title: asText(row.thread_name, ""), stamp });
    }
  }
  return latest;
}

function collectRolloutCandidates(root, archived, groups) {
  if (!fs.existsSync(root)) return;
  const pending = [root];
  while (pending.length) {
    const current = pending.pop();
    for (const entry of fs.readdirSync(current, { withFileTypes: true })) {
      const fullPath = path.join(current, entry.name);
      if (entry.isDirectory()) {
        pending.push(fullPath);
        continue;
      }
      if (!entry.isFile() || !entry.name.toLowerCase().endsWith(".jsonl")) continue;
      const match = entry.name.match(/(019[a-f0-9]{5}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})/i);
      if (!match) continue;
      const id = match[1].toLowerCase();
      const stat = fs.statSync(fullPath);
      const candidate = {
        path: path.resolve(fullPath),
        archived,
        size: stat.size,
        mtimeMs: stat.mtimeMs,
      };
      const existing = groups.get(id) ?? [];
      existing.push(candidate);
      groups.set(id, existing);
    }
  }
}

function inspectFirstJsonRow(filePath) {
  const handle = fs.openSync(filePath, "r");
  const buffer = Buffer.allocUnsafe(256 * 1024);
  try {
    const count = fs.readSync(handle, buffer, 0, buffer.length, 0);
    const chunk = buffer.subarray(0, count);
    const newline = chunk.indexOf(0x0a);
    if (newline < 0 && count === buffer.length) {
      return { valid: false, error: "first JSON row exceeds 256 KiB" };
    }
    const line = chunk.subarray(0, newline < 0 ? count : newline).toString("utf8").replace(/^\uFEFF/, "").trim();
    if (!line) return { valid: false, error: "empty first JSON row" };
    JSON.parse(line);
    return { valid: true, error: null };
  } catch (error) {
    return { valid: false, error: error.message };
  } finally {
    fs.closeSync(handle);
  }
}

function hashFile(filePath) {
  const hash = crypto.createHash("sha256");
  const handle = fs.openSync(filePath, "r");
  const buffer = Buffer.allocUnsafe(1024 * 1024);
  try {
    while (true) {
      const count = fs.readSync(handle, buffer, 0, buffer.length, null);
      if (count === 0) break;
      hash.update(buffer.subarray(0, count));
    }
  } finally {
    fs.closeSync(handle);
  }
  return hash.digest("hex");
}

function isFilePrefix(prefixPath, completePath, prefixSize) {
  if (prefixSize === 0) return true;
  const prefix = fs.openSync(prefixPath, "r");
  const complete = fs.openSync(completePath, "r");
  const left = Buffer.allocUnsafe(1024 * 1024);
  const right = Buffer.allocUnsafe(1024 * 1024);
  let remaining = prefixSize;
  try {
    while (remaining > 0) {
      const requested = Math.min(left.length, remaining);
      const leftCount = fs.readSync(prefix, left, 0, requested, null);
      const rightCount = fs.readSync(complete, right, 0, requested, null);
      if (leftCount !== rightCount || leftCount === 0) return false;
      if (!left.subarray(0, leftCount).equals(right.subarray(0, rightCount))) return false;
      remaining -= leftCount;
    }
    return true;
  } finally {
    fs.closeSync(prefix);
    fs.closeSync(complete);
  }
}

function resolveRolloutUnion(groups) {
  const rollouts = new Map();
  const conflicts = [];
  let duplicateGroups = 0;
  let redundantFiles = 0;
  let prefixExtensions = 0;
  const corruptCopies = [];

  for (const [id, originalCandidates] of groups) {
    const candidatesByPath = new Map(originalCandidates.map((candidate) => [candidate.path.toLowerCase(), candidate]));
    const uniqueCandidates = [...candidatesByPath.values()];
    const inspectedCandidates = uniqueCandidates.map((candidate) => ({
      candidate,
      inspection: inspectFirstJsonRow(candidate.path),
    }));
    const validCandidates = inspectedCandidates
      .filter((entry) => entry.inspection.valid)
      .map((entry) => entry.candidate);
    const candidates = (validCandidates.length ? validCandidates : uniqueCandidates).sort(
      (left, right) =>
        right.size - left.size ||
        Number(left.archived) - Number(right.archived) ||
        left.path.localeCompare(right.path),
    );
    if (validCandidates.length) {
      for (const entry of inspectedCandidates.filter((item) => !item.inspection.valid)) {
        corruptCopies.push({
          thread_id: id,
          path: entry.candidate.path,
          size: entry.candidate.size,
          error: entry.inspection.error,
        });
      }
    }
    const selected = candidates[0];
    if (uniqueCandidates.length > 1) duplicateGroups += 1;

    let selectedHash = null;
    for (const candidate of candidates.slice(1)) {
      if (candidate.size === selected.size) {
        selectedHash ??= hashFile(selected.path);
        if (hashFile(candidate.path) === selectedHash) {
          redundantFiles += 1;
          continue;
        }
      } else if (
        candidate.size < selected.size &&
        isFilePrefix(candidate.path, selected.path, candidate.size)
      ) {
        prefixExtensions += 1;
        continue;
      }
      conflicts.push({
        thread_id: id,
        selected_path: selected.path,
        selected_size: selected.size,
        conflicting_path: candidate.path,
        conflicting_size: candidate.size,
      });
    }
    rollouts.set(id, selected);
  }

  return { rollouts, conflicts, duplicateGroups, redundantFiles, prefixExtensions, corruptCopies };
}

function findAutomationId(text) {
  for (const line of asText(text).split(/\r?\n/)) {
    const match = line.match(/^\s*Automation ID:\s*`?([A-Za-z0-9._-]+)`?\s*$/i);
    if (match) return match[1];
  }
  return null;
}

async function loadRolloutMetadata(filePath, indexedTitle) {
  const stat = fs.statSync(filePath);
  const input = fs.createReadStream(filePath, { encoding: "utf8" });
  const lines = readline.createInterface({ input, crlfDelay: Infinity });
  let meta = null;
  let firstUserMessage = "";
  let turnContext = null;
  let automationId = null;
  let inspected = 0;
  try {
    for await (const line of lines) {
      inspected += 1;
      if (!line.trim()) continue;
      let row;
      try {
        row = JSON.parse(line);
      } catch {
        if (inspected === 1) throw new Error(`Invalid first JSON row in ${filePath}`);
        continue;
      }
      if (row.type === "session_meta" && row.payload) meta = row.payload;
      if (row.type === "turn_context" && row.payload && !turnContext) turnContext = row.payload;
      const payload = row.type === "response_item" ? row.payload : null;
      if (payload?.type === "message") {
        const pieces = Array.isArray(payload.content)
          ? payload.content.map((part) => asText(part?.text, "")).filter(Boolean)
          : [];
        const message = pieces.join("\n").trim();
        if (!firstUserMessage && payload.role === "user") firstUserMessage = message;
        automationId ??= findAutomationId(message);
      }
      const automationMetadataComplete =
        asText(meta?.thread_source, "user") !== "automation" || automationId !== null;
      if (meta && firstUserMessage && turnContext && automationMetadataComplete) break;
      if (inspected >= 300) break;
    }
  } finally {
    lines.close();
    input.destroy();
  }
  if (!meta) throw new Error(`Missing session_meta in ${filePath}`);
  const id = asText(meta.id || meta.session_id).toLowerCase();
  if (!id) throw new Error(`Missing session id in ${filePath}`);
  const createdMs = parseTime(meta.timestamp, stat.birthtimeMs || stat.mtimeMs);
  const updatedMs = Math.max(createdMs, stat.mtimeMs);
  const title = indexedTitle || firstUserMessage || "Untitled task";
  return {
    id,
    rollout_path: path.resolve(filePath),
    created_at: Math.floor(createdMs / 1000),
    updated_at: Math.floor(updatedMs / 1000),
    source: asText(meta.source, "unknown"),
    model_provider: asText(meta.model_provider, "openai"),
    cwd: asText(meta.cwd, process.cwd()),
    title,
    sandbox_policy: asText(turnContext?.sandbox_policy, "{}"),
    approval_mode: asText(turnContext?.approval_policy, "on-request"),
    tokens_used: 0,
    has_user_event: firstUserMessage ? 1 : 0,
    git_sha: meta.git?.commit_hash ?? null,
    git_branch: meta.git?.branch ?? null,
    git_origin_url: meta.git?.repository_url ?? null,
    cli_version: asText(meta.cli_version, ""),
    first_user_message: firstUserMessage || title,
    agent_nickname: null,
    agent_role: null,
    memory_mode: "enabled",
    model: asText(turnContext?.model, "") || null,
    reasoning_effort: asText(turnContext?.reasoning_effort, "") || null,
    agent_path: null,
    created_at_ms: Math.floor(createdMs),
    updated_at_ms: Math.floor(updatedMs),
    thread_source: asText(meta.thread_source, "user"),
    preview: firstUserMessage || title,
    recency_at: Math.floor(updatedMs / 1000),
    recency_at_ms: Math.floor(updatedMs),
    history_mode: "legacy",
    automation_id: automationId,
    input_size: stat.size,
    input_mtime_ms: stat.mtimeMs,
  };
}

function assertMetadataInputUnchanged(row) {
  const stat = fs.statSync(row.rollout_path);
  if (stat.size !== row.input_size || stat.mtimeMs !== row.input_mtime_ms) {
    throw new Error(`Rollout changed during thread-catalog reconciliation: ${row.rollout_path}`);
  }
}

function insertThread(database, columns, row) {
  const supported = columns.filter((column) => Object.hasOwn(row, column.name));
  const missingRequired = columns.filter(
    (column) => column.notnull && column.defaultValue === null && !Object.hasOwn(row, column.name),
  );
  if (missingRequired.length) {
    throw new Error(`Unsupported required threads columns: ${missingRequired.map((column) => column.name).join(", ")}`);
  }
  const names = supported.map((column) => `"${column.name.replaceAll('"', '""')}"`);
  const placeholders = supported.map(() => "?");
  const statement = database.prepare(
    `INSERT INTO threads (${names.join(",")}) VALUES (${placeholders.join(",")})`,
  );
  return statement.run(...supported.map((column) => row[column.name])).changes;
}

function updateAutomationPath(database, columns, row, archived) {
  const available = new Set(columns.map((column) => column.name));
  const assignments = ["rollout_path=?"];
  const values = [row.rollout_path];
  if (available.has("archived")) {
    assignments.push("archived=?");
    values.push(archived ? 1 : 0);
  }
  if (available.has("archived_at")) {
    assignments.push("archived_at=?");
    values.push(archived ? row.updated_at : null);
  }
  values.push(row.id);
  return database.prepare(`UPDATE threads SET ${assignments.join(",")} WHERE lower(id)=?`).run(...values).changes;
}

function summarizeAutomationHistory(automationRows, database) {
  const grouped = new Map();
  let cataloged = 0;
  let unresolved = 0;
  let unknownIds = 0;
  for (const row of automationRows.values()) {
    const found = Boolean(database.prepare("SELECT 1 AS found FROM threads WHERE lower(id)=? LIMIT 1").get(row.id));
    if (found) cataloged += 1;
    else unresolved += 1;
    const automationId = row.automation_id || "<unknown>";
    if (!row.automation_id) unknownIds += 1;
    const entry = grouped.get(automationId) ?? {
      automation_id: automationId,
      rollout_count: 0,
      cataloged_count: 0,
      latest_updated_at_ms: 0,
    };
    entry.rollout_count += 1;
    if (found) entry.cataloged_count += 1;
    entry.latest_updated_at_ms = Math.max(entry.latest_updated_at_ms, row.updated_at_ms);
    grouped.set(automationId, entry);
  }
  return {
    total: automationRows.size,
    cataloged,
    unresolved,
    unknownIds,
    byAutomation: [...grouped.values()].sort((left, right) =>
      left.automation_id.localeCompare(right.automation_id),
    ),
  };
}

async function main() {
  const args = parseArgs(process.argv);
  if (!fs.existsSync(args.database)) throw new Error(`Thread database is missing: ${args.database}`);
  const titles = await loadTitleIndex(args["session-index"]);
  const rolloutGroups = new Map();
  collectRolloutCandidates(args["sessions-root"], false, rolloutGroups);
  collectRolloutCandidates(args["archived-root"], true, rolloutGroups);
  const union = resolveRolloutUnion(rolloutGroups);

  if (union.conflicts.length) {
    writeReport(args["report-output"], {
      schema_version: 2,
      status: "rollout-conflict",
      indexed_titles: titles.size,
      rollout_files: [...rolloutGroups.values()].reduce((sum, entries) => sum + entries.length, 0),
      rollout_union_count: union.rollouts.size,
      rollout_duplicate_groups: union.duplicateGroups,
      rollout_redundant_files: union.redundantFiles,
      rollout_prefix_extensions: union.prefixExtensions,
      corrupt_rollout_copy_count: union.corruptCopies.length,
      corrupt_rollout_copies: union.corruptCopies,
      rollout_conflict_count: union.conflicts.length,
      rollout_conflicts: union.conflicts,
      unresolved_count: 0,
      automation_history_unresolved_count: 0,
    });
    throw new Error(
      `Detected ${union.conflicts.length} divergent rollout copy/copies for the same thread ID; no local catalog changes were made.`,
    );
  }

  const database = new DatabaseSync(args.database, { timeout: 5000 });
  const inserted = [];
  const unresolved = [];
  const ignoredAliases = [];
  const automationPathRepairs = [];
  const automationRows = new Map();
  try {
    const quickCheck = database.prepare("PRAGMA quick_check").get();
    if (!quickCheck || Object.values(quickCheck)[0] !== "ok") throw new Error("SQLite quick_check did not return ok");
    const table = database.prepare("SELECT name FROM sqlite_master WHERE type='table' AND name='threads'").get();
    if (!table) throw new Error("The local state database has no threads table");
    const columns = database.prepare("PRAGMA table_info(threads)").all().map((column) => ({
      name: column.name,
      notnull: Boolean(column.notnull),
      defaultValue: column.dflt_value,
    }));
    const columnNames = new Set(columns.map((column) => column.name));
    const selectedColumns = ["id", "rollout_path"];
    if (columnNames.has("thread_source")) selectedColumns.push("thread_source");
    const existingRows = new Map(
      database
        .prepare(`SELECT ${selectedColumns.join(",")} FROM threads`)
        .all()
        .map((row) => [row.id.toLowerCase(), row]),
    );

    const metadata = new Map();
    for (const [id, title] of titles) {
      const rollout = union.rollouts.get(id);
      if (!rollout) continue;
      const existing = existingRows.get(id);
      if (!existing || existing.thread_source === "automation") {
        const row = await loadRolloutMetadata(rollout.path, title.title);
        metadata.set(id, row);
        if (row.id !== id) {
          ignoredAliases.push({ indexed_id: id, canonical_id: row.id, rollout_path: rollout.path });
          continue;
        }
        if (row.thread_source === "automation") automationRows.set(id, row);
      }
    }

    const insertRows = [];
    const pathRepairRows = [];
    for (const [id, row] of metadata) {
      if (ignoredAliases.some((entry) => entry.indexed_id === id)) continue;
      const existing = existingRows.get(id);
      if (!existing) {
        insertRows.push({ row, rollout: union.rollouts.get(id) });
      } else if (
        row.thread_source === "automation" &&
        (!existing.rollout_path || !fs.existsSync(existing.rollout_path))
      ) {
        pathRepairRows.push({ row, rollout: union.rollouts.get(id), oldPath: existing.rollout_path });
      }
    }
    for (const entry of [...insertRows, ...pathRepairRows]) assertMetadataInputUnchanged(entry.row);

    database.exec("BEGIN IMMEDIATE");
    try {
      for (const { row, rollout } of insertRows) {
        row.archived = rollout.archived ? 1 : 0;
        row.archived_at = rollout.archived ? row.updated_at : null;
        let changes;
        try {
          changes = insertThread(database, columns, row);
        } catch (error) {
          throw new Error(`Could not register indexed task ${row.id} from ${rollout.path}: ${error.message}`);
        }
        if (changes === 1) inserted.push(row.id);
      }
      for (const { row, rollout, oldPath } of pathRepairRows) {
        const changes = updateAutomationPath(database, columns, row, rollout.archived);
        if (changes === 1) {
          automationPathRepairs.push({
            thread_id: row.id,
            automation_id: row.automation_id || "<unknown>",
            old_path: oldPath,
            new_path: row.rollout_path,
          });
        }
      }
      for (const [id] of titles) {
        if (!union.rollouts.has(id)) continue;
        if (ignoredAliases.some((entry) => entry.indexed_id === id)) continue;
        const found = database.prepare("SELECT 1 AS found FROM threads WHERE lower(id)=? LIMIT 1").get(id);
        if (!found) unresolved.push(id);
      }
      if (unresolved.length) {
        throw new Error(
          `Thread catalog still misses ${unresolved.length} indexed task(s): ${unresolved.slice(0, 10).join(", ")}`,
        );
      }
      database.exec("COMMIT");
    } catch (error) {
      database.exec("ROLLBACK");
      throw error;
    }
    database.exec("PRAGMA wal_checkpoint(TRUNCATE)");

    const automation = summarizeAutomationHistory(automationRows, database);
    const report = {
      schema_version: 2,
      status: "reconciled",
      indexed_titles: titles.size,
      rollout_files: [...rolloutGroups.values()].reduce((sum, entries) => sum + entries.length, 0),
      rollout_union_count: union.rollouts.size,
      rollout_duplicate_groups: union.duplicateGroups,
      rollout_redundant_files: union.redundantFiles,
      rollout_prefix_extensions: union.prefixExtensions,
      corrupt_rollout_copy_count: union.corruptCopies.length,
      corrupt_rollout_copies: union.corruptCopies,
      rollout_conflict_count: 0,
      rollout_conflicts: [],
      inserted_count: inserted.length,
      inserted_ids: inserted,
      ignored_alias_count: ignoredAliases.length,
      ignored_aliases: ignoredAliases,
      unresolved_count: unresolved.length,
      automation_history_rollouts: automation.total,
      automation_history_cataloged: automation.cataloged,
      automation_history_inserted_count: inserted.filter((id) => automationRows.has(id)).length,
      automation_history_path_repaired_count: automationPathRepairs.length,
      automation_history_path_repairs: automationPathRepairs,
      automation_history_unknown_id_count: automation.unknownIds,
      automation_history_unresolved_count: automation.unresolved,
      automation_histories: automation.byAutomation,
      database: path.resolve(args.database),
    };
    writeReport(args["report-output"], report);
    console.log(
      `Thread catalog reconciled: ${inserted.length} missing task(s) registered; ` +
        `${automation.total} automation run(s) unioned, ${automationPathRepairs.length} stale path(s) repaired.`,
    );
  } finally {
    database.close();
  }
}

main().catch((error) => {
  console.error(error.stack || error.message);
  process.exitCode = 1;
});
