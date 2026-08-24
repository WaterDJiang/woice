# Woice 语音上下文与 Agent 协作开发计划

> 编号：M2-09  
> 状态：源码与契约门禁已完成；M2-09a/b/c、M2-09d 两个真实 CLI 出站 Journey、M2-09f 用户派发/结果 UI、M2-09g 审计/权限摘要、本机 MCP 入站 Smoke 与 Claude 合成 MCP 入站 Smoke 均已有证据。Codex 外部入站交互批准、真实用户素材入站、稳定签名下的真实 CLI Smoke 仍是人工提醒；Woice 不提供 Agent 再派发入口，未来若新增必须作为新的用户确认任务，不扩展为 Agent 网关
> 日期：2026-08-22  
> 规格：[语音上下文来源产品定位](../spec/2026-08-22-voice-context-source-positioning.md)  
> 设计：[语音上下文与 Agent 协作架构](../design/2026-08-22-voice-context-agent-collaboration.md)  
> 全局状态：[当前路线图与计划迁移表](2026-08-22-current-roadmap-and-plan-transition.md)  
> 替代：旧 M1-06 MCP 待办、M2-05 剩余 PI 验收和旧 M3 中经验证的专用 Agent 适配  
> 保留：现有 Unix Socket RPC、PI 薄适配、受控进程安全原语和 LLM Markdown 兼容读取  
> 迁移：旧 M1-03/M2-03b 的新语义处理需求改为外部 Agent 结果；不迁移 ASR 责任  
> 停止：Agent 网关、多 Agent 控制台、插件市场、任意 Shell 和 Woice 自有 Agent Loop  
> 顺序：R0、M2-08 和 R2 素材库收口之后执行；M2-09a 也不得提前实施

## 1. 计划目标

在不改变“录音与转写是产品核心”的前提下，让 Woice 素材能够：

- 由用户从 Woice 发送给已安装的外部 AI Agent/CLI 继续处理。
- 由 Codex、PI、“小龙虾”等 Agent 在授权范围内查询和读取。
- 以 Artifact、Job、Policy 和 Audit 保持结果可追溯、失败可恢复。

M2-09 不替代 M2-08。M2-08 继续负责 Core/Offline、WhisperKit、模型下载和断网转写；M2-09 只负责转写完成后的素材使用和外部上下文访问。

本计划不是“AI 网关”或“所有 CLI 的统一入口”计划：只实现用户明确选择、已验证契约的 Agent/CLI 适配，以及外部 Agent 读取 Woice 素材的授权接口。没有 Agent 时，Woice 的录音、转写、复听、搜索和导出必须完整可用。

本计划的交付前提和发布边界：

- R0 录音核心、M2-08 ASR/模型/Core/Offline 和 R2 素材库退出检查通过后，才开始 M2-09。
- M2-09 的任何工作包都不是核心录音版本的发布阻塞项；核心版本可以在没有 Connector 的情况下独立发布。
- M2-09 只围绕 `Artifact` 交付与读取，不新增“Agent 首页”“统一会话”“自动路由”或“所有 CLI 兼容”产品能力。

## 2. 成功标准

- 未安装任何 Agent 时，录音、转写、复听、搜索和导出不受影响。
- 用户在录音详情中最多三步把选中素材发送给目标 Agent。
- 至少两个真实 CLI 完成任务派发、状态跟踪、取消和结果 Artifact 回收。（Codex CLI 0.147.0 与 Claude Code CLI 2.1.233 已完成真实出站 Journey；取消矩阵仍待单独桌面验收）
- 至少两个外部 Agent 通过 MCP/RPC 完成素材搜索和分页读取。（Claude 已在合成 Fixture 上通过；Codex CLI 非交互模式仍需要显式 MCP 工具批准，不能用自动绕过方式伪造通过）
- CLI 崩溃、未登录、超时、非法输出和输出超限不修改原始 Artifact。
- Woice 不包含通用 LLM Agent Loop，不自动执行 Agent 返回内容。
- Agent 默认不能启动麦克风，不能读取 Keychain、SQLite 或未授权目录。

## 3. 与现有工作包的关系

### 继续优先完成

- M1 真实 Mac 录音 -> 转写 -> 复听 UI Journey。
- M2-01 系统音频双轨真实验收。
- M2-02 VAD、分段和实时预览基础。
- M2-03 Artifact、时间戳、Job/Lease 和恢复。
- M2-08 模型接入、WhisperKit 与 Core/Offline 双版本。

### 直接复用

- Unix Socket JSON-RPC Server/Client。
- PI Extension 薄适配和 `PiConnectorRouter`。
- Process Provider 的环境白名单、工作目录、超时和输出上限。
- SQLite/WAL、幂等 Job、Lease 和前台确认队列。
- Artifact 不可变、Keychain、外发确认和 Connector Audit 规则。

### 停止扩展

- 不把当前 LLM Markdown Client 扩展成 Woice 自有 Prompt 市场或 Agent 工作流。
- 不在 Woice 内建设多 Agent 聊天、自动规划或自动选择 Agent。
- 不把设置首页改成 AI/Agent 控制台。

## 4. 范围

### 协作首发（非核心发布门槛）

- Context Package v1。
- Connector 能力、方向和 CLI Adapter Manifest。
- 受控 CLI 派发、取消、超时和结果收集。
- 一个 Codex CLI 专用适配器和一个独立 CLI 适配器，证明不是单产品特例。
- 适配器按实际需求逐个接入；通用协议和已验证列表构成兼容承诺，不承诺自动支持所有 AI CLI。
- MCP/RPC 素材查询与分页读取。
- 录音详情“发送给…”和任务状态/结果 UI。
- Connector 权限、目录范围、外发确认和审计。
- 真实 CLI 与真实外部 Agent 验收。

上述内容是核心闭环完成后的协作首发范围，不得前移为录音、转写或模型发布的前置条件。

### P1

- 多条素材和多个时间戳片段组合。
- Agent 返回文件、补丁和结构化 JSON 的专用预览。
- 连接器健康检查、版本升级和兼容提示。
- “小龙虾”等产品在准确 CLI/MCP 契约确认后的专用适配。
- 可选通知和完成后快捷动作。

### 不在本计划

- Woice 自研 LLM、Agent Planner 或 Agent Loop。
- 自动执行返回的命令、脚本、补丁或发布动作。
- 自动跨 Agent 接力和无限任务链。
- Agent 市场、聊天聚合器或终端模拟器。
- 替代 M2-08 的 ASR、模型下载和双版本计划。

## 5. 工作包

### M2-09a：Context Package 与 Connector 契约

产物：

- `ContextPackage` v1 Schema：Artifact 引用、时间范围、任务说明、内容哈希。
- Connector direction：`inbound`、`outbound`、`bidirectional`。
- Connector capability：读取素材、接收音频、接收文本、返回文本/文件、控制已开始录音。
- CLI Adapter Manifest：可执行文件、版本探针、固定参数模板、输入输出协议、超时和目录策略。
- Agent dispatch Job 配置快照和稳定错误码。

当前状态：Core 契约、Context Package Builder、受控 CLI Runner 和 SQLite Agent Job 投影已落地；Agent 结果 Artifact、Codex/Claude 显式适配器、三步用户确认 UI、结果回收和审计事件已落地。fixture 出站派发、原始音频不可变、SQLite 审计、真实 Codex/Claude 出站 Journey 和本机 MCP 入站 Smoke 已通过；真实外部 Agent 入站仍需用户明确选择素材后执行。

测试：

- 未知 major、路径逃逸、重复 Artifact、非法时间范围和超大指令。
- Manifest 不允许 Shell、任意环境变量和调用方覆盖 executable。
- 旧 Provider/Connector 配置继续解码。

验收：Schema 与 RPC 契约测试通过；原始 Artifact SHA 不变。

### M2-09b：Context Package Builder

产物：

- 单条录音、选中时间戳和多条素材的不可变输入快照。
- `context.json`、`transcript.md` 和临时只读音频引用。
- 64 KiB 以上文本使用文件/分页，不放命令行参数。
- 临时目录生命周期和清理。

测试：

- 中文、长文本、空转录、缺失音频、重复片段和多 Artifact 顺序。
- 完成/失败/强退后原始文件与临时文件边界。

验收：同一输入生成稳定哈希；任何结果都不覆盖输入。

### M2-09c：受控 CLI Runner 与结果收集

产物：

- 在现有 Process Provider Runner 基础上增加 CLI 版本探针、取消和进程组回收。
- stdin JSON、文件输入、JSON/JSONL/Markdown/文本输出。
- 标准输出诊断与业务结果分离。
- 完成后创建父子关系明确的派生 Artifact。

当前状态：ControlledCLIRunner 已支持固定 manifest 参数、临时运行目录、版本探针、取消、超时、进程组回收、环境白名单、输出上限和结果文件回收；AgentDispatchService 已创建结果 Artifact 并通过 fixture 及 Codex/Claude 真实 CLI Journey 验证。

测试：

- 成功、未安装、未登录、超时、崩溃、非法 JSON、输出超限和取消。
- 环境变量白名单、工作目录只读/读写和文件路径逃逸。

验收：全部失败夹具下 Runtime 可继续录音，输入 Artifact 哈希不变。

### M2-09d：首批外部 CLI 适配

产物：

- Codex CLI 专用适配器：版本锁定、输入方式、状态和结果解析。
- 第二个真实 CLI 适配器：优先 PI；若其非交互输出不满足契约，则选择另一已验证 CLI，并保留失败证据。
- 通用 CLI Fixture 只用于契约测试，不作为“支持所有 CLI”的产品宣称。

测试：

- 两个 CLI 的版本变化、未登录、审批等待、取消和输出差异。
- Woice 不读取两个 CLI 的密钥或配置文件。

验收：两个真实 CLI 各完成一次“转录素材 -> 派发 -> 返回 Artifact”Journey。

### M2-09e：外部 Agent 读取 Woice 上下文

产物：

- stdio MCP Bridge 的状态、列表、搜索、详情、转录和 Artifact 分页读取。
- 现有 PI Extension 补齐真实安装与交互验收。
- 本地 `woice` CLI 方案仅作为 RPC Client；若 MCP 已覆盖首发调用方，可后置实现。
- Caller、Artifact、分页范围、结果和时间审计。

当前状态：Woice v1 Unix Socket 已提供 woice.read_material、woice.search_materials 和 woice.read_material_page 只读契约，PI Extension/MCP Bridge 已暴露对应工具并通过 Node 契约测试；入站读取会写入元数据审计。`WOICE_RUN_REAL_INBOUND=1 make acceptance-agent-inbound` 已通过真实本机 MCP/RPC Smoke（5 个工具、11 条录音、分页读取）；`WOICE_RUN_EXTERNAL_AGENT_INBOUND=1 WOICE_EXTERNAL_AGENT_IDS=claude-cli make acceptance-agent-external-inbound` 已通过真实 Claude + MCP 合成 Fixture（4 个只读方法），真实用户素材入站仍需明确授权，Codex 外部入站仍需交互式批准。

测试：

- 未知方法、非法 Schema、超大输入、断连、超时和权限拒绝。
- `woice_record_start` 默认 `USER_GESTURE_REQUIRED`。
- Connector 无法直接读取 SQLite、Keychain 或任意文件。

验收：Codex 加至少一个外部 Agent 完成搜索和分页读取 Smoke。

### M2-09f：素材详情与任务 UI

产物：

- 录音详情在原始素材之后增加“发送给…”动作。
- 三步流程：目标 -> 素材与任务 -> 确认派发。
- 任务列表显示目标、输入、状态、耗时、失败动作和结果入口。
- 派生结果显示来源链；不成为新的聊天页。
- 设置新增“Agent 与连接”，与“模型与转写”分离。

当前状态：设置页已新增只读“Agent 与连接”分区，处理工作区已显示持久化 Agent Job 状态、更新时间和中断/失败事实；录音详情已提供三步“发送给…”派发、目标版本/信任提示、结果预览、复制和 Finder 入口；真实 Codex/Claude 出站与本机 MCP 入站 Smoke 已通过。连接器三级权限、审计和 fail-closed 契约已由 WCL-05 收口；外部 Agent 入站批准和完整可访问性矩阵只作人工提醒。

规格：[Agent 任务与连接状态 UI](../../specs/2026-08-23-agent-job-ui-status.md)

验证：

- 未配置 Agent、Agent 未安装、等待审批、完成、失败和取消状态。
- VoiceOver、键盘、深浅色、高对比和 Reduce Motion。
- 两名用户 3 秒盲测首先把 Woice 识别为录音/语音素材工具。

### M2-09g：权限、审计和 Agent 链保护

产物：

- 连接器只读、创建任务、控制已开始录音三级权限。
- 工作目录无/只读/读写范围确认。
- 外发目标、输入 Artifact 和数据类型确认。
- Agent 请求 Woice 再调用另一个 Agent 时默认二次确认。
- traceID、parentJobID 和最大 hop，防止循环派发。

当前状态：派发 Job 已保存 permissionSnapshotHash、traceID、parentJobID、hop/maxHop；出站请求、开始、完成、失败/取消及 PI 入站读取已写入 SQLite 元数据审计，审计不含原文、音频、Prompt 或结果正文。三步外发确认已覆盖目标、素材、数据类型、权限摘要和显式二次勾选；只读权限拒绝出站、录音控制关闭、重复幂等键、父任务自循环、hop 超限、路径逃逸、超时、取消、非零退出和输出超限已加入契约/Runner 测试。当前 PI 协议没有 Agent 再派发方法；若未来增加，必须重新创建用户确认任务，不能由外部 Agent 隐式链式调用。真实 CLI 循环攻击矩阵仍属于人工提醒。

测试：

- 相同 Agent 循环、两个 Agent 互调、重复请求、取消后重放已由 parent/hop/幂等/取消契约覆盖；真实 CLI 循环仍需人工 opt-in。
- 未授权目录、符号链接、环境密钥和超量结果已由 Manifest/Runner 失败矩阵覆盖。

验收：审计可以回答谁、何时、使用了哪些素材、交给谁、得到什么结果。

### M2-09h：端到端与兼容性验收

自动门禁：

```bash
make docs-check
make harness-check
make connectors-check
make acceptance-core
make verify
```

新增后执行：

```bash
make acceptance-agent-outbound
make acceptance-agent-inbound
make acceptance-agent-external-inbound
```

当前自动门禁：

- make acceptance-agent-outbound：运行本机 /bin/cat fixture，验证派发、结果 Artifact、审计和原始音频不变；真实 Codex/Claude 只有设置 WOICE_RUN_REAL_AGENT=1 后才允许单独启动。
- make acceptance-agent-inbound：运行 PI/RPC/MCP 只读契约；真实外部 Agent 调用保持显式 opt-in。

真实 Journey：

- Woice Offline 断网录音和转写，不配置 Agent。
- 一条转录发送给 Codex CLI并保存 Markdown 结果。
- 第二个 CLI 接收时间戳片段并返回结构化结果。
- Codex 通过 MCP 搜索 Woice 素材。
- 第二个 Agent 通过 MCP/RPC 分页读取转录。
- CLI 崩溃、未登录、等待审批、超限和用户取消。

退出：规格 AC-VC-001 至 AC-VC-009 的源码与自动契约门禁通过；真实 CLI 登录、交互批准、素材入站和 UI 可访问性保留人工 Journey，不作为核心发布阻塞。

## 6. 执行顺序

```text
录音核心与 M2-08 保持主线
              |
       M2-09a 契约
          ├─ M2-09b Context Package ─ M2-09c Runner ─ M2-09d CLI
          └─ M2-09e Inbound Tools
                 \                     /
                  M2-09f UI ─ M2-09g 安全
                              |
                          M2-09h 验收
```

M2-09a 只在 M2-08 发布验收和 R2 素材库退出检查通过后开始。优先顺序固定为：录音可靠性 -> 转写与模型 -> 素材管理 -> Agent 协作。

## 7. 里程碑判断

- CP1：未配置 Agent 的核心闭环无回归。
- CP2：Context Package 和受控 CLI Runner 通过失败矩阵。
- CP3：fixture 与两个真实 CLI（Codex/Claude）出站素材任务和结果回收已通过。
- CP4：本机 MCP/RPC 入站读取与 Claude 合成 Fixture Smoke 已通过；Codex 非交互批准链、两个 Agent 读取真实用户素材仍待明确授权/交互验收。
- CP5：UI、安全和真实 Mac Journey 通过。

任何单个 CLI 接通都只代表适配器完成，不代表“支持所有 AI CLI”。产品兼容承诺以已验证适配列表和通用协议边界为准。
