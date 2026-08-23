# Woice

本地优先的 macOS 语音素材采集器和上下文来源。录音、转写、复听与素材库是产品核心；外部 Agent 只在素材完成后处理，或在授权范围内读取上下文。

关键入口：`doc/INDEX.md` · 定位 `doc/spec/2026-08-22-voice-context-source-positioning.md` · 当前路线图 `doc/plan/2026-08-22-current-roadmap-and-plan-transition.md`

## 当前阶段

- 当前优先级：录音可靠性 -> 转写与模型 -> 素材管理 -> Agent 协作。M1 真实 Mac Journey、M2-01 双轨、M2-08 Core/Offline 模型能力优先；M2-09 Agent 协作后置。
- 当前实现使用 SwiftPM：`Package.swift`、`Sources/WoiceCore/`、`Sources/WoiceApp/`、`Tests/`。
- 当前闭环已覆盖菜单栏、录音、复听、设置、Keychain、macOS on-device ASR、真实 WhisperKit Tiny 本机 ASR、OpenAI-compatible ASR/LLM、原文和 Markdown；本机 ASR 会保存模型版本快照。SQLite/WAL、模型下载任务恢复、用户模型版本选择、bundled/downloaded 双库存、Unix Socket RPC、PI 薄适配和受控进程已有基础。WhisperKit Tiny 的固定 revision 已在当前机器完成真实录音转写，Core/Offline ad hoc 产物可生成并严格验签；默认大模型基准、正式签名公证、真实 Agent 素材派发仍按计划推进。
- XcodeGen 在当前机器未安装，因此 `Package.swift` 是现阶段构建真相源；恢复 XcodeGen 后再生成 Xcode 工程，不把未验证依赖描述成已实现。

## 开发环境

- macOS 14+，Apple Silicon
- Xcode 16.4+，Swift 6.1 language mode
- XcodeGen 2.45.4，Swift Package Manager
- SwiftUI + AppKit，AVFoundation，GRDB/SQLite，WhisperKit

## 命令

文档与 Harness 检查：

```bash
make docs-check
make harness-check
```

当前 SwiftPM 工程统一使用：

```bash
make project
make build
make test
make format
make lint
make verify
```

命令缺少前置条件时必须响亮失败；禁止把未执行命令写成“已通过”。

## 计划结构

```text
App/WoiceApp/          App、Entitlement、Info.plist、组合根
Sources/WoiceDomain/  实体、Artifact、错误和 Provider 契约
Sources/WoiceRuntime/ 状态机、Pipeline、Job、Policy、恢复
Sources/WoiceAudio/   设备、录音、分段和音频格式
Sources/WoiceStorage/ GRDB、迁移、FTS 和 Artifact 文件
Sources/WoiceProviders/ WhisperKit、LLM、导出 Provider
Sources/WoiceRPC/     本地 JSON-RPC Server/Client/Schema
Sources/WoiceAgent/   Context Package、受控 CLI 派发和结果回收
Sources/WoiceUI/      共享 View、ViewModel、Design Token
Connectors/           MCP、PI 和 M2-09 已验证的 Agent 薄适配层
Tests/                Unit、Integration、Contract、UI、Fixtures
doc/                  spec -> plan -> log 文档闭环
```

## 核心领域对象

Recording · Artifact · Transcript · Job · Event · Profile · Provider · Connector · ContextPackage · Policy · Permission

新增概念前先证明这些对象无法表达；不要创建同义模型。

## 项目特有规则

### 1. 原始数据不可覆盖

原始音频和原始转录创建后不可原位修改。重转录、人工编辑、摘要和修订一律创建带父子关系的新 Artifact；测试必须验证原始 SHA-256 不变。

### 2. 录音由用户控制

录音开始必须来自用户快捷键、可见按钮或已明确开启的连接器权限。Agent 默认得到 `USER_GESTURE_REQUIRED`；录音期间始终显示可见状态。

### 3. Local-first 不等于隐式降级

本地 Provider 失败时报告失败，不自动把音频或文字发送到云端。每个云端 Provider 首次外发前单独授权，并显示目标和数据类型。

### 4. Durable before clever

录音先分段固化，再转录和处理。Job 状态、Lease、幂等键和失败原因持久化；界面成功状态必须来自已提交事实，不能来自乐观内存状态。

### 5. MIT-first

新增代码依赖前记录许可证、精确版本和替代方案。默认只接受 MIT；模型权重单独审查。非 MIT 依赖先写 ADR 并获得明确确认。

### 6. 稳定边界，不加载任意动态库

内置能力是随 App 签名的 Swift Provider；跨语言能力是受控进程 Provider；Agent 是本地 RPC Connector。禁止运行时下载并加载任意 dylib 或 Swift bundle。

### 7. Agent 产品只能是薄适配层

PI 使用当前 `@earendil-works/pi-coding-agent` Extension API；DeepSeek 等产品只有在准确协议确认后才能进入 M2-09 P1 评估。旧 M3 插件生态已停止；适配层不得进入 Runtime 核心或直读数据库。

### 8. Woice 不是 Agent 网关

没有 Agent 时，录音、转写、复听、搜索和导出必须完整可用。通用推理、规划、编码交给外部 Agent；Woice 只打包素材、受控派发、回收结果和记录审计，不自动执行返回内容。

## 架构与组件化

**先定边界再实现，用组合吸收变化，不把所有东西都插件化。**

- 依赖单向：Domain <- Audio/Storage/Providers/RPC/Agent <- Runtime <- UI <- App。
- App 是唯一组合根；具体 Provider 只在组合根注册。
- UI 不直接操作 GRDB、文件、AVAudioEngine 或 URLSession。
- Connector 只调用 WoiceRPC，不读 SQLite、不访问音频设备。
- Agent 派发只接收 Artifact/ContextPackage；不得暴露任意 Shell、Keychain 或未授权目录。
- Storage 在 M1 不是插件；SQLite + 文件系统是事务真相源。
- 跨任务可变状态放 Actor；`@unchecked Sendable` 必须有 ADR 和并发测试。
- 命中任一才抽：重复 2 次、View > 250 行、ViewModel > 300 行、函数 > 60 行、参数 > 5、一个类型有两个变更原因。
- 仅为一次调用创建协议或 `Utils` 模块，视为过度抽象。

## Swift 代码风格

- 4 空格缩进；格式以 `swift format` 为准，不手调与工具冲突的样式。
- 类型 PascalCase；函数/属性 lowerCamelCase；布尔值使用 `is/has/can/should` 前缀。
- 一个文件一个主类型；文件名与主类型一致。
- 错误跨模块时使用稳定 Domain Error Code；底层错误只进入脱敏诊断。
- SDK 类型在 Provider 边界转换，不得穿透到 Domain、Runtime 或 UI。
- 能用确定性状态机、Schema 或策略代码决定的事，不交给 LLM 判断。

## UI 原则

- Quiet Native Utility：系统字体、系统材质、SF Symbols、语义色；不做网页式 AI 仪表盘。
- 4 pt 间距网格；Popover 默认宽 336 pt；历史窗口最小 800 x 560 pt。
- 红色只用于正在录音、错误和破坏性操作；状态必须同时有图标和文字。
- MenuBar Popover 只放状态、主动作、Profile、最近结果和入口；复杂管理进入独立窗口。
- 首批共享组件以开发计划第 7.4 节为准；第二个使用点出现前不扩建设计系统。
- 支持浅色、深色、高对比、键盘操作、VoiceOver 和 Reduce Motion。

## UX 原则：D-S-T-E

- Diagnose：盲测“是否在录音、是否已转成文字、谁在使用哪些素材、失败后是否安全”；2 人停顿超过 3 秒即不通过。
- Simplify：录音 1 个快捷键；最近结果复制不超过 2 次操作；首次启动只做产品承诺、麦克风、模型 3 步。
- Translate：写“正在本机转录”“发送给 Codex 处理”，不写 Provider/Gateway；错误说明发生什么、素材是否安全、下一步动作。
- Emotify：300 ms 内反馈录音状态；处理超过 3 秒显示阶段；成功反馈克制，AI 内容持续标注模型与时间。

## 测试门槛

- 修 bug：先写失败复现；加验证：先写失败测试；重构：前后测试都通过。
- Domain/Runtime/RPC 行覆盖率 >= 90%；Storage/Provider >= 80%。
- 音频、TCC、签名和恢复必须在真实 Mac 验证，Mock 不能替代。
- 固定音频和 RPC Fixture 不得包含真实用户隐私。
- 数据 Schema、RPC Schema、Provider Manifest 变更必须附迁移或契约测试。
- Agent Connector 还必须测试未安装、未登录、审批等待、超时、崩溃、输出超限和路径逃逸。

## 安全约束

- 密钥只进 Keychain；禁止写入配置、日志、数据库、Artifact 或子进程环境。
- 日志默认不记录完整音频、转录、Prompt 或模型响应。
- 外部进程使用环境白名单、独立工作目录、超时和输出上限。
- 禁止 `/bin/sh -c` 或任意命令拼接；CLI 凭据由目标 Agent 管理，Woice 不读取或复制。
- 删除默认可恢复；永久删除必须明确目标和二次确认。
- 不读取、提交或展示本地密钥文件；发现疑似密钥立即停止并报告。

## 文档闭环

工作前：读 `doc/INDEX.md` -> 相关 spec INDEX -> 当前 plan -> log INDEX 顶部。只读当前任务需要的 1-2 个分片。

计划任务先读当前路线图；旧 `m0-mvp` 只作历史执行基线。新计划必须写明替代、保留、迁移、停止和顺序，否则不得实施。

工作后：追加 `doc/log/YYYY-MM-DD.md`，更新 `doc/log/INDEX.md`；范围变化先更新 spec，再更新 plan。INDEX 只放指针和一句话结论。

## 行为与提交

- 简单优先；有更简单做法时直接指出，不默默选复杂方案。
- 只改当前任务需要的内容，不顺手重构相邻模块。
- 写前先读相邻文件；冲突规则二选一，不折中保留两套模式。
- 先定义成功标准，再循环到验证通过；长任务每个工作包设检查点。
- 失败贴原文、触发命令、影响和推断原因；不静默吞掉或伪造完成。
- 提交使用 `type(scope): description`；未获明确指令，不推送、不发版。
