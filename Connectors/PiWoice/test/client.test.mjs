import { strict as assert } from "node:assert";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import net from "node:net";
import test from "node:test";
import { callWoice } from "../src/client.mjs";

async function listen(server, socketPath) {
  await new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(socketPath, resolve);
  });
}

test("PI client sends the versioned Woice JSON Lines envelope", async (t) => {
  const root = await mkdtemp(join(tmpdir(), "woice-pi-client-"));
  const socketPath = join(root, "woice.sock");
  const server = net.createServer((socket) => {
    let input = "";
    socket.setEncoding("utf8");
    socket.on("data", (chunk) => {
      input += chunk;
      if (!input.includes("\n")) return;
      const request = JSON.parse(input.trim());
      assert.equal(request.protocolVersion, "1");
      assert.equal(request.method, "woice.status");
      assert.deepEqual(request.parameters, {});
      socket.end(JSON.stringify({
        protocolVersion: "1",
        requestID: request.requestID,
        result: { state: "准备就绪" },
      }) + "\n");
    });
  });
  t.after(async () => {
    await new Promise((resolve) => server.close(resolve));
    await rm(root, { recursive: true, force: true });
  });
  await listen(server, socketPath);

  const result = await callWoice({ method: "woice.status", socketPath });
  assert.deepEqual(result, { state: "准备就绪" });
});

test("PI client preserves structured Woice errors without exposing credentials", async (t) => {
  const root = await mkdtemp(join(tmpdir(), "woice-pi-error-"));
  const socketPath = join(root, "woice.sock");
  const server = net.createServer((socket) => {
    socket.once("data", () => {
      socket.end(JSON.stringify({
        protocolVersion: "1",
        requestID: "error",
        error: { code: "ROUTER_ERROR", message: "录音还没有原文" },
      }) + "\n");
    });
  });
  t.after(async () => {
    await new Promise((resolve) => server.close(resolve));
    await rm(root, { recursive: true, force: true });
  });
  await listen(server, socketPath);

  await assert.rejects(
    callWoice({ method: "woice.read_transcript", socketPath, parameters: { recording_id: "x" } }),
    (error) => error.code === "ROUTER_ERROR" && error.message === "录音还没有原文"
  );
});

test("PI package manifest and adapter keep the Woice boundary explicit", async () => {
  const packageJSON = JSON.parse(
    await readFile(new URL("../package.json", import.meta.url), "utf8")
  );
  const extension = await readFile(new URL("../src/index.ts", import.meta.url), "utf8");
  assert.equal(packageJSON.pi.extensions[0], "./src/index.ts");
  assert.equal(packageJSON.peerDependencies["@earendil-works/pi-coding-agent"], "0.83.0");
  for (const method of [
    "woice_status",
    "woice_list_recordings",
    "woice_read_transcript",
    "woice_read_material",
    "woice_search_materials",
    "woice_read_material_page",
    "woice_request_markdown",
  ]) {
    assert.match(extension, new RegExp(`name: "${method}"`));
  }
  assert.doesNotMatch(extension, /from ["'](?:sqlite3|keychain|avfoundation)/i);
  assert.doesNotMatch(extension, /process\.env\.(?:API_KEY|APIKEY)/i);
});

test("PI 0.83 host surface loads the extension and receives all registrations", async () => {
  const { default: register } = await import("../src/index.ts");
  const registrations = [];
  register({
    registerTool: (tool) => registrations.push(["tool", tool.name]),
    registerCommand: (name) => registrations.push(["command", name]),
    registerShortcut: (name) => registrations.push(["shortcut", name]),
  });
  assert.deepEqual(registrations, [
    ["tool", "woice_status"],
    ["tool", "woice_list_recordings"],
    ["tool", "woice_read_transcript"],
    ["tool", "woice_read_material"],
    ["tool", "woice_search_materials"],
    ["tool", "woice_read_material_page"],
    ["tool", "woice_request_markdown"],
    ["command", "woice"],
    ["shortcut", "ctrl+shift+w"],
  ]);
});

test("PI read_material tool only requests the versioned read-only RPC", async (t) => {
  const root = await mkdtemp(join(tmpdir(), "woice-pi-material-"));
  const socketPath = join(root, "woice.sock");
  const server = net.createServer((socket) => {
    let input = "";
    socket.setEncoding("utf8");
    socket.on("data", (chunk) => {
      input += chunk;
      if (!input.includes("\n")) return;
      const request = JSON.parse(input.trim());
      assert.equal(request.method, "woice.read_material");
      assert.deepEqual(request.parameters, { recording_id: "recording-1" });
      socket.end(JSON.stringify({
        protocolVersion: "1",
        requestID: request.requestID,
        result: { artifact_id: "recording-1", status: "material_ready" },
      }) + "\n");
    });
  });
  t.after(async () => {
    await new Promise((resolve) => server.close(resolve));
    await rm(root, { recursive: true, force: true });
  });
  await listen(server, socketPath);
  const previousSocketPath = process.env.WOICE_SOCKET_PATH;
  process.env.WOICE_SOCKET_PATH = socketPath;
  t.after(() => {
    if (previousSocketPath === undefined) delete process.env.WOICE_SOCKET_PATH;
    else process.env.WOICE_SOCKET_PATH = previousSocketPath;
  });

  const registrations = [];
  const { default: register } = await import("../src/index.ts");
  register({
    registerTool: (tool) => registrations.push(tool),
    registerCommand: () => {},
    registerShortcut: () => {},
  });
  const tool = registrations.find(({ name }) => name === "woice_read_material");
  assert.ok(tool);
  const result = await tool.execute("call-1", { recording_id: "recording-1" });
  assert.deepEqual(result.details, { artifact_id: "recording-1", status: "material_ready" });
});

test("PI search and page tools only request read-only versioned RPC", async (t) => {
  const root = await mkdtemp(join(tmpdir(), "woice-pi-search-page-"));
  const socketPath = join(root, "woice.sock");
  const requests = [];
  const server = net.createServer((socket) => {
    let input = "";
    socket.setEncoding("utf8");
    socket.on("data", (chunk) => {
      input += chunk;
      if (!input.includes("\n")) return;
      const request = JSON.parse(input.trim());
      requests.push(request);
      socket.end(JSON.stringify({
        protocolVersion: "1",
        requestID: request.requestID,
        result: { next_offset: "3", text: "页" },
      }) + "\n");
    });
  });
  t.after(async () => {
    await new Promise((resolve) => server.close(resolve));
    await rm(root, { recursive: true, force: true });
  });
  await listen(server, socketPath);

  const registrations = [];
  const { default: register } = await import("../src/index.ts");
  register({
    registerTool: (tool) => registrations.push(tool),
    registerCommand: () => {},
    registerShortcut: () => {},
  });
  const search = registrations.find(({ name }) => name === "woice_search_materials");
  const page = registrations.find(({ name }) => name === "woice_read_material_page");
  assert.ok(search);
  assert.ok(page);

  const previousSocketPath = process.env.WOICE_SOCKET_PATH;
  process.env.WOICE_SOCKET_PATH = socketPath;
  t.after(() => {
    if (previousSocketPath === undefined) delete process.env.WOICE_SOCKET_PATH;
    else process.env.WOICE_SOCKET_PATH = previousSocketPath;
  });
  await search.execute("search-call", { query: "会议", offset: 0, limit: 20 });
  await page.execute("page-call", { recording_id: "recording-1", offset: 3, limit: 10 });
  assert.equal(requests[0].method, "woice.search_materials");
  assert.deepEqual(requests[0].parameters, { query: "会议", offset: "0", limit: "20" });
  assert.equal(requests[1].method, "woice.read_material_page");
  assert.deepEqual(requests[1].parameters, {
    recording_id: "recording-1",
    field: "transcript",
    offset: "3",
    limit: "10",
  });
});
