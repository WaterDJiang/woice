# Woice 项目文档索引

进入项目先读本文件；再读相关分类的 `INDEX.md`，只打开当前任务需要的分片。

## 文档分类

| 分类 | 用途 | 入口 |
|---|---|---|
| spec/ | 产品需求、验收标准、接口契约 | [spec/INDEX.md](spec/INDEX.md) |
| plan/ | 实施计划、里程碑、工作包 | [plan/INDEX.md](plan/INDEX.md) |
| design/ | 架构决策、技术选型、UI 设计基线 | [design/INDEX.md](design/INDEX.md) |
| log/ | 执行记录与最近结论 | [log/INDEX.md](log/INDEX.md) |

## 当前焦点

- 当前实施顺序与旧计划状态只看[当前路线图与计划迁移表](plan/2026-08-22-current-roadmap-and-plan-transition.md)：R0 录音核心收口 -> M2-08 ASR/模型/双版本 -> R2 素材库收口 -> M2-09 Agent 协作。旧 M3 插件生态已停止，旧总计划不能单独作为当前排期来源。
- [工作区侧栏与权限连续性优化计划](plan/2026-08-23-workspace-sidebar-and-permission-continuity.md)主体代码已完成；2026-08-24 双轨采集后的可靠合并转写已修复并通过自动契约，待新安装包真实会议复验。稳定 Build `2026082332` 的工作台、导入与状态投影证据仍有效；真实 TCC、完整视觉/无障碍、长文件和发行验收仍待。
- [菜单栏、设置、快捷键与 Dock 图标精简优化计划](plan/2026-08-23-menubar-settings-shortcut-optimization.md)已完成 MSS-07R 代码与自动测试收口：Popover、四动作、设置分层、快捷键、Bundle AppIcon、录音来源命名、loopback 信任持久化、工作台确认、可恢复“稍后处理”、主/片段任务去重、导入页、处理任务和可继续入口活动转写状态投影已落地；当前稳定 Build B `2026082332`；双轨系统会议转写按用户手动验收记为通过，云端稍后处理和视觉/TCC Journey 仍按[进度复核](plan/2026-08-23-plan-progress-review.md)及手册验收。
- [当前计划进度复核](plan/2026-08-23-plan-progress-review.md)记录了本轮新增内容、已执行门禁、当前安装包证据和未关闭清单；当前判断是“核心代码已完成，自动门禁通过，真实 Mac 验收和发行关闭条件未完成”。
- [Mac App Store 上架计划](plan/2026-08-23-mac-app-store-launch.md)已建立并标记“待实施”：Store Edition 使用单一商店记录，单独承接 Xcode Archive、App Sandbox、能力裁剪、隐私/素材、TestFlight 和审核；官网 Core/Offline 的 Developer ID/公证仍留在 M1-07/M2-08i，等待用户按需启动。
- [公开 GitHub 仓库与 ad hoc 预发布准备](../specs/2026-08-24-public-github-adhoc-release-preparation.md)已完成并推送到公开 GitHub：首批只支持 Apple Silicon，保留无模型 Core 和含模型 Offline 两个 DMG；产物为未公证的 ad hoc 预发布包，等待单独上传，不替代 Developer ID/Notarization 发行门禁。
- [录音与转写产品升级门禁](plan/2026-08-22-recording-product-upgrade.md)已并入当前路线图：文档只保留 1,650 条 App Store 评论、设置页截图与验收门禁；录音、双轨会议 ASR、模型、素材与发布分别由 M1-02/M1-04/M2-01/M2-03/M2-08 承接，不再使用 `UP-*` 工作包或第二套工期。
- 会议双音轨边界已修正：一场会议是一条 Recording，底层保留麦克风 WAV 与系统声音 CAF 两条不可变原件；`meetingMix` 只负责统一回放，默认分别转写两条原轨并按时间线合并，避免重叠说话稳定漏轨。详见[会议双音轨与合并转写规格](spec/2026-08-22-dual-track-meeting-transcription.md)与 `specs/2026-08-24-reliable-dual-track-transcription.md`。
- 产品定位已再次确认并冻结为“录音与语音素材工具、外部 Agent 的上下文来源”：录音、转写、复听、搜索、导出和 Core/Offline 模型能力是核心；Agent 只在素材完成后承担后续处理，或在授权范围内读取上下文，不承诺所有 CLI，也不形成网关/入口/聊天聚合器。详见[定位规格](spec/2026-08-22-voice-context-source-positioning.md)、[协作设计](design/2026-08-22-voice-context-agent-collaboration.md)与 [M2-09 计划](plan/2026-08-22-voice-context-agent-integration.md)。
- M2-08 双版本与模型接入继续有效：macOS on-device Speech 与固定 revision 的 WhisperKit Tiny/Large-v3 已完成本机真实录音/已有 WAV 转写闭环；Tiny 与 Large-v3 已通过五类各 300 秒严格性能矩阵，未显式选择时默认路由冻结为 Large-v3，损坏或缺失时回退 Tiny/Speech；模型下载任务恢复、Catalog 信任/回滚/轮换校验、受限 HTTPS Catalog 传输、Catalog 条目到多文件模型包的受控下载编排、显式设置页更新入口、Core/Offline ad hoc 双发行、可验证本地 DMG、三步首启引导和四个只填草稿的 loopback 本机服务预设已实现；全部专项验收、完整 `make verify`、最新安装和 Core/Offline DMG 校验均已通过；生产 Catalog host/key 配置、Developer ID/公证、干净账户覆盖安装、真实会议准确率和全桌面/多窗口/长录音 UI 矩阵仍按专项计划推进；详见[本机闭环规格](spec/2026-08-22-local-asr-model-closed-loop.md)、[双版本规格](spec/2026-08-22-dual-edition-model-integration.md)、[模型基准记录](benchmarks/2026-08-23-whisperkit-300s-matrix.md)、[设计](design/2026-08-22-model-onboarding-provider-architecture.md)与[开发计划](plan/2026-08-22-model-integration.md)。
- 进行中：M1 麦克风录音/Large-v3 主链已通过；M2-01 双轨采集由用户手动通过，但 2026-08-24 修复后的双轨分别转写与合并原文仍待真实会议复验；逐项 TCC/真实会议应用和全桌面矩阵仍待。
- 最近决策：先把录音到可复用上下文做完整，再接外部 Agent；不在 Woice 内建设通用 Agent Loop 或多 Agent 控制台。
- 当前增量：录音详情不再承载 TTS；文字/文件转音频进入独立窗口；本机 ASR 对已关闭声音片段后台串行处理，外部 ASR 仍停止后确认外发。详见[独立 TTS 与后台转写规格](spec/2026-08-22-independent-tts-and-background-transcription.md)。
- 当前增量：修复已失败本机转写任务在切换模型后无法重新取得 Lease 的问题；重试保存当前模型快照，同一录音重复点击不并发。详见[模型切换后的已有录音重转写规格](spec/2026-08-22-model-switch-retranscription.md)。
- 当前增量：录音详情支持原始音频、规范化 TXT、时间戳 JSON 和 Markdown 开放导出；音频配置变化或 Mac 即将休眠时自动复用安全停止流程，已捕获素材仍可继续转写。详见 `specs/2026-08-23-open-material-export.md` 与 `specs/2026-08-23-recording-interruption-safety.md`。
- 当前增量：模型设置支持取消活动下载并在重启后恢复，库存只允许删除非当前、非安装指针的已下载版本。详见 `specs/2026-08-23-model-download-controls.md`。
- 当前增量：素材就绪状态由持久化事实投影，现有 Unix Socket 增加 `woice.read_material` 只读引用；不触发外发或处理。详见 `specs/2026-08-23-material-readiness-status.md`。
- 当前增量：ASR 旧设置已迁移到统一 `ASRProviderConfiguration`，有限可信 Provider Registry 投影能力、数据位置和健康状态到模型与转写设置页；API Key 仍只进 Keychain。详见 `specs/2026-08-23-provider-configuration-migration.md`。
- 当前增量：所有录音与导入素材统一以设置页当前转写目标为唯一路由；默认使用本机模型，只有用户明确选择自定义服务才使用 Endpoint，旧 `automatic` 不再因残留地址隐式切换。详见 `specs/2026-08-23-transcription-route-single-source.md`。
- 当前增量：模型与转写设置支持用户主动发现本机/局域网 `/v1/models` 并把模型 ID 填入草稿；公网 Endpoint fail-closed，不自动探测。详见 `specs/2026-08-23-local-asr-discovery.md`。
- 当前增量：录音详情可把已保存的原始音频交给 Finder 或 macOS 默认播放器；缺失文件 fail-closed，不改变 Recording/Artifact。详见 `specs/2026-08-23-open-material-action.md`。
- 当前增量：素材库与兼容历史视图共用确定性搜索投影，支持标题、规范化原文、Markdown、日期、状态和音轨来源，多词使用 AND 语义。详见 `specs/2026-08-23-recording-search-projection.md`。
- 当前增量：录音开始前写入会话 Journal；异常退出后启动会验证并恢复已落盘音频，正常停止/取消会清理 Journal。详见 `specs/2026-08-23-recording-session-recovery.md`。
- 当前增量：真实 Mac 音频配置变化会复用安全停止流程，新增 `make acceptance-interruption` 验证录音落盘、Journal 清理和本机转写；睡眠/设备移除/崩溃/磁盘矩阵仍待真实桌面验收。
- 当前增量：已验证 Catalog 条目可在显式用户动作下按多文件 manifest 下载，受 HTTPS host allowlist、Range 续传、逐文件 SHA-256 和 ModelPackStore 原子提交保护；设置页对非内置 Catalog 条目提供下载入口。详见 `specs/2026-08-23-catalog-model-download-orchestration.md`。
- 当前增量：本机后台分段转写结果会在每个片段完成后原子写入 sidecar；异常退出可恢复部分原文，原始 WAV SHA-256 不变。详见 `specs/2026-08-23-background-transcription-durability.md`。
- 当前增量：新建和重试的 ProcessingTask 写入 `sha256-v1` 配置快照；摘要不含 API Key、授权头或 URL 凭据，模型/Endpoint/语言变化可被审计。详见 `specs/2026-08-23-processing-configuration-snapshot.md`。
- 当前增量：模型与转写设置新增本机 ASR 服务预设；选择只填入草稿，不自动启动服务、扫描端口或发请求，保存和健康检查仍由用户控制。详见 `specs/2026-08-23-local-asr-service-presets.md`。
- 当前增量：真实素材证明单次 meetingMix ASR 会漏掉重叠声源；默认改为麦克风/电脑声音分别进入当前模型，再按时间线合并。纯文本原文只保留说话内容，声音来源保留在时间戳片段和 JSON `sourceTrack`。历史混音素材重转写、异常恢复及旧来源前缀迁移均保留原始 Artifact；`make acceptance-meeting-transcription` 已更新为双轨门禁。
- 当前安装：CLI 文字默认与素材废纸篓交互已用同一 Apple Development 身份 A `2026082405` → B `2026082406` 覆盖安装；严格签名、单实例启动和“Woice 工作台”窗口通过。运行态确认删除按钮、行级“移到废纸篓”和统一确认框可访问；真实会议合并内容仍待用户复验。
- 当前增量：系统音频启动将屏幕录制权限拒绝、没有可共享显示器或窗口和其他运行时失败分开提示；有显示器时优先全桌面，无显示器但存在可捕获窗口时使用活动窗口并持久化采集目标。修正为可见 QuickTime 播放源后，`make acceptance-meeting` 已验证窗口级可听系统声音、CAF 和 meetingMix；当前安装包 TCC 复核失败时设置页显示“需要重新授权当前安装包”，全桌面、多窗口和真实会议应用仍待真实桌面复验。详见 `spec/2026-08-22-system-audio-permission-reliability.md` 与 `specs/2026-08-23-system-audio-window-fallback.md`。
- 当前增量：设置页改为录音与输入、模型与转写、文件与隐私分区独立保存；保存当前分区不会校验或触碰其他分区草稿/Keychain，专项门禁为 `make acceptance-settings`。详见 `specs/2026-08-23-settings-section-save.md`。
- 当前增量：录音开始前会检查保存卷最低可用空间；低于 256 MiB 时 fail-closed 并说明清理空间/更换目录，容量不可读时保留实际写入错误路径。详见 `specs/2026-08-23-recording-storage-preflight.md`。
- 当前增量：系统音频采集在有显示器时优先使用全桌面目标；无显示器但存在可捕获窗口时降级到活动窗口，并在能力状态、录音详情和持久化 Recording 中明确标记窗口级声音。详见 `specs/2026-08-23-system-audio-window-fallback.md`。
- 当前增量：API Key 真正写入 Keychain 失败时区分未解锁、授权拒绝、签名权限缺失、用户取消和未知状态；普通设置保存仍不触碰 Keychain。详见 `specs/2026-08-23-keychain-state-diagnostics.md`。
- 当前增量：AppState 启动不再读取 API Key；进入“模型与转写”或准备外部请求时才延迟读取，已有运行时密钥不会被覆盖。详见 `specs/2026-08-23-keychain-lazy-read.md`。
- 当前增量：录音设置的识别语言改为原生语言选择；空值显示“自动检测（推荐）”，旧 `zh`/`en` 代码映射为语言名称，未知代码保持可见且可往返保存。详见 `specs/2026-08-23-language-picker-ux.md`。
- 当前增量：重转写不再丢弃旧原文；每次成功转写追加带模型快照和 `supersedesID` 的 Transcript Artifact，详情页可切换历史版本，时间戳 JSON 同步导出版本链。详见 `specs/2026-08-23-transcript-artifact-lineage.md`。
- 当前增量：新增可重复的模型 Fixture 生成器；严格门禁使用五类各 300 秒本机合成音频，拒绝覆盖已有用户文件。详见 `specs/2026-08-23-model-benchmark-fixture-generator.md`。
- 当前增量：基于 Tiny/Large-v3 严格矩阵冻结默认本机模型为 Large-v3；用户显式选择优先，缺失/损坏时安全回退，不自动下载或切云端。详见 `specs/2026-08-23-default-model-freeze.md`。
- 当前增量：M2-09e 只读素材能力增加 `woice.search_materials` 与 `woice.read_material_page`，PI 暴露对应搜索/分页工具；只返回有上限的本地素材，不触发录音、处理或外发。详见 `specs/2026-08-23-agent-readonly-search-pagination.md`。
- 当前增量：M2-09a/b/c 已落地 Context Package Builder、CLI 适配器契约、受控 Runner 和 SQLite Agent Job 投影；M2-09f 已增加只读 Agent 连接/任务状态 UI；真实 CLI、结果 Artifact 和用户派发流程仍后置，不改变录音/转写主线。详见 `specs/2026-08-23-agent-context-package-contract.md` 与 `specs/2026-08-23-agent-job-ui-status.md`。
- 当前增量：CLI 默认只交付规范化原文，不强制附带 WAV；素材列表删除采用“侧滑/右键/按钮/Delete 键 -> 统一确认 -> macOS 废纸篓”的可恢复路径。详见 `specs/2026-08-24-cli-text-default-and-material-deletion.md`。
