import { homedir } from "node:os";
import { join } from "node:path";
import { randomUUID } from "node:crypto";
import net from "node:net";

export const WOICE_PROTOCOL_VERSION = "1";
export const WOICE_MAX_RESPONSE_BYTES = 64 * 1024;

export function socketPathForChannel(channel = "release") {
  const directory = channel === "dev"
    ? "Woice Dev"
    : channel === "release"
      ? "Woice"
      : null;
  if (directory === null) {
    throw new Error(`Unsupported Woice app channel: ${channel}`);
  }
  return join(homedir(), "Library", "Application Support", directory, "woice.sock");
}

export function defaultSocketPath() {
  return process.env.WOICE_SOCKET_PATH
    ?? socketPathForChannel(process.env.WOICE_APP_CHANNEL ?? "release");
}

/**
 * Call Woice's current-user-only JSON Lines socket. The client never receives
 * or sends API keys; high-risk operations remain gated by Woice's own UI.
 */
export function callWoice({
  method,
  parameters = {},
  socketPath = defaultSocketPath(),
  timeoutMs = 5_000,
}) {
  if (typeof method !== "string" || method.length === 0) {
    return Promise.reject(new Error("Woice method is required"));
  }
  if (Buffer.byteLength(socketPath) >= 104) {
    return Promise.reject(new Error("Woice socket path is too long"));
  }

  const request = JSON.stringify({
    protocolVersion: WOICE_PROTOCOL_VERSION,
    requestID: randomUUID(),
    method,
    parameters,
  }) + "\n";
  if (Buffer.byteLength(request) > WOICE_MAX_RESPONSE_BYTES) {
    return Promise.reject(new Error("Woice request is too large"));
  }

  return new Promise((resolve, reject) => {
    const socket = net.createConnection({ path: socketPath });
    let responseBuffer = Buffer.alloc(0);
    let settled = false;
    const finish = (callback, value) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      callback(value);
    };
    const fail = (error) => {
      socket.destroy();
      finish(reject, error instanceof Error ? error : new Error(String(error)));
    };
    const timer = setTimeout(() => fail(new Error("Woice connector request timed out")), timeoutMs);

    socket.setEncoding("utf8");
    socket.on("connect", () => socket.write(request));
    socket.on("data", (chunk) => {
      responseBuffer = Buffer.concat([responseBuffer, Buffer.from(chunk)]);
      if (responseBuffer.byteLength > WOICE_MAX_RESPONSE_BYTES) {
        fail(new Error("Woice response is too large"));
        return;
      }
      const newline = responseBuffer.indexOf(0x0a);
      if (newline < 0) return;
      const line = responseBuffer.subarray(0, newline).toString("utf8");
      let response;
      try {
        response = JSON.parse(line);
      } catch {
        fail(new Error("Woice returned invalid JSON"));
        return;
      }
      if (response.protocolVersion !== WOICE_PROTOCOL_VERSION) {
        fail(new Error("Woice returned an unsupported protocol version"));
        return;
      }
      if (response.error) {
        const code = response.error.code || "WOICE_ERROR";
        const error = new Error(response.error.message || "Woice connector request failed");
        error.code = code;
        fail(error);
        return;
      }
      socket.end();
      finish(resolve, response.result || {});
    });
    socket.on("error", fail);
    socket.on("end", () => {
      if (!settled) fail(new Error("Woice closed the connector before replying"));
    });
  });
}
