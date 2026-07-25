import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const helper = path.resolve(path.dirname(new URL(import.meta.url).pathname.replace(/^\/(.:)/, "$1")), "..", "Repair-CodexSessionIndex.mjs");
const work = fs.mkdtempSync(path.join(os.tmpdir(), "codexkit-index-test-"));

function run(inputName, lines) {
  const input = path.join(work, inputName);
  const output = path.join(work, `${inputName}.out`);
  const report = path.join(work, `${inputName}.report.json`);
  fs.writeFileSync(input, `${lines.join("\n")}\n`, "utf8");
  execFileSync(process.execPath, [helper, "--input", input, "--output", output, "--report-output", report]);
  return {
    rows: fs.readFileSync(output, "utf8").trim().split(/\r?\n/).filter(Boolean).map(JSON.parse),
    report: JSON.parse(fs.readFileSync(report, "utf8")),
  };
}

try {
  const repaired = run("valid.jsonl", [
    JSON.stringify({ id: "a", thread_name: "old", updated_at: "2026-01-01T00:00:00Z" }),
    JSON.stringify({ id: "b", thread_name: "only", updated_at: "2026-01-01T00:00:00Z" }),
    JSON.stringify({ id: "a", thread_name: "new", updated_at: "2026-02-01T00:00:00Z" }),
    JSON.stringify({ id: "c", thread_name: "tie-old", updated_at: "2026-03-01T00:00:00Z" }),
    JSON.stringify({ id: "c", thread_name: "tie-new", updated_at: "2026-03-01T00:00:00Z" }),
  ]);
  assert.equal(repaired.report.input_rows, 5);
  assert.equal(repaired.report.output_rows, 3);
  assert.equal(repaired.report.duplicate_ids, 2);
  assert.equal(repaired.rows.find((row) => row.id === "a").thread_name, "new");
  assert.equal(repaired.rows.find((row) => row.id === "c").thread_name, "tie-new");

  const invalidInput = path.join(work, "invalid.jsonl");
  const invalidOutput = path.join(work, "invalid.out");
  const invalidReport = path.join(work, "invalid.report.json");
  fs.writeFileSync(invalidInput, "{not-json}\n", "utf8");
  assert.throws(() => execFileSync(process.execPath, [
    helper,
    "--input", invalidInput,
    "--output", invalidOutput,
    "--report-output", invalidReport,
  ], { stdio: "pipe" }));
  assert.equal(fs.existsSync(invalidOutput), false);
  assert.equal(fs.existsSync(invalidReport), false);

  console.log("Repair-CodexSessionIndex tests passed");
} finally {
  fs.rmSync(work, { recursive: true, force: true });
}
