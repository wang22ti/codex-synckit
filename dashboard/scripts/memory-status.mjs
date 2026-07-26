import fs from "node:fs";
import fsp from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const projectRoot = process.env.CODEXKIT_ROOT
  ? path.resolve(process.env.CODEXKIT_ROOT)
  : path.resolve(here, "..", "..");
const userRoot = os.homedir();
const registryPath = path.join(projectRoot, "memory-system", "project-memory-registry.tsv");
const discoveryConfigPath = path.join(
  projectRoot,
  "memory-system",
  "discovery-roots.json",
);
const projectMemoryRoot = path.join(projectRoot, ".learnings");
const globalRootCandidates = [
  path.join(userRoot, "global-memory"),
  path.join(projectRoot, "global-memory"),
];
const stateRoot = path.join(userRoot, ".local", "state", "memory-and-improvement");
const removalQuarantineRoot = path.join(
  userRoot,
  ".local",
  "state",
  "memory-dashboard",
  "removed-memory",
);
const hooksPath = path.join(userRoot, ".codex", "hooks.json");
const managedWorkspaceRoot = path.join(userRoot, "Documents", "Codex");
const managedWorkspaceTransportRoot = path.join(projectRoot, "CodexProjects");
const previewableTextExtensions = new Set([
  ".md",
  ".txt",
  ".json",
  ".jsonl",
  ".yaml",
  ".yml",
  ".toml",
  ".tsv",
  ".csv",
  ".log",
]);
const maxFilePreviewBytes = 512 * 1024;

const exists = (target) => {
  try {
    return fs.existsSync(target);
  } catch {
    return false;
  }
};

async function statSafe(target) {
  try {
    return await fsp.stat(target);
  } catch {
    return null;
  }
}

async function readSafe(target) {
  try {
    return await fsp.readFile(target, "utf8");
  } catch {
    return "";
  }
}

async function listFiles(root, depth = 3) {
  const found = [];
  async function walk(current, remaining) {
    if (remaining < 0) return;
    let entries = [];
    try {
      entries = await fsp.readdir(current, { withFileTypes: true });
    } catch {
      return;
    }
    for (const entry of entries) {
      if (entry.name === ".git" || entry.name.endsWith(".lock")) continue;
      const target = path.join(current, entry.name);
      if (entry.isDirectory()) await walk(target, remaining - 1);
      else found.push(target);
    }
  }
  await walk(root, depth);
  return found;
}

async function inspectMemoryDirectory(root) {
  if (!exists(root)) {
    return {
      available: false,
      entryCount: 0,
      fileCount: 0,
      summaryExists: false,
      lastActivity: null,
      recentFiles: [],
    };
  }
  const files = await listFiles(root);
  let entryCount = 0;
  let lastActivity = null;
  const recentFiles = [];
  for (const file of files) {
    const stats = await statSafe(file);
    if (stats && (!lastActivity || stats.mtime > new Date(lastActivity))) {
      lastActivity = stats.mtime.toISOString();
    }
    if (stats) {
      recentFiles.push({
        name: path.basename(file),
        relativePath: path.relative(root, file).replaceAll("\\", "/"),
        sizeBytes: stats.size,
        modifiedAt: stats.mtime.toISOString(),
      });
    }
    if (file.toLowerCase().endsWith(".md")) {
      const content = await readSafe(file);
      entryCount += (content.match(/^## \[[A-Z]+-\d{8}-\d+\]/gm) ?? []).length;
    }
  }
  return {
    available: true,
    entryCount,
    fileCount: files.length,
    summaryExists: exists(path.join(root, "SUMMARY.md")),
    lastActivity,
    recentFiles: recentFiles
      .sort((a, b) => new Date(b.modifiedAt) - new Date(a.modifiedAt))
      .slice(0, 12),
  };
}

function expandDiscoveryPath(value) {
  const expanded = String(value)
    .replace(/^~(?=[\\/]|$)/, userRoot)
    .replace(/%USERPROFILE%/gi, userRoot)
    .replace(/%OneDrive%/gi, process.env.OneDrive || path.join(userRoot, "OneDrive"));
  return path.resolve(expanded);
}

async function readDiscoveryConfig() {
  const defaults = {
    roots: [
      process.env.OneDrive || path.join(userRoot, "OneDrive"),
      path.join(userRoot, "Documents"),
      path.join(userRoot, "Desktop"),
    ],
    maxDepth: 8,
    maxDirectories: 50000,
    excludeNames: [
      ".git",
      "node_modules",
      "AppData",
      "$RECYCLE.BIN",
      "System Volume Information",
    ],
  };
  const raw = await readSafe(discoveryConfigPath);
  if (!raw) return defaults;
  try {
    const parsed = JSON.parse(raw);
    return {
      roots: Array.isArray(parsed.roots) ? parsed.roots.map(expandDiscoveryPath) : defaults.roots,
      maxDepth: Number.isInteger(parsed.maxDepth) ? parsed.maxDepth : defaults.maxDepth,
      maxDirectories: Number.isInteger(parsed.maxDirectories)
        ? parsed.maxDirectories
        : defaults.maxDirectories,
      excludeNames: Array.isArray(parsed.excludeNames)
        ? parsed.excludeNames.map(String)
        : defaults.excludeNames,
    };
  } catch {
    return defaults;
  }
}

function normalizeRegistryPath(storage, device, rawPath, hostname) {
  if (storage === "onedrive") {
    const oneDriveRoot =
      process.env.OneDrive ||
      process.env.OneDriveConsumer ||
      path.join(userRoot, "OneDrive");
    return path.join(oneDriveRoot, ...rawPath.replaceAll("\\", "/").split("/"));
  }

  const sameDevice = device.toLowerCase() === hostname.toLowerCase();
  const looseSameDevice =
    device.toLowerCase().replace(/-+$/, "") ===
    hostname.toLowerCase().replace(/-+$/, "");
  if (!sameDevice && !looseSameDevice) return null;

  const gitBashMatch = rawPath.match(/^\/([a-zA-Z])\/(.*)$/);
  if (gitBashMatch) {
    return `${gitBashMatch[1].toUpperCase()}:\\${gitBashMatch[2].replaceAll("/", "\\")}`;
  }
  const wslMatch = rawPath.match(/^\/mnt\/([a-zA-Z])\/(.*)$/);
  if (wslMatch) {
    return `${wslMatch[1].toUpperCase()}:\\${wslMatch[2].replaceAll("/", "\\")}`;
  }
  return rawPath;
}

function memoryName(rawPath) {
  const clean = rawPath.replaceAll("\\", "/").replace(/\/\.learnings\/?$/, "");
  const parts = clean.split("/").filter(Boolean);
  return parts.at(-1) || "Root memory";
}

async function readRegistry(hostname) {
  const raw = await readSafe(registryPath);
  const lines = raw.split(/\r?\n/).filter(Boolean);
  const validHeader = lines[0] === "storage\tdevice\tpath";
  const rows = lines.slice(1).map((line, index) => {
    const [storage, device, ...pathParts] = line.split("\t");
    return {
      index,
      storage,
      device,
      registryPath: pathParts.join("\t"),
    };
  }).filter((row) => row.storage && row.device && row.registryPath);

  const seen = new Set();
  let duplicateCount = 0;
  const projects = [];
  for (const row of rows) {
    const signature = `${row.storage}\t${row.device}\t${row.registryPath}`;
    if (seen.has(signature)) duplicateCount += 1;
    seen.add(signature);
    const resolvedPath = normalizeRegistryPath(
      row.storage,
      row.device,
      row.registryPath,
      hostname,
    );
    const info = resolvedPath
      ? await inspectMemoryDirectory(resolvedPath)
      : {
          available: false,
          entryCount: 0,
          fileCount: 0,
          summaryExists: false,
          lastActivity: null,
          recentFiles: [],
        };
    const isCurrentDevice =
      row.storage === "onedrive" ||
      row.device.toLowerCase().replace(/-+$/, "") ===
        hostname.toLowerCase().replace(/-+$/, "");
    projects.push({
      id: `project-${row.index}`,
      name: memoryName(row.registryPath),
      storage: row.storage,
      device: row.device,
      registryPath: row.registryPath,
      resolvedPath,
      isCurrentDevice,
      ...info,
      state: info.available
        ? "healthy"
        : row.registryPath.startsWith("/home/") || !isCurrentDevice
          ? "remote"
          : "warning",
    });
  }
  return { projects, valid: validHeader, duplicateCount };
}

async function readNamespaces(globalRoot) {
  const namespacesRoot = path.join(globalRoot, "namespaces");
  let entries = [];
  try {
    entries = await fsp.readdir(namespacesRoot, { withFileTypes: true });
  } catch {
    return [];
  }
  const namespaces = [];
  for (const entry of entries.filter((item) => item.isDirectory())) {
    const target = path.join(namespacesRoot, entry.name);
    const info = await inspectMemoryDirectory(target);
    namespaces.push({
      name: entry.name,
      path: target,
      ...info,
      state: info.available ? "healthy" : "warning",
    });
  }
  return namespaces.sort((a, b) => a.name.localeCompare(b.name));
}

function samePath(first, second) {
  if (!first || !second) return false;
  return path.resolve(first).replaceAll("/", "\\").toLowerCase() ===
    path.resolve(second).replaceAll("/", "\\").toLowerCase();
}

function pathInside(candidate, root) {
  if (!candidate || !root) return false;
  const relative = path.relative(path.resolve(root), path.resolve(candidate));
  return relative === "" || (!relative.startsWith("..") && !path.isAbsolute(relative));
}

export function describeManagedWorkspaceMemory(
  memoryDir,
  localRoot = managedWorkspaceRoot,
  transportRoot = managedWorkspaceTransportRoot,
) {
  const target = path.resolve(memoryDir);
  for (const candidate of [
    { root: localRoot, peerRoot: transportRoot, transportCopy: false },
    { root: transportRoot, peerRoot: localRoot, transportCopy: true },
  ]) {
    if (!pathInside(target, candidate.root)) continue;
    const relativePath = path.relative(candidate.root, target);
    return {
      managedSync: true,
      transportCopy: candidate.transportCopy,
      relativePath: relativePath.replaceAll("\\", "/"),
      canonicalMemoryDir: path.join(localRoot, relativePath),
      syncPeerPath: path.join(candidate.peerRoot, relativePath),
    };
  }
  return {
    managedSync: false,
    transportCopy: false,
    relativePath: null,
    canonicalMemoryDir: target,
    syncPeerPath: null,
  };
}

async function readSidebarProjects(projects, globalRoot) {
  const statePath = path.join(userRoot, ".codex", ".codex-global-state.json");
  const raw = await readSafe(statePath);
  let state = {};
  try {
    state = JSON.parse(raw);
  } catch {
    return [];
  }
  const localProjects = state["local-projects"] ?? {};
  const namespacesRoot = path.join(globalRoot, "namespaces");
  const results = [];
  const seen = new Set();
  for (const [fallbackId, project] of Object.entries(localProjects)) {
    for (const rawRoot of project.rootPaths ?? []) {
      const root = path.resolve(String(rawRoot));
      const signature = root.toLowerCase();
      if (seen.has(signature)) continue;
      seen.add(signature);
      const rootExists = exists(root);
      const memoryDir = path.join(root, ".learnings");
      const info = await inspectMemoryDirectory(memoryDir);
      const managedWorkspace = describeManagedWorkspaceMemory(memoryDir);
      const globalManaged = pathInside(root, namespacesRoot);
      const registryProject = projects.find((item) =>
        samePath(item.resolvedPath, memoryDir),
      );
      let coverageStatus = "uninitialized";
      if (!rootExists) coverageStatus = "missing-root";
      else if (globalManaged && info.available) coverageStatus = "global-managed";
      else if (info.available && registryProject) coverageStatus = "registered";
      else if (info.available) coverageStatus = "unregistered";
      results.push({
        id: String(project.id ?? fallbackId),
        name: String(project.name ?? path.basename(root)),
        root,
        memoryDir,
        rootExists,
        globalManaged,
        managedSync: managedWorkspace.managedSync,
        syncPeerPath: managedWorkspace.syncPeerPath,
        syncPeerAvailable: managedWorkspace.syncPeerPath
          ? exists(managedWorkspace.syncPeerPath)
          : false,
        coverageStatus,
        registered: Boolean(registryProject),
        ...info,
        state:
          coverageStatus === "registered" || coverageStatus === "global-managed"
            ? "healthy"
            : "warning",
      });
    }
  }
  return results.sort((a, b) => a.name.localeCompare(b.name, "zh-CN"));
}

export async function scanForMemoryDirectories() {
  const startedAt = Date.now();
  const hostname = os.hostname();
  const namespaceRoots = globalRootCandidates
    .map((candidate) => path.join(candidate, "namespaces"))
    .filter(exists);
  const registry = await readRegistry(hostname);
  const config = await readDiscoveryConfig();
  const roots = [...new Set(config.roots.map(expandDiscoveryPath))].filter(exists);
  const excluded = new Set(config.excludeNames.map((item) => item.toLowerCase()));
  const found = [];
  const seen = new Set();
  let scannedDirectories = 0;
  let truncated = false;

  async function walk(current, depth) {
    if (truncated || depth > config.maxDepth) return;
    if (scannedDirectories >= config.maxDirectories) {
      truncated = true;
      return;
    }
    scannedDirectories += 1;
    let entries = [];
    try {
      entries = await fsp.readdir(current, { withFileTypes: true });
    } catch {
      return;
    }
    for (const entry of entries) {
      if (truncated) return;
      if (!entry.isDirectory() || excluded.has(entry.name.toLowerCase())) continue;
      const target = path.join(current, entry.name);
      if (entry.name.toLowerCase() === ".learnings") {
        const discoveredWorkspace = describeManagedWorkspaceMemory(target);
        const memoryDir =
          discoveredWorkspace.transportCopy &&
          exists(discoveredWorkspace.canonicalMemoryDir)
            ? discoveredWorkspace.canonicalMemoryDir
            : target;
        const managedWorkspace = describeManagedWorkspaceMemory(memoryDir);
        const signature = path.resolve(memoryDir).toLowerCase();
        if (seen.has(signature)) continue;
        seen.add(signature);
        const info = await inspectMemoryDirectory(memoryDir);
        const registered = registry.projects.some((item) =>
          samePath(item.resolvedPath, memoryDir),
        );
        const globalManaged = namespaceRoots.some((root) =>
          pathInside(path.dirname(memoryDir), root),
        );
        const transportCopy = managedWorkspace.transportCopy;
        found.push({
          id: `discovered-${found.length}`,
          name: memoryName(memoryDir),
          projectRoot: path.dirname(memoryDir),
          memoryDir,
          registered,
          globalManaged,
          managedSync: managedWorkspace.managedSync,
          transportCopy,
          syncPeerPath: managedWorkspace.syncPeerPath,
          syncPeerAvailable: managedWorkspace.syncPeerPath
            ? exists(managedWorkspace.syncPeerPath)
            : false,
          status: globalManaged
            ? "global-managed"
            : transportCopy
              ? "transport-copy"
            : registered
              ? "registered"
              : "unregistered",
          ...info,
        });
        continue;
      }
      await walk(target, depth + 1);
    }
  }

  for (const root of roots) await walk(root, 0);
  found.sort((a, b) => {
    if (a.status !== b.status) return a.status === "unregistered" ? -1 : 1;
    return a.name.localeCompare(b.name, "zh-CN");
  });
  return {
    generatedAt: new Date().toISOString(),
    configPath: discoveryConfigPath,
    roots,
    maxDepth: config.maxDepth,
    scannedDirectories,
    truncated,
    elapsedMs: Date.now() - startedAt,
    candidates: found,
    unregisteredCount: found.filter((item) => item.status === "unregistered").length,
  };
}

function registryRecordForMemoryDir(memoryDir, hostname) {
  const oneDriveRoot =
    process.env.OneDrive ||
    process.env.OneDriveConsumer ||
    path.join(userRoot, "OneDrive");
  if (pathInside(memoryDir, oneDriveRoot)) {
    const relative = path
      .relative(oneDriveRoot, memoryDir)
      .replaceAll("\\", "/");
    return `onedrive\t-\t${relative}`;
  }
  return `local\t${hostname}\t${path.resolve(memoryDir)}`;
}

function registrationError(message, statusCode = 400) {
  const error = new Error(message);
  error.statusCode = statusCode;
  return error;
}

export function removalSourcesForCandidate(candidate) {
  if (!candidate || candidate.status !== "unregistered" || candidate.registered) {
    throw registrationError("只能移除扫描发现的未注册项目记忆。");
  }
  if (candidate.globalManaged) {
    throw registrationError("全局记忆不能从项目扫描结果中移除。");
  }
  if (candidate.transportCopy) {
    throw registrationError("孤立的同步副本不能直接移除，请先恢复工作副本。");
  }
  const sources = [path.resolve(candidate.memoryDir)];
  if (
    candidate.managedSync &&
    candidate.syncPeerAvailable &&
    candidate.syncPeerPath
  ) {
    const peer = path.resolve(candidate.syncPeerPath);
    if (!samePath(peer, sources[0])) sources.push(peer);
  }
  return sources;
}

function quarantineLabel(candidate) {
  const safeName = String(candidate.name || "memory")
    .replace(/[<>:"/\\|?*\u0000-\u001f]/g, "-")
    .slice(0, 80);
  const timestamp = new Date().toISOString().replace(/[:.]/g, "-");
  return `${timestamp}-${process.pid}-${safeName || "memory"}`;
}

export async function removeDiscoveredMemory(memoryDirInput) {
  const memoryDir = path.resolve(String(memoryDirInput || ""));
  if (path.basename(memoryDir).toLowerCase() !== ".learnings") {
    throw registrationError("只能移除 .learnings 目录。");
  }
  const discovery = await scanForMemoryDirectories();
  const candidate = discovery.candidates.find((item) =>
    samePath(item.memoryDir, memoryDir),
  );
  if (!candidate) throw registrationError("该目录不在当前受控扫描结果中。");

  const sources = removalSourcesForCandidate(candidate);
  for (const source of sources) {
    const stats = await statSafe(source);
    if (!stats?.isDirectory()) {
      throw registrationError(`待移除目录已经不存在：${source}`);
    }
  }

  const quarantineRoot = path.join(
    removalQuarantineRoot,
    quarantineLabel(candidate),
  );
  const moved = [];
  try {
    for (const [index, source] of sources.entries()) {
      const role = index === 0 ? "working-copy" : "transport-copy";
      const destination = path.join(quarantineRoot, role, ".learnings");
      await fsp.mkdir(path.dirname(destination), { recursive: true });
      await fsp.rename(source, destination);
      moved.push({ source, destination });
    }
  } catch {
    let rollbackComplete = true;
    for (const item of [...moved].reverse()) {
      try {
        await fsp.mkdir(path.dirname(item.source), { recursive: true });
        await fsp.rename(item.destination, item.source);
      } catch {
        rollbackComplete = false;
      }
    }
    if (rollbackComplete) {
      await fsp.rm(quarantineRoot, { recursive: true, force: true });
    }
    throw registrationError(
      rollbackComplete
        ? "移除失败，原目录已恢复，没有丢失数据。"
        : `移除未完全成功，请从隔离区检查并恢复：${quarantineRoot}`,
      500,
    );
  }

  return {
    status: "quarantined",
    memoryDir,
    removedPaths: moved.map((item) => item.source),
    quarantinePath: quarantineRoot,
    managedSync: candidate.managedSync,
  };
}

async function withRegistryLock(action) {
  const lockPath = path.join(stateRoot, "project-memory-registry.lock");
  await fsp.mkdir(stateRoot, { recursive: true });
  const deadline = Date.now() + 8000;
  while (true) {
    try {
      await fsp.mkdir(lockPath);
      break;
    } catch (error) {
      if (error?.code !== "EEXIST" || Date.now() >= deadline) {
        throw registrationError("注册表当前正被其他任务使用，请稍后重试。", 409);
      }
      await new Promise((resolve) => setTimeout(resolve, 100));
    }
  }
  try {
    return await action();
  } finally {
    await fsp.rm(lockPath, { recursive: true, force: true });
  }
}

export async function registerDiscoveredMemory(memoryDirInput) {
  const memoryDir = path.resolve(String(memoryDirInput || ""));
  if (path.basename(memoryDir).toLowerCase() !== ".learnings") {
    throw registrationError("只能注册 .learnings 目录。");
  }
  const stats = await statSafe(memoryDir);
  if (!stats?.isDirectory()) throw registrationError("候选记忆目录不存在。");

  const discovery = await scanForMemoryDirectories();
  const candidate = discovery.candidates.find((item) =>
    samePath(item.memoryDir, memoryDir),
  );
  if (!candidate) throw registrationError("该目录不在当前受控扫描结果中。");
  if (candidate.globalManaged) {
    throw registrationError("全局记忆不应加入项目注册表。");
  }
  if (candidate.transportCopy) {
    throw registrationError("同步副本不应加入项目注册表。");
  }

  const hostname = os.hostname();
  const record = registryRecordForMemoryDir(memoryDir, hostname);
  const result = await withRegistryLock(async () => {
    const raw = await readSafe(registryPath);
    const lines = raw.split(/\r?\n/).filter(Boolean);
    const records = lines[0] === "storage\tdevice\tpath" ? lines.slice(1) : lines;
    const unique = [...new Set(records.filter((line) => line.includes("\t")))];
    const alreadyRegistered = unique.includes(record);
    if (!alreadyRegistered) unique.push(record);
    const output = ["storage\tdevice\tpath", ...unique.sort(), ""].join("\n");
    await fsp.mkdir(path.dirname(registryPath), { recursive: true });
    const tempPath = `${registryPath}.tmp-${process.pid}-${Date.now()}`;
    await fsp.writeFile(tempPath, output, "utf8");
    try {
      await fsp.rename(tempPath, registryPath);
    } catch {
      await fsp.copyFile(tempPath, registryPath);
      await fsp.rm(tempPath, { force: true });
    }
    return { alreadyRegistered };
  });

  return {
    status: result.alreadyRegistered ? "already-registered" : "registered",
    memoryDir,
    record,
  };
}

async function jsonFileTime(target) {
  const stats = await statSafe(target);
  if (!stats) return null;
  const raw = await readSafe(target);
  try {
    const json = JSON.parse(raw);
    return (
      json.completed_at ||
      json.finished_at ||
      json.timestamp ||
      json.updated_at ||
      stats.mtime.toISOString()
    );
  } catch {
    return stats.mtime.toISOString();
  }
}

async function runtimeStatus() {
  const hooksRaw = await readSafe(hooksPath);
  let hooks = {};
  try {
    hooks = JSON.parse(hooksRaw).hooks ?? {};
  } catch {
    hooks = {};
  }
  const sessionStart = Array.isArray(hooks.SessionStart) && hooks.SessionStart.length > 0;
  const userPrompt = Array.isArray(hooks.UserPromptSubmit) && hooks.UserPromptSubmit.length > 0;
  const lastSessionStart = await jsonFileTime(
    path.join(stateRoot, "session-start-hook.last-run.json"),
  );
  const lastUserPrompt = await jsonFileTime(
    path.join(stateRoot, "user-prompt-hook.last-run.json"),
  );
  const maintenanceFile = path.join(stateRoot, "interval-maintenance.last-run");
  const maintenanceStats = await statSafe(maintenanceFile);
  let lastRun = maintenanceStats?.mtime.toISOString() ?? null;
  const rawTimestamp = (await readSafe(maintenanceFile)).trim();
  if (/^\d+$/.test(rawTimestamp)) {
    const date = new Date(Number(rawTimestamp) * 1000);
    if (!Number.isNaN(date.getTime())) lastRun = date.toISOString();
  }
  const ageHours = lastRun
    ? Math.round(((Date.now() - new Date(lastRun).getTime()) / 3600000) * 10) / 10
    : null;
  const state = ageHours === null ? "unknown" : ageHours < 72 ? "healthy" : "stale";
  return {
    hooks: { sessionStart, userPrompt, lastSessionStart, lastUserPrompt },
    maintenance: { lastRun, ageHours, state },
  };
}

function mergeActivityProjects(registryProjects, sidebarProjects) {
  const merged = sidebarProjects.filter((item) => !item.globalManaged);
  const seenPaths = new Set(
    merged
      .map((item) => item.memoryDir)
      .filter(Boolean)
      .map((item) => path.resolve(item).toLowerCase()),
  );
  for (const item of registryProjects) {
    const resolvedKey = item.resolvedPath
      ? path.resolve(item.resolvedPath).toLowerCase()
      : "";
    if (resolvedKey && seenPaths.has(resolvedKey)) continue;
    if (resolvedKey) seenPaths.add(resolvedKey);
    merged.push(item);
  }
  return merged;
}

function buildActivity(projects, namespaces, runtime) {
  const activity = [];
  for (const item of [...projects, ...namespaces]) {
    if (!item.lastActivity) continue;
    const isProject = "coverageStatus" in item || "storage" in item;
    const targetPath = isProject
      ? "memoryDir" in item
        ? item.memoryDir
        : item.resolvedPath ?? item.registryPath
      : item.path;
    activity.push({
      title: `${item.name} 有新活动`,
      detail: isProject
        ? `${item.entryCount} 条项目记忆 · ${item.fileCount} 个文件`
        : `${item.entryCount} 条全局记忆 · ${item.fileCount} 个文件`,
      time: item.lastActivity,
      kind: "memory",
      targetId: isProject ? item.id : `namespace-${item.name}`,
      targetPath,
    });
  }
  if (runtime.hooks.lastUserPrompt) {
    activity.push({
      title: "UserPrompt Hook 已运行",
      detail: "已完成本轮召回上下文检查",
      time: runtime.hooks.lastUserPrompt,
      kind: "hook",
      targetView: "runtime",
    });
  }
  if (runtime.maintenance.lastRun) {
    activity.push({
      title: "Maintenance 已运行",
      detail: "维护状态时间戳已更新",
      time: runtime.maintenance.lastRun,
      kind: "maintenance",
      targetView: "runtime",
    });
  }
  return activity
    .sort((a, b) => new Date(b.time) - new Date(a.time))
    .slice(0, 12);
}

export async function collectMemoryStatus() {
  const hostname = os.hostname();
  const globalRoot =
    globalRootCandidates.find((candidate) => exists(path.join(candidate, "namespaces"))) ??
    globalRootCandidates[0];
  const registry = await readRegistry(hostname);
  const namespaces = await readNamespaces(globalRoot);
  const sidebarProjects = await readSidebarProjects(registry.projects, globalRoot);
  const runtime = await runtimeStatus();
  const availableProjects = registry.projects.filter((item) => item.available).length;
  const remoteProjects = registry.projects.filter((item) => item.state === "remote").length;
  const entries = [...registry.projects, ...namespaces].reduce(
    (sum, item) => sum + item.entryCount,
    0,
  );
  const files = [...registry.projects, ...namespaces].reduce(
    (sum, item) => sum + item.fileCount,
    0,
  );
  const issues = [];
  if (!registry.valid) issues.push("项目注册表表头或格式异常。");
  if (registry.duplicateCount) issues.push(`注册表存在 ${registry.duplicateCount} 个重复项。`);
  const unavailableCurrent = registry.projects.filter(
    (item) => item.state === "warning",
  ).length;
  if (unavailableCurrent) issues.push(`${unavailableCurrent} 个当前设备目录无法访问。`);
  if (!runtime.hooks.sessionStart || !runtime.hooks.userPrompt) {
    issues.push("Recall Hooks 未完整启用。");
  }
  if (runtime.maintenance.state === "stale") {
    issues.push(`维护任务已 ${Math.floor(runtime.maintenance.ageHours / 24)} 天未更新。`);
  }
  const uncoveredSidebar = sidebarProjects.filter(
    (item) =>
      item.coverageStatus !== "registered" &&
      item.coverageStatus !== "global-managed",
  );
  if (uncoveredSidebar.length) {
    issues.push(`${uncoveredSidebar.length} 个侧边栏项目尚未完成 Memory 覆盖。`);
  }
  const penalty =
    (!registry.valid ? 25 : 0) +
    registry.duplicateCount * 5 +
    unavailableCurrent * 8 +
    (!runtime.hooks.sessionStart ? 10 : 0) +
    (!runtime.hooks.userPrompt ? 10 : 0) +
    (runtime.maintenance.state === "stale" ? 12 : 0) +
    (runtime.maintenance.state === "unknown" ? 5 : 0) +
    uncoveredSidebar.length * 8;
  const score = Math.max(0, Math.min(100, 100 - penalty));

  return {
    generatedAt: new Date().toISOString(),
    device: { hostname, platform: `${os.platform()} ${os.release()}` },
    roots: { registry: registryPath, global: globalRoot, project: projectMemoryRoot },
    stats: {
      registeredProjects: registry.projects.length,
      availableProjects,
      remoteProjects,
      namespaces: namespaces.length,
      entries,
      files,
      sidebarProjects: sidebarProjects.length,
      coveredSidebarProjects: sidebarProjects.length - uncoveredSidebar.length,
    },
    projects: registry.projects,
    sidebarProjects,
    namespaces,
    activity: buildActivity(
      mergeActivityProjects(registry.projects, sidebarProjects),
      namespaces,
      runtime,
    ),
    health: {
      score,
      level: score >= 90 ? "healthy" : score >= 70 ? "attention" : "warning",
      issues,
    },
    runtime: {
      ...runtime,
      registry: { valid: registry.valid, duplicateCount: registry.duplicateCount },
    },
  };
}

export async function readMemoryFileContent(memoryRootInput, relativePathInput) {
  const memoryRoot = path.resolve(String(memoryRootInput ?? ""));
  const relativePath = String(relativePathInput ?? "").trim();
  if (
    !relativePath ||
    relativePath.includes("\0") ||
    path.isAbsolute(relativePath)
  ) {
    throw registrationError("文件路径无效。");
  }

  const status = await collectMemoryStatus();
  const allowedRoots = [
    ...status.projects.map((item) => item.resolvedPath),
    ...status.sidebarProjects.map((item) => item.memoryDir),
    ...status.namespaces.map((item) => item.path),
  ].filter(Boolean);
  if (!allowedRoots.some((candidate) => samePath(candidate, memoryRoot))) {
    throw registrationError("该目录不在当前记忆目录白名单中。", 403);
  }

  const target = path.resolve(memoryRoot, relativePath);
  if (samePath(target, memoryRoot) || !pathInside(target, memoryRoot)) {
    throw registrationError("文件路径超出记忆目录。", 403);
  }
  if (!previewableTextExtensions.has(path.extname(target).toLowerCase())) {
    throw registrationError("当前仅支持查看常见文本与 Markdown 文件。", 415);
  }

  const [rootRealPath, targetRealPath] = await Promise.all([
    fsp.realpath(memoryRoot).catch(() => null),
    fsp.realpath(target).catch(() => null),
  ]);
  if (!rootRealPath || !targetRealPath || !pathInside(targetRealPath, rootRealPath)) {
    throw registrationError("文件不存在或真实路径超出记忆目录。", 403);
  }
  const stats = await statSafe(targetRealPath);
  if (!stats?.isFile()) throw registrationError("目标不是可读取的文件。");

  const bytesToRead = Math.min(stats.size, maxFilePreviewBytes);
  const handle = await fsp.open(targetRealPath, "r");
  let content = "";
  try {
    const buffer = Buffer.alloc(bytesToRead);
    const { bytesRead } = await handle.read(buffer, 0, bytesToRead, 0);
    content = buffer.subarray(0, bytesRead).toString("utf8");
  } finally {
    await handle.close();
  }

  return {
    name: path.basename(targetRealPath),
    relativePath: path.relative(rootRealPath, targetRealPath).replaceAll("\\", "/"),
    sizeBytes: stats.size,
    modifiedAt: stats.mtime.toISOString(),
    content,
    truncated: stats.size > maxFilePreviewBytes,
    maxBytes: maxFilePreviewBytes,
  };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const result = await collectMemoryStatus();
  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
}
