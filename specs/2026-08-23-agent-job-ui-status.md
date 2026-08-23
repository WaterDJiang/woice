# Agent 任务与连接状态 UI 初稿

## 目标

把已经落地的 Context Package、受控 Runner 和 SQLite Agent Job 投影成可理解的本地状态，让用户知道：

- 当前 Woice 仍是录音与语音素材工具，不是 Agent 网关。
- 哪些 Agent 基础能力已经验证，哪些真实连接尚未配置。
- 任务是否排队、运行、完成、失败、取消或被重启恢复为中断。

## 范围

- 设置新增“Agent 与连接”只读分区；不在此处自动发现、登录或启动 CLI。
- 处理工作区显示 durable Agent 任务，与录音转写任务分组展示。
- 失败和中断状态显示下一步事实；不自动重放、不覆盖原始 Artifact。
- 继续复用 `AgentDispatchJob` 和 `agent_dispatch_jobs`，不新增同义状态模型。

## 不在范围

- 录音详情的“发送给…”派发流程。
- Codex 或第二个 CLI 的实际适配、登录和结果 Artifact 回收。
- 任意 Agent 聊天、自动路由、自动执行返回命令。

## 验收标准

- 没有 Agent 任务时，设置页明确显示“尚无 Agent 任务”和“真实连接尚未配置”。
- 有任务时，设置页和处理工作区显示 Connector、更新时间、状态和脱敏错误；中断文案明确“未自动重放”。
- Agent 分区点击“保存本页”不触碰 AppSettings 或 Keychain；其他设置草稿仍可独立保存。
- 深浅色、键盘导航、VoiceOver 和 Reduce Motion 不依赖 Agent 连接存在。
- `make docs-check`、`make lint`、`make test` 通过；真实 Agent Smoke 仍按 M2-09d/e/h 单独验收。

