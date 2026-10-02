# Woice

本地优先的 macOS 语音素材采集器和上下文来源。录音、转写、复听、搜索与导出必须脱离外部 Agent 独立可用；Agent 只处理已完成素材或读取明确授权的上下文。

关键入口：`doc/INDEX.md` · 当前路线图 `doc/plan/2026-08-22-current-roadmap-and-plan-transition.md` · 产品定位 `doc/spec/2026-08-22-voice-context-source-positioning.md`

## 行为规则

1. **读取有效依据** — 先读 `doc/INDEX.md`，再按索引打开当前任务相关的 1–2 个 Spec/Design/Plan 分片和 `doc/log/INDEX.md` 顶部；写前读相邻代码和测试。
2. **Spec 先于产品代码** — feature、fix、refactor 开工前必须有有效 Spec，写清目标、范围、验收、影响面和兼容迁移。能从代码与对话确认的直接写；仅把未决的产品范围、验收或兼容取舍交给用户决定。
3. **先调研再自研** — 新 Provider、模型 Runtime、音频算法、Agent 协议或基础组件先查官方文档、成熟开源方案和仓库既有实现；涉及选型时记录来源、许可证、复用/自研结论与替代方案。
4. **简单且局部** — 只改当前任务需要的内容，不顺手重构；一次调用不建协议或 `Utils`。有更简单路径时直接采用并说明取舍。
5. **证据决定完成** — 先定义成功标准，循环到对应自动门禁和真实设备门禁通过；失败必须给出原命令、原错误、影响和推断，不把未运行或 Mock 结果写成通过。

## 开发环境与命令

- macOS 14+，Apple Silicon
- Xcode 16.4+，Swift 6 language mode（`Package.swift`/`project.yml` 当前为 6.0），XcodeGen 2.46.0
- SwiftPM + SwiftUI/AppKit + AVFoundation + GRDB/SQLite + WhisperKit/Qwen3ASR
- Node.js 只用于 `Connectors/` 的契约测试

```bash
make project
make build
make test
make format
make lint
make verify
make xcode-build-store
swift test --no-parallel --filter MeetingTranscriptionAcceptanceTests
```

- `Package.swift` 是核心开发和测试真相源；`project.yml` 生成正式 `Woice.xcodeproj`，不得复制业务实现。
- `make build` 与 `make xcode-build-direct` 只证明无签名编译，不可作为安装、TCC 连续性或发行证据。
- 命令缺少前置条件必须 fail-closed；执行结果只记录实际运行的命令和当前证据。

## 当前代码结构

```text
Sources/WoiceCore/   领域模型、Provider/RPC/Agent 契约与纯逻辑
Sources/WoiceApp/    App 组合、Runtime、UI、音频、存储与 Provider 实现
App/WoiceApp/        App Store Entitlement、Info.plist 与组合资源
Connectors/          PI/MCP 的 Node.js 薄适配层
Tests/               Swift 单元、集成、契约及真实 Mac 条件测试
Resources/           隐私、权限、许可证、Catalog 与发行元数据
scripts/             构建、打包、验证和真实设备验收脚本
doc/                 Spec、Design、Plan、Log、Benchmark 与索引
```

- 上述是已实现结构。未来拆分为 Domain/Runtime/Audio/Storage/Providers/RPC/Agent/UI 等 Target 只以有效设计和迁移计划为准，不得写成当前事实。
- `Connectors/` 使用各自 `package.json` 和 ESM 约定；根目录 Swift 格式规则只适用于 `Sources/` 与 `Tests/`。当前无需嵌套 Harness，出现相互冲突的子目录规则时再拆。

## 核心领域对象

Recording · Artifact · Transcript · Job · Event · Profile · Provider · Connector · ContextPackage · Policy · Permission

新增概念前先证明这些对象无法表达；不要创建同义模型。

## 产品不变量

### 1. 原始数据不可覆盖

原始音频和原始转录创建后不可原位修改。重转录、人工编辑、摘要和修订创建带父子关系的新 Artifact；测试必须验证原始 SHA-256 不变。

### 2. 录音由用户控制

录音开始必须来自快捷键、可见按钮或明确授权的 Connector；Agent 默认返回 `USER_GESTURE_REQUIRED`。录音期间始终显示可见状态，并提供可到达的结束入口。

### 3. Local-first 不隐式外发

本地 Provider 失败时报告失败，不自动将音频或文字发往云端。每个云端目标首次外发前单独授权，并显示目标与数据类型。

### 4. Durable before clever

录音先分段固化，再转录和处理。Job 状态、Lease、幂等键和失败原因持久化；界面成功状态来自已提交事实，不来自乐观内存状态。

### 5. MIT-first

新增代码依赖前记录许可证、精确版本和替代方案。默认只接受 MIT；模型权重单独审查；非 MIT 先写 ADR 并取得明确确认。

### 6. 稳定扩展边界

内置能力是随 App 签名的 Swift Provider；跨语言能力是受控进程 Provider；Agent 是本地 RPC Connector。禁止运行时下载并加载任意 dylib 或 Swift bundle。

### 7. Agent 只做薄适配

Connector 只调用 WoiceRPC，不直读 SQLite、音频设备、Keychain 或任意目录。Agent 派发只接收 Artifact/ContextPackage，不暴露任意 Shell；返回内容不自动执行。

### 8. 两个发行 Channel 隔离

Dev 只使用 `/Applications/Woice (Dev).app`、Bundle ID `com.woice.app`、`~/Library/Application Support/Woice Dev`、Keychain service `com.woice.app.dev` 及独立 lock/socket。Store 只使用 `Woice.app` 与 `com.water.woice`；任何安装、清理、迁移不得触碰另一 Channel 或 `~/Library/Application Support/Woice*` 用户数据。

## 架构与组件化

- 当前依赖方向是 `WoiceApp -> WoiceCore`；具体实现只在 `WoiceApp.swift`/AppState 组合，SDK 类型必须在 Provider 边界转换，不得进入 Core 契约。
- SwiftUI View 不直接操作 GRDB、文件、AVAudioEngine 或 URLSession；状态和副作用进入 AppState 或对应 Service/Actor。
- SQLite + 文件系统是事务真相源，不抽象成可替换 Storage 插件。
- 跨任务可变状态使用 Actor；新增 `@unchecked Sendable` 必须附 ADR 和并发测试。
- 重复 ≥2 次、View >250 行、ViewModel >300 行、函数 >60 行、参数 >5 或一个类型有两个变更原因，只触发职责评审；按状态归属和独立变化拆分，不机械抽象。
- 修改共享组件或契约前列出调用方、兼容策略和回归范围；同一外观但语义不同的组件不得强行合并。

## Swift 与 UI 规则

- Swift 使用 4 空格；格式以 `make format` 为准。类型 PascalCase，函数/属性 lowerCamelCase，布尔值使用 `is/has/can/should` 前缀；一个文件一个主类型，文件名与主类型一致。
- 跨模块错误使用稳定 Domain Error Code；底层错误只进入脱敏诊断。能由状态机、Schema 或 Policy 确定的决策不得交给 LLM。
- UI 遵循 `doc/design/INDEX.md` 中的有效设计依据：系统字体、系统材质、SF Symbols、语义色、4 pt 网格；红色只用于录音、错误和破坏性动作，状态同时有图标和文字。
- MenuBar Popover 只放状态、主动作、Profile、最近结果和入口；复杂管理进入独立窗口。支持浅/深色、高对比、键盘、VoiceOver 和 Reduce Motion。
- 涉及 UI 的 Spec 必须覆盖加载、空、错误、成功、禁用状态，窗口尺寸、焦点/键盘、共享组件调用方及真实截图或人工验收方式。

## UX：D-S-T-E

- **Diagnose** — 盲测“是否在录音、是否已转成文字、谁在使用素材、失败后是否安全”；2 人任一关键步骤停顿超过 3 秒即不通过。
- **Simplify** — 录音一个主动作；最近结果复制不超过 2 次操作；首次启动只做产品承诺、麦克风和模型 3 步。
- **Translate** — 写“正在本机转录”“发送给 Codex 处理”，不写 Provider/Gateway；错误必须说明发生了什么、素材是否安全、下一步是什么。
- **Emotify** — 录音动作 300 ms 内反馈；处理超过 3 秒显示阶段；成功反馈克制，AI 内容持续标注模型和时间。

## 测试门槛

- 修 bug 先写失败复现；加验证先写失败测试；重构前后测试均须通过。测试必须验证用户可见行为或稳定契约，不照抄实现。
- 音频、TCC、签名和恢复必须在真实 Mac 验证；Mock 只证明逻辑，不替代设备证据。真实测试失败时不得静默改成 Mock。
- 固定音频与 RPC Fixture 不得包含真实用户隐私。Schema、RPC Schema、Provider Manifest 变更必须附迁移或契约测试。
- Agent Connector 必须覆盖未安装、未登录、审批等待、超时、崩溃、输出超限和路径逃逸。
- 仓库目前没有统一行覆盖率命令；只有当前 Spec/Plan 明确要求且能产生报告时才声明覆盖率达标，不沿用历史目标冒充门禁。

## 安全约束

- 密钥只进 Keychain；禁止写入配置、日志、数据库、Artifact、子进程环境或 Harness。发现疑似密钥立即停止并报告。
- 日志默认不记录完整音频、转录、Prompt 或模型响应。外部进程使用环境白名单、独立工作目录、超时和输出上限；禁止 `/bin/sh -c` 或任意命令拼接。
- 删除默认可恢复；永久删除必须明确目标和二次确认。构建清理只处理已确认可重建产物，不删除录音、模型、数据库、设置或另一 Channel。

## 本机安装与线上发行

- 本机覆盖安装或验证 TCC 连续性必须显式传入本机未跟踪的 `WOICE_LOCAL_SIGNING_IDENTITY` 并运行 `make install`；最终 Bundle 必须通过 `codesign --verify --deep --strict`，且不是 Ad Hoc、Team 未缺失。
- 证书名称、SHA-1、Team ID、私钥、Provisioning Profile、钥匙串文件和个人签名命令不得进入仓库、模型包、Release 资产、CI 或日志；只记录脱敏结论。
- 覆盖安装后验证 Bundle ID、Team、权限声明、签名要求和真实 TCC。静态签名检查不等于 TCC 连续性；从 Ad Hoc 切换稳定身份可能需要一次重新授权。
- 公开 Ad Hoc、Developer ID/公证和 App Store 是独立发行门禁。本机 Apple Development 身份不得用于公开资产。未获明确指令，不推送、不提交审核、不发布。
- 安装前替换同 Channel 旧 App；安装后仅清理 `build/` 顶层和 `.build/xcode-*-derived/Build/Products` 的可重建 App。Store Archive/导出包按当前发行计划保留，不擅自删除。

## 文档与变更闭环

- Spec 定义行为和验收；Design 记录稳定架构与选型；Plan 管实施顺序、依赖和状态；Log 只记录发生过的变更与证据，不作为隐式新规格。
- 同一范围只保留一套有效约定，按用户授权和显式替代关系判断，不按日期猜。Plan 不改写 Spec；Log 中改变行为的决定必须同步回有效文档。
- 新计划使用稳定任务 ID，并写明替代、保留、迁移、停止和顺序。局部变化只替代相关任务；受影响下游和已完成任务标为待复核，明确代码保留、修改、迁移或移除。
- 用户已授权的范围或常规实施调整，文档同步后继续，不重复确认；未决范围、验收或兼容取舍只暂停受影响工作，独立工作继续。
- 中断时在当前 Plan 记录有效依据、任务状态、验证证据、阻塞和下一步；恢复时核对实际文件，不执行已替代、已废弃或依赖未满足的任务。
- 工作后追加 `doc/log/YYYY-MM-DD.md` 并更新各 INDEX。INDEX 只放指针和一句话结论。关键判断或失误修正已有截图时，复制到 `doc/assets/YYYY-MM-DD-{标识}.png` 并在 Log 引用；普通过程截图不存。

## 提交

- 提交格式：`type(scope): description`。
- 只暂存当前任务已验证文件；脏工作树中的其他改动视为用户内容。
- 未获明确指令，不 commit、不 push、不创建 Release。
