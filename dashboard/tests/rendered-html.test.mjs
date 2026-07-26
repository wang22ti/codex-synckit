import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import {
  collectMemoryStatus,
  describeManagedWorkspaceMemory,
  readMemoryFileContent,
  removalSourcesForCandidate,
  scanForMemoryDirectories,
} from "../scripts/memory-status.mjs";

async function render() {
  const workerUrl = new URL("../dist/server/index.js", import.meta.url);
  workerUrl.searchParams.set("test", `${process.pid}-${Date.now()}`);
  const { default: worker } = await import(workerUrl.href);

  return worker.fetch(
    new Request("http://localhost/", {
      headers: { accept: "text/html" },
    }),
    {
      ASSETS: {
        fetch: async () => new Response("Not found", { status: 404 }),
      },
    },
    {
      waitUntil() {},
      passThroughOnException() {},
    },
  );
}

test("server-renders the Memory Observatory loading shell", async () => {
  const response = await render();
  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type") ?? "", /^text\/html\b/i);

  const html = await response.text();
  assert.match(html, /<title>Memory Observatory<\/title>/i);
  assert.match(html, /正在读取本地 Memory 状态/);
  assert.doesNotMatch(html, /codex-preview|react-loading-skeleton/);

  const clientSource = await readFile(
    new URL("../app/memory-dashboard.tsx", import.meta.url),
    "utf8",
  );
  assert.match(clientSource, /你的记忆系统/);
  assert.match(clientSource, /系统概览/);
  assert.match(clientSource, /记忆目录/);
  assert.match(clientSource, /最近修改的文件/);
  assert.match(clientSource, /openMemoryDetail/);
  assert.match(clientSource, /删除记忆/);
  assert.match(clientSource, /移入本机隔离区/);
  assert.match(clientSource, /const registeredProjects = data\.projects/);
  assert.match(clientSource, /\.filter\(\(item\) => !item\.globalManaged\)/);
  assert.match(
    clientSource,
    /return \[\.\.\.sidebarProjects, \.\.\.registeredProjects, \.\.\.namespaces\]/,
  );
  assert.match(clientSource, /const sortedMemories = useMemo/);
  assert.match(clientSource, /changeSort\("activity"\)|sortHeader\("activity"/);
  assert.match(clientSource, /aria-sort=/);
  assert.match(clientSource, /\/api\/file-content/);
  assert.match(clientSource, /openFilePreview/);
  assert.match(clientSource, /<pre className="file-content">/);
});

test("status collector returns metadata without memory body content", async () => {
  const status = await collectMemoryStatus();
  assert.equal(typeof status.generatedAt, "string");
  assert.equal(Array.isArray(status.projects), true);
  assert.equal(Array.isArray(status.namespaces), true);
  assert.equal(typeof status.runtime.registry.valid, "boolean");
  assert.equal(status.stats.registeredProjects, status.projects.length);
  assert.ok(status.health.score >= 0 && status.health.score <= 100);

  for (const item of [
    ...status.projects,
    ...status.sidebarProjects,
    ...status.namespaces,
  ]) {
    assert.equal("content" in item, false);
    assert.equal("summary" in item, false);
    assert.equal("details" in item, false);
    assert.equal(Array.isArray(item.recentFiles), true);
    for (const file of item.recentFiles) {
      assert.deepEqual(
        Object.keys(file).sort(),
        ["modifiedAt", "name", "relativePath", "sizeBytes"].sort(),
      );
    }
  }

  const memoryActivities = status.activity.filter((item) => item.kind === "memory");
  assert.ok(memoryActivities.every((item) => item.targetId && item.targetPath));
});

test("file preview reads an allowlisted text file and rejects traversal", async () => {
  const status = await collectMemoryStatus();
  const source = [
    ...status.sidebarProjects.map((item) => ({
      root: item.memoryDir,
      files: item.recentFiles,
    })),
    ...status.namespaces.map((item) => ({
      root: item.path,
      files: item.recentFiles,
    })),
  ].find((item) =>
    item.files.some((file) =>
      /\.(md|txt|json|jsonl|ya?ml|toml|tsv|csv|log)$/i.test(file.relativePath),
    ),
  );
  assert.ok(source, "expected at least one previewable memory file");
  const file = source.files.find((item) =>
    /\.(md|txt|json|jsonl|ya?ml|toml|tsv|csv|log)$/i.test(item.relativePath),
  );
  const preview = await readMemoryFileContent(source.root, file.relativePath);
  assert.equal(typeof preview.content, "string");
  assert.equal(preview.relativePath, file.relativePath);
  assert.ok(preview.content.length <= preview.maxBytes);

  await assert.rejects(
    readMemoryFileContent(source.root, "../outside.md"),
    /超出记忆目录/,
  );
});

test("manual discovery is bounded and returns metadata-only candidates", async () => {
  const result = await scanForMemoryDirectories();
  assert.equal(Array.isArray(result.roots), true);
  assert.equal(Array.isArray(result.candidates), true);
  assert.equal(typeof result.scannedDirectories, "number");
  assert.equal(typeof result.truncated, "boolean");
  assert.ok(result.maxDepth >= 0);

  for (const item of result.candidates) {
    assert.equal(item.memoryDir.endsWith(".learnings"), true);
    assert.equal("content" in item, false);
    assert.equal("details" in item, false);
  }
});

test("managed Documents Codex memory and CodexProjects transport share one identity", () => {
  const localRoot = "C:\\Users\\tester\\Documents\\Codex";
  const transportRoot = "C:\\Users\\tester\\OneDrive\\CodexKit\\CodexProjects";
  const relative = "2026-07-20\\new-chat\\.learnings";
  const local = describeManagedWorkspaceMemory(
    `${localRoot}\\${relative}`,
    localRoot,
    transportRoot,
  );
  const transport = describeManagedWorkspaceMemory(
    `${transportRoot}\\${relative}`,
    localRoot,
    transportRoot,
  );

  assert.equal(local.managedSync, true);
  assert.equal(local.transportCopy, false);
  assert.equal(transport.managedSync, true);
  assert.equal(transport.transportCopy, true);
  assert.equal(local.relativePath, transport.relativePath);
  assert.equal(local.canonicalMemoryDir, transport.canonicalMemoryDir);
  assert.equal(local.syncPeerPath, `${transportRoot}\\${relative}`);
});

test("removal policy only accepts unregistered project memories", () => {
  const localMemory = "C:\\Users\\tester\\Documents\\Codex\\task\\.learnings";
  const peerMemory =
    "C:\\Users\\tester\\OneDrive\\CodexKit\\CodexProjects\\task\\.learnings";
  const candidate = {
    name: "task",
    memoryDir: localMemory,
    status: "unregistered",
    registered: false,
    globalManaged: false,
    transportCopy: false,
    managedSync: true,
    syncPeerAvailable: true,
    syncPeerPath: peerMemory,
  };

  assert.deepEqual(removalSourcesForCandidate(candidate), [
    localMemory,
    peerMemory,
  ]);
  assert.throws(
    () => removalSourcesForCandidate({ ...candidate, status: "registered" }),
    /只能移除扫描发现的未注册项目记忆/,
  );
  assert.throws(
    () =>
      removalSourcesForCandidate({
        ...candidate,
        managedSync: false,
        syncPeerAvailable: false,
        syncPeerPath: null,
        globalManaged: true,
      }),
    /全局记忆不能/,
  );
  assert.throws(
    () =>
      removalSourcesForCandidate({
        ...candidate,
        managedSync: true,
        syncPeerAvailable: false,
        syncPeerPath: null,
        transportCopy: true,
      }),
    /同步副本不能直接移除/,
  );
});
