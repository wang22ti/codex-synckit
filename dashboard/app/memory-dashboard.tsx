"use client";

import { useCallback, useEffect, useMemo, useState } from "react";

type MemoryFile = {
  name: string;
  relativePath: string;
  sizeBytes: number;
  modifiedAt: string;
};

type FilePreview = MemoryFile & {
  content: string;
  truncated: boolean;
  maxBytes: number;
};

type ProjectMemory = {
  id: string;
  name: string;
  storage: "local" | "onedrive";
  device: string;
  registryPath: string;
  resolvedPath: string | null;
  available: boolean;
  isCurrentDevice: boolean;
  entryCount: number;
  fileCount: number;
  summaryExists: boolean;
  lastActivity: string | null;
  recentFiles: MemoryFile[];
  state: "healthy" | "remote" | "warning";
};

type NamespaceMemory = {
  name: string;
  path: string;
  available: boolean;
  entryCount: number;
  fileCount: number;
  summaryExists: boolean;
  lastActivity: string | null;
  recentFiles: MemoryFile[];
  state: "healthy" | "warning";
};

type SidebarProject = {
  id: string;
  name: string;
  root: string;
  memoryDir: string;
  rootExists: boolean;
  globalManaged: boolean;
  managedSync: boolean;
  syncPeerPath: string | null;
  syncPeerAvailable: boolean;
  coverageStatus:
    | "registered"
    | "global-managed"
    | "unregistered"
    | "uninitialized"
    | "missing-root";
  registered: boolean;
  available: boolean;
  entryCount: number;
  fileCount: number;
  summaryExists: boolean;
  lastActivity: string | null;
  recentFiles: MemoryFile[];
  state: "healthy" | "warning";
};

type DiscoveredMemory = {
  id: string;
  name: string;
  projectRoot: string;
  memoryDir: string;
  registered: boolean;
  globalManaged: boolean;
  managedSync: boolean;
  status: "registered" | "global-managed" | "transport-copy" | "unregistered";
  transportCopy: boolean;
  syncPeerPath: string | null;
  syncPeerAvailable: boolean;
  available: boolean;
  entryCount: number;
  fileCount: number;
  summaryExists: boolean;
  lastActivity: string | null;
  recentFiles: MemoryFile[];
};

type ScanResult = {
  generatedAt: string;
  configPath: string;
  roots: string[];
  maxDepth: number;
  scannedDirectories: number;
  truncated: boolean;
  elapsedMs: number;
  candidates: DiscoveredMemory[];
  unregisteredCount: number;
};

type Activity = {
  title: string;
  detail: string;
  time: string;
  kind: string;
  targetId?: string;
  targetPath?: string;
  targetView?: "runtime";
};

type DashboardView = "overview" | "memories" | "runtime" | "detail";
type SortKey = "name" | "entries" | "activity" | "status";
type SortDirection = "asc" | "desc";

type StatusData = {
  generatedAt: string;
  device: { hostname: string; platform: string };
  roots: { registry: string; global: string; project: string };
  stats: {
    registeredProjects: number;
    availableProjects: number;
    remoteProjects: number;
    namespaces: number;
    entries: number;
    files: number;
    sidebarProjects: number;
    coveredSidebarProjects: number;
  };
  projects: ProjectMemory[];
  sidebarProjects: SidebarProject[];
  namespaces: NamespaceMemory[];
  activity: Activity[];
  health: {
    score: number;
    level: "healthy" | "attention" | "warning";
    issues: string[];
  };
  runtime: {
    hooks: {
      sessionStart: boolean;
      userPrompt: boolean;
      lastSessionStart: string | null;
      lastUserPrompt: string | null;
    };
    maintenance: {
      lastRun: string | null;
      ageHours: number | null;
      state: "healthy" | "stale" | "unknown";
    };
    registry: { valid: boolean; duplicateCount: number };
  };
};

const API_URL = "http://127.0.0.1:4174/api/status";
const SCAN_API_URL = "http://127.0.0.1:4174/api/scan";
const REGISTER_API_URL = "http://127.0.0.1:4174/api/register";
const REMOVE_API_URL = "http://127.0.0.1:4174/api/remove";
const FILE_CONTENT_API_URL = "http://127.0.0.1:4174/api/file-content";

function normalizeStatus(payload: Partial<StatusData>): StatusData {
  const projects = Array.isArray(payload.projects)
    ? payload.projects.map((item) => ({
        ...item,
        recentFiles: Array.isArray(item.recentFiles) ? item.recentFiles : [],
      }))
    : [];
  const sidebarProjects = Array.isArray(payload.sidebarProjects)
    ? payload.sidebarProjects.map((item) => ({
        ...item,
        recentFiles: Array.isArray(item.recentFiles) ? item.recentFiles : [],
      }))
    : projects.map((item) => ({
        id: item.id,
        name: item.name,
        root: item.resolvedPath?.replace(/[\\/]\.learnings$/, "") ?? item.registryPath,
        memoryDir: item.resolvedPath ?? item.registryPath,
        rootExists: item.available,
        globalManaged: false,
        managedSync: false,
        syncPeerPath: null,
        syncPeerAvailable: false,
        coverageStatus: item.available ? ("registered" as const) : ("unregistered" as const),
        registered: true,
        available: item.available,
        entryCount: item.entryCount,
        fileCount: item.fileCount,
        summaryExists: item.summaryExists,
        lastActivity: item.lastActivity,
        recentFiles: item.recentFiles,
        state: item.available ? ("healthy" as const) : ("warning" as const),
      }));
  const namespaces = Array.isArray(payload.namespaces)
    ? payload.namespaces.map((item) => ({
        ...item,
        recentFiles: Array.isArray(item.recentFiles) ? item.recentFiles : [],
      }))
    : [];
  const activity = Array.isArray(payload.activity) ? payload.activity : [];
  const stats = payload.stats ?? ({} as StatusData["stats"]);
  const coveredSidebarProjects =
    stats.coveredSidebarProjects ??
    sidebarProjects.filter((item) =>
      ["registered", "global-managed"].includes(item.coverageStatus),
    ).length;

  return {
    generatedAt: payload.generatedAt ?? new Date().toISOString(),
    device: payload.device ?? { hostname: "unknown", platform: "unknown" },
    roots: payload.roots ?? { registry: "", global: "", project: "" },
    stats: {
      registeredProjects: stats.registeredProjects ?? projects.length,
      availableProjects:
        stats.availableProjects ?? projects.filter((item) => item.available).length,
      remoteProjects: stats.remoteProjects ?? 0,
      namespaces: stats.namespaces ?? namespaces.length,
      entries: stats.entries ?? 0,
      files: stats.files ?? 0,
      sidebarProjects: stats.sidebarProjects ?? sidebarProjects.length,
      coveredSidebarProjects,
    },
    projects,
    sidebarProjects,
    namespaces,
    activity,
    health: payload.health ?? { score: 0, level: "warning", issues: [] },
    runtime:
      payload.runtime ??
      ({
        hooks: {
          sessionStart: false,
          userPrompt: false,
          lastSessionStart: null,
          lastUserPrompt: null,
        },
        maintenance: { lastRun: null, ageHours: null, state: "unknown" },
        registry: { valid: false, duplicateCount: 0 },
      } satisfies StatusData["runtime"]),
  };
}

function relativeTime(value: string | null) {
  if (!value) return "暂无";
  const delta = Date.now() - new Date(value).getTime();
  const minutes = Math.max(0, Math.floor(delta / 60000));
  if (minutes < 1) return "刚刚";
  if (minutes < 60) return `${minutes} 分钟前`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours} 小时前`;
  const days = Math.floor(hours / 24);
  return `${days} 天前`;
}

function formatBytes(value: number) {
  if (value < 1024) return `${value} B`;
  if (value < 1024 * 1024) return `${(value / 1024).toFixed(1)} KB`;
  return `${(value / 1024 / 1024).toFixed(1)} MB`;
}

function shortPath(path: string | null) {
  if (!path) return "当前设备不可解析";
  const chunks = path.replaceAll("\\", "/").split("/");
  return chunks.length > 5 ? `…/${chunks.slice(-4).join("/")}` : path;
}

function memoryPathKey(value: string | null) {
  if (!value) return "";
  return value
    .replaceAll("/", "\\")
    .replace(/\\+$/, "")
    .toLowerCase();
}

function stateLabel(state: string) {
  if (state === "healthy") return "可访问";
  if (state === "remote") return "其他环境";
  return "需检查";
}

function coverageLabel(state: SidebarProject["coverageStatus"]) {
  if (state === "registered") return "已注册";
  if (state === "global-managed") return "全局管理";
  if (state === "unregistered") return "待注册";
  if (state === "missing-root") return "根目录缺失";
  return "待初始化";
}

function statusSortRank(item: {
  state: string;
  coverageStatus?: SidebarProject["coverageStatus"];
}) {
  if (item.coverageStatus === "registered") return 0;
  if (item.coverageStatus === "global-managed") return 1;
  if (item.state === "healthy") return 2;
  if (item.state === "remote") return 3;
  if (item.coverageStatus === "unregistered") return 4;
  if (item.coverageStatus === "uninitialized") return 5;
  if (item.coverageStatus === "missing-root") return 6;
  return 7;
}

function Metric({
  value,
  label,
  delta,
}: {
  value: number | string;
  label: string;
  delta?: string;
}) {
  return (
    <div className="metric">
      <div className="metric-top">
        <div className="metric-value">{value}</div>
        {delta ? <div className="metric-delta">{delta}</div> : null}
      </div>
      <div className="metric-label">{label}</div>
    </div>
  );
}

export function MemoryDashboard() {
  const [data, setData] = useState<StatusData | null>(null);
  const [error, setError] = useState("");
  const [refreshing, setRefreshing] = useState(false);
  const [view, setView] = useState<DashboardView>("overview");
  const [selectedMemoryId, setSelectedMemoryId] = useState<string | null>(null);
  const [query, setQuery] = useState("");
  const [filter, setFilter] = useState<"all" | "available" | "remote">("all");
  const [sort, setSort] = useState<{
    key: SortKey;
    direction: SortDirection;
  }>({ key: "activity", direction: "desc" });
  const [scanResult, setScanResult] = useState<ScanResult | null>(null);
  const [scanning, setScanning] = useState(false);
  const [scanError, setScanError] = useState("");
  const [registeringPath, setRegisteringPath] = useState("");
  const [removingPath, setRemovingPath] = useState("");
  const [registrationNotice, setRegistrationNotice] = useState("");
  const [filePreview, setFilePreview] = useState<FilePreview | null>(null);
  const [fileLoading, setFileLoading] = useState(false);
  const [fileError, setFileError] = useState("");

  const load = useCallback(async () => {
    setRefreshing(true);
    try {
      const response = await fetch(`${API_URL}?t=${Date.now()}`, {
        cache: "no-store",
      });
      if (!response.ok) throw new Error(`状态接口返回 ${response.status}`);
      setData(normalizeStatus((await response.json()) as Partial<StatusData>));
      setError("");
    } catch (reason) {
      setError(
        reason instanceof Error
          ? reason.message
          : "无法连接本地状态服务",
      );
    } finally {
      setRefreshing(false);
    }
  }, []);

  const scanMemories = useCallback(async () => {
    setScanning(true);
    setScanError("");
    try {
      const response = await fetch(`${SCAN_API_URL}?t=${Date.now()}`, {
        method: "POST",
        cache: "no-store",
      });
      if (!response.ok) throw new Error(`扫描接口返回 ${response.status}`);
      const result = (await response.json()) as ScanResult;
      setScanResult({
        ...result,
        roots: Array.isArray(result.roots) ? result.roots : [],
        candidates: Array.isArray(result.candidates) ? result.candidates : [],
      });
    } catch (reason) {
      setScanError(reason instanceof Error ? reason.message : "扫描失败");
    } finally {
      setScanning(false);
    }
  }, []);

  const registerMemory = useCallback(
    async (item: DiscoveredMemory) => {
      setRegisteringPath(item.memoryDir);
      setRegistrationNotice("");
      try {
        const response = await fetch(REGISTER_API_URL, {
          method: "POST",
          cache: "no-store",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ memoryDir: item.memoryDir }),
        });
        const result = (await response.json()) as {
          status?: string;
          error?: string;
        };
        if (!response.ok) {
          throw new Error(result.error || `注册接口返回 ${response.status}`);
        }
        setScanResult((current) =>
          current
            ? {
                ...current,
                unregisteredCount: Math.max(0, current.unregisteredCount - 1),
                candidates: current.candidates.map((candidate) =>
                  candidate.memoryDir === item.memoryDir
                    ? { ...candidate, registered: true, status: "registered" }
                    : candidate,
                ),
              }
            : current,
        );
        setRegistrationNotice(`${item.name} 已加入项目记忆注册表。`);
        await load();
      } catch (reason) {
        setRegistrationNotice(
          reason instanceof Error ? reason.message : "加入注册表失败",
        );
      } finally {
        setRegisteringPath("");
      }
    },
    [load],
  );

  const removeMemory = useCallback(
    async (item: DiscoveredMemory) => {
      const syncWarning =
        item.managedSync && item.syncPeerAvailable
          ? "\n\n这是 CodexKit 托管项目，工作副本和同步副本会一起移入隔离区。"
          : "";
      const confirmed = window.confirm(
        `确定移除“${item.name}”的 .learnings 吗？\n\n项目本身不会删除，记忆目录会移入本机隔离区，可按返回路径恢复。${syncWarning}`,
      );
      if (!confirmed) return;

      setRemovingPath(item.memoryDir);
      setRegistrationNotice("");
      try {
        const response = await fetch(REMOVE_API_URL, {
          method: "POST",
          cache: "no-store",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ memoryDir: item.memoryDir }),
        });
        const result = (await response.json()) as {
          status?: string;
          quarantinePath?: string;
          error?: string;
        };
        if (!response.ok) {
          throw new Error(result.error || `移除接口返回 ${response.status}`);
        }
        setScanResult((current) =>
          current
            ? {
                ...current,
                unregisteredCount: Math.max(0, current.unregisteredCount - 1),
                candidates: current.candidates.filter(
                  (candidate) => candidate.memoryDir !== item.memoryDir,
                ),
              }
            : current,
        );
        setRegistrationNotice(
          `${item.name} 的记忆已移入隔离区，可从这里恢复：${result.quarantinePath}`,
        );
        await load();
      } catch (reason) {
        setRegistrationNotice(
          reason instanceof Error ? reason.message : "移除记忆失败",
        );
      } finally {
        setRemovingPath("");
      }
    },
    [load],
  );

  useEffect(() => {
    const initial = window.setTimeout(() => void load(), 0);
    const timer = window.setInterval(() => void load(), 60000);
    return () => {
      window.clearTimeout(initial);
      window.clearInterval(timer);
    };
  }, [load]);

  const allMemories = useMemo(() => {
    if (!data) return [];
    const sidebarProjects = data.sidebarProjects
      .filter((item) => !item.globalManaged)
      .map((item) => ({
        ...item,
        kind: "项目",
        path: item.memoryDir,
        storage: "sidebar" as const,
        device: "",
        registryPath: item.memoryDir,
        resolvedPath: item.memoryDir,
        isCurrentDevice: true,
      }));
    const sidebarPaths = new Set(
      sidebarProjects.map((item) => memoryPathKey(item.memoryDir)),
    );
    const registeredProjects = data.projects
      .filter((item) => {
        const key = memoryPathKey(item.resolvedPath);
        return !key || !sidebarPaths.has(key);
      })
      .map((item) => {
        const memoryDir = item.resolvedPath ?? item.registryPath;
        return {
          ...item,
          kind: "项目",
          path: memoryDir,
          memoryDir,
          root: memoryDir.replace(/[\\/]\\.learnings$/, ""),
          rootExists: item.available,
          globalManaged: false,
          managedSync: false,
          syncPeerPath: null,
          syncPeerAvailable: false,
          coverageStatus: "registered" as const,
          registered: true,
        };
      });
    const namespaces = data.namespaces.map((item) => ({
      ...item,
      id: `namespace-${item.name}`,
      storage: "global" as const,
      device: "全局",
      registryPath: item.path,
      resolvedPath: item.path,
      isCurrentDevice: true,
      kind: "全局",
      managedSync: false,
    }));
    return [...sidebarProjects, ...registeredProjects, ...namespaces];
  }, [data]);

  const filteredMemories = useMemo(() => {
    const needle = query.trim().toLowerCase();
    return allMemories.filter((item) => {
      const queryMatch =
        !needle ||
        item.name.toLowerCase().includes(needle) ||
        item.path.toLowerCase().includes(needle);
      const filterMatch =
        filter === "all" ||
        (filter === "available" && item.available) ||
        (filter === "remote" && !item.available);
      return queryMatch && filterMatch;
    });
  }, [allMemories, query, filter]);

  const sortedMemories = useMemo(() => {
    const direction = sort.direction === "asc" ? 1 : -1;
    return [...filteredMemories].sort((a, b) => {
      let comparison = 0;
      if (sort.key === "name") {
        comparison = a.name.localeCompare(b.name, "zh-CN", {
          numeric: true,
          sensitivity: "base",
        });
      } else if (sort.key === "entries") {
        comparison = a.entryCount - b.entryCount || a.fileCount - b.fileCount;
      } else if (sort.key === "activity") {
        if (!a.lastActivity && !b.lastActivity) comparison = 0;
        else if (!a.lastActivity) return 1;
        else if (!b.lastActivity) return -1;
        else {
          comparison =
            new Date(a.lastActivity).getTime() - new Date(b.lastActivity).getTime();
        }
      } else {
        comparison = statusSortRank(a) - statusSortRank(b);
      }
      if (comparison === 0) {
        return a.name.localeCompare(b.name, "zh-CN", {
          numeric: true,
          sensitivity: "base",
        });
      }
      return comparison * direction;
    });
  }, [filteredMemories, sort]);

  const changeSort = useCallback((key: SortKey) => {
    setSort((current) => {
      if (current.key === key) {
        return {
          key,
          direction: current.direction === "asc" ? "desc" : "asc",
        };
      }
      return {
        key,
        direction: key === "name" || key === "status" ? "asc" : "desc",
      };
    });
  }, []);

  const selectedMemory = useMemo(
    () => allMemories.find((item) => item.id === selectedMemoryId) ?? null,
    [allMemories, selectedMemoryId],
  );

  const openMemoryDetail = useCallback((id: string) => {
    setFilePreview(null);
    setFileError("");
    setSelectedMemoryId(id);
    setView("detail");
  }, []);

  const openActivity = useCallback((item: Activity) => {
    if (item.targetId) {
      setFilePreview(null);
      setFileError("");
      setSelectedMemoryId(item.targetId);
      setView("detail");
      return;
    }
    if (item.targetView === "runtime") setView("runtime");
  }, []);

  const openFilePreview = useCallback(
    async (file: MemoryFile) => {
      if (!selectedMemory) return;
      setFileLoading(true);
      setFileError("");
      try {
        const response = await fetch(FILE_CONTENT_API_URL, {
          method: "POST",
          cache: "no-store",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            memoryRoot: selectedMemory.path,
            relativePath: file.relativePath,
          }),
        });
        const result = (await response.json()) as FilePreview & { error?: string };
        if (!response.ok) {
          throw new Error(result.error || `文件接口返回 ${response.status}`);
        }
        setFilePreview(result);
      } catch (reason) {
        setFilePreview(null);
        setFileError(reason instanceof Error ? reason.message : "无法读取文件");
      } finally {
        setFileLoading(false);
      }
    },
    [selectedMemory],
  );

  const sortHeader = (key: SortKey, label: string) => {
    const active = sort.key === key;
    const ariaSort: "ascending" | "descending" | "none" = active
      ? sort.direction === "asc"
        ? "ascending"
        : "descending"
      : "none";
    return (
      <div role="columnheader" aria-sort={ariaSort}>
        <button
          className={`sort-header ${active ? "active" : ""}`}
          onClick={() => changeSort(key)}
          aria-label={`${label}，当前${
            active ? (sort.direction === "asc" ? "升序" : "降序") : "未排序"
          }，点击切换排序`}
        >
          <span>{label}</span>
          <span className="sort-arrow" aria-hidden="true">
            {active ? (sort.direction === "asc" ? "↑" : "↓") : "↕"}
          </span>
        </button>
      </div>
    );
  };

  if (!data && !error) {
    return (
      <div className="loading">
        <div>
          <div className="loading-mark">◎</div>
          <div className="eyebrow">正在读取本地 Memory 状态</div>
        </div>
      </div>
    );
  }

  if (!data && error) {
    return (
      <div className="error-screen">
        <div className="error-card">
          <div className="loading-mark">!</div>
          <h2>本地状态服务未连接</h2>
          <p>
            {error}。请从 Memory Dashboard 项目运行本地启动命令；服务只监听
            127.0.0.1，不会上传你的记忆数据。
          </p>
          <button className="refresh-button" onClick={() => void load()}>
            重新连接
          </button>
        </div>
      </div>
    );
  }

  if (!data) return null;

  const recent = allMemories
    .filter((item) => item.lastActivity)
    .sort(
      (a, b) =>
        new Date(b.lastActivity ?? 0).getTime() -
        new Date(a.lastActivity ?? 0).getTime(),
    );

  return (
    <div className="app-shell">
      <aside className="sidebar">
        <div className="brand">
          <div className="brand-mark">M</div>
          <div className="brand-copy">
            <div className="brand-name">Memory</div>
            <div className="brand-sub">Observatory</div>
          </div>
        </div>

        <div className="nav-label">Workspace</div>
        <nav className="nav-list" aria-label="主要导航">
          <button
            className={`nav-item ${view === "overview" ? "active" : ""}`}
            onClick={() => setView("overview")}
          >
            <span className="nav-glyph">⌁</span>
            <span className="nav-copy">系统概览</span>
          </button>
          <button
            className={`nav-item ${view === "memories" ? "active" : ""}`}
            onClick={() => setView("memories")}
          >
            <span className="nav-glyph">▤</span>
            <span className="nav-copy">记忆目录</span>
          </button>
          <button
            className={`nav-item ${view === "runtime" ? "active" : ""}`}
            onClick={() => setView("runtime")}
          >
            <span className="nav-glyph">◉</span>
            <span className="nav-copy">运行状态</span>
          </button>
        </nav>

        <div className="sidebar-foot">
          <div className="device-card">
            <div className="device-row">
              <i className="live-dot" />
              <span>本地连接</span>
            </div>
            <div className="device-meta">
              {data.device.hostname}
              <br />
              仅监听 127.0.0.1
            </div>
          </div>
        </div>
      </aside>

      <main className="main">
        <header className="topbar">
          <div className="breadcrumb">
            <span>Memory &amp; Improvement</span>
            <span>›</span>
            <strong>
              {view === "overview"
                ? "系统概览"
                : view === "memories"
                  ? "记忆目录"
                  : view === "runtime"
                    ? "运行状态"
                    : selectedMemory?.name ?? "目录详情"}
            </strong>
          </div>
          <div className="top-actions">
            <span className="updated-at">
              更新于 {new Date(data.generatedAt).toLocaleTimeString("zh-CN")}
            </span>
            <button
              className="refresh-button"
              onClick={() => void load()}
              disabled={refreshing}
              aria-label="刷新状态"
            >
              <span className={refreshing ? "spin" : ""}>↻</span>
              {refreshing ? "读取中" : "刷新"}
            </button>
          </div>
        </header>

        {view === "overview" ? (
          <>
            <section className="hero">
              <div className="hero-grid">
                <div>
                  <div className="eyebrow">Local-first memory intelligence</div>
                  <h1>
                    你的记忆系统，
                    <br />
                    此刻一目了然。
                  </h1>
                  <p className="hero-copy">
                    实时汇总项目记忆、全局命名空间和维护链路。仅在你主动打开文件时
                    从本机读取正文，不向外部服务发送任何 Memory 内容。
                  </p>
                </div>
                <div className="health-orbit" aria-label={`健康分 ${data.health.score}`}>
                  <i className="orbit-node a" />
                  <i className="orbit-node b" />
                  <div className="health-score">
                    <div className="score-number">{data.health.score}</div>
                    <div className="score-label">系统健康分 / 100</div>
                  </div>
                </div>
              </div>
            </section>

            <section className="metric-strip" aria-label="核心指标">
              <Metric
                value={`${data.stats.coveredSidebarProjects}/${data.stats.sidebarProjects}`}
                label="侧边栏项目 Memory 覆盖"
                delta={
                  data.stats.coveredSidebarProjects === data.stats.sidebarProjects
                    ? "全部覆盖"
                    : "仍需处理"
                }
              />
              <Metric value={data.stats.namespaces} label="全局命名空间" />
              <Metric value={data.stats.entries} label="已记录 Memory 条目" />
              <Metric
                value={data.runtime.maintenance.lastRun ? relativeTime(data.runtime.maintenance.lastRun) : "未知"}
                label="最近维护"
              />
            </section>

            <section className="content-grid">
              <div className="panel">
                <div className="panel-head">
                  <div>
                    <div className="section-kicker">Memory map</div>
                    <h2 className="panel-title">最近活跃的记忆目录</h2>
                  </div>
                  <button className="text-button" onClick={() => setView("memories")}>
                    查看全部 →
                  </button>
                </div>
                <div className="directory-list">
                  {recent.slice(0, 6).map((item) => {
                    const itemId =
                      "coverageStatus" in item ? item.id : `namespace-${item.name}`;
                    return (
                      <button
                        className="directory-row directory-link"
                        key={`${item.name}-${item.path}`}
                        onClick={() => openMemoryDetail(itemId)}
                        aria-label={`查看 ${item.name} 的记忆详情`}
                      >
                        <div className={`directory-icon ${"coverageStatus" in item ? "" : "global"}`}>
                          {"coverageStatus" in item ? "P" : "G"}
                        </div>
                        <div>
                          <div className="directory-name">{item.name}</div>
                          <div className="directory-path">
                            {shortPath("memoryDir" in item ? item.memoryDir : item.path)}
                          </div>
                        </div>
                        <div className="row-stat">
                          <strong>{item.entryCount}</strong>
                          <span>条目</span>
                        </div>
                        <span className={`status-pill ${item.state}`}>
                          {"coverageStatus" in item
                            ? coverageLabel(item.coverageStatus)
                            : stateLabel(item.state)}
                        </span>
                      </button>
                    );
                  })}
                </div>
              </div>

              <div className="panel">
                <div className="panel-head">
                  <div>
                    <div className="section-kicker">Pulse</div>
                    <h2 className="panel-title">最近活动</h2>
                  </div>
                </div>
                <div className="timeline">
                  {data.activity.slice(0, 4).map((item, index) => (
                    <button
                      className="timeline-item timeline-link"
                      key={`${item.title}-${index}`}
                      onClick={() => openActivity(item)}
                      aria-label={`${item.title}，查看详情`}
                    >
                      <i className="timeline-dot" />
                      <div>
                        <div className="timeline-title">{item.title}</div>
                        <div className="timeline-detail">{item.detail}</div>
                      </div>
                      <div className="timeline-time">{relativeTime(item.time)}</div>
                    </button>
                  ))}
                </div>
                <div className="alert-card">
                  <div className="alert-top">
                    <div>
                      <div className="alert-count">{data.health.issues.length}</div>
                      <div className="alert-label">需要留意的状态</div>
                    </div>
                    <div className="section-kicker" style={{ color: "rgba(255,255,255,.5)" }}>
                      Health notes
                    </div>
                  </div>
                  <div className="alert-list">
                    {(data.health.issues.length
                      ? data.health.issues
                      : ["没有发现需要处理的问题，当前链路运行正常。"]
                    ).slice(0, 3).map((issue) => (
                      <div className="alert-item" key={issue}>
                        <i className="alert-marker" />
                        <span>{issue}</span>
                      </div>
                    ))}
                  </div>
                </div>
              </div>
            </section>
          </>
        ) : null}

        {view === "memories" ? (
          <>
            <section className="page-title-block">
              <div className="eyebrow">Registry & namespaces</div>
              <h1>记忆目录</h1>
              <p>注册记录、当前设备可达性、规模与最近活动的统一视图。</p>
            </section>
            <div className="toolbar">
              <input
                className="search"
                value={query}
                onChange={(event) => setQuery(event.target.value)}
                placeholder="搜索名称或路径…"
                aria-label="搜索记忆目录"
              />
              {(["all", "available", "remote"] as const).map((key) => (
                <button
                  className={`filter-button ${filter === key ? "active" : ""}`}
                  onClick={() => setFilter(key)}
                  key={key}
                >
                  {key === "all" ? "全部" : key === "available" ? "可访问" : "其他环境"}
                </button>
              ))}
              <button
                className="scan-button"
                onClick={() => void scanMemories()}
                disabled={scanning}
              >
                {scanning ? "正在扫描…" : "扫描未注册记忆"}
              </button>
            </div>
            {scanResult || scanError ? (
              <section className="panel discovery-panel" aria-live="polite">
                <div className="panel-head">
                  <div>
                    <div className="section-kicker">Manual discovery</div>
                    <h2 className="panel-title">
                      {scanError
                        ? "扫描失败"
                        : scanResult?.unregisteredCount
                          ? `发现 ${scanResult.unregisteredCount} 个未注册目录`
                          : "没有发现未注册记忆"}
                    </h2>
                  </div>
                  {scanResult ? (
                    <div className="discovery-summary">
                      扫描 {scanResult.scannedDirectories} 个目录 ·{" "}
                      {(scanResult.elapsedMs / 1000).toFixed(1)} 秒
                      {scanResult.truncated ? " · 已达到扫描上限" : ""}
                    </div>
                  ) : null}
                </div>
                {scanError ? <div className="scan-error">{scanError}</div> : null}
                {registrationNotice ? (
                  <div className="registration-notice">{registrationNotice}</div>
                ) : null}
                {scanResult ? (
                  <>
                    <div className="scan-roots">
                      {scanResult.roots.map((root) => (
                        <span key={root}>{root}</span>
                      ))}
                    </div>
                    <div className="discovery-list">
                      {scanResult.candidates.length ? (
                        scanResult.candidates.map((item) => (
                          <div className="discovery-row" key={item.memoryDir}>
                            <div>
                              <div className="memory-title">{item.name}</div>
                              <div className="memory-path">{item.memoryDir}</div>
                              {item.managedSync ? (
                                <div className="managed-sync-note">
                                  CodexKit 托管同步
                                  {item.syncPeerAvailable ? " · 同步副本已存在" : " · 等待首次同步"}
                                </div>
                              ) : null}
                            </div>
                            <div className="memory-cell">
                              {item.entryCount} 条
                              <span>{item.fileCount} 个文件</span>
                            </div>
                            <div className="discovery-actions">
                              <span
                                className={`status-pill ${
                                  item.status === "unregistered" ? "warning" : "healthy"
                                }`}
                              >
                                {item.status === "unregistered"
                                  ? "未注册"
                                  : item.status === "global-managed"
                                    ? "全局管理"
                                    : item.status === "transport-copy"
                                      ? "同步副本"
                                      : "已注册"}
                              </span>
                              {item.status === "unregistered" ? (
                                <>
                                  <button
                                    className="register-candidate-button"
                                    disabled={Boolean(registeringPath || removingPath)}
                                    onClick={() => void registerMemory(item)}
                                  >
                                    {registeringPath === item.memoryDir
                                      ? "正在加入…"
                                      : "加入注册表"}
                                  </button>
                                  <button
                                    className="remove-candidate-button"
                                    disabled={Boolean(registeringPath || removingPath)}
                                    onClick={() => void removeMemory(item)}
                                  >
                                    {removingPath === item.memoryDir
                                      ? "正在移除…"
                                      : "删除记忆"}
                                  </button>
                                </>
                              ) : null}
                            </div>
                          </div>
                        ))
                      ) : (
                        <div className="empty-discovery">
                          当前扫描根目录中没有找到 `.learnings`。
                        </div>
                      )}
                    </div>
                    <div className="discovery-note">
                      此操作只读，不会自动注册或修改任何项目。扫描范围由{" "}
                      <code>{scanResult.configPath}</code> 控制。
                    </div>
                  </>
                ) : null}
              </section>
            ) : null}
            <section className="panel memory-table">
              <div className="memory-row header" role="row">
                {sortHeader("name", "目录")}
                {sortHeader("entries", "规模")}
                {sortHeader("activity", "最近活动")}
                {sortHeader("status", "状态")}
              </div>
              {sortedMemories.map((item) => (
                <button
                  className="memory-row memory-link"
                  key={item.id}
                  onClick={() => openMemoryDetail(item.id)}
                  aria-label={`查看 ${item.name} 的记忆详情`}
                >
                  <div className="memory-main">
                    <div className="memory-title">
                      {item.name}
                      <span className="mini-tag">{item.kind}</span>
                      {item.managedSync ? (
                        <span className="mini-tag managed">托管同步</span>
                      ) : null}
                    </div>
                    <div className="memory-path">{item.path}</div>
                  </div>
                  <div className="memory-cell">
                    {item.entryCount} 条
                    <span>{item.fileCount} 个文件</span>
                  </div>
                  <div className="memory-cell">
                    {relativeTime(item.lastActivity)}
                    <span>{item.summaryExists ? "含 Summary" : "无 Summary"}</span>
                  </div>
                  <span className={`status-pill ${item.state}`}>
                    {"coverageStatus" in item
                      ? coverageLabel(item.coverageStatus)
                      : stateLabel(item.state)}
                  </span>
                </button>
              ))}
            </section>
          </>
        ) : null}

        {view === "detail" && selectedMemory ? (
          <>
            <section className="detail-heading">
              <button className="back-button" onClick={() => setView("overview")}>
                ← 返回概览
              </button>
              <div className="detail-heading-row">
                <div>
                  <div className="eyebrow">
                    {"coverageStatus" in selectedMemory
                      ? "Project memory"
                      : "Global namespace"}
                  </div>
                  <h1>{selectedMemory.name}</h1>
                  <div className="detail-path">{selectedMemory.path}</div>
                </div>
                <span className={`status-pill ${selectedMemory.state}`}>
                  {"coverageStatus" in selectedMemory
                    ? coverageLabel(selectedMemory.coverageStatus)
                    : stateLabel(selectedMemory.state)}
                </span>
              </div>
            </section>

            <section className="detail-metrics" aria-label="目录详情摘要">
              <Metric value={selectedMemory.entryCount} label="Memory 条目" />
              <Metric value={selectedMemory.fileCount} label="元数据文件" />
              <Metric
                value={selectedMemory.summaryExists ? "已有" : "暂无"}
                label="Summary"
              />
              <Metric
                value={relativeTime(selectedMemory.lastActivity)}
                label="最近活动"
              />
            </section>

            <section className="detail-grid">
              <div className="panel detail-files">
                <div className="panel-head">
                  <div>
                    <div className="section-kicker">File activity</div>
                    <h2 className="panel-title">
                      {filePreview ? filePreview.name : "最近修改的文件"}
                    </h2>
                  </div>
                  <div className="detail-privacy">按需本地读取</div>
                </div>
                {fileLoading ? (
                  <div className="file-reader-state">正在读取本机文件…</div>
                ) : fileError ? (
                  <div className="file-reader-state error">
                    <button
                      className="file-reader-back"
                      onClick={() => setFileError("")}
                    >
                      ← 返回文件列表
                    </button>
                    <p>{fileError}</p>
                  </div>
                ) : filePreview ? (
                  <div className="file-reader">
                    <div className="file-reader-toolbar">
                      <button
                        className="file-reader-back"
                        onClick={() => setFilePreview(null)}
                      >
                        ← 返回文件列表
                      </button>
                      <span>
                        {formatBytes(filePreview.sizeBytes)} ·{" "}
                        {filePreview.relativePath}
                      </span>
                    </div>
                    {filePreview.truncated ? (
                      <div className="file-reader-notice">
                        文件较大，仅展示前 {formatBytes(filePreview.maxBytes)}。
                      </div>
                    ) : null}
                    <pre className="file-content">{filePreview.content}</pre>
                  </div>
                ) : (
                  <div className="file-list">
                    {selectedMemory.recentFiles.length ? (
                    selectedMemory.recentFiles.map((file) => (
                      <button
                        className="file-row file-link"
                        key={file.relativePath}
                        onClick={() => void openFilePreview(file)}
                        aria-label={`查看 ${file.relativePath}`}
                      >
                        <div className="file-mark">
                          {file.name.toLowerCase().endsWith(".md") ? "MD" : "F"}
                        </div>
                        <div className="file-main">
                          <div className="file-name">{file.name}</div>
                          <div className="file-path">{file.relativePath}</div>
                        </div>
                        <div className="file-size">{formatBytes(file.sizeBytes)}</div>
                        <div className="file-time">
                          <strong>{relativeTime(file.modifiedAt)}</strong>
                          <span>
                            {new Date(file.modifiedAt).toLocaleString("zh-CN")}
                          </span>
                        </div>
                      </button>
                    ))
                  ) : (
                    <div className="empty-detail">这个目录暂时没有可展示的文件。</div>
                  )}
                  </div>
                )}
              </div>

              <aside className="panel detail-status">
                <div className="section-kicker">Directory state</div>
                <h2 className="panel-title">目录状态</h2>
                <dl className="detail-list">
                  <div>
                    <dt>类型</dt>
                    <dd>
                      {"coverageStatus" in selectedMemory ? "项目记忆" : "全局命名空间"}
                    </dd>
                  </div>
                  <div>
                    <dt>可访问性</dt>
                    <dd>{selectedMemory.available ? "当前设备可访问" : "当前设备不可访问"}</dd>
                  </div>
                  <div>
                    <dt>Summary</dt>
                    <dd>{selectedMemory.summaryExists ? "已建立" : "尚未建立"}</dd>
                  </div>
                  {"coverageStatus" in selectedMemory ? (
                    <>
                      <div>
                        <dt>注册状态</dt>
                        <dd>{coverageLabel(selectedMemory.coverageStatus)}</dd>
                      </div>
                      <div>
                        <dt>同步方式</dt>
                        <dd>
                          {selectedMemory.managedSync
                            ? selectedMemory.syncPeerAvailable
                              ? "CodexKit 托管同步"
                              : "托管目录，等待同步副本"
                            : "目录自身的存储位置"}
                        </dd>
                      </div>
                    </>
                  ) : null}
                </dl>
                {"coverageStatus" in selectedMemory &&
                selectedMemory.managedSync &&
                selectedMemory.syncPeerPath ? (
                  <div className="sync-peer">
                    <span>同步副本</span>
                    {selectedMemory.syncPeerPath}
                  </div>
                ) : null}
                <div className="detail-safety">
                  默认只汇总元数据；只有点击文件时才从白名单目录按需读取文本正文。
                </div>
              </aside>
            </section>
          </>
        ) : null}

        {view === "runtime" ? (
          <>
            <section className="page-title-block">
              <div className="eyebrow">Runtime & maintenance</div>
              <h1>运行状态</h1>
              <p>检查召回 Hook、维护节奏和注册表完整性。</p>
            </section>
            <section className="health-grid">
              <div className="panel health-card">
                <div className="health-card-top">
                  <div className="health-symbol">C</div>
                  <span className="health-state">
                    {data.stats.coveredSidebarProjects === data.stats.sidebarProjects
                      ? "全部覆盖"
                      : "需补齐"}
                  </span>
                </div>
                <h3>Sidebar Coverage</h3>
                <p>侧边栏项目根目录、Memory 初始化与注册表的一致性。</p>
                <div className="health-detail">
                  {data.stats.coveredSidebarProjects} / {data.stats.sidebarProjects} 个项目
                  <br />
                  来源 · Codex local-projects
                </div>
              </div>
              <div className="panel health-card">
                <div className="health-card-top">
                  <div className="health-symbol">H</div>
                  <span className="health-state">
                    {data.runtime.hooks.sessionStart && data.runtime.hooks.userPrompt
                      ? "已启用"
                      : "需检查"}
                  </span>
                </div>
                <h3>Recall Hooks</h3>
                <p>会话启动与用户输入时的 Memory 召回提示链路。</p>
                <div className="health-detail">
                  SessionStart · {relativeTime(data.runtime.hooks.lastSessionStart)}
                  <br />
                  UserPrompt · {relativeTime(data.runtime.hooks.lastUserPrompt)}
                </div>
              </div>
              <div className="panel health-card">
                <div className="health-card-top">
                  <div className="health-symbol">M</div>
                  <span className="health-state">
                    {data.runtime.maintenance.state === "healthy" ? "正常" : "需关注"}
                  </span>
                </div>
                <h3>Maintenance</h3>
                <p>整理、写回、索引与 Git 维护的最近运行状态。</p>
                <div className="health-detail">
                  最近运行 · {relativeTime(data.runtime.maintenance.lastRun)}
                  <br />
                  状态 · {data.runtime.maintenance.state}
                </div>
              </div>
              <div className="panel health-card">
                <div className="health-card-top">
                  <div className="health-symbol">R</div>
                  <span className="health-state">
                    {data.runtime.registry.valid ? "有效" : "需修复"}
                  </span>
                </div>
                <h3>Project Registry</h3>
                <p>跨设备项目记忆注册表的格式与重复项检查。</p>
                <div className="health-detail">
                  {data.stats.registeredProjects} 条记录
                  <br />
                  {data.runtime.registry.duplicateCount} 个重复项
                </div>
              </div>
            </section>

            <section className="panel" style={{ marginTop: 14 }}>
              <div className="panel-head">
                <div>
                  <div className="section-kicker">Paths</div>
                  <h2 className="panel-title">当前数据源</h2>
                </div>
              </div>
              <div className="directory-list">
                {[
                  ["项目注册表", data.roots.registry],
                  ["全局 Memory", data.roots.global],
                  ["当前项目 Memory", data.roots.project],
                ].map(([name, path]) => (
                  <div className="directory-row" key={name}>
                    <div className="directory-icon">↳</div>
                    <div>
                      <div className="directory-name">{name}</div>
                      <div className="directory-path">{path}</div>
                    </div>
                    <div className="row-stat">
                      <strong>只读</strong>
                      <span>数据接口</span>
                    </div>
                    <span className="status-pill healthy">已连接</span>
                  </div>
                ))}
              </div>
            </section>
          </>
        ) : null}
      </main>
    </div>
  );
}
