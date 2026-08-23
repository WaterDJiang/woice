import { createMcpServer } from "../Connectors/McpWoice/src/index.mjs";

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

const server = createMcpServer();
const initialize = await server.handle({
  jsonrpc: "2.0",
  id: 1,
  method: "initialize",
  params: { protocolVersion: "2025-06-18" },
});
assert(initialize?.result?.protocolVersion, "MCP initialize 未协商版本");
await server.handle({ jsonrpc: "2.0", method: "notifications/initialized" });

const tools = await server.handle({
  jsonrpc: "2.0",
  id: 2,
  method: "tools/list",
});
const toolNames = tools?.result?.tools?.map((tool) => tool.name) ?? [];
for (const name of [
  "woice_status",
  "woice_list_recordings",
  "woice_read_material",
  "woice_search_materials",
  "woice_read_material_page",
]) {
  assert(toolNames.includes(name), "MCP 缺少只读工具：" + name);
}

async function callTool(id, name, args = {}) {
  const response = await server.handle({
    jsonrpc: "2.0",
    id,
    method: "tools/call",
    params: { name, arguments: args },
  });
  assert(!response?.error, "MCP 工具调用失败：" + name);
  assert(response?.result?.isError !== true, "Woice 工具返回错误：" + name);
  return response.result.structuredContent;
}

const status = await callTool(3, "woice_status");
const listing = await callTool(4, "woice_list_recordings");
const recordingIDs = String(listing.recording_ids ?? "")
  .split(",")
  .map((value) => value.trim())
  .filter(Boolean);
assert(status && typeof status.recording_count === "string", "真实 Woice status 缺少计数");
assert(recordingIDs.length > 0, "真实入站 Smoke 需要至少一条已保存素材");

const recordingID = recordingIDs[0];
const material = await callTool(5, "woice_read_material", { recording_id: recordingID });
assert(material?.recording_id === recordingID, "素材详情未返回请求的 recording_id");
const page = await callTool(6, "woice_read_material_page", {
  recording_id: recordingID,
  field: "transcript",
  offset: 0,
  limit: 64,
});
assert(page?.recording_id === recordingID, "素材分页未返回请求的 recording_id");
assert(typeof page?.text === "string", "素材分页未返回文本字段");

// Deliberately report only metadata, never the user's transcript or file names.
console.log(
  "real inbound passed: " +
    toolNames.length +
    " MCP tools, " +
    recordingIDs.length +
    " recordings, " +
    Buffer.byteLength(page.text, "utf8") +
    " page bytes"
);
