import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const helper = path.resolve(path.dirname(new URL(import.meta.url).pathname.replace(/^\/(.:)/, "$1")), "..", "Merge-CodexSidebarState.mjs");
const work = fs.mkdtempSync(path.join(os.tmpdir(), "codexkit-sidebar-test-"));

function write(name, value) {
  const file = path.join(work, name);
  fs.writeFileSync(file, JSON.stringify(value), "utf8");
  return file;
}

function state(device, organization) {
  const persisted = {
    "device-only-value": device,
    "thread-descriptions-v1": organization.descriptions ?? {},
  };
  if (organization.preferences !== undefined) {
    persisted["flat-project-sidebar-preferences-v1"] = organization.preferences;
  }
  return {
    "electron-main-window-bounds": { x: device },
    "electron-persisted-atom-state": persisted,
    "electron-saved-workspace-roots": organization.roots ?? [],
    "project-order": organization.order ?? [],
    "pinned-thread-ids": organization.pinned ?? [],
    "thread-workspace-root-hints": {},
    "thread-projectless-output-directories": {},
    "thread-writable-roots": {},
    "local-projects": organization.projects ?? {},
    "project-writable-roots": {},
    "thread-project-assignments": organization.assignments ?? {},
    "projectless-thread-ids": organization.projectless ?? [],
  };
}

function run(base, local, shared, suffix, mode = "merge") {
  const files = {
    base: write(`base-${suffix}.json`, base),
    local: write(`local-${suffix}.json`, local),
    shared: write(`shared-${suffix}.json`, shared),
    localOutput: path.join(work, `local-output-${suffix}.json`),
    sharedOutput: path.join(work, `shared-output-${suffix}.json`),
    baseOutput: path.join(work, `base-output-${suffix}.json`),
    reportOutput: path.join(work, `report-${suffix}.json`),
  };
  execFileSync(process.execPath, [
    helper,
    "--local", files.local,
    "--shared", files.shared,
    "--base", files.base,
    "--local-output", files.localOutput,
    "--shared-output", files.sharedOutput,
    "--base-output", files.baseOutput,
    "--report-output", files.reportOutput,
    "--mode", mode,
  ]);
  return Object.fromEntries(Object.entries(files).slice(3).map(([key, file]) => [key, JSON.parse(fs.readFileSync(file, "utf8"))]));
}

try {
  const baseOrganization = {
    "electron-saved-workspace-roots": ["p1", "p2"],
    "project-order": ["p1", "p2"],
    "pinned-thread-ids": ["t1"],
    "thread-workspace-root-hints": {},
    "thread-projectless-output-directories": {},
    "thread-writable-roots": {},
    "local-projects": { p1: { name: "one" }, p2: { name: "two" } },
    "project-writable-roots": {},
    "thread-project-assignments": { t1: { projectId: "p1" } },
    "projectless-thread-ids": ["t2"],
    "thread-descriptions-v1": { t1: "base" },
  };
  const local = state(1, {
    roots: ["p1", "p3"],
    order: ["p3", "p1"],
    pinned: ["t1", "t2"],
    projects: { p1: { name: "one" }, p3: { name: "three" } },
    assignments: { t1: { projectId: "p1" }, t2: { projectId: "p3" } },
    descriptions: { t1: "local" },
  });
  const shared = state(2, {
    roots: ["p1", "p2", "p4"],
    order: ["p1", "p2", "p4"],
    pinned: ["t1", "t4"],
    projects: { p1: { name: "one" }, p2: { name: "two" }, p4: { name: "four" } },
    assignments: { t1: { projectId: "p1" }, t4: { projectId: "p4" } },
    projectless: ["t2"],
    descriptions: { t1: "base", t4: "shared" },
  });
  const merged = run(baseOrganization, local, shared, "nonconflict");

  assert.equal(merged.localOutput["electron-main-window-bounds"].x, 1);
  assert.equal(merged.sharedOutput["electron-main-window-bounds"].x, 2);
  assert.deepEqual(Object.keys(merged.localOutput["local-projects"]).sort(), ["p1", "p3", "p4"]);
  assert.equal(merged.localOutput["thread-project-assignments"].t2.projectId, "p3");
  assert.equal(merged.localOutput["thread-project-assignments"].t4.projectId, "p4");
  assert.deepEqual(new Set(merged.localOutput["pinned-thread-ids"]), new Set(["t1", "t2", "t4"]));
  assert.equal(merged.localOutput["local-projects"].p2, undefined);
  assert.deepEqual(merged.reportOutput.conflicts, []);

  const conflictLocal = state(1, { assignments: { t1: { projectId: "p2" } } });
  const conflictShared = state(2, { assignments: { t1: { projectId: "p3" } } });
  const conflictBase = {
    ...baseOrganization,
    "thread-project-assignments": { t1: { projectId: "p1" } },
    "projectless-thread-ids": [],
  };
  const conflicted = run(conflictBase, conflictLocal, conflictShared, "conflict");
  assert.equal(conflicted.localOutput["thread-project-assignments"].t1.projectId, "p2");
  assert.ok(conflicted.reportOutput.conflicts.some((value) => value.includes("thread-classification.t1")));

  const pulled = run(baseOrganization, local, shared, "pull", "pull");
  assert.equal(pulled.localOutput["electron-main-window-bounds"].x, 1);
  assert.deepEqual(pulled.localOutput["thread-project-assignments"], shared["thread-project-assignments"]);
  assert.deepEqual(pulled.localOutput["projectless-thread-ids"], shared["projectless-thread-ids"]);
  assert.equal(pulled.reportOutput.mode, "pull");

  const localWithDeletedPreference = state(1, { preferences: { compact: true } });
  const sharedWithoutPreference = state(2, {});
  const deletedPreference = run({}, localWithDeletedPreference, sharedWithoutPreference, "pull-delete", "pull");
  assert.equal(
    Object.hasOwn(deletedPreference.localOutput["electron-persisted-atom-state"], "flat-project-sidebar-preferences-v1"),
    false,
  );

  const pushed = run(baseOrganization, local, shared, "push", "push");
  assert.equal(pushed.sharedOutput["electron-main-window-bounds"].x, 2);
  assert.deepEqual(pushed.sharedOutput["thread-project-assignments"], local["thread-project-assignments"]);
  assert.deepEqual(pushed.sharedOutput["projectless-thread-ids"], local["projectless-thread-ids"]);
  assert.equal(pushed.reportOutput.mode, "push");

  console.log("Merge-CodexSidebarState tests passed");
} finally {
  fs.rmSync(work, { recursive: true, force: true });
}
