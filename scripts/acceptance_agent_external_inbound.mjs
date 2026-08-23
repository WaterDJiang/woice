#!/usr/bin/env node

/**
 * Safe external-Agent inbound Smoke.
 *
 * This deliberately serves synthetic material from a temporary Unix Socket.
 * It never points Codex/Claude at the user's Woice database or recordings.
 */
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawn } from "node:child_process";
import net from "node:net";

const ROOT = join(tmpdir(), "woice-external-agent-inbound-");
const MCP_BRIDGE = join(
  process.cwd(),
  "Connectors",
  "McpWoice",
  "src",
  "index.mjs",
);
const RECORDING_ID = "fixture-recording-001";
const SYNTHETIC_PAGE = "合成 Woice 验收素材：只用于 MCP 入站协议验证。";
const REQUIRED_METHODS = [
  "woice.status",
  "woice.list_recordings",
  "woice.search_materials",
  "woice.read_material_page",
];

function responseFor(request) {
  const base = { protocolVersion: "1", requestID: request.requestID };
  switch (request.method) {
    case "woice.status":
      return { ...base, result: { state: "fixture", is_recording: "false", recording_count: "1" } };
    case "woice.list_recordings":
      return { ...base, result: { recordings: [{ recording_id: RECORDING_ID, status: "ready" }] } };
    case "woice.search_materials":
      return {
        ...base,
        result: {
          query: request.parameters?.query ?? "",
          offset: request.parameters?.offset ?? "0",
          limit: request.parameters?.limit ?? "20",
          total: "1",
          items: [{ recording_id: RECORDING_ID, status: "ready" }],
        },
      };
    case "woice.read_material_page":
      return {
        ...base,
        result: {
          recording_id: RECORDING_ID,
          field: "transcript",
          offset: request.parameters?.offset ?? "0",
          limit: request.parameters?.limit ?? "16384",
          text: SYNTHETIC_PAGE,
          next_offset: null,
        },
      };
    case "woice.read_material":
      return {
        ...base,
        result: { recording_id: RECORDING_ID, status: "ready", artifact_count: "1" },
      };
    default:
      return { ...base, error: { code: "METHOD_NOT_FOUND", message: "fixture method not found" } };
  }
}

function startFixtureSocket(socketPath) {
  const calls = [];
  const server = net.createServer((socket) => {
    let buffer = "";
    socket.setEncoding("utf8");
    socket.on("data", (chunk) => {
      buffer += chunk;
      let newline;
      while ((newline = buffer.indexOf("\n")) >= 0) {
        const line = buffer.slice(0, newline);
        buffer = buffer.slice(newline + 1);
        if (!line.trim()) continue;
        const request = JSON.parse(line);
        calls.push(request.method);
        socket.write(`${JSON.stringify(responseFor(request))}\n`);
      }
    });
  });
  return new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(socketPath, () => resolve({ server, calls }));
  });
}

function run(command, args, env, label) {
  return new Promise((resolve) => {
    const child = spawn(command, args, { env, stdio: ["ignore", "pipe", "pipe"] });
    let stdoutBytes = 0;
    let stderrBytes = 0;
    let stdoutPreview = "";
    let stderrPreview = "";
    const timeout = setTimeout(() => child.kill("SIGTERM"), 180_000);
    child.stdout.on("data", (chunk) => {
      stdoutBytes += chunk.byteLength;
      if (stdoutPreview.length < 16_384) stdoutPreview += chunk.toString("utf8").slice(0, 16_384);
    });
    child.stderr.on("data", (chunk) => {
      stderrBytes += chunk.byteLength;
      if (stderrPreview.length < 2_048) stderrPreview += chunk.toString("utf8").slice(0, 2_048);
    });
    child.on("error", (error) => {
      clearTimeout(timeout);
      resolve({ label, code: null, error: error.message, stdoutBytes, stderrBytes, stdoutPreview, stderrPreview });
    });
    child.on("close", (code, signal) => {
      clearTimeout(timeout);
      resolve({ label, code, signal, stdoutBytes, stderrBytes, stdoutPreview, stderrPreview });
    });
  });
}

function codexArgs(socketPath) {
  return [
    "exec", "--ephemeral", "--ignore-user-config", "--skip-git-repo-check",
    "--sandbox", "read-only", "--color", "never", "--json",
    "-c", 'mcp_servers.woice.command="node"',
    "-c", `mcp_servers.woice.args=["${MCP_BRIDGE}"]`,
    "-c", `mcp_servers.woice.env.WOICE_SOCKET_PATH="${socketPath}"`,
    "Use only the woice_status, woice_list_recordings, woice_search_materials, and woice_read_material_page tools from the Woice MCP server. Do not use shell, file, or other built-in tools. Use the synthetic fixture recording. Do not include transcript text, file names, or IDs in your final response; report only whether the four tool calls succeeded.",
  ];
}

function claudeArgs(socketPath) {
  const config = JSON.stringify({
    mcpServers: {
      woice: {
        type: "stdio",
        command: "node",
        args: [MCP_BRIDGE],
        env: { WOICE_SOCKET_PATH: socketPath },
      },
    },
  });
  return [
    "--no-session-persistence", "--strict-mcp-config", "--mcp-config", config,
    "--permission-mode", "dontAsk", "--allowedTools",
    "mcp__woice__woice_status,mcp__woice__woice_list_recordings,mcp__woice__woice_search_materials,mcp__woice__woice_read_material_page",
    "--output-format", "text", "-p",
    "Use the woice_status, woice_list_recordings, woice_search_materials, and woice_read_material_page tools from the Woice MCP server. Use the synthetic fixture recording. Do not include transcript text, file names, or IDs in your final response; report only whether the four tool calls succeeded.",
  ];
}

async function main() {
  if (process.env.WOICE_RUN_EXTERNAL_AGENT_INBOUND !== "1") {
    console.log("external inbound skipped: set WOICE_RUN_EXTERNAL_AGENT_INBOUND=1 to run synthetic Agent/MCP Smoke");
    return;
  }

  const root = await mkdtemp(ROOT);
  try {
    const env = { ...process.env };
    const results = [];
    const callsByAgent = new Map();
    const requestedIDs = process.env.WOICE_EXTERNAL_AGENT_IDS?.split(",").filter(Boolean)
      ?? ["codex-cli", "claude-cli"];
    for (const agentID of requestedIDs) {
      const socketPath = join(root, `${agentID}.sock`);
      const fixture = await startFixtureSocket(socketPath);
      const agentEnv = { ...env, WOICE_SOCKET_PATH: socketPath };
      const result = agentID === "codex-cli"
        ? await run("/opt/homebrew/bin/codex", codexArgs(socketPath), agentEnv, agentID)
        : agentID === "claude-cli"
          ? await run("/opt/homebrew/bin/claude", claudeArgs(socketPath), agentEnv, agentID)
          : { label: agentID, code: null, error: "unsupported fixture agent" };
      results.push(result);
      callsByAgent.set(agentID, fixture.calls);
      fixture.server.close();
    }
    const missingByAgent = Object.fromEntries(
      requestedIDs.map((agentID) => [
        agentID,
        REQUIRED_METHODS.filter((method) => !callsByAgent.get(agentID)?.includes(method)),
      ]),
    );
    const missing = Object.entries(missingByAgent)
      .filter(([, methods]) => methods.length > 0)
      .map(([agentID, methods]) => `${agentID}:${methods.join(",")}`);
    const failed = results.filter((result) => result.code !== 0);
    if (results.length !== requestedIDs.length || failed.length > 0 || missing.length > 0) {
      const diagnostics = results.map(({ label, code, stdoutBytes, stderrBytes, stdoutPreview, stderrPreview }) => ({
        label,
        code,
        stdoutBytes,
        stderrBytes,
        stdoutTypes: stdoutPreview.split("\n").filter(Boolean).map((line) => {
          try {
            const value = JSON.parse(line);
            return [value.type, value.item?.type, value.item?.name].filter(Boolean).join(":") || "json";
          } catch { return "text"; }
        }).slice(0, 20),
        stderrTail: stderrPreview.slice(-500).replace(/\s+/g, " "),
      }));
      throw new Error(
        `external inbound failed: results=${JSON.stringify(diagnostics)} missing=${missing.join(",")}`,
      );
    }
    console.log(
      `external inbound passed: ${results.length} real Agents, ${REQUIRED_METHODS.length} MCP methods per Agent, synthetic fixture only`,
    );
  } finally {
    await rm(root, { recursive: true, force: true });
  }
}

main().catch((error) => {
  process.stderr.write(`external inbound failed: ${error instanceof Error ? error.message : String(error)}\n`);
  process.exitCode = 1;
});
