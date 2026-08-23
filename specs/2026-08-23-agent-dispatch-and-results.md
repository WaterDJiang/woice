# Agent 出站派发与结果 Artifact 规格

## 目标

把已完成转写的 Woice 素材，经过用户确认后交给一个已发现的本机 CLI，并把返回内容保存为不可变的结果 Artifact。原始录音、原始转写和上下文包均不可覆盖；Woice 不执行 Agent 返回的命令、补丁或脚本。

## 范围

- 录音详情三步派发：目标、素材与任务、最终确认。
- 首批显式适配器：Codex CLI 与 Claude CLI；未发现或未验证的 CLI 不出现在可选列表。
- 受控进程：固定可执行路径、只读工作目录、环境白名单、超时、取消、输出上限。
- 文本、Markdown、JSON/JSONL 输出保存到 agent-results/，权限为用户可读写；结果携带来源录音、输入 Artifact、Connector、版本、哈希和受限预览。
- durable Job 记录状态、错误、取消和结果入口；应用重启后运行中的任务恢复为 interrupted。
- Audit 记录调用方、时间、目标、输入 Artifact、数据类型、Job/Trace/父任务关系和结果，不记录完整音频、原文、Prompt 或 Agent 输出。

## 非目标

- 不把 Woice 做成 Agent 网关、聊天聚合器或通用 Agent Loop。
- 不读取 CLI 的 Keychain、配置密钥或任意用户目录。
- 不自动执行返回内容，不自动跨 Agent 接力。
- 不承诺“支持所有 CLI”；支持列表以实际版本探针和真实验收证据为准。

## 验收标准

- AgentDispatchTests 使用本地 fixture 完成一次派发，结果文件可读且原始音频 SHA-256 不变。
- 未安装、超时、取消、非零退出、非法 JSON、超限输出都只更新 Job 失败事实，不修改输入 Artifact。
- 结果详情可在录音详情和处理工作区看到；可复制预览或在 Finder 中显示结果文件。
- Audit 在任务请求、完成、失败、取消和入站素材读取时持久化，重启后可查询。
- 权限语义固定为只读素材、创建任务、控制已开始录音三级；当前出站 CLI 只能使用“创建任务”，录音控制能力保持关闭，权限摘要必须进入派发 Job 的哈希。
- make acceptance-agent-outbound 默认只运行本机 fixture；设置 WOICE_RUN_REAL_AGENT=1 且显式安装目标 CLI 后，Codex CLI 0.147.0 与 Claude Code CLI 2.1.233 的真实版本探针/Smoke 已通过。
- make acceptance-agent-inbound 默认运行 MCP/RPC 只读契约；`WOICE_RUN_REAL_INBOUND=1 make acceptance-agent-inbound` 已通过本机真实 MCP/RPC Smoke。真实外部 Agent 读取用户素材必须由用户在已登录环境中选择非敏感录音并明确开启，不在自动门禁中代为外发。
- `WOICE_RUN_EXTERNAL_AGENT_INBOUND=1 make acceptance-agent-external-inbound` 使用合成 Woice Socket Fixture，让已配置的外部 Agent 通过真实 MCP Bridge 调用状态、列表、搜索和分页工具；当前 Claude 已通过，Codex 非交互执行仍需显式 MCP 工具批准；该门禁只证明外部 Agent ↔ MCP ↔ Woice 协议链，不代表已读取用户真实素材。

## 影响面

- WoiceCore：Agent 结果与审计契约。
- WoiceApp：CLI 适配、派发服务、SQLite 审计、结果 UI。
- Connectors：入站读取继续只走 RPC，增加审计投影。
- doc/plan：更新 M2-09c/d/e/f/g/h 状态和剩余真实 Mac 门禁。
