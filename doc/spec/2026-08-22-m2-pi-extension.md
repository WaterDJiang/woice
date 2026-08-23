# M2-05 PI Extension 实际适配包

> 状态：薄适配实现完成，待真实 PI 0.83 安装加载验收

## 1. 目标

把已验证的 Woice v1 Unix Socket 协议接入 PI Extension，提供只读状态/历史/原文工具和受控 Markdown 请求；扩展本身不进入 Woice Runtime，不读 SQLite、不访问麦克风、不接触 API Key。

## 2. 实现边界

- 包路径：`Connectors/PiWoice/`，由 `package.json` 的 `pi.extensions` 指向 `src/index.ts`。
- 运行时依赖固定为 `@earendil-works/pi-coding-agent@0.83.0` peer dependency；扩展网络客户端只使用 Node 内置 `net`、`crypto`、`os` 和 `path`。
- 当前工具：`woice_status`、`woice_list_recordings`、`woice_read_transcript`、`woice_read_material`、`woice_request_markdown`；其中 `woice_read_material` 只读取已持久化素材状态、原文、时间戳和音轨引用，不触发转写、外发或 Markdown 处理。
- 命令/快捷键：`/woice` 与 `Ctrl+Shift+W` 只查询状态，不触发录音。
- 所有请求使用 `protocolVersion=1`、单行 JSON、5 秒超时和 64 KiB 响应上限；结构化错误保留错误码，不把敏感请求内容写入日志。

## 3. 用户控制与安全

- PI 工具在调用 Woice 处理请求前先展示 PI 确认；Woice 仍会显示自己的外发确认，双层门禁不能绕过。
- 不提供开始录音工具；录音仍必须来自 Woice 可见按钮/快捷键。
- Socket 路径默认使用当前用户 `~/Library/Application Support/Woice/woice.sock`，可用 `WOICE_SOCKET_PATH` 仅覆盖开发测试路径。

## 4. 验收

- `npm test --prefix Connectors/PiWoice` 通过：版本化请求、结构化错误和 Socket 生命周期。
- Node 客户端不包含 API Key、音频 Base64、SQLite 路径读写或任意动态加载。
- 在真实 PI 0.83 环境执行 `pi install ./Connectors/PiWoice` 后，`/woice` 能返回 Woice 状态；真实 PI 安装加载仍需解锁桌面和已安装 PI CLI。

## 5. 非目标

- 不把 PI 包打进 Woice.app，不在 Swift Runtime 内嵌 Node。
- 不自动安装 PI、不发布 npm、不引入未经验证的 PI 版本兼容层。
