# M2-09a/b：Context Package 与受控 CLI 契约

> 状态：契约、Context Package、受控 Runner、真实 Codex/Claude 出站和自动门禁已完成；真实外部 Agent 入站与完整权限矩阵仍待验收。本规格不改变录音/转写核心状态机。

## 1. 目标

为“素材完成后交给外部 Agent”建立一个可验证的最小边界：

- `ContextPackage` 表达一条或多条 Recording 的 Artifact 引用、时间范围、用户原始指令、文件清单和内容哈希。
- `ContextPackageBuilder` 生成独立临时目录中的 `context.json`、`transcript.md` 和选定音频只读副本。
- `AgentCLIAdapterManifest` 固定可执行文件、版本探针、参数模板、输入/输出协议、超时、目录策略和能力，不接受调用方任意 Shell。
- `AgentDispatchJob` 表达连接器版本、输入包、权限链、hop 限制和稳定状态，不把 Agent 任务伪装成 ASR/LLM 任务。

## 2. 为什么不能直接复用现有对象

- `RecordingRecord` 是素材事实，不能保存一次派发的用户指令、目标连接器和临时包生命周期。
- `TranscriptArtifact` 是转写版本，不能表达音频 + 多条素材 + 时间范围的组合输入。
- `ProcessingTask` 目前只记录 ASR/分段/Markdown 任务，缺少 connector、context package、trace、父任务和 hop 字段。
- `ProcessProviderManifest` 面向 ASR/LLM/TTS Provider；Agent CLI 需要输入/输出传输、目录策略和固定版本探针，不能把 Provider kind 当作 Agent 身份。

因此新增的是边界值对象和契约，不新增第二份 Recording、Transcript 或文件数据库。

## 3. 契约

### 3.1 ContextPackage v1

- schema 版本固定为 major `1`。
- Artifact 引用必须唯一；不携带绝对路径、Keychain、数据库路径或完整 Endpoint。
- 时间范围必须满足 `0 <= start <= end`，单段不超过 24 小时。
- 指令最多 8,192 个 Unicode 字符，保留用户原文，不由 Woice 补写 Prompt。
- 文件路径只能是包内相对路径，禁止 `..`、绝对路径、NUL 和 Shell 元字符。
- 内容哈希是 64 位小写 SHA-256；Builder 对 `context.json`、`transcript.md` 和音频副本计算稳定摘要。
- 超过 64 KiB 的文字只能放在包文件/分页中，不能进入 CLI 参数或 JSON-RPC 参数。

### 3.2 AgentCLIAdapterManifest

- executable 必须是绝对路径且通过路径穿越检查。
- 版本探针和参数模板只允许固定参数与受控占位符：`{context_package}`、`{context_file}`、`{instruction_file}`。
- 禁止 Shell 片段、命令替换、重定向、管道和调用方覆盖 executable/参数/环境变量。
- 环境变量只声明允许转发的键名，不保存键值；默认只提供固定 `PATH`。
- 超时范围 1 秒至 1 小时；工作目录策略只能是无目录、只读或读写三种之一。
- 输入/输出传输协议和能力使用有限枚举，未知值拒绝解码或验证。

### 3.3 AgentDispatchJob

- 状态至少覆盖 `draft`、`awaitingAuthorization`、`queued`、`launching`、`running`、`collecting`、`awaitingAgentApproval`、`completed`、`failed`、`cancelled`、`interrupted`。
- 保存 connector ID/版本、Context Package ID、指令摘要、trace ID、可选父任务和 `hop/maxHop`。
- 默认 `maxHop = 1`；超过上限、形成自循环或缺少权限快照时 fail-closed。
- 幂等键、原始 Artifact 哈希和结果 Artifact 由后续 durable Job/Result Collector 工作包落库；本工作包先冻结编码/校验契约。

### 3.4 Controlled CLI Runner

- 只使用 manifest 的 executable 与固定参数，不经过 `/bin/sh -c` 或字符串拼接。
- `context.json`、`transcript.md` 和音频只通过受控临时目录提供；用户指令文件不写回 Context Package 根目录。
- 环境默认只有固定 `PATH`；调用方提供的环境键必须同时出现在 manifest 白名单中，Woice 不注入 API Key。
- 轮询超时、显式取消或输出文件超过上限时终止进程组并删除 Runner 临时目录。
- stdout 是候选业务结果，stderr 只作为截断诊断；非零退出、非法输出和超限不得标记任务成功。
- 版本探针和业务运行使用同一信任/路径校验，但版本输出不进入用户 Artifact。

### 3.5 Durable Agent Job 投影

- Agent Job 单独存于 SQLite `agent_dispatch_jobs`，不塞进 Recording 的 ASR/LLM `processing_tasks`。
- payload 保存已验证的 `AgentDispatchJob`；`idempotency_key` 唯一，重复保存只能更新同一 Job，不产生第二条任务。
- App 重启时 `launching/running/collecting/awaitingAgentApproval` 统一恢复为 `interrupted`，不自动重启 CLI 或外发素材。
- 该表只保存连接器版本、Context Package ID、哈希、状态和错误摘要，不保存 API Key、完整 Prompt 结果或任意 Shell。

## 4. 验收标准

- 中文、长文本、多素材、重复 Artifact、非法时间范围和路径穿越有契约测试。
- 同一输入 Builder 生成的文件内容和 package hash 稳定；不同指令或素材哈希必然变化。
- Builder 失败时不覆盖原始音频/原文，不删除用户素材；临时目录只包含白名单文件。
- Manifest 拒绝 Shell 元字符、未知占位符、任意环境变量、非法超时和不安全路径。
- Dispatch Job 拒绝未知状态、空 connector、hop 超限和不一致的 parent/trace 关系。
- 本工作包不声称真实 Codex/PI/其他 CLI 已接入；真实派发进入 M2-09c/d/h。
- Runner 夹具覆盖成功、版本探针、未授权、超时、取消、非零退出和输出超限；真实 CLI 仍进入 M2-09d/h。
- Durable Job 覆盖 schema 迁移、幂等更新和重启中断恢复；真正创建/执行任务仍需用户确认和后续 UI。

## 5. 下一步

1. 实现 Core 契约与 `ContextPackageBuilder`。
2. 接入受控 CLI Runner 的取消、进程组回收和版本探针。
3. 再实现“发送给…”三步 UI 和 durable Agent Job；完成前保持外部 Agent 出站能力关闭。
