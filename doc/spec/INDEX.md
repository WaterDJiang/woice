# spec/ 索引

| 功能域 | 状态 | 一句话定义 | 文件 |
|---|---|---|---|
| App Store Build 7 资料与门禁收口 | 本机准备完成；Catalog v2、正式 Archive 与导出包已验证，远端/账号/实机状态待完成 | 递增 Build、修复检查更新、生成含 Qwen 的签名 Catalog v2、准备正式 Archive/导出包和审核材料 | [../specs/2026-09-03-app-store-submission-readiness.md](../specs/2026-09-03-app-store-submission-readiness.md) |
| 模型清单 Raw 响应类型兼容修复 | 已实现；定向传输回归通过 | 兼容 GitHub Raw 返回 `text/plain; charset=utf-8` 的合法 JSON，同时保留 Catalog schema、签名和版本门禁 | [../specs/2026-09-03-model-catalog-content-type.md](../specs/2026-09-03-model-catalog-content-type.md) |
| 本机已完成任务重转写 | 代码与定向回归完成；真实桌面由用户验收 | 已有本机转写任务为 `completed` 时，重新转写先回到 `queued`，重新取得 Lease 并追加新的 Artifact；不覆盖旧原文 | [../specs/2026-09-01-local-retranscription-completed-task.md](../specs/2026-09-01-local-retranscription-completed-task.md) |
| 模型库存扫描隔离 | 代码与定向回归完成；真实模型页视觉由用户验收 | 损坏或半安装版本按版本隔离，不阻塞其它已验证模型显示、切换和回滚；运行时校验仍 fail-closed | [../specs/2026-09-01-model-inventory-isolation.md](../specs/2026-09-01-model-inventory-isolation.md) |
| 模型基准空信号与严格门禁 | 代码、30/300/3600 秒 Qwen-only 自动门禁与官方中英文参考对照通过；多模型矩阵仍暴露 Whisper 静音/噪声幻觉 | 固定 URL/SHA 的官方参考夹具、静音/噪声预期空结果与异常失败分离，语音空输出、模型异常和非空幻觉继续 fail-closed | [../specs/2026-09-01-model-benchmark-signal-gates.md](../specs/2026-09-01-model-benchmark-signal-gates.md) |
| 素材质量与命名修复 | MRQ-01/MRQ-02 代码与自动测试完成；Qwen 公开英文样本烟测通过；完整模型/升级验收待 | Qwen 输出质量门禁、短尾静音过滤与 `userTitle`/`displayTitle` 真相源 | [../specs/2026-09-01-material-quality-and-naming.md](../specs/2026-09-01-material-quality-and-naming.md) |
| 导入转写浮窗后台继续 | 代码与定向测试完成，真实桌面手感待确认 | 转写开始后可明确关闭浮窗，任务继续后台运行；支持处理页路由、Escape、VoiceOver 和原件安全提示 | [../specs/2026-09-01-media-import-background-transcription.md](../specs/2026-09-01-media-import-background-transcription.md) |
| 导入转写后台继续真实桌面验收 | 隔离 Journey 已实现，需在无其他 Woice 进程的目标桌面执行 | 测试模式让 Fixture 转写保持运行，验证“关闭并后台继续”后窗口仍可操作且任务最终持久化 | [../specs/2026-09-01-media-import-background-journey.md](../specs/2026-09-01-media-import-background-journey.md) |
| 录音耐久与详情性能 | MRQ-00/MRQ-03/MRQ-04 代码、自动测试与合成基准完成；故障保留/事务回滚/hydrate fail-closed 自动验证通过；真实 Mac 待 | 滚动音频块、Manifest 恢复、摘要/详情加载与性能基线；不把 SIGKILL/掉电和真实 UI 体验静态测试冒充完成 | [../specs/2026-09-01-recording-durability-and-detail-performance.md](../specs/2026-09-01-recording-durability-and-detail-performance.md) |
| App Store 0.1.4 Build 6 正式提交 | Build 6 已上传并由 Apple 处理；商店资料与提交审核待完成 | 发布三声道录音及当前已验证修复的无模型 Store Build，上传后补齐资料并提交审核 | [../specs/2026-09-01-app-store-build6-submission.md](../specs/2026-09-01-app-store-build6-submission.md) |
| Qwen 推荐 Catalog 与 Dev / Store 0.1.4 发布 | Build 5 已上传，Catalog 私钥仍阻塞 v2 | 本地安装稳定签名 Dev，Catalog v2 加入千问，正式无模型 Store Build 上传 App Store Connect | [../specs/2026-08-31-qwen-catalog-dev-store-release.md](../specs/2026-08-31-qwen-catalog-dev-store-release.md) |
| Dev / Store App 命名、隔离与旧包清理 | 代码与自动门禁完成；真实双安装/TCC Journey 待可信本机签名 | Dev 为 `Woice (Dev)` 并使用独立 Application Support、Keychain、锁与 Socket；Store 保持 `Woice`，不触碰正式数据与 Archive | [../specs/2026-08-31-dev-store-app-naming-and-cleanup.md](../specs/2026-08-31-dev-store-app-naming-and-cleanup.md) |
| 直接发行包模型下载重试 | 代码与自动门禁完成；真实 WhisperKit 下载验收通过 | Core/Offline 的 WhisperKit Hub 与通用模型包下载对瞬时 TLS、连接中断和超时有限重试，并保留续传、取消和原子安装边界 | [../specs/2026-08-30-model-download-retry.md](../specs/2026-08-30-model-download-retry.md) |
| 实时文字预览、顶部面板收起与导入页优化 | 代码与自动门禁完成 | 录音期间在工作台和菜单栏显示本机 partial transcript，Popover 点击外部收起，导入页收紧并支持拖放 | [../specs/2026-08-25-live-preview-popover-and-import-ux.md](../specs/2026-08-25-live-preview-popover-and-import-ux.md) |
| 本机模型一键安装与 App Store 兼容 | 库存去重、Tiny/Qwen/Large 三档推荐、首启提示与 Store 无模型门禁完成；新版签名 Catalog 待发布 | 无模型时只需一次点击，自动完成下载、校验、安装、切换和等待任务恢复；Store 安装包不携带模型 | [../specs/2026-08-25-one-click-model-installation-and-store-compatibility.md](../specs/2026-08-25-one-click-model-installation-and-store-compatibility.md) |
| 录音控制区视觉层级 | 按用户复核移除工作台顶部动作，代码、自动门禁与覆盖安装完成 | 菜单栏音源使用中性状态按钮、录音是唯一主动作；工作台顶部不再复制导入和录音控制 | [../specs/2026-08-25-recording-control-visual-hierarchy.md](../specs/2026-08-25-recording-control-visual-hierarchy.md) |
| 双音源、压缩存储与长素材详情 | 代码与自动门禁完成，SwiftPM QuickTime 系统声音/会议合成验收通过；当前安装包 TCC/双轨手测待 | 工作台顶部独立控制麦克风/电脑声音，默认双开；新录音使用 AAC/M4A，双开生成 48 kHz 单声道会议合成回放，默认按原轨分别转写；详情只保留一个按需播放器及固定滚动原文/时间轴 | [../specs/2026-08-25-dual-source-storage-and-long-detail.md](../specs/2026-08-25-dual-source-storage-and-long-detail.md) |
| Large 模型启动校验内存 | 已修复并完成安装包实测 | 所有模型与素材 SHA-256 校验统一使用 1 MiB 固定缓冲；Large-v3 用户数据启动 RSS 从 1,785,056 KiB 降至约 135 MiB，仍保持完整哈希和 fail-closed | [../specs/2026-08-24-model-validation-startup-memory.md](../specs/2026-08-24-model-validation-startup-memory.md) |
| 会议双音轨、统一回放与合并转写 | 代码与自动门禁完成，真实会议验收仅作提醒 | 保留双原轨，默认按麦克风/系统音频分别转写并按时间线合并；`standardMix` 仅为显式兼容模式，`meetingMix` 主要用于统一回放 | [2026-08-22-dual-track-meeting-transcription.md](2026-08-22-dual-track-meeting-transcription.md) |
| 真实会议录音验收声源 | 可见 QuickTime 声源验收已通过；当前安装包 TCC/真实会议应用 Journey 待复验 | 窗口级 ScreenCaptureKit 只能用可捕获窗口归属的播放应用；QuickTime 无法启动或会话锁定时必须失败，不把静音 buffer 当作成功 | [../specs/2026-08-23-real-meeting-acceptance.md](../specs/2026-08-23-real-meeting-acceptance.md) |
| 系统音频权限状态与真实采集可靠性 | 权限/无显示器错误分层已实现，当前安装包需真实桌面确认 | 修复已授权仍显示需要授权的误报，并以 ScreenCaptureKit 实际能力验证视频/会议声音；无采集目标时不伪造成功 | [2026-08-22-system-audio-permission-reliability.md](2026-08-22-system-audio-permission-reliability.md) |
| 系统声音来源与采集事实可见性 | 本轮实现，麦克风 UI Journey 已通过；系统声音仍待当前安装包 TCC 复验 | 明确系统声音是获取后独立保存的 CAF，详情页展示可复听音轨、时长、buffer 和峰值，设置区合并权限与能力 | [2026-08-22-system-audio-source-observability.md](2026-08-22-system-audio-source-observability.md) |
| 菜单栏状态图标可识别性 | 已实现，安装包已更新，待用户视觉确认 | 用圆形音频图标和明确提示替代窄条波形，区分空闲入口与录音状态 | [2026-08-22-menubar-status-mark-clarity.md](2026-08-22-menubar-status-mark-clarity.md) |
| 菜单栏、设置、快捷键与 Dock 图标精简优化 | 代码实施完成，真实 Mac Journey 待用户 | Popover 动态高度、四动作命令面板、默认/高级设置、自定义快捷键冲突回滚、Bundle AppIcon 单一来源和录音来源投影 | [../specs/2026-08-23-menubar-settings-shortcut-optimization.md](../specs/2026-08-23-menubar-settings-shortcut-optimization.md) |
| 系统声音采集与按钮视觉审计 | UI 已实现，自动门禁通过，系统声音真实 Journey 受当前安装包 TCC 阻塞 | 统一按钮层级与反馈，验证会议模式下 ScreenCaptureKit 系统声音独立落盘与复听 | [2026-08-22-system-audio-and-button-visual-audit.md](2026-08-22-system-audio-and-button-visual-audit.md) |
| 全局按钮反馈与操作质感 | 已实现，待桌面 Journey 人工验收 | 统一按钮按下、处理中、成功、失败和 VoiceOver 反馈，优先覆盖复制/粘贴/刷新 | [2026-08-22-button-feedback-ux.md](2026-08-22-button-feedback-ux.md) |
| Logo 白底替换 | 已实现，安装包已更新 | 保持 W 标记不变，将生产母版、尺寸族和 App Bundle 背景统一为纯白 | [2026-08-22-logo-white-background.md](2026-08-22-logo-white-background.md) |
| 产品定位：语音上下文来源 | 已确认，最新修正版 | Woice 先完成录音/转写/素材闭环；外部 Agent 仅作为素材交付方或授权读取方，不形成网关/入口 | [2026-08-22-voice-context-source-positioning.md](2026-08-22-voice-context-source-positioning.md) |
| 设置页与菜单栏操作体验 | 实现中 | 设置侧栏、草稿保存和菜单栏历史/设置/退出动作遵循原生 macOS 交互 | [2026-08-22-settings-menu-experience.md](2026-08-22-settings-menu-experience.md) |
| 模型下载状态显示 | 实现中 | 按模型 packID/revision 显示活动下载，避免 Tiny/Large 状态串显示 | [2026-08-22-model-download-status-display.md](2026-08-22-model-download-status-display.md) |
| 独立文字转音频与后台转写 | 已实现，待长会人工验收 | 录音链路只做 ASR；文字/文件转音频独立入口；本机 VAD 片段可在长录音期间后台串行转写 | [2026-08-22-independent-tts-and-background-transcription.md](2026-08-22-independent-tts-and-background-transcription.md) |
| 模型切换后的已有录音重转写 | 已实现，Large 已安装 WAV 本机推理验收通过 | 切换已安装模型后重转写使用当前快照，短暂 Lease 竞争可恢复且不覆盖原始素材；性能基准与发布门禁另计 | [2026-08-22-model-switch-retranscription.md](2026-08-22-model-switch-retranscription.md) |
| 双版本分发与模型接入 | 实现中；Core/Offline ad hoc 打包基础已实现 | 同一 App 产出轻量版/离线版，并统一内置模型包、本地服务和受控进程 Provider 的接入体验 | [2026-08-22-dual-edition-model-integration.md](2026-08-22-dual-edition-model-integration.md) |
| Catalog 多文件模型下载编排 | 基础实现完成；真实生产 Catalog 服务待验证 | 已验证 Catalog 条目通过 HTTPS host allowlist、Range 续传、逐文件 SHA-256 和原子安装进入本机模型库存 | [../specs/2026-08-23-catalog-model-download-orchestration.md](../specs/2026-08-23-catalog-model-download-orchestration.md) |
| 后台分段转写耐久化 | 本轮实现，真实长会 Journey 待验收 | VAD 片段转写结果原子写入本地 sidecar，异常退出后恢复部分原文，不覆盖原始录音 | [../specs/2026-08-23-background-transcription-durability.md](../specs/2026-08-23-background-transcription-durability.md) |
| ProcessingTask 配置快照 | 本轮实现，历史任务兼容 | 新建/重试任务写入不含 API Key 的 `sha256-v1` 配置摘要，记录实际 Provider、模型、Endpoint 边界和转写参数 | [../specs/2026-08-23-processing-configuration-snapshot.md](../specs/2026-08-23-processing-configuration-snapshot.md) |
| 本机 ASR 服务预设 | 本轮实现，真实服务连接待用户确认 | 为 OpenAI-compatible 的通用、whisper.cpp、faster-whisper、FunASR/LocalAI 提供可编辑 loopback 起点，不自动扫描或启动服务 | [../specs/2026-08-23-local-asr-service-presets.md](../specs/2026-08-23-local-asr-service-presets.md) |
| 双轨会议转写本机验收 | 本轮实现，真实会议与桌面矩阵待完成 | 用确定性 loopback Fixture 验证标准 meetingMix 单请求、来源分离双请求和系统轨 WAV 标准化，不伪造真实服务或会议 Journey | [../specs/2026-08-23-meeting-transcription-acceptance.md](../specs/2026-08-23-meeting-transcription-acceptance.md) |
| Agent 只读素材搜索与分页读取 | M2-09e 只读增量已实现，真实 PI/Agent Smoke 待后续 | 外部 Agent 通过版本化本地 RPC 搜索素材并按 Unicode 边界分页读取原文；不触发处理、外发或录音 | [../specs/2026-08-23-agent-readonly-search-pagination.md](../specs/2026-08-23-agent-readonly-search-pagination.md) |
| Context Package 与受控 CLI 契约 | M2-09a/b/c 本机基础已实现，真实 CLI/外部结果链待后续 | 冻结多素材/时间范围/指令/文件哈希、CLI 适配器元数据、受控 Runner 和 Agent Job 状态；不自动启动真实 CLI | [../specs/2026-08-23-agent-context-package-contract.md](../specs/2026-08-23-agent-context-package-contract.md) |
| Agent 任务与连接状态 UI | M2-09f 三步派发/结果入口已实现，真实外部 Journey 待后续 | 在设置、录音详情与处理工作区展示目标、durable 任务状态和结果来源链；不自动发现或执行 CLI | [../specs/2026-08-23-agent-job-ui-status.md](../specs/2026-08-23-agent-job-ui-status.md) |
| Agent 出站派发与结果 Artifact | fixture 闭环已实现，真实 CLI/外部 Agent Journey 待执行 | 三步用户确认、Codex/Claude 受控派发、结果落盘、不可变来源链和元数据审计；不执行返回内容 | [../specs/2026-08-23-agent-dispatch-and-results.md](../specs/2026-08-23-agent-dispatch-and-results.md) |
| MAS 本机发行门禁补强 | 本机资源与 Archive 前置门禁已完成；正式签名/上传/审核待外部条件 | 正式 Xcode Store Bundle 资源、签名参数 fail-closed 和 Apple 上架资料快照 | [../specs/2026-08-24-mas-release-gates.md](../specs/2026-08-24-mas-release-gates.md) |
| 音视频导入连续转写 | 代码与失败边界测试已实现；正常/损坏/无音轨隔离桌面 Journey 已通过，真实用户文件/长文件/Provider 仍待验收 | 受控复制原件、提取视频音轨、原件 SHA-256 不变、同一 Sheet 立即转文字，并复用现有任务/Artifact 链；空文件、损坏容器和无音轨视频 fail-closed | [../specs/2026-08-23-media-import-continuity.md](../specs/2026-08-23-media-import-continuity.md) |
| Finder/Dock 启动与工作台窗口连续性 | 代码与已安装包实测通过 | 双击或 `open -a` 后显示统一工作台，重复启动保持单进程和单菜单栏入口 | [../specs/2026-08-23-launch-window-continuity.md](../specs/2026-08-23-launch-window-continuity.md) |
| 设置分区独立保存 | 本轮实现，桌面视觉 Journey 待确认 | 录音、模型与转写、文件与隐私分别提交；无关草稿和 Keychain 不互相污染 | [../specs/2026-08-23-settings-section-save.md](../specs/2026-08-23-settings-section-save.md) |
| 稳定签名 TCC A/B 覆盖安装 | Apple Development A/B 已生成并覆盖到 B；TCC 连续性待用户手动验收 | 同 Bundle ID、Team ID、权限声明和 designated requirement 下只改变 Build Number；不自动重置 TCC | [../specs/2026-08-23-stable-signing-tcc-ab.md](../specs/2026-08-23-stable-signing-tcc-ab.md) |
| 当前版本手动验收运行手册 | 自动化代码门禁已通过，真实权限/视觉/素材测试由用户执行 | 提供稳定 A→B、工作台 UI、设置、TCC、无障碍、录音、系统声音、导入和 CLI Beta 的逐步路径与通过标准 | [../specs/2026-08-23-manual-acceptance-runbook.md](../specs/2026-08-23-manual-acceptance-runbook.md) |
| Keychain 状态诊断 | 本轮实现，真实锁定状态待用户钥匙串复验 | 密钥保存失败区分锁定、授权拒绝、取消和签名权限问题；普通设置仍零 Keychain 访问 | [../specs/2026-08-23-keychain-state-diagnostics.md](../specs/2026-08-23-keychain-state-diagnostics.md) |
| Keychain 延迟读取 | 本轮实现，真实授权交互待用户复验 | 启动和普通设置不读取密钥；进入模型设置或外部请求前按需加载 | [../specs/2026-08-23-keychain-lazy-read.md](../specs/2026-08-23-keychain-lazy-read.md) |
| 识别语言选择体验 | 本轮实现，待桌面设置 Journey | 用原生语言选择替代 `zh` 裸文本输入，保留未知旧代码并以自动检测作为新安装首选 | [../specs/2026-08-23-language-picker-ux.md](../specs/2026-08-23-language-picker-ux.md) |
| 转写 Artifact 版本链 | 本轮实现，待完整 UI/历史数据 Journey | 重转写保留旧原文，追加带 `supersedesID`、模型快照和可切换投影的新版本 | [../specs/2026-08-23-transcript-artifact-lineage.md](../specs/2026-08-23-transcript-artifact-lineage.md) |
| 模型基准 Fixture 生成器 | 本轮实现，严格矩阵已执行 | 用本机系统语音和音频滤镜生成五类各 300 秒无隐私 Fixture，拒绝覆盖用户文件，不改变模型计算逻辑 | [../specs/2026-08-23-model-benchmark-fixture-generator.md](../specs/2026-08-23-model-benchmark-fixture-generator.md) |
| WhisperKit 默认模型冻结 | Large-v3 默认路由已冻结，真实会议准确率仍待 | Tiny/Large-v3 均通过五类 300 秒性能门禁；未显式选择时优先 Large，损坏或缺失时安全回退 Tiny/Speech | [../specs/2026-08-23-default-model-freeze.md](../specs/2026-08-23-default-model-freeze.md) |
| 录音磁盘空间预检 | 本轮实现，真实磁盘矩阵待完成 | 录音启动前检查保存卷最低可用空间，低容量 fail-closed，不伪造成功状态 | [../specs/2026-08-23-recording-storage-preflight.md](../specs/2026-08-23-recording-storage-preflight.md) |
| 系统音频窗口级回退 | 本轮实现，真实全桌面与多窗口矩阵待完成 | 有显示器时采集全桌面；无显示器但有可捕获窗口时明确降级为活动窗口声音，并持久化采集目标 | [../specs/2026-08-23-system-audio-window-fallback.md](../specs/2026-08-23-system-audio-window-fallback.md) |
| 本机 ASR 模型版本与转写闭环 | Speech 与 WhisperKit Tiny 真实闭环已实现；默认模型性能/双发行待完成 | 停止录音后使用本机 Provider 转写，保存模型版本快照并保留原始 WAV | [2026-08-22-local-asr-model-closed-loop.md](2026-08-22-local-asr-model-closed-loop.md) |
| 产品调研与需求 | 历史调研基线 | 最初调研报告；与当前定位冲突处以“语音上下文来源”规格为准 | [2026-08-22-product-research-and-design-draft.md](2026-08-22-product-research-and-design-draft.md) |
| 录音与 UI 修复 | 实现完成，待真实 TCC 验证 | 修复权限后退出、重复实例、音频落盘和 macOS 原生界面 | [2026-08-22-recording-ui-fix.md](2026-08-22-recording-ui-fix.md) |
| 录音输入与时长显示 | 实现完成，待真实 App 录音验证 | 验证真实输入帧、补录音状态计时和输入电平反馈 | [2026-08-22-recording-audio-monitoring-fix.md](2026-08-22-recording-audio-monitoring-fix.md) |
| M2 音频复听与转写 | 基础闭环完成；模型必填校验已接入，待真实第三方服务验收 | 播放原始录音、稳定时间位置、可配置转写 API 并为会议能力建立输入契约 | [2026-08-22-m2-audio-review-transcription.md](2026-08-22-m2-audio-review-transcription.md) |
| 自定义 ASR 回环 HTTP 验收 | 基础验收完成；已覆盖 AppState 真实麦克风闭环 | 用真实 URLSession 验证自定义 multipart ASR 请求和原文响应 | [2026-08-22-local-asr-http-acceptance.md](2026-08-22-local-asr-http-acceptance.md) |
| M2-01 系统音频双轨前置 | 能力探针已实现，双轨落盘待后续 | 验证屏幕录制权限、可共享显示器和系统音频接入前置条件 | [2026-08-22-m2-system-audio-dual-track.md](2026-08-22-m2-system-audio-dual-track.md) |
| M2-01 系统音频双轨落盘 | 实现完成；CAF 显式收尾已补，待真实 App UI 验收 | 在用户开启会议模式后保存系统音频 CAF，并与麦克风 WAV 独立复听 | [2026-08-22-m2-system-audio-capture.md](2026-08-22-m2-system-audio-capture.md) |
| M2-02 VAD 与分段状态基础 | 基础实现完成，声音片段已持久化，实时 ASR 待后续 | 基于真实 PCM 帧提供确定性的声音活动、静音 hangover、片段计数和时间范围 | [2026-08-22-m2-vad-segmentation-foundation.md](2026-08-22-m2-vad-segmentation-foundation.md) |
| M2-02 本机实时转写预览 | 基础实现完成；待主动授权后的人工 partial 验收 | 用户主动开启后显示本机 partial transcript，不覆盖最终原文、不自动上云 | [2026-08-22-m2-live-transcription.md](2026-08-22-m2-live-transcription.md) |
| M2-03b 转写时间戳片段基础 | 基础实现完成，待真实第三方服务验收 | 可选 verbose_json 转写、保存时间戳片段并在详情页回看 | [2026-08-22-m2-transcription-timestamps.md](2026-08-22-m2-transcription-timestamps.md) |
| M2-03b 结构化笔记区块 | 本轮实现 | 将 Markdown 要点和待办以可扫读 UI 展示，同时保留原文 | [2026-08-22-m2-structured-note-sections.md](2026-08-22-m2-structured-note-sections.md) |
| M2-03c 可恢复处理任务边界 | 本轮实现；多条前台确认队列已接入 | 持久化 ASR/LLM 状态、失败诊断和显式重试，不自动外发 | [2026-08-22-m2-processing-recovery.md](2026-08-22-m2-processing-recovery.md) |
| M2-03c SQLite 元数据与 Job/Lease | 基础实现完成；后台守护调度待后续 | SQLite/WAL 真相源、旧 JSON 迁移、幂等 Job 和过期 Lease 恢复 | [2026-08-22-m2-sqlite-job-lease.md](2026-08-22-m2-sqlite-job-lease.md) |
| M2-04 辅助功能粘贴 | 本轮实现；全局快捷键已支持配置 | 显式/可选自动粘贴原文，默认关闭并渐进申请权限 | [2026-08-22-m2-accessibility-paste.md](2026-08-22-m2-accessibility-paste.md) |
| M2-06 系统 TTS 与结果朗读 | 能力保留，入口已迁移 | `AVSpeechSynthesizer` 只由独立文字/文件转音频窗口调用；不再嵌入录音详情或自动触发 | [2026-08-22-m2-tts.md](2026-08-22-m2-tts.md) |
| M2-07 受控进程 Provider SDK 契约 | 契约基础完成；签名验证与运行时待后续 | 冻结 Manifest、来源和信任状态，拒绝任意动态库 | [2026-08-22-m2-provider-sdk.md](2026-08-22-m2-provider-sdk.md) |
| M2-05 PI Connector 协议边界 | Swift Router 基础完成；Extension 依赖锁定后接入 | 版本化本地协议、只读优先和用户手势约束 | [2026-08-22-m2-pi-connector.md](2026-08-22-m2-pi-connector.md) |
| M2-07 受控进程 Provider 运行时 | 本轮实现；签名验证待发布阶段 | 固定环境、独立目录、超时和输出上限 | [2026-08-22-m2-provider-runtime.md](2026-08-22-m2-provider-runtime.md) |
| M2-02/M2-03 分段转写闭环 | 本轮实现；实时增量 ASR 待后续 | 消费 VAD 片段、抽取 WAV、串行 ASR 并保存时间戳文本 | [2026-08-22-m2-segment-transcription.md](2026-08-22-m2-segment-transcription.md) |
| M2-05/M2-07 本地 RPC 与 Provider 信任 | 基础实现完成，待真实 PI 加载/发布签名 | Unix Socket 传输、大小/权限门禁和 Security.framework 代码签名来源验证 | [2026-08-22-m2-local-rpc-provider-trust.md](2026-08-22-m2-local-rpc-provider-trust.md) |
| M2-05 PI Extension 实际适配 | 薄适配实现完成，待真实 PI 0.83 加载 | PI 工具、命令和快捷键只走 Woice v1 Unix Socket，不读本地数据库 | [2026-08-22-m2-pi-extension.md](2026-08-22-m2-pi-extension.md) |
| 全局录音快捷键 | 基础实现完成；配置化已接入 | 不打开 Popover 也能开始/结束录音，失败时保留菜单栏按钮 | [2026-08-22-global-recording-shortcut.md](2026-08-22-global-recording-shortcut.md) |
| 可配置录音快捷键 | 基础实现完成；待真实桌面冲突验收 | 在不申请 Input Monitoring 的前提下选择、关闭和重新注册录音快捷键 | [2026-08-22-configurable-recording-shortcut.md](2026-08-22-configurable-recording-shortcut.md) |
| 设置页 API Key 字段体验 | 基础实现完成 | API Key 默认隐藏、显式显示/隐藏并保持 Keychain 存储 | [2026-08-22-settings-key-field-ux.md](2026-08-22-settings-key-field-ux.md) |
| 设置页草稿隔离 | 已实现，Keychain 按字段隔离，待真实桌面 Journey | 编辑期间只改草稿；普通设置保存不访问 Keychain，ASR/LLM 密钥仅在各自变更时独立提交 | [2026-08-22-settings-draft-isolation.md](2026-08-22-settings-draft-isolation.md) |
| 自定义转写 API 健康检查 | 本轮实现，待真实桌面按钮验收 | 用本机生成短测试音频验证地址、模型和授权，不发送历史录音 | [2026-08-22-asr-provider-health-check.md](2026-08-22-asr-provider-health-check.md) |
| 麦克风输入自检 | 基础实现完成；待真实桌面按钮验收 | 设置页短暂采样临时 WAV，展示帧数、时长和峰值，不进入历史或外发 | [2026-08-22-microphone-input-check.md](2026-08-22-microphone-input-check.md) |
| 麦克风采集就绪门禁 | 代码、核心/Store 自动门禁完成，真实 TCC/VoiceOver 仅作提醒 | 录音进入“正在录音”前必须收到首个 PCM 缓冲；无回调时 fail-closed 清理空文件并提示可执行错误 | [../specs/2026-08-24-microphone-capture-readiness.md](../specs/2026-08-24-microphone-capture-readiness.md) |
| 音频资源生命周期与状态探测 | 代码与核心/Store 自动门禁完成，真实 TCC/VoiceOver 仅作提醒 | 设置页不再同步创建输入 Engine；麦克风状态异步探测并有界返回，退出时先固化录音并释放音频/Connector 资源 | [../specs/2026-08-24-audio-resource-lifecycle.md](../specs/2026-08-24-audio-resource-lifecycle.md) |
| 原文显示清理与品牌资产接入 | 已实现，待桌面 UI 人工验收 | 清理 Whisper 控制/时间 token，保留独立时间戳片段，并将已确认 PNG 品牌资产接入菜单栏、Popover 和 App 资源 | [2026-08-22-transcript-display-and-brand-assets.md](2026-08-22-transcript-display-and-brand-assets.md) |
| 菜单栏 Popover 前端优化 | 本轮实现，待安装包人工验收 | 菜单栏回到快速录音控制器定位：状态自适应、真实时长与输入电平、低频动作收进更多菜单、空闲图标单色化 | [2026-08-22-menubar-popover-optimization.md](2026-08-22-menubar-popover-optimization.md) |
| App Bundle Logo 正式打包 | 本轮实现，待 Finder/LaunchServices 人工验收 | 通过 actool 编译 Assets.car/AppIcon.icns，补齐 Bundle 图标元数据并刷新安装后的系统图标缓存 | [2026-08-22-app-icon-bundle-packaging.md](2026-08-22-app-icon-bundle-packaging.md) |
| Woice 统一工作台 | 主体已实现；侧栏顶底固定布局迁入 WCL-01 | 以一个主窗口承载素材、任务、工具和设置；三个主功能固定顶部、设置固定底部、中部上下文独立滚动，导入完成后原位转写 | [2026-08-22-unified-workspace.md](2026-08-22-unified-workspace.md) |

规则：当前产品定位以“语音上下文来源”规格为最高优先级，初稿保留历史背景；需求变化先更新规格，再更新计划。
