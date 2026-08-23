# Woice 需求与设计初稿

> 状态：历史技术调研基线；需求与范围以[语音上下文来源产品定位](2026-08-22-voice-context-source-positioning.md)为准  
> 整理日期：2026-08-22  
> 来源：Codex 任务「调研 mac 常驻录音转写工具」及本轮技术复核  
> 工作名：Woice

> 需求修正版：Woice 首先是录音工具和语音素材库，不是 AI 网关、AI 工具入口或聊天聚合器。录音、原始音频保存、转写、模型管理、复听、搜索和导出是核心能力；WhisperKit、本机模型下载和 Core/Offline 双版本继续有效。素材完成后，用户可以把选中的素材交给已验证的外部 Agent/CLI，外部 Agent 也可以在授权范围内读取 Woice 上下文。下文与当前定位规格冲突处，以当前定位规格为准。

> 再次修正（2026-08-22）：不要把“Woice 能调用其他 Agent”解释成“Woice 是 AI 能力入口”。Woice 的唯一核心任务是把录音做成可靠、可复用的语音素材；外部 Agent 只是素材完成后的可选消费者，或经过授权的上下文读取方。核心版本必须在没有任何 Agent 的情况下独立完成录音、转写、复听、搜索和导出。

## 1. 结论

方案有条件可行，核心链路没有技术阻断项：

```text
全局快捷键 / 菜单栏
  -> 麦克风录音
  -> 原始音频持久化
  -> 本机/已授权 ASR Provider
  -> 原始转录持久化
  -> 复听、历史、搜索、Markdown 导出
  -> （可选）把已完成素材交给已验证的外部 Agent/CLI
  -> （可选）外部 Agent 通过 MCP / RPC 读取授权上下文
```

建议把产品定义为：

> 一个本地优先的 macOS 录音与语音素材工具；它把可靠的音频和文字素材提供给用户及外部 Agent 使用，但不在自身内部实现通用 AI 推理或 Agent 工作流。

第一版采用“模块化单体”，先保证录音、数据安全和模型切换可靠；不要一开始拆成多个常驻服务，也不要加载任意第三方动态库。稳定接口保留后，外部 Provider 和 Agent 连接器再通过本地 RPC 独立演进。

总体可行性评级：**可进入技术 Spike 和 MVP 开发**。

## 2. 本轮复核后的关键修正

### 2.1 DeepSeek Harness 只能作为架构参考和后置适配目标

[DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) 当前为 MIT 许可证，但官方仍标记为 Developer Preview，并明确可能发生破坏性变更。它适合借鉴以下原则：

- 能力由 Service Definition、Provider、Consumer 三个角色组成。
- 插件通过配置组合。
- 注册和副作用应可卸载。
- 模型可见内容应能由持久事件恢复。

不应把 Woice 核心直接建立在 DeepSeek Harness 包或内部 ABI 上。DeepSeek Harness 连接器放在 P2，并锁定兼容版本。

参考：[DeepSeek Harness README](https://github.com/deepseek-ai/deepseek-harness)、[架构文档](https://github.com/deepseek-ai/deepseek-harness/blob/master/docs/architecture.md)。

### 2.2 PI 使用专用 Extension，不假设它原生支持 Woice 或 MCP

PI 当前官方示例使用包名 `@earendil-works/pi-coding-agent`，与旧调研中的 `@mariozechner/pi-coding-agent` 不同。其 Extension 支持 `registerTool()`、`registerCommand()`、`registerShortcut()`、事件拦截和 Provider 注册；RPC 模式使用 stdin/stdout JSON 协议。

Woice 应提供单独的 `pi-woice-extension`，由它连接 Woice 本地 RPC。通用 Agent 兼容通过 MCP 实现，PI 的产品体验通过专用 Extension 实现，两者互不替代。

参考：[PI Extensions](https://pi.dev/docs/latest/extensions)、[PI RPC Mode](https://pi.dev/docs/latest/rpc)。

### 2.3 第三方插件不使用任意进程内动态库

macOS Hardened Runtime、代码签名、Swift ABI、依赖冲突和崩溃传播，使“下载一个 `.bundle` 后直接加载”不适合作为通用插件机制。

插件分成三类：

- 内置 Swift Provider：随应用编译和签名，进程内运行。
- 受控进程 Provider：Python、Node、Rust 等通过 stdio JSON-RPC 运行，超时或崩溃不拖垮主应用。
- Agent Connector：MCP、PI、DeepSeek Harness 适配器，只调用稳定本地 RPC。

### 2.4 MCP 是外部协议，不是核心内部总线

MCP 适合向 Agent 暴露工具、资源和长任务，但不适合作为 Swift 模块之间的内部函数调用协议。

- 应用内部：Swift Protocol + Actor 隔离。
- App 与本机连接器：Unix Domain Socket 上的版本化 JSON-RPC。
- 通用 Agent：stdio MCP Bridge；需要时再开启绑定 `127.0.0.1` 的 Streamable HTTP。

MCP 当前标准传输包括 stdio 和 Streamable HTTP。HTTP 版本必须做鉴权、Origin 校验和版本协商；不能因为只监听 localhost 就视为安全。

参考：[MCP Transport 规范](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports)、[本地 MCP 安装安全要求](https://modelcontextprotocol.io/seps/1024-mcp-client-security-requirements-for-local-server-)。

## 3. 产品目标

### 3.1 用户目标

- 随时用自定义快捷键开始和结束录音。
- 录音完成后可靠保存原始音频和原始转录。
- 选择本机模型、已授权本地服务或云端 ASR，不绑定单一模型；本机模型与 Core/Offline 双版本属于核心能力。
- 在本机查看、复听、搜索、复制和导出原始素材与转录。
- 在素材完成后，把选中的素材交给已验证的外部 Agent/CLI 处理，并保存返回的派生 Artifact。
- 允许 Codex、PI、“小龙虾”等外部 Agent 在授权范围内查询或读取语音资产；具体适配以实际验收列表为准。

### 3.2 产品原则

- Local-first：默认录音、存储和转录都在本机完成。
- Raw is immutable：外部 Agent、兼容处理和人工编辑都不能覆盖原始转录。
- Configuration over branching：切换已安装 Provider 不修改业务代码。
- Fail closed：录音、云端外发和自动粘贴默认需要明确授权。
- Artifact first：外部 Agent 获取 Artifact 引用，不直接接收整段音频或无限长文本。
- Durable jobs：录音完成后的转录和处理任务可在应用重启后恢复。
- MIT-first：代码参考和直接复用仅采用已核实的 MIT 项目；模型权重单独审查许可证。

## 4. 用户与核心场景

### 4.1 目标用户

- 需要快速口述输入的个人用户。
- 需要会议记录、摘要和待办的知识工作者。
- 希望把语音能力接入本地 Agent 工作流的开发者。

### 4.2 P0 场景：快速口述

1. 用户按下全局快捷键。
2. Woice 显示明确的录音状态和计时。
3. 用户再次按快捷键停止。
4. Woice 立即固化原始音频，后台执行 ASR。
5. 保存原始转录，显示模型、版本、处理位置和数据来源。
6. 用户在历史记录中复听、搜索、复制或导出；需要后续处理时，再选择外部 Agent/CLI。

### 4.3 P1 场景：会议记录

1. 用户选择会议录音 Profile。
2. Woice 捕获系统音频和可选麦克风音轨。
3. 停止后分别保存音轨，执行转录并保留时间戳。
4. 用户回到时间戳定位音频、搜索和导出；摘要和待办由用户选择的外部 Agent 处理。

### 4.4 P1 场景：PI 深度接入

- `/voice` 命令打开 Woice 或展示当前状态。
- PI Tool 查询历史转录、读取 Artifact；需要摘要时由 PI 自己完成推理，或由 Woice 按用户确认派发给目标 Agent。
- 用户主动允许后，快捷键录音结果可作为 PI 的 user message 或结构化上下文。
- PI 不能在默认配置下静默启动麦克风。

## 5. 范围

### 5.1 MVP / P0

- Apple Silicon，macOS 14+。
- SwiftUI 菜单栏应用，无 Dock 图标模式。
- 开机启动设置。
- 普通组合键形式的自定义全局快捷键。
- 麦克风录音；开始、停止、取消、错误状态。
- 原始音频分段落盘和异常恢复。
- WhisperKit 本地 ASR Provider 与 macOS on-device Speech。
- OpenAI-compatible ASR；允许配置本地或云端 ASR，但云端必须显式授权。
- Core/Offline 双版本、模型清单、模型下载、完整性校验与断网转写。
- SQLite 元数据、Artifact 索引、持久任务队列和全文搜索。
- 原始音频、原始转录、时间戳和派生 Artifact 分开存储且可追溯。
- Markdown 导出。
- ASR Profile、模型与转写设置。
- Keychain 保存密钥。
- 本地版本化 JSON-RPC。
- 外部 Agent 协作不作为核心发布前置；仅在核心素材闭环完成后接入。

### 5.2 P1

- 系统音频 + 麦克风双音轨。
- 会议模式和说话人分离。
- 实时转录预览和 VAD。
- 自动粘贴到当前应用。
- Fn/Globe、单修饰键等低层快捷键。
- PI Extension。
- 系统 TTS 朗读作为现有兼容能力保留，不扩展为新的 TTS Provider 生态。
- 受控进程 Provider SDK。
- 可选 Streamable HTTP MCP。

### 5.3 P2

- 已验证的外部 Agent/CLI 适配器（按需求逐个增加）。
- 更多 MCP/RPC 读取连接器。
- 自动会议检测。
- 加密同步、多设备和团队能力。
- 插件签名、分发和市场。

### 5.4 明确不做

- MVP 不支持 Intel Mac。
- MVP 不支持 Windows、Linux、iOS。
- MVP 不做任意第三方动态库热加载。
- MVP 不做无感知、无人确认的自动录音。
- MVP 不把云端模型设为隐式兜底。
- MVP 不承诺支持所有 AI CLI，不做自动发现、自动安装或自动选择 Agent。
- MVP 不做 Woice 自有 LLM、Prompt 编排、Agent Planner 或 Agent Loop。
- MVP 不做账号系统和云同步。
- 本初稿不承诺 Mac App Store 分发；外部进程插件和模型下载会影响分发方案。

## 6. 功能需求

### 6.1 常驻与快捷键

- FR-001：应用可在菜单栏常驻，并显示 Idle、Recording、Processing、Failed 状态。
- FR-002：用户可配置开始/停止录音快捷键，冲突时明确提示。
- FR-003：MVP 只支持标准组合键；Fn/Globe 等需要 Event Tap 的按键放入 P1。
- FR-004：用户可选择开机启动，基于 `SMAppService` 实现。
- FR-005：录音期间必须持续显示可见指示，不允许后台静默录音。

### 6.2 录音

- FR-010：MVP 使用麦克风作为 `AudioSource`。
- FR-011：用户可选择输入设备并查看输入电平。
- FR-012：录音数据按固定时长分段落盘，进程异常后最多丢失当前未固化分段。
- FR-013：停止时生成 Recording 记录和原始音频 Artifact；后续任务失败不删除原始音频。
- FR-014：取消录音需二次确认是否丢弃；若保留则标记为 `cancelled`。
- FR-015：同一时间只允许一个活跃录音会话。
- FR-016：系统音频作为独立 `AudioSource`，P1 不与麦克风在采集层混成单轨。

### 6.3 转录

- FR-020：ASR Provider 输入标准音频 Artifact，输出标准 Transcript。
- FR-021：保存语言、完整文本、时间戳分段、置信度、模型和 Provider 版本。
- FR-022：原始转录创建后不可原位覆盖。
- FR-023：重跑 ASR 产生新的 Artifact，并通过 `supersedes` 关联旧版本。
- FR-024：Provider 不可用时任务进入可诊断失败状态，不自动切换到云端。
- FR-025：长音频支持可恢复的分段转录和增量合并。

### 6.4 外部 Agent 素材使用

- FR-030：只有在录音、音频和原始转录已安全提交后，用户才能从详情页选择“发送给…”外部 Agent/CLI。
- FR-031：派发输入是 Artifact 引用、选中时间范围和用户原始任务说明；Woice 不自动补写 Prompt、不替用户规划任务。
- FR-032：任务保存目标 Agent、适配器版本、输入 Artifact、数据位置、授权事实和调用时间。
- FR-033：外部 Agent 返回文本、Markdown、JSON 或文件时，Woice 创建新的派生 Artifact，并保留父子来源链。
- FR-034：外发前显示目标、数据类型、工作目录和网络范围；云端目标必须单独确认。
- FR-035：Agent 未安装、未登录、失败或超时只影响派发任务；原始音频和原始转录必须保留。

### 6.5 TTS

- FR-040：系统朗读作为现有兼容能力保留，不改变录音和转写核心边界。
- FR-041：新增 TTS 或语音生成 Provider 必须另立规格，不得进入录音转写核心发布门槛。

### 6.6 历史、搜索和导出

- FR-050：历史列表展示标题、时间、时长、来源、状态和标签。
- FR-051：支持按关键字、时间、标签、Provider 和状态过滤。
- FR-052：详情页区分原始转录、人工编辑稿和外部 Agent 派生内容。
- FR-053：人工编辑保存为新版本，不修改原始转录。
- FR-054：Markdown 导出包含元数据、正文、时间戳和用户选定的派生结果；音频采用相对链接或显式附件策略。
- FR-055：删除操作区分“移到废纸篓”和“永久删除”，默认使用可恢复删除。

### 6.7 Agent 接入

- FR-060：外部接口统一返回稳定 ID 和 `voice://` Artifact URI。
- FR-061：大文本必须分页或分块读取，单次返回默认不超过 64 KiB。
- FR-062：MCP/RPC Bridge 默认提供状态、列表、搜索、详情和分页读取工具；创建 Agent 任务必须显式授权。
- FR-063：`voice_record_start` 默认返回 `USER_GESTURE_REQUIRED`。
- FR-064：外部 Agent 默认不能启动录音；如未来开放控制，仅能控制已由用户开始且当前可见的录音。
- FR-065：每次 Agent 调用记录调用方、工具、Artifact、结果和时间。
- FR-066：PI 和 DeepSeek Harness 适配器不得访问 Swift 内部类型，只能使用版本化本地 RPC。

## 7. 非功能需求

### 7.1 性能预算

- NFR-001：在最低支持设备上，快捷键到录音指示出现的 P95 不超过 300 ms。
- NFR-002：停止录音后 1 秒内完成 Recording 元数据和已固化音频分段登记。
- NFR-003：默认本地 ASR 模型在最低支持设备上的离线转录 RTF 应不高于 1.0；最终阈值由 M0 基准测试确认。
- NFR-004：10,000 条记录规模下，本地关键字搜索 P95 不超过 200 ms。
- NFR-005：MCP Artifact 分页读取首包 P95 不超过 500 ms，不含模型推理。

### 7.2 可靠性

- NFR-010：任务具备幂等键，同一任务重放不得产生无法识别的重复 Artifact。
- NFR-011：应用重启后恢复 `queued`、`running` 和 `interrupted` 任务。
- NFR-012：Provider 超时、崩溃或返回非法 Schema 时，Runtime 保持可用。
- NFR-013：原始音频、原始转录和所有派生 Artifact 保存内容哈希。
- NFR-014：数据库迁移必须可备份、可验证，失败时停止启动写操作。

### 7.3 隐私与安全

- NFR-020：本地 Profile 在模型已下载后可在断网环境完成录音、转录、搜索和导出。
- NFR-021：API Key 只保存在 Keychain，不进入配置、日志、事件或环境继承。
- NFR-022：日志默认不记录完整音频、完整转录、Prompt 或模型响应。
- NFR-023：本地 RPC Socket 文件权限仅允许当前用户访问。
- NFR-024：Streamable HTTP 如被启用，只绑定 `127.0.0.1`，同时要求随机 Bearer Token、Origin 校验和请求大小限制。
- NFR-025：外部进程 Provider 使用最小环境变量白名单、独立工作目录、超时和输出大小限制。
- NFR-026：安装外部 Provider 前展示可执行文件、参数、来源、哈希和权限声明。

## 8. 总体架构

```text
┌────────────────────────────────────────────┐
│ Woice macOS App                            │
│ 菜单栏 / 设置 / 历史 / 权限 / 可见录音状态 │
└──────────────────┬─────────────────────────┘
                   │ Swift Protocol / Actor
┌──────────────────▼─────────────────────────┐
│ Voice Context Core                         │
│ Recording / Transcript / Artifact / Search │
└──────┬───────────┬─────────────┬───────────┘
       │           │             │
  AudioSource   ASR / Model     Artifact Store
  AVAudioEngine Provider        SQLite + Files
       │           │
       │      内置 Swift / 受控进程
       │
┌──────▼─────────────────────────────────────┐
│ Context Collaboration Boundary             │
│ Unix Domain Socket + versioned JSON-RPC    │
└──────┬────────────┬──────────────┬─────────┘
       │            │              │
  MCP Bridge   PI Extension   DSH Plugin(P2)
   stdio/HTTP
```

### 8.1 模块边界

| 模块 | 职责 | 不负责 |
|---|---|---|
| `WoiceApp` | UI、菜单栏、设置、权限引导 | 模型实现、数据库 SQL |
| `WoiceDomain` | ID、Artifact、事件、任务、错误模型 | IO |
| `WoiceRuntime` | 录音/转写状态机、任务恢复、策略 | 具体 ASR、Agent 推理 |
| `WoiceAudio` | 设备、采集、分段、波形 | 转录 |
| `WoiceProviders` | ASR/模型契约和内置实现 | UI、Agent 推理 |
| `WoiceStorage` | SQLite、文件、迁移、全文索引 | Agent 协议 |
| `WoiceRPC` | 本地 JSON-RPC、鉴权、版本协商 | 业务决策 |
| `connectors/mcp` | MCP Tool/Resource 到本地 RPC 的转换 | 直接读数据库 |
| `connectors/pi` | PI Tool、Command、Shortcut 和上下文转换 | 直接控制录音设备 |
| `connectors/dsh` | DeepSeek Harness 能力适配 | Woice 核心依赖 |

### 8.2 为什么 MVP 使用模块化单体

- 录音权限、代码签名和菜单栏生命周期集中处理更可靠。
- 避免一开始承担守护进程升级、跨进程崩溃恢复和双份配置。
- Swift Provider 保持低开销。
- 本地 RPC 已提供未来拆分边界，不妨碍 Agent 接入。

## 9. Runtime 状态与任务模型

### 9.1 录音状态机

```text
idle
  -> authorizing
  -> recording
  -> finalizing
  -> queued
  -> transcribing
  -> completed

任意处理中状态 -> failed / interrupted -> queued(显式重试)
recording -> cancelled
```

要求：

- 状态变化先写事件，再更新投影。
- `recording` 期间每个固化分段产生 Artifact 事件。
- 失败事件保存稳定错误码、Provider 原文错误摘要和可重试标记。
- 自动重试只用于明确可重试错误，并使用上限和退避；用户取消不重试。

### 9.2 持久任务

任务最少包含：

```text
id, kind, state, input_artifact_id, provider_id,
config_snapshot, attempt, lease_until, idempotency_key,
created_at, started_at, finished_at, error_code
```

MVP 使用 SQLite 实现持久队列。ASR 默认并发 1；外部 Agent 派发使用独立任务状态，不占用录音与转写状态机。

## 10. Artifact 与数据模型

### 10.1 核心实体

```text
Recording
  ├─ AudioArtifact(raw.microphone.segment.*)
  ├─ AudioArtifact(raw.system.segment.*)        P1
  ├─ TranscriptArtifact(raw)
  ├─ TranscriptArtifact(retranscribed)
  ├─ TextArtifact(corrected / edited)
  ├─ TextArtifact(agent-derived / edited)
  ├─ JsonArtifact(agent-derived)
  └─ AudioArtifact(tts)                         P1
```

### 10.2 Artifact 字段

```text
id, recording_id, kind, mime_type, uri, byte_size,
sha256, parent_id, supersedes_id, provider_id,
model_id, config_snapshot, created_at, deleted_at
```

### 10.3 Transcript 标准结构

```json
{
  "schemaVersion": "1",
  "language": "zh",
  "text": "...",
  "segments": [
    {
      "startMs": 0,
      "endMs": 1830,
      "text": "...",
      "speaker": null,
      "confidence": null
    }
  ],
  "provider": "whisperkit",
  "model": "..."
}
```

Agent 接口优先返回：

```json
{
  "recordingId": "rec_...",
  "artifactId": "art_...",
  "uri": "voice://recordings/rec_.../artifacts/art_..."
}
```

## 11. Provider 与插件设计

### 11.1 Provider 类型

| 类型 | 示例 | MVP |
|---|---|---|
| `AudioSource` | 麦克风、系统音频、文件 | 麦克风 |
| `AudioProcessor` | 重采样、VAD、降噪 | 基础重采样 |
| `ASRProvider` | WhisperKit、whisper.cpp、SenseVoice、云端 ASR | WhisperKit |
| `DiarizationProvider` | SpeakerKit、外部模型 | 否 |
| `TTSProvider` | Apple TTS、TTSKit、云端 TTS | 仅契约 |
| `ExportProvider` | Markdown、Webhook | Markdown |
| `AgentConnector` | MCP、PI、DeepSeek Harness | MCP |
| `PolicyProvider` | 授权、外发、录音策略 | 内置 |

存储不在 MVP 中做可替换插件。Artifact 一致性和任务恢复依赖事务边界，先把 SQLite + 文件系统作为核心基础设施。

### 11.2 运行形态

#### 内置 Provider

- Swift Protocol。
- 随 App 编译、签名和发布。
- 适合 AVAudioEngine、WhisperKit、Keychain、SQLite。

#### 进程 Provider

- stdio JSON-RPC。
- 首次调用执行 `initialize` 和版本协商。
- 每次任务传 Artifact 引用或受控临时文件，不传无限大 base64。
- stdout 只允许协议消息，stderr 进入脱敏诊断日志。
- 超时后终止子进程，Runtime 记录失败并继续运行。

### 11.3 Manifest 草案

```json
{
  "id": "com.example.woice.asr.sensevoice",
  "version": "0.1.0",
  "apiVersion": "1",
  "license": "MIT",
  "kind": "process-provider",
  "capabilities": ["asr", "language:zh", "language:yue"],
  "entrypoint": {
    "executable": "./bin/provider",
    "args": []
  },
  "configSchema": "./config.schema.json",
  "permissions": {
    "network": false,
    "artifactRead": ["audio.raw"],
    "artifactWrite": ["transcript.raw"]
  },
  "limits": {
    "timeoutMs": 600000,
    "maxStdoutBytes": 1048576
  }
}
```

Manifest 声明不等于操作系统级沙箱。MVP 必须在 UI 中明确这一点；真正的进程沙箱和插件签名属于 P2。

## 12. 配置与 Pipeline

配置必须经过 Schema 校验，未知字段或类型错误直接拒绝启用，不能静默忽略。

```yaml
version: 1

profiles:
  quick_note:
    source: microphone.default
    asr: whisperkit.default
    outputs:
      - sqlite
      - markdown.default

  local_private:
    source: microphone.default
    asr: whisperkit.default
    networkPolicy: deny
    outputs:
      - sqlite

  meeting:
    sources:
      - microphone.default
      - system_audio.default
    asr: whisperkit.default
    diarization: speakerkit.default
    outputs:
      - sqlite
      - markdown.default
```

配置快照随任务保存。用户后来修改模型，不应改变历史任务的可追溯信息。

## 13. 本地 RPC 与 Agent 接口

### 13.1 本地 JSON-RPC

- 传输：Unix Domain Socket。
- Socket 仅当前用户可读写。
- 首次连接协商 `apiVersion` 和客户端能力。
- 每个请求包含 `requestId`、调用方标识和可选幂等键。
- 长任务立即返回 `taskId`，由调用方查询或订阅状态。

### 13.2 MCP 暴露面

MVP Tools：

```text
woice_status_get
woice_recordings_list
woice_recording_get
woice_transcript_get
woice_transcript_search
woice_artifact_read
woice_agent_task_create  # 仅在用户确认后可用
woice_task_get
```

默认不注册或拒绝：

```text
woice_record_start
```

允许的控制工具：

```text
woice_record_stop
woice_record_cancel
```

停止和取消只作用于已由用户启动、当前可见的录音。若 P1 开启外部启动录音，需要单独设置并记录审批。

### 13.3 PI Extension

P1 提供：

  - `pi.registerTool()`：搜索、读取、状态；摘要由 PI 自己完成，或走用户确认后的 Agent 派发。
- `pi.registerCommand("voice", ...)`：打开 Woice 或展示状态。
- `pi.registerShortcut()`：触发 PI 侧交互，不绕过 Woice 录音策略。
- `tool_call` 拦截：高风险操作要求确认。
- 录音完成事件转为 PI 消息时，默认注入 Artifact 引用和摘要，不注入无限长全文。

### 13.4 DeepSeek Harness Plugin

P2 实现薄适配层：

- 只依赖 Woice 本地 RPC。
- 对 DeepSeek Harness 锁定已验证版本。
- 使用其工具审批和事件机制。
- 兼容性测试失败时不影响 Woice Runtime 和 MCP。

## 14. macOS 实现与权限边界

### 14.1 MVP

- 菜单栏：SwiftUI + AppKit 菜单栏能力。
- 开机启动：`SMAppService`，macOS 13+。
- 普通全局快捷键：MIT 的 [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts)，可在 App Sandbox 内工作。
- 麦克风：AVFoundation / AVAudioEngine；配置 `NSMicrophoneUsageDescription` 和 Audio Input Entitlement。
- 本地 ASR：[Argmax OSS / WhisperKit](https://github.com/argmaxinc/argmax-oss-swift)，当前要求 macOS 14+、Xcode 16+。

### 14.2 P1 系统音频

Apple 的 ScreenCaptureKit 可采集屏幕内容和音频。官方示例在 macOS 15+ 同时展示 `.audio` 与 `.microphone` Stream Output，并要求 Screen Recording 权限。

P1 采用以下策略之一，必须先完成 Spike：

- macOS 15+：同一 ScreenCaptureKit Stream 输出系统音频与麦克风，仍分别保存音轨。
- 保持 macOS 14：ScreenCaptureKit 捕获系统音频，AVAudioEngine 独立捕获麦克风，再按时间戳对齐。

系统音频还需正确配置 `NSAudioCaptureUsageDescription`。拒绝权限时功能降级为麦克风录音，不能无限弹窗。

参考：[ScreenCaptureKit](https://developer.apple.com/documentation/ScreenCaptureKit)、[Apple macOS 捕获示例](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos)、[受保护资源](https://developer.apple.com/documentation/bundleresources/protected-resources)。

### 14.3 额外权限

- Accessibility：仅自动粘贴或模拟键盘输入需要，MVP 不要求。
- Input Monitoring：普通注册式快捷键不要求；Fn/Globe、单修饰键等 Event Tap 方案才进入 P1 权限流程。
- TCC 权限依赖稳定签名和 App 身份；开发、升级和安装路径变化都要纳入测试。

## 15. 可行性矩阵

| 能力 | 结论 | 风险 | 决策 |
|---|---|---|---|
| 菜单栏常驻 | 高 | 生命周期和登录项授权 | SwiftUI/AppKit + SMAppService |
| 普通全局快捷键 | 高 | 快捷键冲突 | MVP 使用 KeyboardShortcuts |
| 麦克风录音 | 高 | TCC、设备切换、异常中断 | AVAudioEngine + 分段落盘 |
| 系统音频 | 高但有条件 | Screen Recording 权限、OS 差异、音轨同步 | P1 Spike 后固定基线 |
| 本地 ASR | 高 | 模型体积、首载时延、最低硬件 | WhisperKit；M0 做真实基准 |
| 中文增强 ASR | 中高 | Python/ONNX 打包与模型许可证 | 进程 Provider，非 MVP |
| 外部 Agent 派发 | 中高 | CLI 兼容、数据外发、结果回收 | 只接入已验证适配器，逐目标授权 |
| TTS | 高 | 模型大小和系统版本 | P1，先保留契约 |
| 持久任务恢复 | 高 | 幂等、迁移、部分文件 | SQLite 事件 + 任务表 |
| MCP 接入 | 高 | 本地服务安全、长任务、客户端差异 | stdio Bridge 优先 |
| PI 接入 | 中高 | API 版本和包名变化 | 独立 Extension + 兼容测试 |
| DeepSeek Harness | 中 | Developer Preview、破坏性变更 | P2 薄适配，不进核心 |
| 跨语言插件 | 中 | 供应链、依赖、沙箱、签名 | 受控进程，不加载任意 dylib |

最大风险排序：

1. 系统音频权限和双音轨同步。
2. 长录音的分段持久化、任务恢复和数据迁移。
3. 外部 Provider 的信任、隔离和依赖分发。
4. Agent 读取/派发素材的授权边界。
5. DeepSeek Harness 与 PI 的快速版本变化。

## 16. MIT 参考项目与复用边界

| 项目 | 当前许可证 | 主要参考点 | 复用态度 |
|---|---|---|---|
| [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) | MIT | 服务缝隙、配置组合、持久事件 | 只参考架构，P2 适配 |
| [Argmax OSS / WhisperKit](https://github.com/argmaxinc/argmax-oss-swift) | MIT | Swift/Core ML ASR、Speaker、TTS 契约 | MVP 依赖候选 |
| [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) | MIT | 用户可配置全局快捷键 | MVP 依赖候选 |
| [Looped Whisper](https://github.com/loopedautomation/whisper) | MIT | 菜单栏、快捷键、WhisperKit、权限分层 | 参考实现 |
| [WhisperNotes](https://github.com/reidemeister94/whisper-notes) | MIT | SQLite、Markdown、Provider 适配 | 参考数据与导出设计 |
| [Muninn](https://github.com/bnomei/muninn) | MIT | Provider Route、Pipeline、MCP 安全默认值 | 参考 Pipeline |
| [Recap](https://github.com/RecapAI/Recap) | MIT | 系统音频、麦克风、WhisperKit、Ollama | 仅 POC 参考；官方说明当前不完整 |
| [whisper.cpp](https://github.com/ggml-org/whisper.cpp) | MIT | Intel/Arm 兼容、Metal/Core ML、量化 | P1 备选 ASR |
| [MCP Specification](https://github.com/modelcontextprotocol/modelcontextprotocol) | MIT | Agent 通用工具和资源协议 | MVP 外部协议 |

许可证规则：

- 引入前锁定仓库、版本或 Commit SHA，复核根许可证和第三方 Notices。
- 保存 SPDX 标识、版权声明、变更记录和 SBOM。
- 代码 MIT 不代表模型权重、训练数据和下载资产也是 MIT；模型必须单独登记许可证和分发条件。
- GPL 项目只能做产品观察，不复制代码、资源或派生实现。
- 参考项目的功能声明不能代替 Woice 自己的运行验证。

## 17. 验收标准

### 17.1 M0 技术 Spike

- AC-001：在 M1 16 GB、macOS 14 的测试机上完成菜单栏、普通全局快捷键、麦克风录音和稳定 App 身份验证。
- AC-002：连续录音 60 分钟；音频总时长误差不超过 1%，无未解释的分段缺口。
- AC-003：录音中强制结束 App，重启后能识别已固化分段；丢失不超过一个配置分段时长。
- AC-004：WhisperKit 对固定 5 分钟中英文样本输出 RTF、峰值内存、模型大小和首载时间报告；据此冻结默认模型。
- AC-005：完成 App 内 Runtime -> Unix Socket -> stdio MCP Bridge -> 测试客户端的端到端调用。
- AC-006：进程 Provider 超时、崩溃、输出非法 JSON、输出超限四种情况下，App 不崩溃且产生稳定错误码。
- AC-007：ScreenCaptureKit Spike 分别验证系统音频、麦克风、双音轨时钟和权限拒绝路径，决定 P1 最低 macOS 版本。

### 17.2 MVP

- AC-010：首次使用只在用户点击录音时请求麦克风权限；拒绝后给出可恢复引导。
- AC-011：快捷键到可见录音状态 P95 ≤ 300 ms，100 次测试无丢触发。
- AC-012：停止后 1 秒内持久化 Recording 和全部已固化音频分段。
- AC-013：转录、外部派发或导出失败都不删除原始音频和原始转录。
- AC-014：对同一原始转录执行三次外部 Agent 派发，原始 Artifact 的 ID、内容和 SHA-256 不变。
- AC-015：切换两个已安装 Provider 或模型只修改配置，不修改 Pipeline 业务代码。
- AC-016：本地 Profile 在模型下载完成后断网运行，不产生外部网络请求。
- AC-017：云端 Provider 首次外发前展示目标域名、数据类型和授权；拒绝后不发请求。
- AC-018：应用重启后恢复待处理任务；重复恢复不产生未关联重复 Artifact。
- AC-019：10,000 条测试记录下全文搜索 P95 ≤ 200 ms。
- AC-020：MCP 默认无法启动录音，返回 `USER_GESTURE_REQUIRED`；查询和分页读取可用。
- AC-021：MCP 单次文本返回默认 ≤ 64 KiB，长转录可完整分页读取。
- AC-022：设置、日志、数据库和 MCP 错误中不出现明文 API Key。
- AC-023：每项第三方代码和模型均有版本、许可证、来源和 Notice 记录。

## 18. 开发顺序

### M0：风险 Spike

- 稳定签名身份、菜单栏、登录项和权限。
- 麦克风分段录音与异常恢复。
- WhisperKit 真实设备性能。
- SQLite Artifact / Event / Job 最小闭环。
- Unix Socket JSON-RPC + stdio MCP Bridge。
- ScreenCaptureKit 双音轨验证。

### M1：可用 MVP

- 完成 P0 功能和验收。
- 发布直接下载的签名、Notarized 测试包。
- 建立数据库迁移、崩溃恢复、隐私和许可证回归测试。

### M2：素材增强与 Agent 协作

- 系统音频、双音轨、实时预览、说话人分离。
- PI Extension。
- 自动粘贴和 TTS。
- 受控进程 Provider SDK。
- 在核心录音、转写、素材库退出检查后，接入已验证的外部 Agent/CLI。

### M3：后续扩展

- 更多已验证的 Agent/CLI 适配器和 MCP/RPC 读取连接器。
- 连接器签名、沙箱和分发机制；不建设 Agent 市场或网关。

## 19. 待确认问题

- Q-001：首个商业目标是“快速口述”还是“会议纪要”？本稿默认先做快速口述。
- Q-002：MVP 是否必须录系统音频？本稿将其放入 P1，但在 M0 提前 Spike。
- Q-003：最低系统版本选 macOS 14 还是 15？这会影响双音轨实现和 TTS 方案。
- Q-004：首发只支持 Apple Silicon 是否可接受？本稿默认可接受。
- Q-005：首发分发走官网签名/Notarization，还是必须进入 Mac App Store？
- Q-006：默认 ASR 更重视中文准确率、实时速度还是模型体积？
- Q-007：原始音频默认保留多久？是否需要自动清理策略？
- Q-008：首个外部 Agent/CLI 适配目标与输入输出契约是什么？在 M2-09 启动前冻结。
- Q-009：PI Extension 是否必须进入 MVP？本稿放在 M2，但 M0 会验证本地 RPC 边界。
- Q-010：TTS 的首要用途是结果朗读、语音助手回复，还是语音合成导出？

## 20. 立项门槛

满足以下条件后进入完整 MVP 开发：

- M0 的 AC-001 至 AC-007 全部通过。
- 冻结最低 macOS 版本、默认模型和首发分发方式。
- 冻结本地 RPC v1、Artifact v1 和 Provider v1 Schema。
- 完成第三方许可证和模型许可证清单。
- 对系统音频、PI、TTS 和外部 Agent 是否进入各阶段作出书面范围决定；外部 Agent 不得阻塞录音转写核心。
