# 本机模型一键安装与 App Store 兼容规格

> 状态：待实施  
> 日期：2026-08-25  
> 计划入口：[当前技术开发收口计划](../doc/plan/2026-08-24-current-technical-development-closure.md)  
> 相关设计：[模型接入、连接向导与双版本架构设计](../doc/design/2026-08-22-model-onboarding-provider-architecture.md)  
> 上架边界：[Mac App Store 上架计划](../doc/plan/2026-08-23-mac-app-store-launch.md)

## 1. 目标

- Core 与 Store 安装包可以不携带模型；没有模型时，用户只点击一次主按钮即可开始下载。
- 同一次用户动作串联下载、校验、安装、设为当前模型，以及恢复等待中的转写任务。
- 模型名称、来源、许可证和磁盘占用保持可见，但不增加确认弹窗、配置页或必须勾选的步骤。
- 官网版与 Store 版共用 ModelPack、Job、Provider 和 UI 状态机；差异只由组合根决定，不建立两套产品流程。
- 为 Qwen3-ASR-0.6B 预留正式接入路径，同时保持 WhisperKit Tiny/Large-v3 的现有能力。

## 2. 非目标

- 不在首次启动时静默下载模型。
- 不让用户选择模型文件、安装 Python、配置 Endpoint 或理解 Provider 后才能完成第一次转写。
- 不允许模型包携带可执行文件、安装脚本、dylib、Swift bundle 或运行时依赖。
- 不在本机模型失败后自动把音频发送到云端。
- 不把 App Store 审核结果写成可由代码保证的验收项。

## 3. 核心产品决策

### 3.1 一个动作，不是自动替用户决定

“一键安装”定义为：用户明确点击一次后，系统自动完成后续技术步骤；它不等于应用启动后无提示下载。

三个入口使用同一条命令：

| 触发位置 | 无模型时主按钮 | 完成后的动作 |
|---|---|---|
| 工作台无模型状态 | `下载本机模型` | 模型就绪，页面回到可录音/可导入状态 |
| 录音或导入后的待转写状态 | `下载并转写` | 自动恢复当前素材的原转写任务 |
| 设置页模型卡 | `下载并使用` | 设为后续本机转写的当前模型 |

三个按钮只改变完成后的 continuation，不复制下载实现。

### 3.2 默认推荐由能力策略决定

- 用户无需先比较模型；界面突出一个“推荐”模型和一个主按钮。
- 其他模型放在“其他本机模型”中，允许主动展开和切换。
- 推荐策略只读取机器能力、磁盘空间、已验证库存和发行配置，不读取用户录音内容。
- 策略结果必须可解释，例如“适合当前 Mac”“占用较小”“中文和方言优先”。
- 推荐策略变化不自动切换已安装且由用户选定的当前模型。

首期策略：

- 已安装且可用的用户当前模型优先。
- 没有当前模型时，优先发行 Catalog 标记的 `recommended` 条目。
- Qwen3-ASR-0.6B 只有在原生 Store-compatible Runtime、许可证 ADR、性能门禁和固定模型包全部通过后，才能成为推荐项。
- 条件未满足时继续推荐已验证的 WhisperKit 模型，不展示点击后无法完成的 Qwen 下载按钮。

### 3.3 下载前信息内联展示

主卡固定显示：

- 用户可理解的模型名称与用途。
- 预计下载大小、预计安装空间和“仅在本机运行”。
- 来源与许可证短标签；详情通过 Disclosure 打开。
- 网络不可用或空间不足时，主按钮保持可操作或明确禁用，并在原位置说明处理办法。

Apache-2.0 不增加强制勾选或二次确认；点击主按钮即是明确下载动作。许可证全文、来源、revision 和 Notice 进入模型详情与“第三方许可”。

## 4. 用户流程

### 4.1 首次打开 Core/Store，无本机模型

```text
打开工作台
  -> 发现没有可用模型
  -> 展示推荐模型卡 + “下载本机模型”
  -> 用户点击一次
  -> downloading -> verifying -> installing -> ready
  -> 页面显示“已可在本机转文字”
```

- 不自动弹出设置页。
- 不要求先选择 Tiny、Large 或 Qwen。
- 下载期间用户可以录音和导入；素材先安全保存，任务进入 `waitingForModel`。
- 关闭窗口不取消任务；退出 App 后任务持久化为可恢复状态。

### 4.2 已有素材，点击转写时没有模型

```text
点击“转文字”
  -> 原位置变为模型缺失卡
  -> 用户点击“下载并转写”
  -> 模型安装完成
  -> 自动恢复这一次转写
  -> 打开同一素材详情并展示处理阶段
```

- 不让用户回到素材库重新寻找文件。
- continuation 只保存 Recording/Artifact/Task ID，不复制音频。
- 自动恢复前再次核对任务、原件 SHA-256 和当前模型快照。

### 4.3 设置页切换模型

- 当前模型卡展示 `当前使用`，不再显示可点击的安装按钮。
- 未安装模型使用 `下载并使用`。
- 已安装的非当前模型使用 `使用此模型`。
- 下载中的模型卡只显示进度、预计剩余量和 `取消`。
- 删除只允许非当前、非活动任务依赖的 downloaded 版本。

## 5. 状态与反馈

### 5.1 单一状态机

```text
available
  -> preflighting
  -> downloading
  -> verifying
  -> installing
  -> activating
  -> ready

preflighting/downloading
  -> paused | cancelled | failed

verifying/installing/activating
  -> failed（保留旧模型和已下载的可恢复事实）
```

- UI 成功只来自已提交的 ModelPack inventory/current pointer。
- `100%` 下载不等于安装成功；校验、安装和启用分别显示阶段。
- 同一 packID/revision 只有一个 durable download Job；多个入口附着到同一任务。
- 多个等待转写可以在模型就绪后按原队列恢复，不并发加载多个模型实例。

### 5.2 错误文案

| 错误 | 用户文案 | 主动作 |
|---|---|---|
| 网络中断 | `下载已暂停，录音和素材都已保存。` | `继续下载` |
| 空间不足 | `还需要约 X GB 可用空间。` | `打开存储设置` |
| 校验失败 | `模型文件未通过安全校验，未安装。` | `重新下载` |
| Runtime 不兼容 | `这个模型暂不支持当前 Mac。` | `改用推荐模型` |
| App 退出后恢复 | `上次下载已暂停。` | `继续下载` |
| 用户取消 | `已取消下载，现有模型没有变化。` | `重新下载` |

错误不得显示 Hub、revision、Provider ID 或底层异常作为主文案；技术详情进入可复制诊断。

## 6. Qwen3-ASR-0.6B 接入边界

### 6.1 模型身份

- 上游固定为官方 `Qwen/Qwen3-ASR-0.6B-hf` 的精确 revision。
- 如为 Apple Silicon 生成派生格式，产品名称写为“基于 Qwen3-ASR-0.6B 官方权重的本机版本”，不得暗示派生运行时由 Qwen 官方维护。
- Manifest 必须记录上游 revision、转换工具及版本、转换参数、派生文件 SHA-256、Apache-2.0、来源 URL 和 Notice。

### 6.2 Runtime

- Store 共用方案必须是随 App 构建、签名并接受沙盒约束的 in-process Runtime。
- Runtime 代码可以作为已审计 Swift Package/Framework 进入 App；模型下载只能包含数据。
- 官网版优先复用同一 in-process Runtime，避免形成官网进程版与 Store 原生版两套转写结果。
- 若原生 Runtime 尚未通过准确率、内存、长文件和崩溃隔离门禁，Qwen 卡保持内部实验状态，不进入正式 Catalog。
- 受控 Python/Transformers 进程只允许作为研发对照基准，不作为 Store 产品实现，也不成为用户一键安装链路的隐藏依赖。

### 6.3 输出映射

- Qwen Provider 输出统一映射到现有 `TranscriptionResult(text, segments)`。
- 没有 ForcedAligner 时，复用 Woice 分段边界生成片段级时间戳。
- ForcedAligner 作为独立可选增强包，不阻塞基础转写模型安装。
- 双轨分别转写后继续由现有时间线合并器写入 `sourceTrack`；不得退回混音单请求作为默认。

## 7. App Store 兼容设计

### 7.1 沙盒与可执行边界

- 模型下载到 App 容器内的 Application Support；不依赖容器外缓存。
- 使用受限 HTTPS、固定 host、签名 Catalog、逐文件 SHA-256 和原子提交。
- 不执行下载内容，不修改 App Bundle，不安装 Python/uv/ffmpeg，不调用用户 Shell。
- Runtime、Tokenizer、音频预处理代码随 Store Bundle 签名；下载项只包含权重、词表、配置和许可证数据。
- Store 与官网使用同一 ModelPackManifest、ModelDownloadTask 和 ModelInventory。

### 7.2 审核可解释性

- App Review Notes 说明：下载是用户主动触发的本机语音识别资源；下载内容不可执行；录音不会因模型失败自动外发。
- App Privacy、PrivacyInfo、SBOM、NOTICES 和 Catalog 元数据保持一致。
- 模型来源、磁盘占用、删除入口和数据位置对用户可见。
- Store 首次启动不要求登录或 API Key；没有模型时仍可录音和安全保存素材。

### 7.3 发行降级

- Qwen Runtime 或许可证未通过 Store 门禁时，Store Catalog 不发布该条目。
- UI 自动回到已批准的 WhisperKit/Speech 组合，不显示灰色 Qwen 营销入口。
- 官网版不得因 Store 未批准而静默改用外部进程；若两版能力不同，必须由发行 Catalog 明确控制并保留相同任务语义。

## 8. 组件边界

- `RecommendedModelPolicy`：输入机器能力、发行 Catalog、库存和空间，输出一个推荐模型及解释。
- `ModelInstallIntent`：记录入口和完成后的 continuation，不执行下载。
- `ModelInstallCoordinator`：拥有 durable Job、去重、恢复、校验、安装和激活。
- `ModelInstallCard`：工作台、详情和设置共用状态展示；允许文案和 completion action 配置。
- `Qwen3ASRTranscriptionService`：实现 `LocalASRTranscribing`，SDK 类型不穿透 Domain/UI。
- `ModelRuntimeRegistry`：按 providerID 创建已签名内置 Runtime，不从模型包加载代码。

第二个使用点出现前不扩建设计系统；上述组件只服务已经确认的三个入口和两个 Runtime。

## 9. 技术工作包

| 工作包 | 内容 | 退出条件 |
|---|---|---|
| MOD-01 契约与 ADR | 冻结官方 revision、派生格式、许可证、Runtime 依赖和 Store 决策 | ADR、Manifest Fixture、NOTICE/SBOM 门禁通过 |
| MOD-02 Store-compatible Runtime | Qwen 原生 Runtime、音频预处理、Tokenizer、输出映射 | 官网/Store 条件编译均无外部进程；固定音频结果一致 |
| MOD-03 一键状态机 | Intent、Coordinator、durable Job、去重、continuation | 三入口单击后均完成或给出可恢复失败 |
| MOD-04 统一 UI | 推荐卡、下载阶段、错误、模型管理和无障碍 | 工作台/详情/设置共用状态，不出现强制二次确认 |
| MOD-05 Store 发行门禁 | 沙盒路径、Catalog、不可执行资源、Notices/Privacy/Review Notes | Store Bundle 不含下载执行入口，模型包数据门禁通过 |
| MOD-06 回归与性能 | 长文件、双轨、重启、磁盘、损坏、内存和版本链 | 自动矩阵及固定模型性能阈值通过 |

顺序：MOD-01 -> MOD-02 -> MOD-03 -> MOD-04 -> MOD-05 -> MOD-06。MOD-02 未退出前，不对正式用户展示 Qwen 下载选项。

## 10. 技术验收标准

- MOD-TAC-001：无模型时，工作台到下载开始只有一次用户点击。
- MOD-TAC-002：已有素材点击“下载并转写”后，安装完成自动恢复原任务，无需返回素材库。
- MOD-TAC-003：工作台、详情和设置附着到同一 durable download Job，不重复下载。
- MOD-TAC-004：下载、校验、安装和激活阶段可区分；只有 inventory/current 提交后显示成功。
- MOD-TAC-005：网络中断、取消、退出和重启均可恢复；旧模型、录音和 Transcript 不改变。
- MOD-TAC-006：空间不足、文件损坏、签名/哈希失败和 Runtime 不兼容全部 fail-closed。
- MOD-TAC-007：模型包没有 Mach-O、脚本、dylib、bundle 或可执行权限文件。
- MOD-TAC-008：Store 条件构建不注册 Process Provider；Qwen 推理不依赖外部 Python、Shell 或容器外路径。
- MOD-TAC-009：Qwen 结果进入现有分段、双轨合并、任务快照和 Transcript Artifact 版本链。
- MOD-TAC-010：模型卡具有可访问名称、阶段、进度和值；取消和继续支持键盘与 VoiceOver。
- MOD-TAC-011：固定 revision、上游/派生 SHA-256、Apache-2.0、Notice、SBOM 和转换元数据完整。
- MOD-TAC-012：未通过 Runtime/许可证/性能门禁的 Qwen 条目不会进入正式 Catalog 或用户 UI。

## 11. 非开发体验提醒

以下仅作提示，不计入开发计划完成率或退出条件：

- 首次用户是否理解只需点击一个按钮。
- 不同网速下的主观等待感、进度可信度和错误文案。
- 低配/高配 Apple Silicon 上的主观发热、噪音和响应速度。
- App Store 审核人员对模型下载说明的实际反馈。

人工体验发现问题后，建立独立 bug/spec，再进入对应 MOD 工作包。
