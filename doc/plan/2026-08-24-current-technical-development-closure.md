# Woice 当前技术开发收口计划

> 状态：WCL-00～03、WCL-05 已完成源码与自动门禁；WCL-04 发行验证待凭据；WCL-06 已完成 MAS-03 本机能力裁剪、正式 Store 工程生成与无签名构建，以及 Store 本机打包/隐私/沙盒静态预检，正式签名 Archive 仍待外部条件  
> 日期：2026-08-24  
> 当前基线：双音源选择、AAC/M4A 新录音、会议合成、长素材详情按需加载与录音控制区视觉层级已实现；官网版 `make verify` 通过 208 项 Swift 测试 / 14 个 Suite，Store 条件通过 186 项 Swift 测试 / 11 个 Suite，PI/MCP、构建、Core 打包和本机 Store Bundle 预检均通过；`Woice-Store / Release-AppStore` Xcode 无签名构建通过。  
> 历史诊断：2026-08-24 早先的原生 macOS 回归曾出现真实麦克风 0 帧/CoreAudio IPC 挂起；后续音频宿主恢复并完成完整回归。该次仅保留为诊断记录，不作为当前产品代码失败结论。  
> 问题证据：[01-workspace-sidebar-layout.png](../audit/2026-08-24-workspace-sidebar-layout/01-workspace-sidebar-layout.png)  
> 迁移来源：[工作区侧栏与权限连续性优化计划](2026-08-23-workspace-sidebar-and-permission-continuity.md)  
> 进度真相源：[当前计划进度复核](2026-08-23-plan-progress-review.md)

> 当前更新（2026-08-24 19:20）：早先的真实麦克风 0 帧/CoreAudio IPC 环境问题已恢复；新增 `AppState.prepareForTermination()` 真实录音清理集成测试，`make acceptance-core`、官网 `make verify`（201 项 Swift 测试 / 13 个 Suite）和 Store 条件回归（179 项 / 10 个 Suite）均通过。此前回归边界仅保留为诊断历史，不作为当前代码失败结论。

> 当前更新（2026-08-24 20:29）：Large-v3 模型校验的重复 `FileHandle`/`Data` 哈希循环已统一为 1 MiB 固定缓冲读取。现有用户数据启动 RSS 从 1,785,056 KiB 降至 135,232～135,424 KiB，并稳定运行 20 秒；官网 `make verify` 通过 203 项 / 13 个 Suite，Store 条件通过 181 项 / 10 个 Suite，正式 Xcode Store 无签名构建通过。

> 当前更新（2026-08-25 00:51）：工作台改为麦克风/电脑声音双按钮，默认双开并允许任一单轨；双关 fail-closed，录音中锁定来源。新录音直接写入 AAC/M4A，双开生成会议合成 M4A；详情页合并为一个按需播放器，原文与时间轴使用固定高度惰性滚动区。异常恢复记录来源选择，不把系统单轨伪造为麦克风或会议合成。`make acceptance-core`、官网 207 项 / 14 Suite、Store 185 项 / 11 Suite 和正式 Xcode Store 无签名构建通过。

> 当前更新（2026-08-25 01:16）：菜单栏音源改为中性状态按钮，录音保持唯一强调主动作并使用 `record.circle` 区分麦克风来源。按用户视觉复核，工作台顶部移除悬空的导入按钮、右上角麦克风/电脑声音/录音控制组和居中的空闲状态胶囊；导入与开始录音仍保留在素材空状态。官网 208 项 / 14 Suite 及覆盖安装启动通过；此前同源码结构的 Store 186 项 / 11 Suite 和正式 Xcode Store 无签名构建证据保留。

## 1. 计划定位

本计划只列需要修改代码、工程、自动测试、签名流水线或发行配置的工作。真实用户、真实会议、真实素材、真实桌面视觉和人工体验验收不作为开发工作包、退出条件或完成阻塞项，只在第 7 节提示。

当前没有新的录音核心大功能缺口。已实现的录音、双轨采集、模型路由、素材库、搜索、导出、可恢复删除和 Markdown 目录快捷键作为回归基线，不重复建设。

## 2. 替代、保留、迁移、停止、顺序

- 替代：替代旧 WPC 作为活动开发待办源的地位；WPC 只保留历史实现与证据。
- 保留：保留现有产品规格、WPC 已完成代码、M2-09 安全边界、Developer ID 发行边界和 MAS-00～08 专项细节。
- 迁移：旧 WPC 中仍需要技术开发的部分迁入 WCL-00～06；纯人工体验与真实环境验收仅迁入第 7 节提醒。
- 停止：停止 `WPC-01R`、WSL 临时编号，以及把真实用户验收写成开发工作包或计划完成门槛。
- 顺序：WCL-00 -> WCL-01 -> WCL-02 -> WCL-03 -> WCL-04 -> WCL-05 -> WCL-06。WCL-05 不阻塞无 Agent 核心发行；WCL-06 已先收口可在本机验证的 MAS-03、正式 Xcode 组合根及 Store Bundle 预检，MAS-00～02、MAS-04～08 的正式签名与商店工作仍需按上架计划和外部条件推进。

## 3. 旧 WPC 未完成项分流

| 旧范围 | 内容 | 处理方式 |
|---|---|---|
| WPC-01 | 顶部三功能、底部设置、中部独立滚动 | 技术开发迁入 WCL-01 |
| WPC-02 | 列表密度、状态和来源布局适配 | 技术开发迁入 WCL-01；真实截图只作提醒 |
| WPC-03 | 空状态、工具栏与首次理解 | 代码回归迁入 WCL-01；首次用户 3 秒理解只作提醒 |
| WPC-04 | 长文件分段、Provider 失败重试、任务恢复 | 技术开发迁入 WCL-02；真实用户文件/真实 Provider 只作提醒 |
| WPC-05 | 键盘路径、无障碍语义与主题适配 | 技术开发迁入 WCL-03；VoiceOver/视觉人工体验只作提醒 |
| WPC-06 | 权限状态机、拒绝/恢复与数据安全 | 技术开发迁入 WCL-03；TCC 手动撤销/授权只作提醒 |
| WPC-07 | Developer ID、公证、Catalog 与发行流水线 | 技术开发迁入 WCL-04；干净账户体验只作提醒 |
| WPC-08 | 自动化稳定性与正式包回归 | 技术开发拆分到 WCL-02～04；真实 Mac 矩阵只作提醒 |
| WPC 第 11 节 | Agent 权限、安全矩阵与 CLI 状态 | 技术开发迁入 WCL-05；真实批准和真实素材只作提醒 |

## 4. 技术工作包

### WCL-00：基线与迁移冻结（已完成）

- 固定此前稳定安装 Build `2026082408`、实施前 190 项 Swift 测试和当前代码契约为迁移基线；本轮覆盖安装的源码包为 `0.1.0 (Build 1)`，收口后官网版 `make verify` 回归为 203 项 Swift 测试 / 13 个 Suite，Store 条件因外部 Agent 实现编译裁剪为 181 项 / 10 个 Suite。
- 旧 WPC 不再保留活动开发待办；所有技术缺口必须能映射到 WCL-01～06。
- 计划索引、路线图、进度复核、规格和日志只指向本计划作为活动开发入口。

退出条件：文档引用一致，旧 WPC 无活动开发状态。

### WCL-01：工作台侧栏与信息密度（已完成）

- 侧栏占满可用高度；素材库、处理任务、文字转音频固定顶部，设置固定底部，只有中部上下文区滚动。
- 空列表、长列表、最小/默认/最大化窗口使用确定性布局，不改变 `WorkspaceRoute`、选择状态和设置草稿。
- 280 pt 侧栏下中英文标题、五种素材状态和双轨来源不出现不可读断词。
- 增加布局、路由、滚动边界、键盘切换与设置草稿回归测试。

退出条件：WCL-TAC-001～004 通过。

### WCL-02：转写、长文件与 Provider 恢复（已完成）

- 用固定无隐私 Fixture 锁定双轨分别转写、时间线合并和原始 Artifact 不覆盖。
- 完成长文件分段、时间戳合并、Lease/幂等、失败重试与重启恢复的确定性实现。
- Provider 大小限制、网络失败、超时和拒绝外发均 fail-closed；“稍后处理”持久化后可恢复。
- 音视频导入成功后自动打开详情；损坏、无音轨和未选模型不留下半成品或虚假完成状态。
- 新录音按选择只启动麦克风、电脑声音或两者；双开生成会议合成。三类新文件使用 AAC/M4A，旧 WAV/CAF 不自动转码或覆盖。
- 长素材详情不再同步预加载三条音轨，只保留一个按需播放器；原文和时间轴固定高度滚动，时间轴使用 `LazyVStack`。

退出条件：WCL-TAC-005～008 通过。

### WCL-03：权限、稳定性与无障碍代码保障（已完成）

- 权限状态机区分麦克风、系统声音、Speech 和辅助功能，覆盖未检查、拒绝、可用、需重新授权与运行时不可用。
- 复制不依赖辅助功能；自动粘贴、外发和录音控制继续使用最小权限与显式用户动作。
- 为睡眠、设备移除、进程异常、磁盘不足和恢复路径补齐可自动执行的状态机/Fixture 测试，保证已落盘素材不可覆盖。
- 侧栏、列表、工具栏、导入 Sheet 和任务状态具备稳定的 Label、Help、键盘顺序与非颜色状态语义。
- AppIcon 只使用 Bundle 资产来源，不在运行时用方形位图覆盖系统图标。
- 麦克风录音只有在收到首个 PCM 缓冲后才进入可见“正在录音”；无回调、写入错误或取消时 fail-closed 清理 Engine、tap、空 WAV 与分段目录。
- 设置页面的麦克风状态读取只返回缓存，不在主线程同步创建 `AVAudioEngine`；显式刷新在后台探测并在 1 秒内返回，避免 CoreAudio IPC 挂起冻结工作台。
- AppKit 退出先等待 `AppState.prepareForTermination()`：固化正在录音的 WAV/CAF、保留会话 journal 供下次启动恢复，并释放系统音频、实时转写、快捷键和本地 Connector；`appStateTerminationFinalizesRecordingAndRetainsJournal` 直接覆盖真实麦克风首帧、WAV 可读性、停止状态与 Journal 保留。
- 模型包、安装器、下载器、ASR、素材导入和 Context Package 的文件哈希统一走 `FileSHA256`，以 1 MiB 固定缓冲完成完整 SHA-256；Large-v3 启动不再因循环 `Data` 分配将物理内存推高到 1.3 GB 峰值。

退出条件：WCL-TAC-009～013 通过；首帧门禁、状态探测、退出清理与 Large 模型启动内存定向测试、`make acceptance-core`、`make verify` 和 Store 条件回归均通过。

### WCL-04：正式发行工程（脚本已就绪，发行验证阻塞）

- Developer ID Application 签名、Hardened Runtime、Notarization 和 Staple 流程可重复执行并响亮失败。
- 配置生产 Catalog host/key；生成 `ReleaseManifest.json`，并通过 `make release-verify-remote` 读回生产 manifest，校验 Catalog 与 Core/Offline 产物的状态、大小和 SHA-256。
- 固定 Bundle ID、Team ID、Designated Requirement、Entitlements、版本号与覆盖升级策略。
- 发行脚本输出唯一 Build 的签名、公证、Staple、DMG 和摘要证据。

退出条件：WCL-TAC-014～016 通过。缺少证书或公证凭据时保持“阻塞”，不得伪造完成。

### WCL-05：Agent Beta 安全收口（已完成源码与契约门禁）

- 实现只读查询、创建任务、录音控制三级独立权限；录音控制默认关闭。
- 当前协议不提供 Agent 再派发入口；未来若增加必须作为新的用户确认任务。现有 hop 上限、循环、重复派发、路径逃逸、超时、崩溃和输出超限全部 fail-closed。
- 完善 Codex CLI 交互批准状态、版本/安装/兼容性诊断；登录状态保持未检查，未经批准不得显示已连接。
- 完成前保留 `Beta`，不扩展为 AI 网关、聊天聚合器或插件市场。

退出条件：WCL-TAC-017～019 通过。

### WCL-06：Mac App Store 工程（MAS-03 本机切片已完成）

- 已按用户完成开发目标启动 MAS-03 本机能力切片：App 组合根使用 `StoreCapabilityProfile`，Store 编译配置不启动 Unix Socket Agent、不提供外部进程/用户可执行文件/自有更新器/自动粘贴入口；录音、本机转写、模型导入、HTTP Provider 和导出保留。
- 已补齐本机 Store 前置工程：`Resources/Woice-Store.entitlements`、`Resources/PrivacyInfo.xcprivacy`、`Resources/DistributionManifest.json`、`Resources/SBOM.json`、隐私/App Privacy 草案、Apple 上架资料快照、Store 打包参数、`make verify-app-store` 和 `make acceptance-app-store-sandbox`；`make store-capability-check` 通过 179 项 / 10 个 Suite，Bundle 静态检查额外拒绝外部 Agent/Provider 实现符号。
- 仍需按[Mac App Store 上架计划](2026-08-23-mac-app-store-launch.md)实施 MAS-00～02、MAS-04～08 的账号决策、Store 签名下 Sandbox/TCC、模型许可证与默认模型裁决、签名 Archive、TestFlight 和提交准备；正式 Xcode Target 已由 `project.yml` 生成并通过无签名构建。
- 官网 Core/Offline 的 Developer ID 产物、权限结论和更新器设计不能直接作为 Store Edition 技术证据。
- Store 本机回归更新：`make store-capability-check` 已通过 179 项 Swift 测试 / 10 个 Suite；`make xcode-build-store`、`verify-xcode-store-bundle`、`verify-app-store` 和 `acceptance-app-store-sandbox` 均通过。Apple 签名、TCC、TestFlight 和审核仍属外部条件。

退出条件：MAS 专项计划的技术工作包完成；当前 MAS-03 与本机静态预检通过，正式 Xcode/签名、沙盒运行、模型/隐私审定、TestFlight 和审核仍未完成。

### 4.1 当前关闭状态（2026-08-24）

| 工作包 | 当前状态 | 代码/门禁证据 | 尚需外部条件 |
|---|---|---|---|
| WCL-00 | 已完成 | 计划、路线图、进度复核、规格和日志已统一指向本计划 | 无 |
| WCL-01 | 已完成 | `WorkspaceSidebarLayout`、侧栏顶/中/底布局接线、几何与文本测试 | 真实视觉体验仅作提醒 |
| WCL-02 | 已完成 | 双轨分别转写/时间线合并、长文件分段、Job Lease/幂等、sidecar 恢复、Provider fail-closed 与媒体导入测试 | 真实会议和真实长文件仅作提醒 |
| WCL-03 | 已完成 | 权限状态、独立 Agent 权限保存、稳定性/磁盘/无障碍回归、AppIcon 单一来源门禁、麦克风首帧门禁、非阻塞状态探测、退出清理策略与真实录音集成测试；`make acceptance-core`、`make verify`、`make store-capability-check` 通过 | TCC 手动撤销/授权与 VoiceOver 体验仅作提醒 |
| WCL-04 | 发行验证阻塞 | `make release-developer-id` 具备签名/公证/staple、本地 manifest 和固定身份门禁；`make release-verify-remote` 具备生产 manifest 读回与远程状态/大小/摘要校验，缺凭据或不一致会失败 | Developer ID 身份、公证 profile、生产 Catalog URL/ID/可信公钥、已发布远程 manifest/产物 |
| WCL-05 | 已完成源码与契约门禁 | Agent 三级独立权限、二次确认、重复派发拒绝、CLI 版本/安装状态诊断和 Beta 文案已接入 | 真实 CLI 登录、批准和素材入站仅作提醒 |
| WCL-06 | MAS-03、正式 Xcode 组合根与 Store 本机静态预检已完成，其他 MAS 工作包未完成 | `StoreCapabilityProfile`、Store 编译条件、Agent/Socket/自动粘贴入口裁剪、`project.yml`/`Woice.xcodeproj`、`make xcode-build-store`（AppIcon/PrivacyInfo/NOTICES/DistributionManifest/SBOM 入 Bundle）、`verify_xcode_store_bundle.py`、`verify-app-store`、`acceptance-app-store-sandbox` | Apple 账号/签名、Store 签名下 Sandbox/TCC、模型/隐私资料、签名 Archive/TestFlight/审核 |

## 5. 技术验收标准

- WCL-TAC-001：顶部三功能、底部设置和中部独立滚动具有自动布局/几何回归。
- WCL-TAC-002：280 pt 侧栏下中英文、五种状态和双轨来源无不可读断词。
- WCL-TAC-003：四路由、搜索/筛选、选择状态、快捷键和未保存设置草稿不回归。
- WCL-TAC-004：布局修复不改变录音、导入和工具栏动作语义。
- WCL-TAC-005：双轨 Fixture 分别转写后按时间线合并，原始音频和旧 Transcript 不覆盖。
- WCL-TAC-006：长文件分段、时间戳合并、Lease、幂等和重启恢复测试通过。
- WCL-TAC-007：Provider 超限、失败、超时和未授权外发全部 fail-closed。
- WCL-TAC-008：导入成功自动打开详情；损坏、无音轨和未选模型不产生半成品。
- WCL-TAC-009：四类权限状态及拒绝/恢复分支具有确定性测试。
- WCL-TAC-010：复制、自动粘贴、外发和录音控制遵守最小权限边界。
- WCL-TAC-011：睡眠、设备变化、异常退出和磁盘不足的可模拟路径不覆盖已落盘素材。
- WCL-TAC-012：关键控件具备可访问名称、键盘路径和非颜色状态表达。
- WCL-TAC-013：Bundle AppIcon 单一来源门禁通过，不存在运行时方形覆盖。
- WCL-TAC-014：Developer ID、Hardened Runtime、Notarization 和 Staple 流程对唯一 Build 成功。
- WCL-TAC-015：生产 Catalog 与 Core/Offline 远程产物的状态、大小和摘要可校验。
- WCL-TAC-016：发行身份、Entitlements、版本与升级策略具有自动门禁。
- WCL-TAC-017：Agent 三级权限、显式用户确认和“当前协议无再派发入口”的 fail-closed 边界具有契约测试。
- WCL-TAC-018：循环、路径逃逸、重复派发、超时、崩溃和输出超限全部 fail-closed。
- WCL-TAC-019：CLI 未批准、未登录或不兼容时不显示已连接或已验证。

## 6. 开发门禁与关闭规则

- 文档门禁：`make docs-check`、`make harness-check`。
- 代码门禁：`make test`、`make lint`、`make verify` 和相关 `make acceptance-*`。
- 固定 Fixture 不得包含真实用户隐私；原始 Artifact SHA-256 必须保持不变。
- 每个工作包回写代码范围、命令原文、结果、Build 和证据路径；未执行项不写成通过。
- WCL-00～03、WCL-05 已完成源码与自动门禁；WCL-04 只有在真实凭据和生产 Catalog 可用后才能关闭。无 Agent 官网版本不因 WCL-05 的真实 CLI 账户验收而阻塞核心发行。
- WCL-05 不反向阻塞无 Agent 核心发行；WCL-06 已完成可在本机验证的 MAS-03、正式 Xcode 组合根和 Store Bundle 预检，其余工作包按上架计划继续，不把外部账号、正式签名、Archive 或审核状态伪造成完成。

## 6.1 本轮验证更新

- WCL-03 已关闭：真实麦克风→ASR、首帧门禁、非阻塞输入状态探测、退出音频资源清理、官网完整门禁和 Store 条件门禁均通过。
- Large-v3 启动内存回归已关闭：安装包使用现有模型数据连续运行 20 秒，RSS 稳定在 135,232～135,424 KiB；用户数据、模型和素材未迁移或删除。
- 当前仍未完成的开发/发行工作只剩 WCL-04 的真实 Developer ID/公证/Catalog/远程产物，以及 WCL-06 的 MAS-00～02、MAS-04～08 外部工作包；M2-09 真实 CLI Journey 和 M2-02 实时增量 ASR继续后置。

## 7. 非开发验收提醒

以下项目不计入开发排期、工作包、完成率或退出条件。技术实现完成后，只提醒用户按需体验：

- 用真实会议确认麦克风与电脑声音都进入最终合并原文。
- 用真实用户音频/视频、长文件和真实 Provider 体验导入、失败重试与“稍后处理”。
- 手动撤销/重新授予麦克风、系统声音、Speech 和辅助功能权限。
- 体验长录音、睡眠唤醒、设备移除、磁盘不足、全桌面、多窗口和常用会议应用。
- 使用 VoiceOver、完整键盘、高对比、Reduce Motion、字体放大、浅色/深色。
- 查看 Dock、Finder、Launchpad/应用切换器图标圆角与小尺寸视觉。
- 邀请首次用户判断页面状态、来源、处理状态和下一步动作是否清楚。
- 在干净账户体验安装、覆盖升级、Gatekeeper、权限连续性和数据保留。
- 按用户授权体验 Codex CLI 交互批准、真实素材入站和 Agent 派发。

发现问题时，再建立独立 bug/spec 并进入对应 WCL 技术工作包；体验本身不长期占用开发计划状态。
