import http from "node:http";
import { spawn } from "node:child_process";
import {
  collectMemoryStatus,
  readMemoryFileContent,
  registerDiscoveredMemory,
  removeDiscoveredMemory,
  scanForMemoryDirectories,
} from "./memory-status.mjs";

const mode = process.argv[2] === "start" ? "start" : "dev";
const API_HOST = "127.0.0.1";
const API_PORT = 4174;
const allowedOrigins = new Set([
  "http://127.0.0.1:3000",
  "http://localhost:3000",
  "http://127.0.0.1:5173",
  "http://localhost:5173",
]);

async function readJsonBody(request) {
  const chunks = [];
  let size = 0;
  for await (const chunk of request) {
    size += chunk.length;
    if (size > 16384) throw new Error("Request body is too large");
    chunks.push(chunk);
  }
  return JSON.parse(Buffer.concat(chunks).toString("utf8") || "{}");
}

const api = http.createServer(async (request, response) => {
  const origin = request.headers.origin ?? "";
  if (request.method === "OPTIONS") {
    response.writeHead(204, {
      "Access-Control-Allow-Origin": allowedOrigins.has(origin) ? origin : "http://127.0.0.1:3000",
      "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type",
      Vary: "Origin",
    });
    response.end();
    return;
  }
  const isStatusRequest =
    request.method === "GET" && request.url?.startsWith("/api/status");
  const isScanRequest =
    request.method === "POST" && request.url?.startsWith("/api/scan");
  const isRegisterRequest =
    request.method === "POST" && request.url?.startsWith("/api/register");
  const isRemoveRequest =
    request.method === "POST" && request.url?.startsWith("/api/remove");
  const isFileContentRequest =
    request.method === "POST" && request.url?.startsWith("/api/file-content");
  if (
    !isStatusRequest &&
    !isScanRequest &&
    !isRegisterRequest &&
    !isRemoveRequest &&
    !isFileContentRequest
  ) {
    response.writeHead(404, { "Content-Type": "application/json; charset=utf-8" });
    response.end(JSON.stringify({ error: "Not found" }));
    return;
  }
  try {
    let result;
    if (isRegisterRequest || isRemoveRequest || isFileContentRequest) {
      const body = await readJsonBody(request);
      if (isRegisterRequest) {
        result = await registerDiscoveredMemory(body.memoryDir);
      } else if (isRemoveRequest) {
        result = await removeDiscoveredMemory(body.memoryDir);
      } else {
        result = await readMemoryFileContent(body.memoryRoot, body.relativePath);
      }
    } else if (isScanRequest) {
      result = await scanForMemoryDirectories();
    } else {
      result = await collectMemoryStatus();
    }
    response.writeHead(200, {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
      "Access-Control-Allow-Origin": allowedOrigins.has(origin) ? origin : "http://127.0.0.1:3000",
      Vary: "Origin",
    });
    response.end(JSON.stringify(result));
  } catch (error) {
    response.writeHead(Number(error?.statusCode) || 500, {
      "Content-Type": "application/json; charset=utf-8",
      "Access-Control-Allow-Origin": allowedOrigins.has(origin) ? origin : "http://127.0.0.1:3000",
      Vary: "Origin",
    });
    response.end(
      JSON.stringify({
        error: error instanceof Error ? error.message : "Unable to collect status",
      }),
    );
  }
});

api.listen(API_PORT, API_HOST, () => {
  process.stdout.write(`Memory status API: http://${API_HOST}:${API_PORT}/api/status\n`);
});

const isWindows = process.platform === "win32";
const command = isWindows ? process.env.ComSpec || "cmd.exe" : "npm";
const args = isWindows
  ? ["/d", "/s", "/c", `npx vinext ${mode} --host 127.0.0.1`]
  : ["exec", "--", "vinext", mode, "--host", "127.0.0.1"];
const frontend = spawn(command, args, {
  stdio: "inherit",
  windowsHide: true,
  env: {
    ...process.env,
    WRANGLER_LOG_PATH: ".wrangler/logs",
  },
});

function shutdown(signal) {
  api.close();
  frontend.kill(signal);
}

process.on("SIGINT", () => shutdown("SIGINT"));
process.on("SIGTERM", () => shutdown("SIGTERM"));
frontend.on("exit", (code) => {
  api.close(() => process.exit(code ?? 0));
});
