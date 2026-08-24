# Woice 当前计划进度复核

> 复核日期：2026-08-24  
> 本轮补充：麦克风首帧门禁、非阻塞输入状态探测与退出音频资源清理代码已实现；`make acceptance-core`、`make verify` 和 Store 条件回归已恢复通过，真实音频宿主不再是当前 P0 阻塞。
> 结论：双音源选择、AAC/M4A 新录音、会议合成、长素材详情按需加载和录音控制视觉层级已实现。本轮官网版 `make verify` 已通过 208 项 Swift 测试 / 14 个 Suite，Store 条件已通过 186 项 / 11 个 Suite，正式 Xcode Store 无签名构建通过。[当前技术开发收口计划](2026-08-24-current-technical-development-closure.md)是唯一活动开发来源；真实会议声源、50 分钟以上素材和视觉体验仍由用户人工复验。

> 结论更新（19:20）：以上 197/175 与 0 帧内容是复核开始时的历史边界；之后已完成音频宿主恢复，并新增退出清理集成测试；官网 `make verify` 通过 201 项 / 13 个 Suite，Store 条件通过 179 项 / 10 个 Suite，WCL-03 已关闭。

> 结论更新（20:29）：启动校验 Large-v3 时的重复大块 `Data` 分配已改为固定 1 MiB 缓冲；安装包携现有用户数据的 RSS 从 1,785,056 KiB 降至稳定约 135 MiB。新增 2 项哈希回归后，官网 `make verify` 通过 203 项 / 13 个 Suite，Store 条件通过 181 项 / 10 个 Suite。

## 1. 本次复核范围

- 当前路线图：R0 录音核心、M2-01 双轨、M2-03 Artifact/恢复、M2-08 模型与发行、M2-09 Agent 协作。
- 新增专项：工作区侧栏与权限连续性（WPC，历史实施与证据记录）、当前技术开发收口（WCL，唯一活动开发计划）、菜单栏/设置/快捷键/Dock 与转写连续性（MSS-07R）。
- 发行基线：当前安装包为源码构建 `0.1.0 (Build 1)`；此前 Markdown 导出目录快捷键修复 A `2026082407` → B `2026082408` 的覆盖安装证据 `/private/tmp/woice-stable-ab-20260824-markdown-edit` 保留。CLI 文字默认与素材废纸篓的 A `2026082405` → B `2026082406`、可靠双轨、原文来源分离与 Build `2026082332` 的导入、VoiceOver、工作台证据仍作为相邻功能回归证据保留。

## 2. 已完成并有证据的内容

### 2.1 代码与自动门禁

- `make verify`：本轮通过 208 项 Swift 测试 / 14 个 Suite、PI/MCP、lint、生产构建和 Core 打包。Store 条件本轮通过 186 项 Swift 测试 / 11 个 Suite；`make xcode-build-store` 与 `verify-xcode-store-bundle` 通过。
- `make acceptance-core`：真实麦克风输入、本机/loopback/自定义 ASR、时长、时间戳和播放元数据通过。
- `make acceptance-meeting`：可见 QuickTime 声源下系统声音、CAF 和 `meetingMix` 双轨编排通过。
- `make acceptance-meeting-transcription`：默认及历史双轨素材均分别转写麦克风/电脑声音，系统轨标准化、来源合并和原始字节不变通过。
- `make acceptance-interruption`：真实麦克风配置变化安全停止，WAV、Journal 和本机转写素材保留通过。
- `make acceptance-settings`、`acceptance-material`、`acceptance-recovery`、`acceptance-local-provider`、`acceptance-catalog` 通过。
- `make acceptance-media-import-transcription`、`acceptance-permission-continuity`、`acceptance-workspace-sidebar` 通过；导入契约、权限拆分和单一侧栏代码边界已锁定。
- 本轮复跑 `acceptance-core`、`acceptance-meeting`、`acceptance-meeting-transcription`、`acceptance-interruption`、`acceptance-settings`、`acceptance-recovery`、`acceptance-media-import-transcription`、`acceptance-local-provider`、`acceptance-catalog`、`acceptance-whisperkit` 和 `acceptance-offline-model` 均通过；真实 WhisperKit 麦克风转写与 Offline DMG 校验也有当前运行证据。
- `make acceptance-agent-outbound`、`acceptance-agent-inbound` 通过；真实 CLI/外部 Agent 仍按 Beta 后置，不把契约通过写成真实产品连接已完成。
- 2026-08-24 复跑侧栏、Agent、Catalog、设置、恢复、素材、媒体导入、权限连续性、稳定升级、启动窗口和无障碍入口矩阵，退出码 `0`；脚本提示的真实签名/TCC、Finder/Dock、VoiceOver 与高对比体验仍保持为显式人工验收。
- 已有运行时证据：稳定 Build B 启动/关闭/重开/单实例、AX 树和 `⌘2 -> 处理任务` Journey 通过。
- 当前 Build B 桌面导入边界已复跑：系统 `Funk.aiff` 正常导入/Fixture 转写通过并验证原件 SHA-256 不变；损坏视频显示“导入失败”且无半成品；有效无音轨视频显示“视频没有可用音轨”且无半成品。

### 2.2 MSS-07R 新增内容

- loopback 健康检查信任摘要持久化，模型、语言、时间戳或配置变化会失效；不保存 API Key。
- 菜单栏不再弹转写模态确认；需要外发的确认统一进入工作台。
- “稍后处理”改为可恢复排队；重启后可继续处理。
- 主转写与声音片段任务去重，避免同一素材产生竞争任务。
- 工作台外部处理确认卡的 VoiceOver 名称已修复为运行时目标标题，不再朗读源码占位文本。
- 菜单栏录音时长/麦克风状态、快捷键候选状态均改为运行时插值；对应启动窗口与工作区契约门禁已加入，避免把源码占位符展示给用户或 VoiceOver。
- 导入 Sheet 的状态卡、状态说明、主按钮标题和禁用态现在共享同一个“活动转写任务”投影；旧记录同时存在主任务和片段任务时，优先显示运行中/等待确认/等待模型/排队状态，避免出现“状态卡显示正在转写、按钮却要求点击转文字”的矛盾。
- 处理任务工作区不再使用 `processingTasks.last` 猜测状态；导入页和处理任务列表共用 `ProcessingTaskProjection`，按状态、更新时间、任务类型和数组位置确定性投影。
- “可继续的任务”只展示活动任务为排队、失败或中断的素材；运行中/等待确认/等待模型任务不会因旧任务残留再次出现继续入口，`resumeProcessing` 也使用同一投影。
- 新增活动任务回归测试 5 项，稳定签名 A `2026082327` → B `2026082328` 已覆盖安装；当前安装包严格签名校验、启动、AX 树和 `⌘2 -> 处理任务` Journey 通过。
- 音视频导入新增空文件/损坏视频错误分类回归测试，桌面脚本新增预期失败模式；稳定签名 A `2026082329` → B `2026082330` 已覆盖安装，启动/AX/键盘 Journey 与正常/失败导入均通过。
- 处理任务侧栏与 VoiceOver 标签现在和可见任务行共用 `activeTask` 投影；稳定签名 A `2026082331` → B `2026082332` 已覆盖安装，启动/AX/键盘 Journey、正常导入、损坏视频和无音轨视频 Journey 均通过。

### 2.3 WPC 新增内容

- 单一工作台侧栏、导入后原位转写、成功后自动选中新素材、来源/状态/空状态表达已实现。
- 普通复制与自动粘贴权限已拆分；稳定签名 A/B 覆盖安装证据已生成。
- 稳定签名 A `2026082317` → B `2026082318` 已在解锁桌面连续覆盖安装；工作台、麦克风、系统音频和粘贴授权状态保持，未重复弹窗。
- Build B 的系统音频 Fixture 导入桌面 Journey已通过，原件与派生 WAV 保留在隔离目录，QuickTime 系统声音/meetingMix 验收已复跑通过。
- 用户此前手动通过的是双轨采集；2026-08-24 发现默认单次混音 ASR 会漏掉其中一路。可靠双轨合并代码与自动契约已修复；当前安装包的原文不再插入声音来源，来源保留在时间戳/JSON，真实会议合并内容需要重新手动确认。
- 前端可见 CLI 统一命名为 `Beta`，未完成项集中在 WPC 第 11 节最后优先级。
- 复核并同步 8 份专项规格的状态头，移除“实施中/开发中”与当前代码证据不一致的表述；真实 Mac 与人工体验边界保留为提醒，不计入开发完成率。

### 2.4 WCL 技术开发分流

- 截图证据：[01-workspace-sidebar-layout.png](../audit/2026-08-24-workspace-sidebar-layout/01-workspace-sidebar-layout.png)。
- 可见问题：空素材库时，“工作区 + 素材上下文 + 设置”整组被垂直居中；上方和下方同时出现大片无意义空白。
- 计划裁决：[WCL 计划](2026-08-24-current-technical-development-closure.md)只管理三个主功能固定顶部、设置固定底部、中部独立滚动及其自动回归；不修改路由、列表数据或设置草稿。
- 技术门禁：新增确定性布局/几何回归，覆盖空/长列表和窗口尺寸变化；真实截图只用于问题提示，不作为计划退出条件。
- 迁移闭环：旧 WPC 中需要代码、自动测试、发行工程和 Agent 安全开发的部分迁入 WCL-01～06；首次用户、真实素材、真实会议、TCC 手动操作和视觉体验进入非开发提醒。

## 3. 技术开发状态

### P0：界面与处理链（已关闭）

- WCL-01：侧栏顶/中/底布局、最小宽度文案约束和几何回归已实现。
- WCL-02：双轨合并、长文件分段、Provider fail-closed、Lease/幂等、重启恢复和导入失败安全已有自动门禁。
- WCL-02 当前增量：双音源四态设置与双关 fail-closed、系统单轨恢复语义、AAC/M4A 会议合成、统一按需播放器及原文/时间轴固定滚动区已接入；当前安装包的真实会议声源与 50 分钟素材由用户复验。

### P1：权限、稳定性与无障碍保障（已关闭）

- WCL-03：四类权限与恢复/稳定性路径、无障碍语义和 AppIcon 单一来源门禁已接入；麦克风首帧门禁、非阻塞输入状态探测和退出音频资源清理已实现并通过定向测试、`make acceptance-core`、`make verify` 与 Store 条件回归；TCC/VoiceOver 体验仅作人工提醒。

### P2：发行与 Agent

- WCL-04：发行脚本、固定身份门禁、本地 `ReleaseManifest.json` 与远程 manifest 读回门禁已完成；真实 Developer ID、公证 profile、生产 Catalog 和已发布远程产物缺失，保持阻塞。
- WCL-05：三级独立权限、二次确认、重复派发拒绝、CLI 版本/安装状态诊断和 Beta 文案已完成源码与契约门禁。
- WCL-06：已完成 MAS-03 本机能力裁剪、`project.yml`/`Woice.xcodeproj` 正式 Store 组合根和 `Woice-Store / Release-AppStore` 无签名构建，以及 Store 本机打包/隐私/沙盒静态预检；MAS-00～02、MAS-04～08 的 Apple 决策、Store 签名下 Sandbox/TCC、模型/隐私资料、签名 Archive、TestFlight 和审核仍待外部条件。

## 4. 非开发提醒

- 真实会议、真实用户音视频、真实 Provider、TCC 手动撤销/授权、长录音与桌面稳定性、VoiceOver/视觉体验、首次用户理解、干净账户安装和真实 CLI/素材入站均只作提示。
- 这些项目不进入开发工作包、完成率或退出条件；体验发现缺陷后再单独建立 bug/spec。

## 5. 下一步顺序

1. WCL-04：补齐真实 Developer ID 身份、公证 profile、生产 Catalog 和已发布远程 manifest/产物后，运行 `make release-developer-id`，再运行 `make release-verify-remote`。
2. WCL-06：在 Apple 账号、Bundle/价格/模型许可证决策明确后，继续 MAS-00～02、MAS-04～08；当前可用 `make xcode-build-store`、`make model-package-check`、`make verify-app-store`、`make acceptance-app-store-sandbox` 和 `make store-capability-check` 回归本机 Store 工程、模型门禁、能力裁剪与 Bundle 预检。

## 5.1 当前待开发清单

| 优先级 | 工作包 | 当前状态 | 下一步/阻塞 |
|---|---|---|---|
| P0 | WCL-04 官网 Developer ID 发行 | 代码、签名/公证脚本和远程 manifest 门禁已完成，发行验证阻塞 | 提供 Developer ID 身份、公证凭据、生产 Catalog URL/ID/可信公钥并发布远程 manifest/产物；运行 `make release-developer-id` → `make release-verify-remote` |
| P0 | MAS-00 产品与账号决策 | 未冻结 | 决定开发者主体、最终 Bundle ID/SKU、价格/地区、默认模型和首版是否保留自动粘贴；这些不是本机代码缺口 |
| P0 | MAS-01 Store 正式签名 Archive | Xcode 工程、Scheme、资源和无签名构建完成；签名 Archive/Validate 未执行 | 提供 Apple Team、Store 签名身份和 Provisioning Profile；运行 `make archive-app-store`，再由 Xcode Organizer Validate |
| P0 | MAS-02 Store Sandbox/TCC | 本机 Entitlements/静态预检完成 | 需要 Apple 团队签名后验证容器路径、Keychain、录音、系统音频、模型导入、覆盖升级和干净用户 |
| P0 | MAS-04 模型发行裁决 | 本机许可证字段/NOTICE/SHA/SBOM 门禁完成 | 完成 Tiny/Large-v3 权重再分发法律确认，冻结首版内置模型；未确认不得进入 Store Bundle |
| P0 | MAS-05～06 隐私与商店资料 | 草案/资产骨架完成 | 完成线上隐私政策 URL、App Privacy/出口合规答卷、Review Notes、真实签名 Build 截图、描述、关键词和支持 URL |
| P0 | MAS-07～08 TestFlight/审核 | 尚未开始 | 先完成 MAS-00～06，再做 TestFlight 真实 Mac 矩阵、提交审核和用户确认后的手动发布 |
| P1（后置） | M2-09 Agent Beta | 源码与契约门禁完成，核心不阻塞 | 真实 CLI 登录/批准、素材入站和外部 Agent Journey 由用户按 Beta 手动验收；不扩成网关或入口 |
| 后续增强 | M2-02 实时增量 ASR/说话人分离 | 当前计划明确后置 | 不影响录音→本机转写闭环，另立规格后再排期 |

## 6. 当前判断

首帧门禁、非阻塞输入状态探测和退出清理代码已完成；本轮 10 项麦克风定向测试、`make acceptance-core`、官网 `make verify` 和 Store 条件回归均通过，之前的 CoreAudio IPC/0 帧环境边界已解除。

这里的“WCL-03 已完成”包含权限、稳定性、无障碍、首帧门禁、非阻塞状态探测、退出清理代码/确定性测试和本轮真实音频门禁；TCC 手动操作与 VoiceOver 体验不计入开发完成率。

当前状态应写为：**当前安装包为源码构建 `0.1.0 (Build 1)`，此前稳定包 Build `2026082408` 仅作历史证据；Large-v3 启动校验内存已修复，安装包携现有用户数据稳定在约 135 MiB RSS；本轮官网版 `make verify` 通过 203 项 Swift 测试 / 13 个 Suite、PI/MCP、构建、lint 和 Core 打包，Store 条件通过 181 项 Swift 测试 / 10 个 Suite；`make acceptance-core`、退出清理集成测试、`make xcode-build-store`、`verify_xcode_store_bundle.py`、`make model-package-check`、`verify-app-store` 与 `acceptance-app-store-sandbox` 均通过。WCL-00～03、WCL-05 已完成源码与自动门禁；WCL-04 因发行凭据阻塞；WCL-06 已完成 MAS-03、正式 Xcode 组合根与本机 Store 预检，签名 Archive、TestFlight、审核和 Apple 决策仍待外部条件。**
