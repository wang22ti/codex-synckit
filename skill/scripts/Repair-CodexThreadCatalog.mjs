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

function collectRollouts(root, archived, result) {
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
      const candidate = { path: path.resolve(fullPath), archived };
      const previous = result.get(id);
      if (!previous || (previous.archived && !archived)) result.set(id, candidate);
    }
  }
}

async function loadRolloutMetadata(filePath, indexedTitle) {
  const stat = fs.statSync(filePath);
  const input = fs.createReadStream(filePath, { encoding: "utf8" });
  const lines = readline.createInterface({ input, crlfDelay: Infinity });
  let meta = null;
  let firstUserMessage = "";
  let turnContext = null;
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
      if (!firstUserMessage && payload?.type === "message" && payload.role === "user") {
        const pieces = Array.isArray(payload.content)
          ? payload.content.map((part) => asText(part?.text, "")).filter(Boolean)
          : [];
        firstUserMessage = pieces.join("\n").trim();
      }
      if (meta && firstUserMessage && turnContext) break;
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
  };
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

async function main() {
  const args = parseArgs(process.argv);
  if (!fs.existsSync(args.database)) throw new Error(`Thread database is missing: ${args.database}`);
  const titles = await loadTitleIndex(args["session-index"]);
  const rollouts = new Map();
  collectRollouts(args["sessions-root"], false, rollouts);
  collectRollouts(args["archived-root"], true, rollouts);

  const database = new DatabaseSync(args.database, { timeout: 5000 });
  const inserted = [];
  const unresolved = [];
  const ignoredAliases = [];
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
    const existing = new Set(database.prepare("SELECT id FROM threads").all().map((row) => row.id.toLowerCase()));
    const candidates = [...titles.keys()].filter((id) => rollouts.has(id) && !existing.has(id)).sort();
    database.exec("BEGIN IMMEDIATE");
    try {
      for (const id of candidates) {
        const rollout = rollouts.get(id);
        const row = await loadRolloutMetadata(rollout.path, titles.get(id)?.title);
        if (row.id !== id) {
          ignoredAliases.push({ indexed_id: id, canonical_id: row.id, rollout_path: rollout.path });
          continue;
        }
        row.archived = rollout.archived ? 1 : 0;
        row.archived_at = rollout.archived ? row.updated_at : null;
        let changes;
        try {
          changes = insertThread(database, columns, row);
        } catch (error) {
          throw new Error(`Could not register indexed task ${id} as row ${row.id} from ${rollout.path}: ${error.message}`);
        }
        if (changes === 1) inserted.push(id);
      }
      for (const [id] of titles) {
        if (!rollouts.has(id)) continue;
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
    const report = {
      schema_version: 1,
      indexed_titles: titles.size,
      rollout_files: rollouts.size,
      inserted_count: inserted.length,
      inserted_ids: inserted,
      ignored_alias_count: ignoredAliases.length,
      ignored_aliases: ignoredAliases,
      unresolved_count: unresolved.length,
      database: path.resolve(args.database),
    };
    fs.writeFileSync(args["report-output"], `${JSON.stringify(report, null, 2)}\n`, "utf8");
    console.log(`Thread catalog reconciled: ${inserted.length} missing task(s) registered locally.`);
  } finally {
    database.close();
  }
}

main().catch((error) => {
  console.error(error.stack || error.message);
  process.exitCode = 1;
});
