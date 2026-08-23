# 模型接入、连接向导与双版本架构设计

> 状态：设计基线；本机 ASR Adapter、真实 Tiny 权重、模型包原子安装/下载、版本选择和 Core/Offline ad hoc 打包基础已实现，正式发行仍待完成  
> 日期：2026-08-22  
> 需求：[双版本分发与模型接入规格](../spec/2026-08-22-dual-edition-model-integration.md)

> 定位关系：该设计只负责录音素材的 ASR 结构化与模型体验，不把模型设置扩展成 Agent 控制台；素材完成后的使用见[语音上下文与 Agent 协作架构](2026-08-22-voice-context-agent-collaboration.md)。

## 1. 设计立场

### 1.1 一个产品，两种初始库存

轻量版和离线版的差异不是 Feature Flag，而是启动时可发现的模型库存：

```text
Woice Core.app
  + 无 bundled model pack

Woice Offline.app
  + bundled WhisperKit model pack

相同 Runtime / UI / Provider Registry / Storage / RPC
```

界面不得出现“该功能只有离线版可用”。轻量版下载同一个模型包后，应进入完全相同的状态。

### 1.2 能力优先，不让用户先理解技术名词

用户首先选择“语言转文字”，然后才选择在哪里运行、使用哪个 ASR。Provider、模型和传输是实现细节，只在高级信息和诊断中完整展示。Markdown 等通用后续处理进入独立的 Agent 协作流程，系统朗读保持系统工具，不混入模型下载页。

当前最小运行实现使用 macOS on-device Speech 作为无模型回退，版本取当前 macOS 版本并随 ProcessingTask 快照保存；已安装且校验通过的 WhisperKit 模型包会在 App 启动或导入后进入本机路由。WhisperKit 仍需经过 M2-08c 的真实权重、许可证和性能门禁后才能成为 Offline 发布默认模型，不改变 Runtime/Artifact 边界。

### 1.3 兼容不是任意文件加载

Woice 的“可接自己的模型”定义为：

- 连接兼容的本地 HTTP 服务。
- 安装经过验证的 Woice 模型包，由已内置 Runtime 运行。
- 安装经过签名/信任确认的受控进程 Provider。

不同架构的模型文件需要不同 Tokenizer、预处理、推理引擎和输出 Schema，因此首版不提供误导性的“导入任意模型文件”。

## 2. 概念边界

复用现有 `Provider`、`Profile`、`Policy`、`Job`、`Artifact`，不新增同义领域对象：

| 概念 | 定义 | 示例 |
|---|---|---|
| Provider | 执行能力的运行时或远端服务 | WhisperKit、OpenAI-compatible ASR、系统 TTS |
| Model Descriptor | Provider 可选择的模型说明，不是独立业务实体 | Whisper large-v3、SenseVoiceSmall |
| Model Installation | 某个模型包在本机可用的事实 | bundled、downloaded、missing、corrupted |
| Provider Configuration | Endpoint、模型选择、能力、数据位置和 Keychain 引用 | 本机 FunASR、局域网 LocalAI |
| Profile | 录音场景对 ASR Provider 的显式路由 | 快速口述、会议、全本地 |
| Policy | 是否允许访问网络、局域网、Artifact 和麦克风 | deny network、首次外发确认 |

模型权重不是用户 Artifact；它使用独立模型目录和清单，不进入录音版本链。

## 3. 技术架构

```text
SwiftUI Settings / Onboarding / Detail
                |
        ProviderRegistry Actor
       /         |          \
Built-in     HTTP Adapter   Process Adapter
WhisperKit   ASR compatible existing Runner
       \         |          /
          ProviderRouter
                |
       Runtime Job / Policy
                |
    Recording / Transcript Artifact

ModelPackStore Actor ---- ModelDownload Job
       |                         |
App Resources              Application Support
bundled read-only          downloaded versioned
```

### 3.1 依赖方向

- Domain/Core 定义能力、配置快照、模型包清单和稳定错误码，不依赖 SwiftUI、Core ML 或 URLSession。
- App/Runtime 组合 ASR ProviderRegistry、Router、模型存储、下载和健康检查。
- UI 只读取状态和发出用户意图，不拼 Endpoint、不直接操作文件或模型 Runtime。
- HTTP、WhisperKit、受控进程 ASR 分别在 Provider Adapter 边界转换成统一转录结果。
- App 仍是唯一组合根；默认 Provider 只在组合根注册。

## 4. 技术栈

| 层 | 选型 | 用途 |
|---|---|---|
| 平台 | macOS 14+、Apple Silicon | 保持现有首发基线 |
| 语言/并发 | Swift 6.1、Actor、AsyncSequence | Registry、下载、健康检查和状态流 |
| UI | SwiftUI + 少量 AppKit | 首启、设置、文件选择、系统跳转 |
| 内置 ASR | Argmax OSS/WhisperKit + Core ML | Offline 默认转录；实现前锁定精确 MIT 版本 |
| 系统朗读 | AVFoundation `AVSpeechSynthesizer` | 保持现有工具，不进入模型路由 |
| HTTP Provider | Foundation URLSession | OpenAI-compatible ASR |
| 本机探测 | URLSession + 明确 loopback allowlist | 用户点击后短超时探测，不全端口扫描 |
| 元数据 | 现有 SQLite/WAL | Provider 配置、模型安装、Job、健康快照 |
| 密钥 | Security/Keychain | 只保存 credential，SQLite 只存稳定引用 |
| 完整性 | CryptoKit SHA-256、Curve25519 签名验证 | 下载清单、文件和 Catalog 验证，不新增依赖 |
| 进程 Provider | 现有 stdio JSON + ProcessProviderRunner | Python/Node/Rust 受控运行时 |
| 打包 | SwiftPM、现有 Make/package、codesign/notarytool | 同二进制产出 Core/Offline 两个 DMG |

模型下载首版使用清单列出的独立文件，不引入新的压缩库；每个文件下载到同文件系统临时目录，校验后原子切换。

## 5. Provider 能力协议

现有 `ProcessProviderKind` 保留 `asr`、`languageModel`、`tts`。能力 ID 冻结命名空间：

- `asr.file`
- `asr.timestamps.segment`
- `asr.streaming`
- `asr.language.<bcp47>`
- `llm.chat`
- `llm.structured-output`
- `tts.speech`
- `tts.streaming`
- `tts.voice-list`

已知能力决定 UI 和路由；未知扩展能力保留但不自动启用。Provider 返回未声明能力时 fail-closed，不让 LLM 推断能力。

### 5.1 Provider 初始化

每种 Adapter 统一经过：

```text
discover -> validate configuration -> initialize -> health check
-> advertise capabilities -> ready | actionable failure
```

### 5.2 路由规则

- Profile 明确指定 Provider Configuration ID 和 Model ID。
- 无 Profile 覆盖时使用能力级默认路由。
- Job 创建时保存 Provider、模型、能力和数据位置快照。
- 已运行 Job 不跟随设置切换；重试默认复用原快照，用户可显式“换模型重试”。
- 本地失败后只进入失败/等待选择状态，不查找云端替代项。

## 6. 模型包设计

### 6.1 ModelPackManifest v1

| 字段 | 规则 |
|---|---|
| schemaVersion | 首版固定 `1`，未知 major 拒绝 |
| packID | 稳定反向域名 ID |
| modelID/version | Provider 可识别的模型和不可变版本 |
| providerID | 必须引用已内置或已验证 Provider |
| capabilities | 使用冻结能力 ID |
| platform/architecture/minOS | 首版仅 macOS/arm64 |
| files | 相对路径、字节数、SHA-256；拒绝路径穿越和符号链接 |
| license | SPDX 或自定义许可证 ID、Notice 路径、来源 URL |
| size | 下载和安装预估；UI 显示，不作为完整性真相源 |
| signature | 下载包使用的清单签名；bundled 包由 App 签名保护并仍校验哈希 |

模型包不得包含可执行文件、安装脚本、动态库或任意启动参数。

### 6.2 存储布局

```text
Woice.app/Contents/Resources/Models/
  com.woice.whisper.large-v3/1.0.0/    # Offline，只读

Application Support/Woice/Models/
  com.woice.whisper.large-v3/
    1.0.0/                              # Core 下载或用户安装
    current.json                        # 原子切换的当前版本指针
  downloads/                            # .partial 与可恢复元数据
```

查找优先级：用户显式选择版本 > 已验证 downloaded current > bundled。更高版本不会自动覆盖用户锁定版本。

### 6.3 下载状态机

```text
available -> awaitingConfirmation -> downloading -> verifying
-> installed
-> paused | failed | cancelled
```

- 下载前检查目标大小加 20% 临时空间；更新时同时考虑旧、新版本。
- 每个文件独立恢复；失败不删除已安装旧版本。
- 校验成功后原子写 `current.json`；UI 成功状态只来自已提交事实。
- 删除显示可释放空间和替代 Provider；删除模型不删除录音或历史 Transcript。

## 7. 发行包设计

### 7.1 构建输入

新增只读 `DistributionManifest`：

- `flavor`: `core` 或 `offline`。
- `bundledModelPackIDs`: Core 为空，Offline 包含默认 ASR pack。
- `appVersion`、`buildVersion`。

`flavor` 只用于“此安装包附带了什么”的展示和发行验收，禁止用它控制业务功能。

### 7.2 产物

```text
make package-core     -> Woice-Core-{version}.app/.dmg
make package-offline  -> Woice-Offline-{version}.app/.dmg
```

实现阶段再改 Makefile；本设计不写构建代码。两者必须分别完成 codesign、Notarization、staple、Gatekeeper 和断网验收。

### 7.3 覆盖安装

同一 Bundle ID 让系统权限、Keychain 和用户数据连续。安装另一发行包等同替换 App，不迁移数据库。模型解析每次启动重建库存：

- App Resources 模型消失：标记 `bundledUnavailable`。
- Application Support 模型仍在：继续可用。
- 当前默认失效：进入等待选择模型并展示一键下载，不自动改路由。

## 8. 本地模型生态接入

### 8.1 预设层

预设只填充协议和默认路径，不复制第三方运行时：

| 预设 | 能力 | 发现方式 | 备注 |
|---|---|---|---|
| OpenAI-compatible | ASR | 用户输入或 loopback URL | 通用兜底 |
| whisper.cpp server | ASR | 明确端口 allowlist + health | 识别为本机服务，不导入 ggml 文件 |
| faster-whisper server | ASR | 明确端口 allowlist + `/v1/models` | 保留服务差异诊断 |
| FunASR/LocalAI | ASR | OpenAI-compatible 探针 | 只启用实际探测成功能力 |

端口 allowlist 必须随预设版本化；探测由用户按钮触发，每个地址 300-800 ms 超时，总时长不超过 5 秒。

### 8.2 手动连接

- Endpoint 接受服务根地址或完整路径，复用现有自动补全行为。
- 用户可覆盖模型 ID、语言和能力；覆盖能力仍需健康检查证实。
- `localhost`/loopback、私网、公网在保存前明确分类。
- 自签名 TLS、代理、自定义 Header 放入高级后续工作包，首版不静默放宽 TLS。

## 9. UX 信息架构

### 9.1 首次启动

继续保持三步：产品承诺、麦克风、转录方式。第三步根据库存变化，不根据发行版写死：

- 已有可用 ASR：展示“本机模型已就绪”。
- 发现用户下载模型：直接复用并显示来源。
- 没有 ASR：展示查找、下载、稍后三个选择。

这让 Core/Offline 覆盖安装、恢复缓存和未来预装渠道都使用同一逻辑。

### 9.2 模型与转写页

页面顶部使用三张紧凑能力行，而非营销卡片：

```text
语言转文字   Whisper large-v3   这台 Mac   已就绪   [测试] [更换]
```

下方分为“已安装模型”和折叠的“高级连接”。保留现有独立设置草稿：向导成功只写入草稿，用户点击设置窗口的“保存”后才切换默认路由；首次启动向导则以单独明确的“启用”提交。

### 9.3 录音后无模型

停止录音后：

```text
录音已安全保存在这台 Mac 上
还没有选择语言转文字模型。
[选择模型并转录] [稍后处理] [播放录音]
```

历史详情持续显示“等待选择模型”，不能使用红色错误。用户连接模型后可选择“只处理这条”或“处理全部 N 条待转录录音”。

### 9.4 数据位置表达

复用计划中的 `PrivacyLocationBadge`：

- 这台 Mac：电脑图标 + 文字。
- 局域网设备：网络图标 + 主机名。
- 云端：云图标 + 域名。
- 待确认：问号图标 + “启用前确认位置”。

不使用“local/remote/provider”等内部术语作为主文案。

## 10. UI 组件边界

先复用现有 `SettingsBanner`、`APIKeyField`、ASR 健康检查和设置草稿。出现第二个使用点后再抽共享组件：

| 组件 | 职责 | 不负责 |
|---|---|---|
| `CapabilityProviderRow` | 显示能力当前路由、位置和健康 | 执行连接或持久化 |
| `ProviderConnectionWizard` | 三步连接意图和测试结果 | 直接写 SQLite/Keychain |
| `ProviderPresetPicker` | 展示已发现/预设服务 | 扫描网络 |
| `ModelPackRow` | 下载、校验、版本和磁盘状态 | 文件 IO |
| `ProviderHealthRow` | 统一 ASR 健康结果 | 构造协议请求 |
| `PrivacyLocationBadge` | 数据位置的图标+文字 | 推断位置 |
| `ActionableProviderError` | 数据安全说明和下一步动作 | 显示原始 stderr/密钥 |

连接向导可先作为一个主 View 加三个小步骤；未超过 250 行且没有第二个流程前，不拆出通用 Wizard 框架。

## 11. 运行时组件边界

在当前 SwiftPM 实际结构中先落到 `WoiceCore`/`WoiceApp`，不为了计划中的未来目录立即拆 Target：

| 逻辑组件 | 隔离 | 主要职责 |
|---|---|---|
| ProviderRegistry | Actor | 注册内置/HTTP/进程 ASR Provider，发布能力和健康状态 |
| ProviderRouter | 值类型/Runtime 服务 | 按 Profile 和快照选择 Provider，不做隐式兜底 |
| ModelPackStore | Actor | 枚举 bundled/downloaded、校验、原子安装和删除 |
| ModelDownloadCoordinator | Actor | 驱动现有 durable Job、进度、暂停/恢复 |
| LocalServiceDiscovery | Actor | 用户触发的 loopback allowlist 探测 |
| ProviderHealthCheckService | Actor | ASR 固定无隐私音频测试和结构化结果 |
| BuiltInWhisperProvider | Provider Adapter | WhisperKit 输入输出转换，不持久化业务状态 |
| OpenAICompatibleProvider | Provider Adapter | 复用现有 API Client，按能力拆请求实现 |
| ProcessProviderAdapter | Provider Adapter | 包装现有 Manifest/Trust/Runner |

多个 Provider 共享的可变注册表、下载和探测必须是 Actor；模型推理回调继续遵守音频实时线程边界，不进入 MainActor。

## 12. 配置与迁移

当前 `AppSettings.asrEndpoint/asrModel/asrAPIKey` 迁移为默认 ASR Provider Configuration：

- 空 Endpoint 不创建外部 Provider。
- 非空 Endpoint 生成稳定配置 ID，模型和语言原样保留。
- API Key 继续留在现有 Keychain account，只在迁移提交成功后切换引用。
- 旧字段至少保留一个 Schema 版本的只读解码兼容；新写入不再复制密钥。
- 迁移必须幂等；失败继续使用旧设置，不能产生半配置路由。

## 13. 无障碍与动效

- 下载进度提供百分比、已下载/总大小和 VoiceOver 数值。
- 探测、测试和下载完成通过状态文字变化，不依赖动画。
- Reduce Motion 下不做卡片位移；ProgressView 保留系统行为。
- 键盘顺序：能力行 -> 主动作 -> 次级动作 -> 高级展开。
- 错误在当前页持久显示，不使用只出现一次的 toast。

## 14. 设计验证

必须人工走查以下六条 Journey：

1. Offline 干净安装，断网完成首次转录。
2. Core 干净安装，发现本机 ASR 并设为默认。
3. Core 无本机服务，下载推荐模型后转录。
4. Core 选择“先只保存录音”，之后从详情页补转录。
5. 本机 Provider 失败，切换另一本机 Provider；无云端兜底。
6. Core/Offline 双向覆盖安装，当前模型缺失时恢复。

每条 Journey 做 D-S-T-E 盲测：“有没有模型、在哪里处理、失败后录音是否安全”任一问题让两名用户停顿超过 3 秒即不通过。
