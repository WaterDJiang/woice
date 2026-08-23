import test from "node:test";
import assert from "node:assert/strict";
import { createMcpServer, MCP_PROTOCOL_VERSIONS } from "../src/index.mjs";

test("MCP bridge negotiates lifecycle and exposes only read-only tools", async () => {
  const calls = [];
  const server = createMcpServer({
    call: async (request) => {
      calls.push(request);
      return { state: "准备就绪" };
    },
  });
  const initialized = await server.handle({
    jsonrpc: "2.0",
    id: 1,
    method: "initialize",
    params: { protocolVersion: MCP_PROTOCOL_VERSIONS[0] },
  });
  assert.equal(initialized.result.protocolVersion, MCP_PROTOCOL_VERSIONS[0]);
  assert.deepEqual(await server.handle({ jsonrpc: "2.0", method: "notifications/initialized" }), null);
  const listed = await server.handle({ jsonrpc: "2.0", id: 2, method: "tools/list" });
  assert.deepEqual(listed.result.tools.map((tool) => tool.name), [
    "woice_status",
    "woice_list_recordings",
    "woice_read_material",
    "woice_search_materials",
    "woice_read_material_page",
  ]);
  const result = await server.handle({
    jsonrpc: "2.0",
    id: 3,
    method: "tools/call",
    params: { name: "woice_search_materials", arguments: { query: "会议", limit: 5 } },
  });
  assert.equal(result.result.isError, false);
  assert.deepEqual(calls[0], {
    method: "woice.search_materials",
    parameters: { query: "会议", offset: "0", limit: "5" },
  });
});

test("MCP bridge rejects calls before initialization and unsafe parameters", async () => {
  const server = createMcpServer({ call: async () => ({}) });
  const before = await server.handle({ jsonrpc: "2.0", id: 1, method: "tools/list" });
  assert.equal(before.error.code, -32002);
  await server.handle({
    jsonrpc: "2.0",
    id: 2,
    method: "initialize",
    params: { protocolVersion: "unsupported" },
  });
  await server.handle({ jsonrpc: "2.0", method: "notifications/initialized" });
  const unsafe = await server.handle({
    jsonrpc: "2.0",
    id: 3,
    method: "tools/call",
    params: { name: "woice_read_material_page", arguments: { recording_id: "x", limit: 99_999 } },
  });
  assert.equal(unsafe.result.isError, true);
  const unknown = await server.handle({
    jsonrpc: "2.0",
    id: 4,
    method: "tools/call",
    params: { name: "woice_record_start", arguments: {} },
  });
  assert.equal(unknown.error.code, -32602);
});
