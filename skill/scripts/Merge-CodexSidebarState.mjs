import fs from "node:fs";
import path from "node:path";

function parseArgs(argv) {
  const result = {};
  for (let i = 0; i < argv.length; i += 2) {
    const key = argv[i];
    const value = argv[i + 1];
    if (!key?.startsWith("--") || value === undefined) {
      throw new Error(`Invalid argument near ${key ?? "end of command"}`);
    }
    result[key.slice(2)] = value;
  }
  return result;
}

function readJson(file, fallback) {
  if (!file || !fs.existsSync(file)) return fallback;
  return JSON.parse(fs.readFileSync(file, "utf8"));
}

function stable(value) {
  if (Array.isArray(value)) return `[${value.map(stable).join(",")}]`;
  if (value && typeof value === "object") {
    return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${stable(value[key])}`).join(",")}}`;
  }
  return JSON.stringify(value);
}

function equal(a, b) {
  return stable(a) === stable(b);
}

function clone(value) {
  return value === undefined ? undefined : JSON.parse(JSON.stringify(value));
}

const projectlessRootToken = "__CODEX_PROJECTLESS_ROOT__";

function portableProjectlessPath(value, localRoot) {
  if (typeof value !== "string") return value;
  const normalized = value.replaceAll("/", "\\");
  if (normalized === projectlessRootToken || normalized.startsWith(`${projectlessRootToken}\\`)) {
    return normalized;
  }
  const roots = [
    localRoot?.replaceAll("/", "\\").replace(/\\+$/, ""),
    normalized.match(/^[A-Za-z]:\\Users\\[^\\]+\\Documents\\Codex(?=\\|$)/i)?.[0],
  ].filter(Boolean);
  for (const root of roots) {
    if (normalized.localeCompare(root, undefined, { sensitivity: "accent" }) === 0) {
      return projectlessRootToken;
    }
    if (normalized.toLowerCase().startsWith(`${root.toLowerCase()}\\`)) {
      return `${projectlessRootToken}\\${normalized.slice(root.length + 1)}`;
    }
  }
  return value;
}

function transformStrings(value, transform) {
  if (typeof value === "string") return transform(value);
  if (Array.isArray(value)) return value.map((entry) => transformStrings(entry, transform));
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.entries(value).map(([key, entry]) => [key, transformStrings(entry, transform)]));
  }
  return value;
}

function portableOrganization(organization, localRoot) {
  const result = clone(organization);
  for (const field of projectlessPathFields) {
    result[field] = transformStrings(result[field], (value) => portableProjectlessPath(value, localRoot));
  }
  return result;
}

function localOrganization(organization, localRoot) {
  const result = clone(organization);
  for (const field of projectlessPathFields) {
    result[field] = transformStrings(result[field], (value) => {
      if (value === projectlessRootToken) return localRoot;
      if (value.startsWith(`${projectlessRootToken}\\`)) {
        return path.join(localRoot, value.slice(projectlessRootToken.length + 1));
      }
      return value;
    });
  }
  return result;
}

function choose(base, local, shared, conflicts, label) {
  if (equal(local, shared)) return clone(local);
  if (equal(local, base)) return clone(shared);
  if (equal(shared, base)) return clone(local);
  conflicts.push(label);
  return clone(local);
}

function orderedKeys(...objects) {
  const seen = new Set();
  const keys = [];
  for (const object of objects) {
    for (const key of Object.keys(object ?? {})) {
      if (seen.has(key)) continue;
      seen.add(key);
      keys.push(key);
    }
  }
  return keys;
}

function mergeMap(base = {}, local = {}, shared = {}, conflicts, label) {
  const result = {};
  for (const key of orderedKeys(local, shared, base)) {
    const value = choose(base[key], local[key], shared[key], conflicts, `${label}.${key}`);
    if (value !== undefined) result[key] = value;
  }
  return result;
}

function mergeArray(base = [], local = [], shared = [], conflicts, label) {
  if (equal(local, shared)) return clone(local);
  if (equal(local, base)) return clone(shared);
  if (equal(shared, base)) return clone(local);

  const baseSet = new Set(base.map(stable));
  const localSet = new Set(local.map(stable));
  const sharedSet = new Set(shared.map(stable));
  const values = new Map([...base, ...shared, ...local].map((value) => [stable(value), value]));
  const included = new Set();

  for (const key of values.keys()) {
    const present = choose(
      baseSet.has(key),
      localSet.has(key),
      sharedSet.has(key),
      conflicts,
      `${label}[${key}]`,
    );
    if (present) included.add(key);
  }

  const result = [];
  for (const value of [...local, ...shared, ...base]) {
    const key = stable(value);
    if (!included.delete(key)) continue;
    result.push(clone(values.get(key)));
  }
  return result;
}

const mapFields = [
  "thread-workspace-root-hints",
  "thread-projectless-output-directories",
  "thread-writable-roots",
  "local-projects",
  "project-writable-roots",
];

const arrayFields = [
  "electron-saved-workspace-roots",
  "project-order",
  "pinned-thread-ids",
];
const projectlessPathFields = [...mapFields, "electron-saved-workspace-roots"];

function organizationFrom(state = {}) {
  const persisted = state["electron-persisted-atom-state"] ?? {};
  const organization = {};
  for (const field of mapFields) organization[field] = clone(state[field] ?? {});
  for (const field of arrayFields) organization[field] = clone(state[field] ?? []);
  organization["thread-project-assignments"] = clone(state["thread-project-assignments"] ?? {});
  organization["projectless-thread-ids"] = clone(state["projectless-thread-ids"] ?? []);
  organization["thread-descriptions-v1"] = clone(persisted["thread-descriptions-v1"] ?? {});
  organization["flat-project-sidebar-preferences-v1"] = clone(persisted["flat-project-sidebar-preferences-v1"]);
  return organization;
}

function classifications(organization) {
  const result = {};
  for (const [threadId, assignment] of Object.entries(organization["thread-project-assignments"] ?? {})) {
    result[threadId] = { kind: "assigned", assignment: clone(assignment) };
  }
  for (const threadId of organization["projectless-thread-ids"] ?? []) {
    if (!Object.hasOwn(result, threadId)) result[threadId] = { kind: "projectless" };
  }
  return result;
}

function mergeOrganization(base = {}, local = {}, shared = {}) {
  const conflicts = [];
  const result = {};
  for (const field of mapFields) {
    result[field] = mergeMap(base[field], local[field], shared[field], conflicts, field);
  }
  for (const field of arrayFields) {
    result[field] = mergeArray(base[field], local[field], shared[field], conflicts, field);
  }

  const mergedClasses = mergeMap(
    classifications(base),
    classifications(local),
    classifications(shared),
    conflicts,
    "thread-classification",
  );
  result["thread-project-assignments"] = {};
  result["projectless-thread-ids"] = [];
  for (const [threadId, classification] of Object.entries(mergedClasses)) {
    if (classification?.kind === "assigned") {
      result["thread-project-assignments"][threadId] = classification.assignment;
    } else if (classification?.kind === "projectless") {
      result["projectless-thread-ids"].push(threadId);
    }
  }

  result["thread-descriptions-v1"] = mergeMap(
    base["thread-descriptions-v1"],
    local["thread-descriptions-v1"],
    shared["thread-descriptions-v1"],
    conflicts,
    "thread-descriptions-v1",
  );
  result["flat-project-sidebar-preferences-v1"] = choose(
    base["flat-project-sidebar-preferences-v1"],
    local["flat-project-sidebar-preferences-v1"],
    shared["flat-project-sidebar-preferences-v1"],
    conflicts,
    "flat-project-sidebar-preferences-v1",
  );

  return { organization: result, conflicts };
}

function applyOrganization(state, organization) {
  const result = clone(state);
  for (const field of [...mapFields, ...arrayFields, "thread-project-assignments", "projectless-thread-ids"]) {
    result[field] = clone(organization[field]);
  }
  const persisted = clone(result["electron-persisted-atom-state"] ?? {});
  persisted["thread-descriptions-v1"] = clone(organization["thread-descriptions-v1"] ?? {});
  if (organization["flat-project-sidebar-preferences-v1"] !== undefined) {
    persisted["flat-project-sidebar-preferences-v1"] = clone(organization["flat-project-sidebar-preferences-v1"]);
  } else {
    delete persisted["flat-project-sidebar-preferences-v1"];
  }
  result["electron-persisted-atom-state"] = persisted;
  return result;
}

function writeJson(file, value) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, `${JSON.stringify(value)}\n`, "utf8");
}

const args = parseArgs(process.argv.slice(2));
for (const required of ["local", "shared", "base", "local-output", "shared-output", "base-output", "report-output"]) {
  if (!args[required]) throw new Error(`Missing --${required}`);
}
const mode = args.mode ?? "merge";
if (!["pull", "push", "merge"].includes(mode)) throw new Error(`Invalid --mode: ${mode}`);
const projectlessRoot = args["projectless-root"];
if (!projectlessRoot) throw new Error("Missing --projectless-root");

const localState = readJson(args.local);
const sharedState = readJson(args.shared);
const baseOrganization = portableOrganization(readJson(args.base, {}), projectlessRoot);
if (!localState || !sharedState) throw new Error("Both local and shared desktop state files are required");

const localOrganizationValue = portableOrganization(organizationFrom(localState), projectlessRoot);
const sharedOrganization = portableOrganization(organizationFrom(sharedState), projectlessRoot);
let organization;
let conflicts = [];
if (mode === "pull") {
  organization = clone(sharedOrganization);
} else if (mode === "push") {
  organization = clone(localOrganizationValue);
} else {
  ({ organization, conflicts } = mergeOrganization(baseOrganization, localOrganizationValue, sharedOrganization));
}

writeJson(args["local-output"], applyOrganization(localState, localOrganization(organization, projectlessRoot)));
writeJson(args["shared-output"], applyOrganization(sharedState, organization));
writeJson(args["base-output"], organization);
writeJson(args["report-output"], {
  schema_version: 1,
  mode,
  merged_at: new Date().toISOString(),
  conflicts,
  conflict_policy: mode === "merge" ? "local-change-wins-with-backups" : `${mode}-is-authoritative`,
});
