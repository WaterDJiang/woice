#!/usr/bin/env node
import { createInterface } from "node:readline";
import { pathToFileURL } from "node:url";
import { callWoice } from "../../PiWoice/src/client.mjs";

export const MCP_PROTOCOL_VERSIONS = ["2025-06-18", "2024-11-05"];

const emptySchema = { type: "object", properties: {}, additionalProperties: false };
const recordingSchema = {
  type: "object",
  properties: { recording_id: { type: "string" } },
  required: ["recording_id"],
  additionalProperties: false,
};
const searchSchema = {
  type: "object",
  properties: {
    query: { type: "string" },
    offset: { type: "integer", minimum: 0 },
    limit: { type: "integer", minimum: 1, maximum: 100 },
  },
  additionalProperties: false,
};
const pageSchema = {
  type: "object",
  properties: {
    recording_id: { type: "string" },
    field: { type: "string", enum: ["transcript"] },
    offset: { type: "integer", minimum: 0 },
    limit: { type: "integer", minimum: 1, maximum: 16384 },
  },
  required: ["recording_id"],
  additionalProperties: false,
};

const TOOLS = [
  {
    name: "woice_status",
    description: "读取 Woice 当前录音和处理状态；只读，不启动录音。",
    inputSchema: emptySchema,
  },
  {
    name: "woice_list_recordings",
    description: "列出 Woice 中可用的录音 ID；只读。",
    inputSchema: emptySchema,
  },
  {
    name: "woice_read_material",
    description: "读取一条已保存素材的状态、原文、时间戳和音轨引用；只读。",
    inputSchema: recordingSchema,
  },
  {
    name: "woice_search_materials",
    description: "按本地素材内容搜索 Woice；不会触发转写、外发或录音。",
    inputSchema: searchSchema,
  },
  {
    name: "woice_read_material_page",
    description: "按 Unicode 字符分页读取一条素材的规范化原文；只读。",
    inputSchema: pageSchema,
  },
];

const TOOL_METHODS = {
  woice_status: "woice.status",
  woice_list_recordings: "woice.list_recordings",
  woice_read_material: "woice.read_material",
  woice_search_materials: "woice.search_materials",
  woice_read_material_page: "woice.read_material_page",
};

function jsonRpcError(id, code, message) {
  return { jsonrpc: "2.0", id, error: { code, message } };
}

function textResult(value) {
  const text = JSON.stringify(value, null, 2);
  return { content: [{ type: "text", text }], structuredContent: value, isError: false };
}

function errorResult(error) {
  const message = error instanceof Error ? error.message : String(error);
  return {
    content: [{ type: "text", text: `Woice 请求失败：${message}` }],
    isError: true,
  };
}

function isObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function stringParameter(parameters, key, required = false) {
  const value = parameters[key];
  if (value === undefined && !required) return undefined;
  if (typeof value !== "string" || value.length > 4_096) {
    throw new Error(`参数 ${key} 必须是有限长度文本`);
  }
  return value;
}

function integerParameter(parameters, key, fallback, maximum) {
  const value = parameters[key] ?? fallback;
  if (!Number.isInteger(value) || value < 0 || value > maximum) {
    throw new Error(`参数 ${key} 超过安全范围`);
  }
  return String(value);
}

function parametersForTool(name, raw) {
  const parameters = raw === undefined ? {} : raw;
  if (!isObject(parameters)) throw new Error("tools/call arguments 必须是对象");
  switch (name) {
    case "woice_status":
    case "woice_list_recordings":
      if (Object.keys(parameters).length > 0) throw new Error("该只读工具不接受参数");
      return {};
    case "woice_read_material":
      return { recording_id: stringParameter(parameters, "recording_id", true) };
    case "woice_search_materials":
      return {
        query: stringParameter(parameters, "query") ?? "",
        offset: integerParameter(parameters, "offset", 0, 100_000),
        limit: integerParameter(parameters, "limit", 20, 100),
      };
    case "woice_read_material_page":
      return {
        recording_id: stringParameter(parameters, "recording_id", true),
        field: stringParameter(parameters, "field") ?? "transcript",
        offset: integerParameter(parameters, "offset", 0, 10_000_000),
        limit: integerParameter(parameters, "limit", 16_384, 16_384),
      };
    default:
      throw new Error("未知 Woice 工具");
  }
}

export function createMcpServer({ call = callWoice } = {}) {
  let initialized = false;
  let negotiatedVersion = null;

  return {
    async handle(message) {
      if (!isObject(message) || message.jsonrpc !== "2.0" || typeof message.method !== "string") {
        return jsonRpcError(message?.id ?? null, -32600, "无效的 JSON-RPC 请求");
      }
      const id = message.id ?? null;
      const isNotification = message.id === undefined;
      switch (message.method) {
        case "initialize": {
          const requested = message.params?.protocolVersion;
          negotiatedVersion = MCP_PROTOCOL_VERSIONS.includes(requested)
            ? requested
            : MCP_PROTOCOL_VERSIONS[0];
          return {
            jsonrpc: "2.0",
            id,
            result: {
              protocolVersion: negotiatedVersion,
              capabilities: { tools: { listChanged: false } },
              serverInfo: { name: "woice-mcp", version: "0.1.0" },
              instructions: "Woice 只提供授权范围内的语音素材读取，不提供录音或任意文件访问。",
            },
          };
        }
        case "notifications/initialized":
          initialized = true;
          return null;
        case "ping":
          return isNotification ? null : { jsonrpc: "2.0", id, result: {} };
        case "tools/list":
          if (!initialized) return jsonRpcError(id, -32002, "MCP 尚未完成 initialized 通知");
          return { jsonrpc: "2.0", id, result: { tools: TOOLS } };
        case "tools/call": {
          if (!initialized) return jsonRpcError(id, -32002, "MCP 尚未完成 initialized 通知");
          const name = message.params?.name;
          if (typeof name !== "string" || !TOOL_METHODS[name]) {
            return jsonRpcError(id, -32602, "未知或无效的 Woice 工具");
          }
          try {
            const parameters = parametersForTool(name, message.params?.arguments);
            const result = await call({ method: TOOL_METHODS[name], parameters });
            return { jsonrpc: "2.0", id, result: textResult(result) };
          } catch (error) {
            return { jsonrpc: "2.0", id, result: errorResult(error) };
          }
        }
        default:
          return jsonRpcError(id, -32601, `不支持的 MCP 方法：${message.method}`);
      }
    },
  };
}

async function runStdio() {
  const server = createMcpServer();
  const input = createInterface({ input: process.stdin, crlfDelay: Infinity });
  for await (const line of input) {
    if (!line.trim()) continue;
    let message;
    try {
      message = JSON.parse(line);
    } catch {
      process.stdout.write(`${JSON.stringify(jsonRpcError(null, -32700, "无效的 JSON"))}\n`);
      continue;
    }
    const response = await server.handle(message);
    if (response) process.stdout.write(`${JSON.stringify(response)}\n`);
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  runStdio().catch((error) => {
    process.stderr.write(`woice-mcp: ${error instanceof Error ? error.message : String(error)}\n`);
    process.exitCode = 1;
  });
}
