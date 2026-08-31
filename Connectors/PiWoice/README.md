# Woice PI Extension

这个扩展是 PI 到 Woice 本地 Unix Socket 的薄适配层：

- `woice_status`：读取录音/处理状态。
- `woice_list_recordings`：列出录音 ID。
- `woice_read_transcript`：读取原始转录。
- `woice_read_material`：读取有上限的素材状态、原文、时间戳和音轨引用；只读，不触发转写或外发。
- `woice_request_markdown`：请求 Markdown 笔记；PI 和 Woice 都保留用户确认门槛。
- `/woice` 与 `Ctrl+Shift+W`：查看当前状态。

扩展不读 SQLite、不访问麦克风、不接触 Keychain/API Key。所有数据调用都经过 Woice v1 JSON Lines Unix Socket。

## 本地验证

```bash
npm test --prefix Connectors/PiWoice
```

## 使用

PI 版本固定为 `@earendil-works/pi-coding-agent@0.83.0` peer dependency。Woice 运行后，在 PI 中安装本目录：

```bash
pi install ./Connectors/PiWoice
```

正式版默认 Socket 为 `~/Library/Application Support/Woice/woice.sock`；Dev 使用 `WOICE_APP_CHANNEL=dev` 并连接 `~/Library/Application Support/Woice Dev/woice.sock`。测试或特殊环境可设置 `WOICE_SOCKET_PATH` 覆盖路径。
