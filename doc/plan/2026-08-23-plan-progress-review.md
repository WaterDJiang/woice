# Woice 当前计划进度复核

> 复核日期：2026-08-24  
> 结论：代码与自动门禁已达到可交付候选，但当前计划尚未整体完成；真实 Mac 权限、视觉无障碍、长时稳定性和发行验收仍是关闭条件。

## 1. 本次复核范围

- 当前路线图：R0 录音核心、M2-01 双轨、M2-03 Artifact/恢复、M2-08 模型与发行、M2-09 Agent 协作。
- 新增专项：工作区侧栏与权限连续性（WPC）、菜单栏/设置/快捷键/Dock 与转写连续性（MSS-07R）。
- 发行基线：当前安装包为 Apple Development Build `2026082406`；CLI 文字默认与素材废纸篓修复 A `2026082405` → B `2026082406` 已覆盖安装，证据 `/private/tmp/woice-stable-ab-20260824-text-only-trash`。可靠双轨、原文来源分离与 Build `2026082332` 的导入、VoiceOver、工作台证据仍作为相邻功能回归证据保留。

## 2. 已完成并有证据的内容

### 2.1 代码与自动门禁

- `make verify`：双轨可靠合并、原文/来源分离、CLI 文字默认和素材废纸篓修复后的 190 项 Swift 测试 / 11 个 Suite、PI 6 项、MCP 2 项、文档/Harness、lint、生产构建和打包全部通过。
- `make acceptance-core`：真实麦克风输入、本机/loopback/自定义 ASR、时长、时间戳和播放元数据通过。
- `make acceptance-meeting`：可见 QuickTime 声源下系统声音、CAF 和 `meetingMix` 双轨编排通过。
- `make acceptance-meeting-transcription`：默认及历史双轨素材均分别转写麦克风/电脑声音，系统轨标准化、来源合并和原始字节不变通过。
- `make acceptance-interruption`：真实麦克风配置变化安全停止，WAV、Journal 和本机转写素材保留通过。
- `make acceptance-settings`、`acceptance-material`、`acceptance-recovery`、`acceptance-local-provider`、`acceptance-catalog` 通过。
- `make acceptance-media-import-transcription`、`acceptance-permission-continuity`、`acceptance-workspace-sidebar` 通过；导入契约、权限拆分和单一侧栏代码边界已锁定。
- 本轮复跑 `acceptance-core`、`acceptance-meeting`、`acceptance-meeting-transcription`、`acceptance-interruption`、`acceptance-settings`、`acceptance-recovery`、`acceptance-media-import-transcription`、`acceptance-local-provider`、`acceptance-catalog`、`acceptance-whisperkit` 和 `acceptance-offline-model` 均通过；真实 WhisperKit 麦克风转写与 Offline DMG 校验也有当前运行证据。
- `make acceptance-agent-outbound`、`acceptance-agent-inbound` 通过；真实 CLI/外部 Agent 仍按 Beta 后置，不把契约通过写成真实产品连接已完成。
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
- 复核并同步 8 份专项规格的状态头，移除“实施中/开发中”与当前代码证据不一致的表述；未完成的真实 Mac、生产服务和 Agent 入站边界仍明确保留。

## 3. 尚未关闭的清单

### P0：需要用户在当前 Mac 上完成

- TCC 连续性：稳定签名 A `2026082317` → B `2026082318` 已覆盖安装实测；已有麦克风、系统声音和粘贴授权在 B 保持，未重复弹窗。当前稳定包已继续完成 A `2026082331` → B `2026082332` 覆盖安装与签名声明门禁；本轮未把声明比较当成新的 TCC 实测，逐项撤销后重新授权、Speech/辅助功能完整矩阵和真实录音仍待，不得用 `tccutil reset` 代替证据。
- 桌面导入 Journey：当前安装包已用系统 `Funk.aiff` 音频正常导入并完成 Fixture 转写；损坏视频和有效无音轨视频均在隔离存储中按预期失败，未留下原件/派生半成品。真实用户文件选择、真实长文件、真实 Provider 失败重试仍待。

### P1：真实 Mac 稳定性与体验矩阵

- 真实会议 UI：双轨采集已由用户手动通过；修复后的“麦克风/电脑声音分别转写并合并”需在新安装包上用一段双方都有独立内容的会议重新确认。
- 长录音、睡眠唤醒、输入设备移除、进程崩溃、磁盘异常和低容量实机路径。
- VoiceOver、完整键盘流程、高对比、Reduce Motion、字体放大、浅色/深色和最小窗口截图。
- Dock、Finder、Launchpad/应用切换器的 AppIcon 圆角与小尺寸视觉复核。
- 首次用户 3 秒理解工作区、来源、状态和下一步动作。
- 云端外发“稍后处理 -> 重启 -> 继续”已验证本地任务恢复和确认卡重现；未点击外发确认，真实 Provider 完成 Journey 仍待。

### P2：发行与外部服务

- 生产 Catalog host/key、Developer ID 签名、公证和干净账户覆盖安装；当前机器仅发现 Apple Development 身份，`xcrun notarytool history` 因未配置凭据退出，属于发行前置条件未满足，不是应用运行时失败。
- 真实 Codex/Claude 入站批准、真实用户素材入站、三级权限/二次确认和正式签名包 Smoke。
- Mac App Store Store Edition 计划仍未启动。

### P3：CLI Beta（计划最后）

- Codex CLI 交互批准、真实素材入站、权限矩阵、派发链循环/越权矩阵、登录/版本/兼容提示和正式发行验收。
- 在上述项目完成前，继续保留前端 `Beta` 标记，不扩展为 AI 网关、聊天入口或通用插件市场。

## 4. 下一步顺序

1. 使用用户明确选择的真实音频/视频文件，补跑真实长文件和真实 Provider 失败重试；无音轨/损坏的自动与桌面边界已关闭。
2. 在不重置 TCC 的前提下，补做逐项撤销/重新授权、Speech/辅助功能和真实录音验证。
3. 在新安装包复验一次双轨合并原文，再完成视觉/无障碍和长时稳定性矩阵。
4. 补齐生产签名、公证、Catalog 和干净账户安装证据。
5. 最后再启动 CLI Beta 清单；未完成前不把 M2-09 或 WPC 整体标为完成。

## 5. 当前判断

当前状态应写为：**双轨可靠合并、纯文本原文/声音来源分离、CLI 默认文字交付和素材可恢复删除代码、完整 verify 和稳定签名 A `2026082405` → B `2026082406` 覆盖安装已通过，旧版单次混音与 CLI 强制 WAV 默认均已停止；真实会议合并内容仍待复验。真实用户长文件/Provider、逐项 TCC 重授权、完整视觉无障碍、长时稳定性和发行关闭条件仍未完成。**
