import fs from "node:fs";
import path from "node:path";

function parseArgs(argv) {
  const result = {};
  for (let i = 0; i < argv.length; i += 2) {
    const key = argv[i];
    const value = argv[i + 1];
    if (!key?.startsWith("--") || value === undefined) throw new Error(`Invalid argument near ${key ?? "end"}`);
    result[key.slice(2)] = value;
  }
  return result;
}

const args = parseArgs(process.argv.slice(2));
for (const required of ["input", "output", "report-output"]) {
  if (!args[required]) throw new Error(`Missing --${required}`);
}

const source = fs.readFileSync(args.input, "utf8");
const lines = source.split(/\r?\n/).filter((line) => line.trim().length > 0);
const selected = new Map();
const counts = new Map();

for (let index = 0; index < lines.length; index += 1) {
  let value;
  try {
    value = JSON.parse(lines[index]);
  } catch (error) {
    throw new Error(`Invalid JSON at line ${index + 1}: ${error.message}`);
  }
  if (typeof value.id !== "string" || value.id.length === 0) throw new Error(`Missing id at line ${index + 1}`);
  counts.set(value.id, (counts.get(value.id) ?? 0) + 1);
  const timestamp = Date.parse(value.updated_at ?? "");
  const candidate = { raw: lines[index], index, timestamp: Number.isFinite(timestamp) ? timestamp : Number.NEGATIVE_INFINITY };
  const previous = selected.get(value.id);
  if (!previous || candidate.timestamp > previous.timestamp ||
      (candidate.timestamp === previous.timestamp && candidate.index > previous.index)) {
    selected.set(value.id, candidate);
  }
}

const outputLines = [...selected.values()].sort((a, b) => a.index - b.index).map((entry) => entry.raw);
fs.mkdirSync(path.dirname(args.output), { recursive: true });
fs.writeFileSync(args.output, outputLines.length > 0 ? `${outputLines.join("\n")}\n` : "", "utf8");
const duplicateIds = [...counts.values()].filter((count) => count > 1).length;
fs.writeFileSync(args["report-output"], `${JSON.stringify({
  schema_version: 1,
  input_rows: lines.length,
  output_rows: outputLines.length,
  duplicate_rows: lines.length - outputLines.length,
  duplicate_ids: duplicateIds,
})}\n`, "utf8");
