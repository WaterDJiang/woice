# M2-03c 可恢复处理任务边界

> 状态：本轮实现；SQLite Job/Lease 仍属于 M0-02 后续工作

## 1. 目标

让录音后的 ASR/LLM 处理状态在 App 重启后可诊断、可恢复、可显式重试。当前使用现有 JSON 索引保存最小任务投影，不把它描述成完整持久队列。

## 2. 范围

- `RecordingRecord` 保存 ASR/LLM 任务的 kind、状态、尝试次数、更新时间、幂等键和脱敏错误摘要。
- 录音结束后，已配置的 ASR 任务先进入 `queued`，用户确认外发后进入 `running`。
- ASR 成功后任务标记 `completed`；若配置 LLM，则创建新的 LLM 任务并再次等待用户确认。
- ASR/LLM 失败后任务标记 `failed`，保留原始录音和已生成原文，并在详情页提供显式重试。
- App 启动时把遗留的 `running` / `awaitingAuthorization` 标记为 `interrupted`；恢复只通过用户点击重试和再次确认，不自动向外部服务发送数据。
- App 启动时若发现已持久化的 `queued` Job 且对应服务已配置，只恢复为“等待你确认外发”的提示；不自动发送请求，用户取消后标记为 `cancelled`。
- 同一会话内存在多条 `queued` Job 时，按录音创建顺序逐条展示确认；当前任务确认或取消后才展示下一条。
- 用户取消外发标记任务 `cancelled`；之后仍可从详情页重新发起新的显式任务。

## 3. 不在本工作包

- 不引入 GRDB/SQLite、事件表、Lease、后台守护进程或跨进程恢复。
- 不自动重试网络请求，不绕过外发确认，不保存 API Key 到录音索引。
- 不覆盖原始音频、原始转录或已经完成的 Markdown。

## 4. 验收标准

- 旧录音 JSON 缺少任务字段时仍可读取。
- ASR -> LLM 端到端 Fixture 能观察到 `queued/awaitingAuthorization/running/completed` 状态变化。
- ASR 或 LLM 失败后，任务状态为 `failed`，原始音频和已有原文仍存在；点击重试会重新进入确认流程。
- 启动时遗留的处理中任务变为 `interrupted`，不会自动发出网络请求。
- 启动时遗留的 `queued` Job 会恢复为 `awaitingAuthorization`，并显示明确的外发确认；没有 Endpoint 时保持本地待处理状态。
- 多条待处理 Job 按顺序进入确认队列，不因第一条的确认或取消而静默丢失后续任务。
- 任务幂等键由录音 ID 与任务类型确定，同一录音不会因状态刷新产生重复任务。
- `make verify`、真实麦克风 ASR smoke test 通过。
