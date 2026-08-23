# Agent 只读素材搜索与分页读取契约

> 状态：M2-09e 的只读增量；不提前实现出站 Agent 派发，不改变录音/转写核心顺序

## 目标

- 允许已授权的外部 Agent 在 Woice 中搜索素材，并读取长原文的有限页面。
- 复用现有 `RecordingRecord`、`TranscriptArtifact` 和 `woice.sock`，不新增数据库真相源。
- 让一次请求只返回有上限的数据，避免把完整素材库或超长原文塞进 Agent 上下文。

## RPC

- `woice.search_materials`：参数 `query`、`offset`、`limit`；按当前素材库时间倒序搜索标题/原文/Markdown/日期/状态/音轨来源和文件名。空 query 返回最近素材。
- `woice.read_material_page`：参数 `recording_id`、`field`（当前只允许 `transcript`）、`offset`、`limit`；按 Unicode 字符边界返回原文页，并返回 `next_offset`、`has_more` 和总字符数。
- 两个方法均为只读，不创建 Job、不发送网络、不读取 Keychain；未找到录音或原文时返回结构化错误。
- 单页 UTF-8 编码上限 64 KiB；`limit` 最大 16,384 字符，实际返回以 64 KiB 为上限。

## PI 适配

- 新增 `woice_search_materials` 和 `woice_read_material_page` 两个工具。
- PI 只调用版本化本地 RPC，不读 SQLite、文件系统、麦克风或凭据。
- 工具描述明确“只读、不会触发处理或外发”。

## 验收

- 契约测试覆盖空搜索、AND 语义、分页连续性、超限裁剪、非法字段和缺失素材。
- 外部 Connector 测试覆盖两个新工具的请求方法和参数。
- `make verify` 通过；真实 PI 安装/Agent Smoke 仍属于 M2-09h，待核心桌面验收和外部 Agent 环境可用后执行。
