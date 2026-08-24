# Woice 模型接入与双版本发布开发计划

> 状态：核心代码与本机发行切片已完成，WCL-04 正式发行验证待凭据（本机 Speech + WhisperKit Tiny/Large 真实闭环、Provider 配置迁移/Registry、版本选择、下载任务、模型 Catalog 信任/回滚/轮换校验、受限 HTTPS 传输与多文件下载编排、Core/Offline 本地 DMG、三步首启引导和本机 ASR 服务预设已落地；Tiny/Large-v3 五类各 300 秒严格性能门禁、默认 Large-v3 路由、QuickTime 可见播放源下真实系统音频验收、最新 `make verify` 和此前稳定 Build `2026082408` 证据均已有记录；当前安装包为源码构建 `0.1.0 (Build 1)`；正式 Developer ID/公证、生产 Catalog、远程产物读回和真实桌面矩阵按 WCL 记录）  
> 日期：2026-08-22  
> 规格：[双版本分发与模型接入](../spec/2026-08-22-dual-edition-model-integration.md) · [会议双音轨与合并转写](../spec/2026-08-22-dual-track-meeting-transcription.md)  
> 设计：[模型接入与连接向导架构](../design/2026-08-22-model-onboarding-provider-architecture.md)  
> 全局状态：[当前路线图与计划迁移表](2026-08-22-current-roadmap-and-plan-transition.md)  
> 替代：旧 M1-03 的 WhisperKit/ASR 路由、M1-05 的模型与 ASR 设置、M1-07 的双发行门禁  
> 保留：现有录音、Artifact、Job/Lease、自定义 ASR HTTP、系统 TTS 兼容行为  
> 迁移：通用 LLM/Markdown 新能力与 Agent 使用交给 M2-09；MCP 不在本计划实施  
> 停止：在本计划新建 LLM/TTS Registry、Agent CLI 或 Agent 设置入口  
> 顺序：R0 核心收口后执行；完成后进入 R2 素材库收口，再进入 M2-09

> 定位关系：M2-08 继续作为录音转文字核心计划执行；外部 Agent 对素材的使用由后续 [M2-09](2026-08-22-voice-context-agent-integration.md) 承接，不能反向阻塞离线录音与转写。

转写路由末次更新：设置页已保存的转写目标现在是唯一真相源。新设置和旧 `automatic` 默认使用本机模型；下载、导入或切换已安装模型会激活本机路线；只有用户明确选择自定义服务才使用 Endpoint/模型 ID。麦克风、系统声音、meetingMix、导入素材和失败任务重试共用该规则，任务快照记录实际 Provider。

当前收口事实（2026-08-24）：旧段落中的 176 项测试与 Build `2026082324` 属于历史记录；最新官网版为 201 项 Swift 测试 / 13 个 Suite，Store 条件为 179 项 / 10 个 Suite，当前安装包为源码构建 `0.1.0 (Build 1)`；此前稳定包 Build `2026082408` 保留为历史证据。正式 `Woice.xcodeproj` 的 Store 无签名构建、模型发行门禁和本机 Store Bundle 预检通过。正式 Developer ID/公证、生产 Catalog/远程 manifest 读回、Store 签名 Archive 和真实桌面矩阵按 WCL-04/WCL-06 及非开发提醒记录。
以下“当前实现进度”段落保留为历史累积记录，不覆盖上面的 2026-08-24 收口事实。

当前实现进度：AppSettings 已迁移到统一 `ASRProviderConfiguration`（旧设置字段兼容读取，API Key 仍只进 Keychain）；有限可信 ASR Registry 发布 Provider、能力、数据位置和健康状态，设置页显示能力状态。停止录音后的本机路径可使用 macOS on-device Speech 或已安装 WhisperKit；ProcessingTask 保存 Provider、模型、版本、位置和不含 API Key 的 `sha256-v1` 配置摘要；设置页可显式下载固定 revision 的 WhisperKit Tiny/Large、查看进度和实际模型，并提供四个只填草稿的 loopback OpenAI-compatible 本机服务预设；外部 Endpoint 仍保留逐次确认。设置页现在按录音与输入、模型与转写、文件与隐私独立保存，识别语言使用原生 Picker 且新设置默认为“自动检测”，其他分区的非法草稿不会阻塞当前分区，普通保存不触碰 Keychain。录音开始前会检查保存卷最低可用空间，低于 256 MiB 时 fail-closed；录音期间已关闭的本机 VAD 片段现在会原子写入耐久 sidecar，异常退出可恢复部分原文且不覆盖原始 WAV。当前机器已通过所有专项验收：`make acceptance-core`、`make acceptance-meeting`、`make acceptance-meeting-transcription`、`make acceptance-interruption`、`make acceptance-settings`、`make acceptance-material`、`make acceptance-recovery`、`make acceptance-catalog`、`make acceptance-local-provider` 和 `WOICE_OFFLINE_MODEL_ROOT="/Users/water/Library/Application Support/Woice" make acceptance-offline-model`；其中可见 QuickTime 播放源下的 `make acceptance-meeting` 已验证窗口级可听系统音频、CAF 与 meetingMix。`TranscriptArtifact` 版本链已接入首次转写、Large 重转写、来源分离转写和历史版本切换，原文与模型快照可导出且不覆盖旧版本。Tiny/Large-v3 通过五类各 300 秒严格性能矩阵，未显式选择时默认路由冻结为 Large-v3；系统音频启动会把“屏幕录制权限未授权”“没有可共享显示器或窗口”和其他运行时失败分开报告；请求权限后的当前实例 TCC 复核失败时，设置页现在显示“需要重新授权当前安装包”并说明旧版 ad hoc 授权边界；全桌面、多窗口、真实会议应用、真实人工语料准确率和睡眠/设备变化/长录音矩阵仍需真实桌面复验。录音 Journal 恢复、模型发现、R2 搜索/外部打开也已通过目标测试。模型 Catalog 已具备版本、条目唯一性、Ed25519 签名、公钥信任根、版本回滚保护、签名历史重放、密钥轮换/撤销、受限 HTTPS 拉取和多文件下载编排；设置页提供显式更新与发行版条目下载入口，未配置发行版信任根时保持禁用；Core/Offline 本地 DMG 均已由 `make verify-core` / `make verify-offline` 的 `hdiutil verify` 校验；首次启动已改为三步可跳过引导。最新 `make verify` 通过 176 项 Swift 测试、6 项 PI、2 项 MCP、文档/Harness/lint 和生产构建；上述 Build B `2026082324` 为历史安装证据，当前 `/Applications/Woice.app` 为源码构建 `0.1.0 (Build 1)`，正式发布仍需 Developer ID/公证和完整覆盖安装/干净账户矩阵。

历史执行覆盖（2026-08-23）：上段历史计数由当时的 183 项 Swift 测试 / 11 个 Suite、PI 6 项、MCP 2 项和稳定签名 Build B `2026082332` 覆盖；导入页、处理任务列表、侧栏和可继续入口共用 `ProcessingTaskProjection`，VoiceOver 标签与活动任务状态一致，空文件/损坏视频/无音轨视频 fail-closed、正常音频导入、启动/AX/键盘 Journey 和 A/B 覆盖安装已通过。后续正式发行、真实会议准确率、真实用户长文件、真实 Provider 失败重试和长时稳定性已按当前 WCL/人工边界归档。

末次更新（2026-08-24，覆盖上句的历史计数）：在上述门禁后又加入可读取部分录音的保留策略及回归测试；本轮另完成 Tiny/Large-v3 五类各 300 秒严格性能矩阵、默认 Large-v3 启动路由冻结、测试专用真实临时钥匙串隔离和完整总门禁。最新 `make verify`、`make install`、`make verify-core` 和 `WOICE_OFFLINE_MODEL_ROOT="/Users/water/Library/Application Support/Woice" make verify-offline` 均通过；生产 Developer ID/公证/Catalog 与远程 manifest 读回仍按 WCL-04 等待真实凭据，真实视觉/TCC/长时矩阵仅作人工提醒。

系统音频末次更新：随后加入窗口级 ScreenCaptureKit 回退和 `systemAudioCaptureTarget` 持久化；验收脚本已改为由可见 QuickTime 循环播放临时音频，最新 `make acceptance-meeting` 通过（15.432 秒），验证窗口级可听系统声音、CAF 和 meetingMix。全桌面/多窗口/真实会议应用仍需真实桌面覆盖验收。完整 Swift 回归已执行 144 项并通过；login Keychain 的真实用户密码/解锁状态不作为自动化门禁的隐式前置条件。

| 工作包 | 当前状态 | 证据/剩余边界 |
|---|---|---|
| M2-08a 契约与迁移 | 代码与自动测试完成，跨版本真实迁移与发行验收待完成 | ModelPackManifest/DistributionManifest、路径与 SHA-256 校验、ProcessingTask 等待模型语义、用户选择的模型版本、`AudioTrackKind/sourceTrack`、`MeetingTranscriptionMode`、`RecordingMaterialStatus`、统一 `ASRProviderConfiguration`、`TranscriptionLanguageOption`、`TranscriptArtifact`、不含 API Key 的 `sha256-v1` 配置摘要和旧数据兼容已落地；数据库迁移与真实跨版本数据矩阵仍待发布验收 |
| M2-08b Registry/Router | 代码与自动门禁完成，真实会议 UI 矩阵待验收 | macOS on-device Speech、downloaded/bundled WhisperKit Adapter 可按用户选择版本路由并保留模型快照；有限可信 ASR Registry、能力/数据位置/健康状态和设置页状态投影已接入；meetingMix 准备、默认来源分离 Router、`standardMix` 显式兼容路由、来源分离确认队列和系统 CAF -> WAV 准备层已接入；本机/局域网模型发现与四个 loopback 本机服务预设已接入；系统音频有显示器时全桌面、无显示器时窗口级目标回退已实现，QuickTime 可见播放源下最新 `make acceptance-meeting` 通过；全桌面、多窗口与真实会议应用 UI 矩阵仍待完成 |
| M2-08c WhisperKit | Tiny/Large 真实本机转写和五类性能门禁已验证 | `argmax-oss-swift` 1.0.0 精确 revision、Tiny 与 Large-v3 候选目录/Tokenizer revision 已固定；Tiny 真实麦克风闭环、Large 已安装 WAV 重转写、五类各 300 秒严格矩阵和默认 Large-v3 路由冻结通过；turbo/small 候选、真实会议/人工语料准确率和睡眠唤醒/内存压力仍待完成 |
| M2-08d 模型包存储 | 代码与本机门禁完成，生产 Catalog 服务验收待完成 | bundled/downloaded inventory、原子 current、路径/符号链接/SHA-256 门禁、流式哈希、显式 Range 续传/空间检查、SQLite durable download task、官方 WhisperKit 显式下载/打包、活动任务取消/暂停和非当前版本删除已实现；Catalog schema、条目唯一性、Ed25519 验签、签名历史重放、版本回滚、密钥轮换/撤销、HTTPS host allowlist、响应边界、设置页显式更新入口、签名条目下载根地址校验、逐文件下载和原子安装已落地；生产 Catalog host/key 配置、真实发行服务上的多文件下载仍待完成 |
| M2-08e-i | 核心代码与本机发行切片完成，外部发布与真实桌面验收待完成 | Core/Offline ad hoc App、发行清单、本地 DMG 与 Offline bundled 路由已实现；本机/局域网 `/v1/models` 主动发现、四个 OpenAI-compatible 本机服务预设、设置页模型选择、语言 Picker、三步可跳过首启引导、显式 Catalog 更新入口、五类 300 秒严格性能报告和默认 Large-v3 路由已接入；生产 Catalog host/key 配置、真实服务连接、Developer ID/公证、Store 签名 Archive、干净账户覆盖安装、真实会议/人工语料准确率和六条真实 UI Journey 仍待完成 |

## 1. 计划目标

在不分叉产品、不破坏现有录音/Artifact/Job/RPC 闭环的前提下，交付：

- `Woice Core`：小体积，不带第三方权重，可连接用户已有模型或主动下载推荐模型。
- `Woice Offline`：随包包含默认 WhisperKit ASR，断网开箱即用。
- ASR 模型与转写设置、三步连接向导、健康检查、下载和磁盘管理。
- 内置 Swift、OpenAI-compatible HTTP、受控进程三类 ASR Provider 的统一注册和显式路由。
- Core/Offline 双向覆盖安装、模型损坏、服务失败和下载中断下的恢复证据。

本计划编号为 `M2-08`，承接已实现的 M2-03c durable Job、M2-07 Provider Manifest/Runner/Trust 和现有自定义 ASR HTTP 契约。系统朗读维持现状，通用 LLM 后续处理由 M2-09 承接。

## 2. 成功标准

- 离线版在 M1 16 GB、macOS 14、断网环境完成录音到原始转录，RTF ≤ 1.0。
- 轻量版无模型时仍可靠保存和复听；连接模型后无需重新录音即可补转录。
- 已发现本机服务的用户最多三步完成启用；主流程不要求手填 Endpoint/模型 ID。
- 切换 Provider 只改配置和 Profile，不改 Pipeline 业务代码。
- 所有 Job 保存 Provider/模型/数据位置快照；本地失败不自动转云端。
- 两个发行包分别签名、公证、Gatekeeper、干净安装、覆盖安装通过。
- 第三方代码、权重、Tokenizer 和 Notice 全部有版本、来源、许可证、哈希和 SBOM 记录。

## 3. 范围与优先级

### P0：首发必须

- Provider/模型配置契约和旧设置迁移。
- ASR ProviderRegistry、显式路由和等待转写模型状态。
- WhisperKit 默认 ASR 与模型包存储。
- Core/Offline 双发行产物。
- 模型与转写设置页、连接向导、无模型录音后恢复。
- OpenAI-compatible 本机服务预设、模型列表发现和健康检查。
- 推荐模型可恢复下载、哈希/签名校验、删除和空间提示。
- 完整自动测试、真实 Mac 基准和发布验收。

### P1：首发后一个小版本

- 局域网服务的用户指定发现和更细权限。
- 模型 Catalog 更新、版本锁定、回滚和差分下载评估。

### 不在本计划

- 任意模型文件自动识别和推理。
- Voice cloning 产品流程。
- 自动安装 Docker、Python、Homebrew 或模型运行时。
- Provider 市场、第三方自动更新和任意网络扫描。
- Mac App Store 沙箱分发。

## 4. 当前基础与缺口

| 能力 | 当前事实 | 本计划补齐 |
|---|---|---|
| 自定义 ASR HTTP | 已支持根地址/完整路径、模型、Keychain、multipart、健康测试和主动模型发现 | 抽成 Provider Configuration、更多本机预设和完整能力探测 |
| macOS on-device Speech | 本轮已接入停止后文件转写与模型快照 | 真实 Speech 授权/中文语音 Journey；后续 WhisperKit 替换 Provider 实现 |
| 系统朗读 | 已支持朗读、暂停、继续、停止 | 保持现状，不进入 ASR 模型路由 |
| Provider SDK | Manifest、来源、信任、受控 Runner 已有基础 | Registry、能力协议、安装/UI 和真实 Provider Fixture |
| Job/Lease | SQLite/WAL、幂等 Job、恢复和前台确认队列已有基础 | 增加等待 Provider、模型下载 Job 和配置快照 |
| 设置 UI | 原生侧栏、独立草稿、APIKeyField、健康检查 | 改为能力概览 + 三步向导 + 已安装模型管理 |
| 打包 | 单一 `make package`、ad hoc strict 签名 | Core/Offline 两产物、模型资源清单、正式签名公证 |
| WhisperKit | Tiny/Large-v3 已接入真实 Runtime | 精确依赖/模型 revision、离线 tokenizer、模型清单/SHA-256、真实录音闭环、五类 300 秒性能门禁和默认 Large-v3 路由已通过；真实人工语料准确率、睡眠唤醒/内存压力和正式双发行仍待完成 |

## 5. 技术决策门禁

进入实现前冻结以下记录：

| 决策 | 默认 | 退出条件 |
|---|---|---|
| 默认 ASR | WhisperKit large-v3 626MB 候选 | M1 16 GB 实测满足 RTF/内存/准确率；否则评估 turbo/small |
| WhisperKit 版本 | 不预写浮动版本 | 锁定精确 tag/commit，复核 MIT、NOTICES 和 Swift 6/macOS 14 |
| 模型来源 | 官方 Argmax/OpenAI 对应模型仓库 | URL、commit/revision、哈希、许可证归档 |
| Core 是否可下载默认模型 | 是 | 产品评审确认；否则首次体验不达标 |
| 模型 Catalog | 首版静态签名清单 | 签名、公钥轮换和回滚策略通过安全评审 |
| 数据位置分类 | on-device/LAN/cloud | loopback/私网/公网 Fixture 契约通过 |
| 发行 Bundle ID | 两版相同 | 权限、覆盖安装、更新工具验证通过 |

任何非 MIT 依赖或模型权重在进入实现前新增 ADR；未批准则从 P0 移除，不用“仅测试”绕过分发门禁。

## 6. 组件与影响面

### 6.1 WoiceCore

- Provider capability 常量和兼容规则。
- Provider Configuration、Model Descriptor、ModelPackManifest、Model Installation 状态。
- 数据位置、健康状态、配置快照和稳定错误码。
- 旧 `AppSettings` 解码兼容与迁移输入结构。

### 6.2 WoiceApp/Runtime

- ProviderRegistry Actor。
- ProviderRouter 和 Profile 默认路由。
- ModelPackStore、ModelDownloadCoordinator、LocalServiceDiscovery。
- BuiltInWhisperProvider、OpenAI-compatible Adapter、ProcessProviderAdapter。
- ProviderHealthCheckService 和固定无隐私 Fixture。
- 处理任务等待 Provider、换模型重试和批量补转录编排。

### 6.3 WoiceUI

- 首次启动第三步按模型库存渲染。
- “服务”改为“模型与转写”，显示 ASR 路由；Agent 连接由 M2-09 使用独立设置分组。
- ProviderConnectionWizard、模型下载/校验/删除、数据位置 Badge。
- 录音详情“等待选择模型”和补转录动作。

### 6.4 Storage/Packaging

- SQLite Provider/Model 表或受控 JSON 列及迁移。
- Application Support 模型目录、下载临时目录和原子 current 指针。
- Core/Offline DistributionManifest、资源复制、双 DMG、双签名/公证。
- Notices、SBOM、模型许可证清单和哈希清单。

### 6.5 不应修改

- 原始音频不可变和 SHA-256 规则。
- Connector 只走 WoiceRPC 的边界。
- 录音用户手势、可见状态和云端外发授权。
- 当前 SQLite/WAL 作为事务真相源的决定。
- 不加载任意动态库的规则。

## 7. 工作包

### M2-08a：契约、Schema 与迁移

依赖：现有 M2-03c、M2-07。

产物：

- 冻结 Provider capability、transport、data location、health、model installation 枚举。
- ModelPackManifest v1 和 DistributionManifest v1 Schema。
- Provider Configuration 持久化；Keychain 只保存 credential。
- 把旧 ASR Endpoint、模型和 Keychain account 幂等迁移为默认配置；旧 LLM 设置保留兼容，不进入新 ASR Registry。
- ProcessingTask 增加“等待选择模型”语义和可选 block reason；不是失败或运行中。
- Job 配置快照包含 Provider ID、模型 ID、版本、位置、能力和参数哈希。
- 在既有 Recording/TranscriptSegment/ProcessingTask 契约上增加 `AudioTrackKind/sourceTrack`，旧记录缺失时按麦克风兼容。
- 新增 `MeetingTranscriptionMode.standardMix/sourceSeparated`，新安装和未显式选择的会议默认 `standardMix`，模式写入 Job/Transcript 快照。
- 转写 Job 幂等键改为 recording + kind + sourceTrack，不再只按单一 transcription kind 更新任务。

测试先行：

- 旧设置空/完整/损坏/重复迁移。
- 未知 Schema major、路径穿越、符号链接、重复 packID、非法能力。
- Keychain 写入失败时配置和默认路由均不提交。
- 历史 Recording/Job 解码兼容。
- 旧单轨、旧双轨未转写、缺失 `sourceTrack` 的 Segment/Task 解码兼容。

验收：`make test`、`make docs-check`、`make harness-check`；迁移失败保留旧配置可用。

预计：3-5 个工程日，已包含轨道 Schema、幂等键与旧数据兼容增量。

### M2-08b：Provider Registry 与显式路由

依赖：M2-08a。

产物：

- 在 App 组合根注册 HTTP ASR、进程 ASR；暂用 Fake Whisper Provider 打通契约。
- Registry Actor 发布已安装、已配置、健康和能力状态。
- Router 按 Profile -> capability default -> waitingForProvider 决策。
- 本机/局域网/云端授权策略由 DataLocation + Policy 决定。
- 运行中 Job 保留快照；“换模型重试”创建新尝试/派生 Transcript，不覆盖原文。
- 受控音频准备层对齐麦克风 WAV/系统 CAF，以固定增益和防削波生成可重建 meetingMix，再转为 Provider 支持的临时 WAV；不覆盖原轨。
- Router 在 `standardMix` 只创建一条 `transcription:meetingMix` Job；只有一轨有效时直接转写该轨的标准化输入。
- Router 在 `sourceSeparated` 才为每条有效原轨创建独立 Job，本机首版串行处理。
- 外部 ASR 确认显示实际文件/请求数：`standardMix` 为 1，`sourceSeparated` 为 2；过去的麦克风单轨授权不扩展到 meetingMix 或系统轨。

测试先行：

- 两个 ASR 切换不改 Pipeline。
- 本地失败不访问已配置云端 Provider。
- 默认 Provider 删除、禁用、能力不足时进入等待状态。
- 历史 Job 重试仍可复用原快照或显式换模型。
- 只有麦克风、只有系统声音、双轨标准模式、双轨来源分离和单轨失败路由均有确定任务状态。

验收：Domain/Runtime 新增代码行覆盖率 ≥ 90%；无 `@unchecked Sendable`。

预计：7-10 个工程日，已包含 meetingMix 准备、默认来源分离路由、`standardMix` 兼容模式和外部确认增量；仅作历史估算。

### M2-08c：WhisperKit Spike 与默认模型冻结

依赖：M2-08a，可与 M2-08b 后半段并行，但不能同时修改 Domain 契约。

产物：

- 锁定 WhisperKit 精确版本、模型 revision、许可证、Notice 和 SBOM。
- BuiltInWhisperProvider Adapter；输入标准 WAV/分段，输出标准 Transcript/时间戳。
- 候选 large-v3、turbo、small 的固定样本基准报告。
- 首载、预热、卸载、内存压力、睡眠唤醒和损坏模型行为。
- 冻结默认模型与低资源替代模型。

固定测量：

- M1 16 GB、macOS 14 最新小版本。
- 中文、英文、中英混合、静音、噪声各一份；5 分钟性能样本。
- 记录 CER/WER、RTF、首载时间、峰值内存、磁盘大小、能耗/温度观察。

退出门槛：

- 默认模型 RTF ≤ 1.0、峰值内存 ≤ 4 GB。
- 静音不产生长段幻觉；空输出不标记成功。
- 断网运行不产生网络连接。
- 原始 WAV SHA-256 前后不变。

预计：4-6 个工程日；若依赖或 Core ML 转换失败，响亮记录原错并暂停默认模型冻结。

### M2-08d：模型包存储、下载与完整性

依赖：M2-08a、M2-08c 清单样本。

产物：

- bundled/downloaded inventory、优先级和版本锁定。
- 静态签名 Catalog、逐文件下载、进度、暂停/恢复、校验和原子 current。
- 空间检查、旧版本保留、删除和重新下载。
- 模型目录权限和禁止可执行文件/符号链接门禁。
- 下载 Job 使用现有 SQLite/Lease/幂等基础；App 重启后恢复为可解释状态。

测试先行：

- 正常、断网、HTTP Range 不支持、磁盘不足、SHA 不符、签名不符、App 强退。
- 更新失败继续使用旧版本。
- 同一 pack 并发下载只能有一个 Lease。
- 删除当前模型先确认替代路由，不触碰用户 Artifact。

验收：下载成功状态只在原子提交后出现；失败路径无半安装目录被 Registry 识别。

预计：4-6 个工程日。

### M2-08e：Core/Offline 双发行打包

依赖：M2-08c、M2-08d。

产物：

- 同一 Release binary 注入 Core/Offline DistributionManifest。
- Offline 把默认模型直接置于 App Resources；Core 不带权重。
- `package-core`、`package-offline`、双 DMG 和产物清单。
- 两包相同 Bundle ID/version/build；模型资源之外二进制哈希一致。
- 正式 Developer ID/Notarization 流程支持两个产物。

发行预算：

- Core DMG ≤ 150 MB。
- Offline DMG ≤ 1 GB。
- Offline 未加载模型时的空闲内存相对 Core 增量 ≤ 50 MB。

验收矩阵：

- Core 干净安装、Offline 干净安装。
- Core -> Offline、Offline -> Core、旧版本 -> 新版本。
- 四条路径均保留数据库、Keychain、用户下载模型和 TCC 身份。
- `codesign --verify --deep --strict`、`spctl --assess`、Notarization/staple 通过。

预计：2-3 个工程日，不含外部证书等待。

### M2-08f：本地服务发现、预设和模型列表

依赖：M2-08b。

产物：

- 用户点击触发的 loopback allowlist 探测；总超时 ≤ 5 秒。
- Generic、whisper.cpp、faster-whisper、FunASR/LocalAI ASR 预设。
- `/v1/models` 能力；不支持时手动模型字段回退。
- Endpoint 自动补全继续复用现有 API Client；预设差异放 Adapter，不散落 UI。
- DataLocation 分类和保存前确认。

测试先行：

- 至少两个真实 loopback HTTP Fixture 同时存在、端口占用、慢响应、错误模型列表。
- 未点击扫描前零探测请求。
- 自定义公网 Endpoint 不被标成“这台 Mac”。

验收：发现服务连接不超过三个主步骤；健康测试只使用临时 Fixture。

预计：3-5 个工程日。

### M2-08g：首次启动与“模型与转写”UX

依赖：M2-08b、M2-08d、M2-08f，可在 Fake Runtime 上先行。

产物：

- 首次启动第三步按 Registry inventory 渲染，不读取发行 Flavor 分支。
- 三步 ProviderConnectionWizard。
- ASR 能力行、模型列表、下载状态、位置 Badge、持久错误。
- 识别语言使用原生 Picker；默认“自动检测（推荐）”，旧语言代码可读化且未知值保留。
- 保留设置草稿隔离：编辑不立即改变下一次录音路由。
- 无模型录音后的安全状态、详情补转录和批量待处理确认。
- VoiceOver、键盘、高对比、Reduce Motion。

UI 文案门禁：

- 主文案使用“语言转文字、这台 Mac、局域网设备、云端”。
- 错误说明发生什么、录音是否安全、下一步。
- `Endpoint`、`Provider`、`Manifest` 只出现在高级区或诊断。

验证：

- XCUITest/Fake Runtime 覆盖 Offline/Core/无模型/下载失败/本机服务失败。
- 解锁真实桌面完成六条设计 Journey。
- 两名首次用户 3 秒盲测通过。

预计：4-6 个工程日。

### M2-08h：素材就绪状态与 M2-09 交接

依赖：M2-08b、M2-08g。

产物：

- 转写完成后形成可复听、可搜索、可引用的原始 Transcript Artifact；录音详情已支持原始音频、TXT、时间戳 JSON 和 Markdown 的开放导出。
- 素材库和详情页使用 `RecordingMaterialStatus` 从持久化 RecordingRecord/ProcessingTask 投影“已保存、等待模型、处理中、素材已就绪、部分就绪、失败但安全”状态；不依赖页面内存状态。
- `standardMix` 完成后形成一份标准会议 Transcript Artifact，来源记为 meetingMix，不伪造句级原轨标签。
- `sourceSeparated` 的有效轨全部成功后形成带原轨来源的合并 Transcript；一轨失败时保留已完成原文并标记部分完成。
- 来源分离有时间戳时按共享 Session 时间线合并；Provider 无时间戳时保留“我的麦克风/电脑声音”分区原文，不使用 LLM 猜测顺序。
- 用户从标准模式改用来源分离重转写时创建新 Transcript Artifact，两个版本都可回看，不覆盖。
- 无模型录音在补转写完成后从“等待选择模型”进入“素材可用”。
- 通过现有 RPC 的 `woice.read_material` 暴露只读 Artifact 引用，为 M2-09 Context Package 提供稳定输入；请求只读取已持久化内容，不触发外发或处理。
- 当前系统朗读行为不回归，但不纳入 Provider Registry。

当前状态：状态投影、开放导出、来源分离部分就绪表达、详情外部打开、现有 Unix Socket 的 `woice.read_material` v1 只读契约和 PI `woice_read_material` 工具已实现并通过协议/PI Router/Node 测试；真实重启后 UI Journey、MCP 搜索/分页、真实 PI 安装、Context Package/派发仍待完成。

验证：没有 Agent 时素材就绪状态完整；RPC 读取不依赖 M2-09 派发实现。

预计：3-5 个工程日，已包含标准/来源分离原文版本、部分完成、时间线合并与无时间戳降级。

### M2-08i：端到端、性能、安全与发布验收

依赖：全部 P0 工作包。

自动门禁：

```bash
make docs-check
make harness-check
make format
make lint
make test
make acceptance-core
make acceptance-whisperkit
make verify
make verify-core
# Offline 需要显式提供已验证模型目录：
WOICE_OFFLINE_MODEL_ROOT="/path/to/Models" make verify-offline
# 完整五类长音频矩阵（默认每类至少 300 秒）：
WOICE_BENCHMARK_AUDIO_DIR="/path/to/benchmark" make model-benchmark-strict
```

实现双发行后增加并执行：

```bash
make verify-core
make verify-offline
make acceptance-offline-model
make acceptance-local-provider
```

真实验收：

- M1 16 GB/macOS 14：默认模型基准和 60 分钟录音后转录。
- 至少一台 8 GB Apple Silicon：低资源模型/无模型录音体验。
- macOS 15：覆盖安装、系统 TTS、会议能力不回归。
- 真实会议：同时播放电脑声音和本机说话，验证双原轨、默认来源分离转写、`standardMix` 兼容单次转写、时间线合并和单轨重试；本机契约门禁 `make acceptance-meeting-transcription` 已通过，但真实会议应用和桌面 Journey 仍未完成。
- 断网、睡眠唤醒、磁盘不足、模型损坏、Provider 崩溃、App 强退。
- Core/Offline 两个公证产物在干净用户账户打开，无隔离属性异常。

安全检查：

- 模型目录无可执行位、符号链接和路径逃逸。
- 日志/SQLite/RPC/诊断包无 API Key、完整音频、完整转录。
- 本机扫描只访问明确 allowlist；云端目标需要外发授权。
- Provider 输出非法 Schema、超时、崩溃、超限时 Runtime 保持可用。

退出：规格 AC-MI-001 至 AC-MI-012 全部有证据；任何未完成真实 Mac/签名项保留为未完成，不以 Mock 替代。

预计：6-8 个工程日，已包含双原轨、默认来源分离转写、`standardMix` 兼容单次转写和真实会议 Journey；仅作历史估算。

## 8. 依赖与执行顺序

```text
M2-08a 契约/迁移
  ├─ M2-08b Registry/Router ─ M2-08f 本地服务 ─┐
  │                         └─ M2-08h 素材就绪 │
  └─ M2-08c WhisperKit ─ M2-08d 模型包 ───────┤
                             └─ M2-08e 双发行   │
M2-08b + M2-08d + M2-08f ─ M2-08g UX ─────────┤
                                               └─ M2-08i 发布验收
```

检查点：

- CP1：M2-08a/b 后，Fake Provider 可切换且旧设置迁移通过。
- CP2：M2-08c 后，默认模型有真实基准和许可证决定。
- CP3：M2-08d/e 后，两个本地发行包可安装并识别库存。
- CP4：M2-08f/g/h 后，六条用户 Journey 完整。
- CP5：M2-08i 后，签名公证产物和验收证据齐全。

M2-08 合并会议转写增量后，P0 顺序执行约 36-54 个工程日；这是唯一模型/会议 ASR 工期基线，不再与双轨规格或升级门禁文档的估时相加。可并行压缩，但同一时间只能有一个任务修改 Domain 契约或数据库迁移。

## 9. 测试矩阵

### 9.1 Provider Contract

- built-in、HTTP、process 三种 transport。
- ASR 能力匹配与不匹配。
- 成功、超时、401/403、404 model、429、5xx、非法 JSON、空输出、超限输出。
- loopback、LAN、public host 数据位置。

### 9.2 Model Pack

- bundled、downloaded、两者同版本、用户锁定旧版本。
- 正常、缺文件、哈希错、签名错、路径穿越、符号链接、可执行位。
- 下载暂停、恢复、取消、强退、磁盘不足、旧版本回滚。

### 9.3 UI Journey

- Offline 开箱、Core 发现、Core 下载、Core 稍后配置。
- 无模型录音、单条补转录、批量待处理。
- Provider 切换、删除当前模型、云端首次授权拒绝。
- VoiceOver/键盘/高对比/深浅色/Reduce Motion。

### 9.4 Release

- 两发行包 binary/version/Bundle ID 一致性。
- 模型资源差异、Notices/SBOM、DMG 体积。
- 签名、公证、Gatekeeper、干净安装、双向覆盖、升级和卸载重装。

## 10. 性能预算

| 指标 | 门槛 |
|---|---|
| 默认 ASR RTF | ≤ 1.0，M1 16 GB/macOS 14 |
| 默认 ASR 峰值内存 | ≤ 4 GB |
| Provider 本机发现总时长 | ≤ 5 秒 |
| 健康检查 | 本机 P95 ≤ 3 秒；云端 P95 ≤ 10 秒，不含用户网络故障 |
| Registry 冷启动库存扫描 | P95 ≤ 500 ms，不加载模型权重 |
| Core DMG | ≤ 150 MB |
| Offline DMG | ≤ 1 GB |
| 模型未加载空闲内存差 | Offline 相对 Core ≤ 50 MB |
| 下载进度持久化 | 至少每 1% 或 2 秒一次，取更稀疏者 |

## 11. 发布与回滚

### 11.1 发布顺序

1. 内部 Core Alpha：迁移、HTTP Provider、无模型状态。
2. 内部 Offline Alpha：WhisperKit、bundled pack、断网闭环。
3. 双发行 Beta：下载 Catalog、覆盖安装和六条 Journey。
4. Release Candidate：正式签名、公证、Notices/SBOM、性能报告。
5. 同版本发布 Core/Offline；发布页明确推荐用户类型和实际文件大小。

### 11.2 回滚

- App 回滚不降级数据库；迁移必须前向兼容至少一个版本。
- 模型更新采用并存+原子 current，失败切回上一已验证版本。
- Catalog 可撤销某版本，但不远程删除用户文件；标记风险并要求用户确认停用。
- 默认 Provider 失效时进入等待选择，不自动切其他 Provider。

## 12. 风险清单

| 风险 | 影响 | 控制 |
|---|---|---|
| WhisperKit/模型实际性能不达标 | Offline 不开箱 | M2-08c 先冻结，准备 turbo/small 备选 |
| 模型资源使每次 App 更新过大 | 下载成本高 | 首版接受；后续评估模型外置和差分，不阻塞 P0 |
| 两发行包让用户困惑 | 选错包/重复下载 | 发布页默认推荐 Offline；App 内能力一致；Core 可一键补模型 |
| 本地服务协议“兼容但不完全一致” | 健康成功、任务失败 | 预设契约 Fixture、能力探测、保留 Generic 手动模式 |
| 下载中断或损坏 | 无法转录/磁盘残留 | durable Job、逐文件校验、原子切换、旧版本保留 |
| 非 MIT 权重/依赖 | 无法商用分发 | 依赖/模型独立门禁，未批准不进 Offline |
| 任意进程 Provider 扩大攻击面 | 本机代码执行风险 | 延续 Manifest、签名、环境白名单、工作目录和输出限制 |
| Core 覆盖 Offline 后 bundled 模型消失 | 默认路由断开 | 启动库存重建、明确提示和一键下载，无云端兜底 |
| Voice cloning 被滥用 | 法律与信任风险 | 本计划不启用，另立授权与水印规格 |

## 13. 文档与交付物

每个工作包必须同步：

- 对应 spec/ADR/Schema 和契约 Fixture。
- `doc/log/YYYY-MM-DD.md` 的命令、结果、未验证项。
- `doc/log/INDEX.md` 一句话指针。
- 模型基准报告、许可证记录、Notices、SBOM 和发行哈希。
- Core/Offline DMG 的签名、公证和覆盖安装证据。

不得把“代码已编译”“Mock 已通过”“包已上传”写成真实模型、真实 Mac 或生产发布已完成。
