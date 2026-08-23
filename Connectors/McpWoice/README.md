# Woice MCP Bridge

这是 Woice 到外部 Agent 的只读 stdio MCP 薄桥。它只暴露素材状态、列表、读取、搜索和原文分页；不启动录音、不触发转写、不派发外部任务、不读 SQLite/Keychain。

MCP 客户端通过 `initialize` / `notifications/initialized` 完成生命周期握手后，使用 `tools/list` 和 `tools/call`。桥接层所有业务请求都转发到当前用户的 Woice v1 Unix Socket。

## 本地验证

```bash
npm test --prefix Connectors/McpWoice
```

## 启动

```bash
node Connectors/McpWoice/src/index.mjs
```

默认 Socket 与 PI Extension 相同，可用 `WOICE_SOCKET_PATH` 覆盖。
