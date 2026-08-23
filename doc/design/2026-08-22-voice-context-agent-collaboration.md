# Woice 语音上下文与 Agent 协作架构

> 状态：设计基线  
> 日期：2026-08-22  
> 需求：[语音上下文来源产品定位](../spec/2026-08-22-voice-context-source-positioning.md)

## 1. 设计结论

架构以 Voice Context Core 为中心，而不是以 Agent Gateway 为中心：

```text
声音采集与素材库
  -> ASR 结构化
  -> 可复听、可搜索、可引用的 Context Artifact
  -> 可选交给外部 Agent 使用
```

外部 Agent 有两个连接方向，但二者都是素材能力的边界接口：

- Woice -> Agent：用户选择素材和任务，Woice 派发并保存结果。
- Agent -> Woice：Agent 在授权范围内搜索和读取语音上下文。

录音、转写和素材管理不依赖任何 Agent；Agent 连接失败不能让核心链路不可用。

### 1.1 先后关系（不可反转）

```text
核心产品：录音 -> 转写 -> 素材库 -> 复听/搜索/导出
                                      |
                                      +-- 可选：交给外部 Agent
                                      +-- 可选：被外部 Agent 读取
```

Agent 不是 Woice 的上游入口，也不是核心状态机的必经节点。Woice 只保存和提供素材事实；推理、规划、编码、联网和业务动作留在目标 Agent 自己的运行时中。

### 1.2 非目标与兼容承诺

- Woice 不提供 AI 网关、统一聊天入口、Agent 市场或多 Agent 控制台。
- Woice 不自动发现、安装或编排所有 AI CLI；首版只承诺通用协议和已经完成真实验收的适配器。
- Agent 协作必须排在录音、转写、模型管理、复听、搜索和导出之后，不能成为核心录音闭环的前置依赖。
- Woice 不在本地实现通用 LLM 推理、Prompt 市场、规划器或 Agent Loop。
- “Woice 调用 Agent”只表示一次由用户发起的素材交付；不抽象成全局 Agent Gateway、统一 Agent Router 或会话中心。
- “Agent 调用 Woice”只表示受控的上下文读取；不开放数据库、文件系统或录音设备的通用访问。

## 2. 总体架构

```text
┌──────────────────────────────────────────────────┐
│ Woice App                                        │
│ 录音 / 最近素材 / 历史 / 详情 / 设置             │
└────────────────────────┬─────────────────────────┘
                         │
┌────────────────────────▼─────────────────────────┐
│ Voice Context Core                               │
│ Audio · Recording · Transcript · Artifact        │
│ Search · Playback · Job · Policy · Audit         │
└───────────────┬──────────────────────┬───────────┘
                │                      │
┌───────────────▼────────────┐  ┌──────▼─────────────────────┐
│ ASR / Model Layer          │  │ Agent Collaboration Layer │
│ WhisperKit / downloaded    │  │ Context Package           │
│ OpenAI-compatible ASR      │  │ Dispatch / Result         │
└────────────────────────────┘  └──────┬───────────┬─────────┘
                                      │           │
                                Outbound CLI   Inbound Tools
                                Codex / PI     MCP / RPC / CLI
```

ASR/Model Layer 是素材结构化核心；Agent Collaboration Layer 是素材使用扩展。两者不能合并成一个通用 Provider/Agent 路由器，否则产品边界会再次变成 AI 网关。

## 3. 领域对象

优先复用现有对象：

| 需求 | 领域表达 |
|---|---|
| 原始录音 | `Recording` + 原始音频 `Artifact` |
| 原始文字 | `Transcript` + 原始转录 `Artifact` |
| 派发过程 | `Job(kind: agentDispatch)` |
| 目标 Agent | `Connector` 的配置与版本快照 |
| 输入内容 | `Artifact` 引用与选中时间范围 |
| 返回内容 | 带父子关系的派生 `Artifact` |
| 权限 | `Policy` + `Permission` |
| 调用记录 | `Event` + Connector Audit |

只新增一个必要值对象 `ContextPackage`，它不是新的持久化真相源，只是派发时的不可变输入快照：

```text
ContextPackage
  id
  recordingID
  artifactRefs[]
  selectedTimeRanges[]
  instruction
  createdAt
  contentHash
```

Agent 的显示名称、可执行文件、协议和能力放在 `Connector` 配置中；不再引入与 Connector 同义的 AgentEndpoint/Provider 对象。

## 4. 组件边界

### 4.1 保留的核心组件

- `RecordingService`：麦克风采集和 WAV 固化。
- `SystemAudioCaptureService`：系统音频 CAF 与双轨状态。
- `AudioPlaybackService`：复听、时间戳和元数据。
- `SQLiteMetadataStore`：Recording、Artifact、Job、Lease 和审计真相源。
- `TranscriptionClient` / Built-in ASR：把音频变成原始文字。
- `WoiceRPC`：所有外部连接器唯一业务入口。

### 4.2 新增逻辑组件

| 组件 | 隔离 | 职责 |
|---|---|---|
| `ContextPackageBuilder` | 值类型/服务 | 选择 Artifact、时间范围和格式，生成不可变派发输入 |
| `ConnectorRegistry` | Actor | 保存已启用连接器、方向、能力、版本和健康状态 |
| `AgentTaskDispatcher` | Actor | 创建 durable Job，调用目标适配器并驱动状态 |
| `ControlledCLIRunner` | Actor | 受控启动 CLI、超时、取消、输出上限和进程回收 |
| `AgentResultCollector` | Actor | 解析结果并创建派生 Artifact，不执行返回内容 |
| `InboundContextRouter` | Runtime 服务 | 将 MCP/RPC 请求映射到搜索、读取和任务查询用例 |
| `ConnectorApprovalCoordinator` | MainActor + Runtime | 展示目标、数据、目录和外发确认，提交权限事实 |

### 4.3 明确不新增

- 通用 Prompt Engine。
- Agent Planner 或多 Agent 自动编排器。
- 自动选择模型或 Agent 的 Router。
- 在 Woice 内复制终端和完整 Agent 聊天 UI。
- 任意 Shell 执行接口。

## 5. Context Package

### 5.1 输入选择

用户可以选择：

- 原始音频引用。
- 原始转录全文。
- 一个或多个时间戳片段。
- 已存在的 Markdown/人工修订 Artifact。
- 多条 Recording 的组合。

默认只发送任务需要的最小内容。超过 64 KiB 的文本通过文件/Artifact 引用或分页传递；不得为了方便把整个素材库塞入命令行参数。

### 5.2 格式

首版支持：

- `context.json`：ID、时间、来源、选区和文件引用。
- `transcript.md`：用户选择的文字与时间戳。
- 原始音频文件路径：仅在连接器获得该 Artifact 的临时只读访问时提供。

临时派发目录使用独立权限和生命周期；完成后删除临时副本，不删除原始 Artifact。

## 6. Woice 调用外部 Agent

### 6.1 适配契约

每个 CLI 适配器声明：

```text
id, displayName, executable, versionProbe,
inputTransport, outputTransport, capabilities,
argumentTemplate, timeout, workingDirectoryPolicy
```

支持的输入输出形态：

- 输入：stdin JSON、固定参数模板、Context Package 文件。
- 输出：JSON/JSONL、Markdown、纯文本和受控文件引用。

调用方只能提供任务说明和 Artifact 选择，不能提供 executable、任意参数、Shell 片段或环境变量。

### 6.2 任务状态

```text
draft
  -> awaitingAuthorization
  -> queued
  -> launching
  -> running
  -> collecting
  -> completed

running -> awaitingAgentApproval
任意活动状态 -> failed / cancelled / interrupted
```

CLI 需要自己的交互审批时，Woice 显示“等待目标 Agent 确认”，不冒充仍在处理。是否打开目标终端由专用适配器决定，不能通过关闭审批参数来绕过。

### 6.3 结果处理

- 标准输出诊断与用户结果分开。
- 文本、Markdown、JSON 或文件引用创建新的派生 Artifact。
- 结果记录父 Artifact、目标 Connector、CLI 版本、任务说明和完成时间。
- 补丁、脚本、命令和发布结果默认只展示，不自动执行。
- 结果解析失败时保留原始受限输出作为诊断，不标记业务成功。

## 7. 外部 Agent 调用 Woice

### 7.1 协议

- 通用 Agent：stdio MCP。
- 本机专用扩展：Unix Socket JSON-RPC。
- PI 等产品：薄 Extension 调用相同 RPC。
- 需要命令行的场景：未来 `woice` CLI 只做 RPC 客户端，不直读数据库。

### 7.2 首版工具

```text
woice_status_get
woice_recordings_list
woice_recording_get
woice_transcript_search
woice_transcript_get
woice_artifact_read
woice_task_get
```

`woice_record_start` 默认拒绝并返回 `USER_GESTURE_REQUIRED`。停止/取消只作用于已经由用户启动且当前可见的录音。

### 7.3 权限与审计

- 连接器按只读素材、创建处理任务、控制已开始录音分级授权。
- 查询结果按 Artifact 和分页范围审计，不记录完整内容。
- Connector 不能访问 Keychain、SQLite、模型目录和任意文件系统路径。
- 外部 Agent 要求 Woice 再派发给另一个 Agent 时，视为新的高风险任务，默认需要用户确认，防止隐藏的 Agent 链和循环。

## 8. UI 信息架构

### 8.1 菜单栏 Popover

继续以录音为中心：

- 当前录音状态、时长和电平。
- 开始/结束录音主动作。
- 最近素材与转写状态。
- 最近一条 Agent 处理结果入口。
- 历史、任务和设置入口。

不在 Popover 放 Agent 市场、模型列表或多 Agent 聊天。

### 8.2 录音详情

信息顺序固定：

1. 音频复听与时间戳。
2. 原始转录。
3. 已有派生结果。
4. `发送给…` 动作。

发送流程最多三步：选择目标 Agent -> 确认素材与任务 -> 派发。默认记住最近一次目标，但每次仍显示实际数据范围。

### 8.3 历史窗口

历史仍是录音素材库，不改成 Agent 会话列表。增加：

- 按“未转写、可使用、有派生结果、处理失败”过滤。
- 多选素材后“发送给…”批量动作。
- 右侧详情展示每个派生结果的来源链。

### 8.4 设置

设置分组调整为：

- 录音。
- 模型与转写。
- Agent 与连接。
- 文件与隐私。

“模型与转写”继续承载 Core/Offline、模型下载、本机/云端 ASR；“Agent 与连接”只管理后续处理和外部读取权限。

### 8.5 任务窗口

任务列表是辅助界面，显示：目标 Agent、输入素材、状态、耗时和结果入口。它不成为 App 默认首页，也不承担 Agent 聊天历史。

## 9. UX 文案原则

- 主状态写“录音已保存”“正在转成文字”“可以使用这条素材”。
- 派发写“发送给 Codex 处理”，不写“路由到 Provider”。
- 外部读取写“Codex 正在读取 1 条转录”，不写“Agent Gateway 请求”。
- 失败必须说明“录音和原始文字仍保存在本机”。
- 没有 Agent 时显示可选连接入口，不显示产品未完成或服务异常。

## 10. 安全边界

- CLI 可执行文件和参数模板来自签名内置适配器或用户确认的受控 Connector Manifest。
- 不调用 `/bin/sh -c`，不拼接任意 Shell 字符串。
- 环境变量使用白名单，不复制 Woice 或其他进程的密钥。
- 工作目录默认无；需要项目目录时由用户显式选择只读或读写范围。
- 输出有字节上限、超时、取消和进程组回收。
- Agent 返回的文件必须位于授权目录或临时结果目录，路径逃逸直接拒绝。
- 所有 Agent 功能失败关闭，不影响录音和 ASR。

## 11. 迁移现有实现

- 保留当前 OpenAI-compatible ASR、WhisperKit/模型计划和双版本计划。
- 当前 LLM Markdown Client 暂时保留，标记为兼容路径；新内容处理能力优先通过 AgentTaskDispatcher 实现。
- `ProcessProviderRunner` 可重命名/泛化为 `ControlledCLIRunner`，但先通过第二个真实 CLI 使用点证明抽离需要。
- `PiConnectorRouter` 和 Unix Socket Server 继续作为 Agent -> Woice 的已实现基础。
- 结构化要点/待办 UI 继续显示已有 Artifact，不负责决定由哪个 AI 生成。

## 12. 设计验收 Journey

1. 未配置 Agent：完成录音、离线转写、复听、搜索和导出。
2. 录音详情：把一条转录发送给 Codex，看到阶段并保存返回 Markdown。
3. 多条素材：选择两个时间戳片段发送给另一个 CLI，输入范围准确。
4. Agent 未登录：任务失败但录音、转录和 Context Package 可重试。
5. Codex 调用 Woice：搜索今天的录音并分页读取转录，不能启动麦克风。
6. Agent 返回脚本或补丁：Woice 只保存和展示，不自动执行。
7. Core/Offline 两版：无论 Agent 是否配置，模型下载和断网转写行为一致。

每条 Journey 必须回答三个问题：素材是否安全、谁正在使用哪些素材、结果保存在哪里。
