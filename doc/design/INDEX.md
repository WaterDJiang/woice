# design/ 索引

| 决策 | 状态 | 结论 | 文件 |
|---|---|---|---|
| 语音上下文与 Agent 协作 | 设计基线 | Voice Context Core 居中；Agent 只负责素材后的处理或授权读取，不成为产品主入口 | [2026-08-22-voice-context-agent-collaboration.md](2026-08-22-voice-context-agent-collaboration.md) |
| 模型接入、连接向导与双版本架构 | 设计基线；本机 Adapter、版本选择和 Core/Offline ad hoc 已实现 | 两版只差模型库存；能力优先连接向导统一本机模型、OpenAI-compatible 服务和受控进程 Provider | [2026-08-22-model-onboarding-provider-architecture.md](2026-08-22-model-onboarding-provider-architecture.md) |
| Argmax OSS / WhisperKit 依赖 | Tiny 权重已验收；默认模型与正式发行待门禁 | 精确使用 argmax-oss-swift 1.0.0 的 WhisperKit product；Provider 隔离，MIT/Apache Notice 与 SBOM 不得省略 | [2026-08-22-argmax-oss-whisperkit-dependency.md](2026-08-22-argmax-oss-whisperkit-dependency.md) |
| 架构、技术栈、组件、UI/UX 基线 | 已实施，待真实 UI 验收 | Swift 模块化单体；连接器只走本地 RPC；macOS 原生界面 | [开发计划第 4-8 节](../plan/2026-08-22-m0-mvp.md#4-技术栈) |
| 设置页 UI/UX | 已实施，待解锁桌面人工 Journey | 侧栏分组、独立设置草稿、ASR 健康检查、Keychain 字段和可执行错误文案 | [2026-08-22-settings-ui-ux.md](2026-08-22-settings-ui-ux.md) |
| 音频回调写入并发边界 | 已采用 | 实时回调使用锁保护写入器和串行队列，不跨 MainActor；`@unchecked Sendable` 限定在边界 | [2026-08-22-system-audio-buffer-concurrency.md](2026-08-22-system-audio-buffer-concurrency.md) |

新增不可逆技术决策时，创建 `YYYY-MM-DD-{主题}.md`，并在此登记；不要把临时讨论写成 ADR。
