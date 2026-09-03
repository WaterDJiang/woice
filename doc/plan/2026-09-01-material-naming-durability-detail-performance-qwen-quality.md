# Woice 素材命名、耐久性、详情性能与 Qwen 输出质量开发计划

> 状态：MRQ-00～MRQ-05 的代码、自动测试与工程门禁已完成；Qwen-only 300 秒、重复夹具 60 分钟严格信号/性能门禁及官方中英文参考对照已通过；导入转写浮窗后台继续 UX 与基础音频链路已有自动/隔离证据；按用户要求跳过真实桌面验收，真实故障、完整 Qwen 质量准入与正式签名仍待人工/外部条件  
> 日期：2026-09-01  
> 当前活动范围：素材标题、异常恢复、详情首屏速度、Qwen3-ASR 输出正确性  
> 前置基线：[当前技术开发收口计划](2026-08-24-current-technical-development-closure.md)已结项为历史；其未完成范围按本文第 2 节迁移  
> 问题证据：用户截图 `codex-clipboard-09c602f8-aedc-46c3-b8a1-65a01e908f0c.png`

## 1. 目标与非目标

### 目标

- 录音素材允许用户设置稳定名称；导入素材默认使用原始文件名，不再被转写首句覆盖。
- 进程崩溃、强制退出、系统崩溃或突然断电后，恢复所有已经确认落盘的音频块、标题和转写进度。
- 点击素材后立即反馈选择状态，右侧在明确性能预算内显示首屏内容，不因长原文、时间轴或音频检查阻塞主线程。
- 修复 Qwen3-ASR 中文乱码；将协议元数据、异常重复和不可读输出挡在“素材已就绪”之前。
- 保持原始音频、原始 Transcript Artifact 和历史版本不可覆盖。

### 非目标

- 不新增 AI 对话、摘要、润色、说话人分离或通用 Agent 工作流。
- 不用 LLM 猜标题，不把转写内容自动改写成营销式标题。
- 不承诺突然断电时保存尚未到达磁盘的内存帧；耐久目标以“已提交音频块零丢失、未提交尾块损失上限”表达。
- 不通过正则或 Latin-1 猜测静默改写已有乱码 Transcript；历史修复必须产生新的 Transcript Artifact。
- 不借本计划改变 Store、Developer ID、公证或 Catalog 信任根。

## 2. 替代、保留、迁移、停止、顺序

- 替代：本文替代[当前技术开发收口计划](2026-08-24-current-technical-development-closure.md)作为唯一活动产品开发计划；旧 WCL 计划只保留历史实现与验证证据。
- 保留：WCL-00～03、WCL-05、WCL-08 的已完成实现保持关闭；现有录音 Journal、后台转写 sidecar、SQLite/WAL、Artifact 不可变、双轨分别转写、模型库存和 Store 数据包门禁继续有效。
- 迁移：
  - WCL-07 的 Qwen 正确性、固定音频准确率、长音频性能和正式推荐准入迁入 `MRQ-01`、`MRQ-04`。
  - WCL-07 的签名 Catalog 发布仍由既有 Qwen Catalog 规格承接；只有 `MRQ-04` 通过后才允许发布 Qwen 条目。
  - WCL-04 的 Developer ID/公证外部条件保留在路线图发行阻塞项，不进入本文开发完成率。
  - WCL-06 的 Store 签名、Sandbox、TestFlight 和审核继续只由[Mac App Store 上架计划](2026-08-23-mac-app-store-launch.md)承接。
  - 旧 R2 “素材库已收口”结论保留为历史基线；本次新增标题与性能需求由 `MRQ-02`、`MRQ-03` 唯一承接。
- 停止：停止从旧 WCL 文件继续追加新的产品工作包；停止把真实崩溃矩阵仅列为非开发提醒；停止将未经输出质量门禁的 Qwen 标记为正式推荐。
- 顺序：`MRQ-00 -> MRQ-01 -> MRQ-02 -> MRQ-03 -> MRQ-04 -> MRQ-05`。`MRQ-01` 是当前用户可见数据错误，先于其他增强修复；`MRQ-03` 的存储迁移完成后，`MRQ-04` 才冻结详情性能结论。

## 3. 当前证据与根因判断

### 3.1 素材标题

- `RecordingRecord.title` 当前优先取转写前 40 个字符，再取 `originalMediaFileName`。
- 结果是导入文件一旦转写完成，列表名称就从原始文件名变成转写开头，不符合素材管理语义。
- 当前没有持久化的用户自定义标题字段，也没有重命名入口。

### 3.2 异常恢复

- 已有 `recording-session.json` 能在启动时发现异常会话；后台转写结果使用原子 sidecar；SQLite 使用 WAL。
- 当前录音文件在整个会话中保持打开。系统突然断电时，最后一个 M4A/CAF 容器可能未完成收尾；现有恢复只能接纳“仍可读”的整文件，无法保证已录制的大部分内容可恢复。
- SQLite 当前为 `synchronous=NORMAL`；普通崩溃具备较好恢复能力，但不能把突然掉电描述为已提交元数据零丢失。

### 3.3 详情打开速度

- 素材列表启动时读取每条 `RecordingRecord.payload_json`，其中包含完整原文、时间戳、Artifact 和任务数组。
- 点击后 `RecordingDetailView` 在主线程再次规范化完整原文、构建完整 `Text` 布局并检查多条音频路径；长原文即使放在 `ScrollView` 内，首屏布局仍可能处理全文。
- 时间轴已使用 `LazyVStack`、播放器已按需打开，这是保留基线；本计划不重复改造这些已完成部分。

### 3.4 Qwen 乱码与多余内容

- 当前固定依赖 `qwen3-asr-swift` revision `4824c95e1e4624200405d639fb4ebe10f93f1075`。
- 该 revision 的 `Qwen3Tokenizer.decode(tokens:)` 对每个 token 单独执行 byte-level UTF-8 解码。中文字符的 UTF-8 字节可能跨多个 BPE token；单 token 解码失败后回退为字节映射字符，形成截图中的 `åk²…`。
- Qwen 官方说明同一字符可能由两个不完整 byte token 组成，必须先合并完整 token 序列的字节再做一次 UTF-8 解码：[Qwen Tokenization](https://github.com/QwenLM/Qwen/blob/main/tokenization_note.md)。因此截图中的主要乱码是 Runtime tokenizer 缺陷，不是 0.6B 模型本身的识别能力结论。
- 当前 Adapter 每 30 秒独立贪心生成，`TranscriptTextNormalizer` 只清理控制 token 和空白，没有采用 Qwen 官方的输出解析与重复检测。官方实现会统一 `batch_decode`、解析 `language ...<asr_text>` 并处理异常重复：[Qwen3-ASR inference](https://github.com/QwenLM/Qwen3-ASR/blob/main/qwen_asr/inference/qwen3_asr.py)、[Qwen3-ASR output parser](https://github.com/QwenLM/Qwen3-ASR/blob/main/qwen_asr/inference/utils.py)。重复句、协议前缀和静音幻觉需要在 tokenizer 修复后单独测量。
- 2026-09-01 本机回归已确认 Qwen 权重、tokenizer 和 MLX Metal shader 可以加载；标准化 16 kHz 文件末尾会出现约 `512～768` 帧的短静音容器尾块。Provider 现在只跳过这一类最终尾块，避免静音输入触发空结果/幻觉并阻断有效主块；整段静音仍 fail-closed。公开 20 秒英文样本已通过 Woice Provider，WER 为 `0`，但这不等于中文、长时或完整质量准入通过。

## 4. 产品与数据设计

### 4.1 标题真相源

在现有 `RecordingRecord` 增加可选 `userTitle`，不创建同义领域对象。统一 `displayTitle` 优先级：

1. 非空 `userTitle`。
2. 导入素材的原始文件名，移除 Woice 内部存储前缀，保留用户原始扩展名。
3. 本机录音规范化后的转写前 40 个字符。
4. `未命名录音 · 月日 时分`。

规则：

- 用户一旦保存标题，后续重转写、切换 Transcript 版本和生成 Markdown 都不得改变标题。
- 导入素材无论是否已转写，默认名称始终是上传文件名。
- 标题允许重复；保存时去除首尾空白，拒绝换行、控制字符和超过 120 个可见字符的输入。
- 清空自定义标题等于“恢复默认名称”，不是保存空字符串。
- 旧数据迁移时 `userTitle = nil`，不批量写回、不修改原始 Artifact；导入素材在升级后按新优先级自然显示文件名。
- 搜索、列表、详情、Markdown 标题、开放导出和只读 RPC 统一使用 `displayTitle`；原始媒体文件名仍单独保留。

### 4.2 重命名交互

- 详情标题右侧显示可识别的“重命名”按钮；点击后原位切换为 `TextField`。
- `Return` 保存，`Escape` 取消，失焦仅在校验通过时保存；失败保留编辑态并显示字段级原因。
- 素材列表右键菜单提供“重命名”；不在窄列表长期显示铅笔按钮。
- 保存成功后列表与详情同步更新，不重置当前选择、播放位置或滚动位置。
- VoiceOver 朗读“重命名素材：当前名称”；状态不能只通过颜色表达。

### 4.3 录音耐久协议

现有单文件录制改为“滚动块 + 会话清单 + 最终合成”：

- 开始录音前原子创建 Session Journal，并使用文件同步确保 Journal 已提交后才接收音频。
- 每个音源独立写 10 秒 M4A 块；块先写 `.partial`，关闭容器、校验时长和 SHA-256 后原子改名为 `.committed`。
- Session Manifest 记录块序号、音源、开始偏移、时长、字节数和 SHA-256；每确认一个块后原子更新并同步。
- 正常停止时，从已提交块生成现有规范化 M4A 原件/会议合成派生物；校验成功并在 SQLite 单事务提交 Recording 后，才清理块与 Journal。
- 崩溃恢复时只信任 Manifest 中摘要匹配的已提交块；最后一个 `.partial` 尝试只读修复，失败则隔离，不删除。
- 恢复出的 Recording 标记“已从异常中恢复”，显示已保存时长和可能缺失的尾部范围；不自动外发。
- SQLite 继续使用 WAL，但素材、标题、任务和恢复提交改为行级事务；关键录音元数据连接使用 `synchronous=FULL`。保存不再重写完整 recordings 数组。
- 明确耐久 SLO：已提交块零丢失；突然断电时未提交尾部损失不超过 10 秒；进程 `SIGKILL` 后已提交块恢复率 100%。

### 4.4 详情即时呈现

保留 `Recording` 领域对象，新增的 Summary/Detail 只属于 Storage/UI 投影：

- SQLite schema 升级时增加素材摘要列；列表只查询 ID、`displayTitle` 所需字段、日期、时长、来源和状态，不解码完整原文/时间轴。
- 点击列表后立即更新选中高亮，并用摘要数据在 100 ms 内显示标题、日期、时长和状态外壳。
- `RecordingDetailLoader` Actor 按 ID 异步读取完整 payload；切换选择时取消旧请求，避免旧素材覆盖新选择。
- 缓存最近 5 条详情快照；Recording/Artifact/Task 更新后按 ID 精确失效。
- 原文规范化在后台完成并缓存。首屏只交付可视窗口附近文本块；全文搜索、复制和导出仍使用完整不可变文本。
- 时间轴继续惰性渲染；音频存在性和时长进入 `AudioMetadataCache`，同一文件变更时间未变化时不重复探测。
- 载入中显示稳定骨架和“正在打开素材”，不闪空白、不切回空状态；失败说明素材是否安全并提供重试。

### 4.5 Qwen 输出正确性与质量门禁

- 首选向上游提交 tokenizer 修复并固定到经过审计的新 commit：将所有普通 token 映射回连续字节流，过滤控制 token 后只做一次 UTF-8 解码。
- 若上游不能及时接收，使用项目控制的最小 fork 并固定精确 revision；需追加 Apache-2.0 Notice、变更 diff 和替代方案记录，不复制整套 Runtime 到 WoiceCore。
- `QwenOutputParser` 对齐官方协议：识别两个 EOS、解析语言和 `<asr_text>`、去除控制元数据、保留纯转写文字。
- 重复治理只处理确定性连续重复：字符重复、短模式连续重复和相邻 chunk 高重合；阈值与算法进入 Fixture，不做语义改写。
- 30 秒固定切片升级为现有 VAD 片段优先；无 VAD 时保留受控 overlap，并在合并时按文本/时间边界去重。静音片段不送入生成或在输出质量门禁中拒绝。
- 输出进入 Artifact 前计算质量信号：UTF-8 替换字符、byte-BPE 映射残留、控制 token、连续重复率、异常长度比。超过阈值时任务标记失败或部分就绪，原音频安全保留，不展示为“素材已就绪”。
- 已有乱码记录不原位修复；详情提供“使用修复后的 Qwen 重新转写”，生成带 `supersedesID` 的新 Transcript Artifact，旧版本仍可查看。

## 5. 组件边界

| 组件 | 责任 | 禁止事项 |
|---|---|---|
| `RecordingRecord.displayTitle` | 决定统一显示名称 | 不读文件、不调用模型 |
| `MaterialTitleEditor` | 编辑、校验、提交 `userTitle` | 不直接写 SQLite |
| `WorkspaceStore` / `SQLiteMetadataStore` | schema 迁移、摘要查询、行级事务 | 不在 UI 主线程做全文处理 |
| `RecordingChunkWriter` | 滚动块关闭、摘要和提交 | 不生成 Transcript |
| `RecordingRecoveryCoordinator` | 校验 Journal/Manifest、恢复或隔离 | 不猜测丢失音频、不自动外发 |
| `RecordingDetailLoader` | 可取消详情加载和 LRU 缓存 | 不持有音频设备 |
| `TranscriptViewport` | 分块显示可视原文 | 不改变完整原文 |
| `QwenOutputParser` | tokenizer 后的协议解析与质量信号 | 不做 LLM 润色 |
| `Qwen3ASRTranscriptionService` | 音频分片、推理和 Segment 组装 | 不把失败输出提交为 ready |

依赖继续遵循 `WoiceCore <- WoiceApp` 的现有 SwiftPM 边界；若未来完成模块拆分，再将组件移动到既定 Domain/Storage/Providers/UI 目录，不为本次计划提前复制实现。

## 6. 工作包

### MRQ-00：基线、测量与规格冻结

- 固定一份小素材、60 分钟素材、500 条素材库和 Qwen 中文 byte-token Fixture。
- 增加 `os_signpost`：列表点击、摘要上屏、详情读取、原文首屏、音频元数据完成。
- 保存当前数据库 schema、标题行为、异常恢复和 Qwen 输出为迁移前 Fixture。
- 已提供 `scripts/create_material_benchmark_fixtures.sh` 与 `make material-benchmark`；合成报告记录 500 条列表、长音频元数据和 10,000 段详情的 P50/P95。

退出条件：四类问题均有失败复现；合成基线可重复，真实应用 signpost 仍需在目标 Mac 上采集。

### MRQ-01：Qwen tokenizer 与输出质量 P0

- 先写跨 token 中文 UTF-8 失败测试，再升级/修补固定依赖。
- 实现官方协议解析、EOS、重复和异常输出门禁。
- 在转写分块边界过滤不超过 2,048 帧的最终静音容器尾块；合法 Unicode 不得被 byte-level 修复器误改。
- 对同一中文音频比较官方 Python/Transformers、修复前 Swift、修复后 Swift 的文本。
- 暂停 Qwen 正式推荐和 Catalog 准入，直到本工作包及 MRQ-04 模型矩阵通过。

退出条件：`MRQ-TAC-001～006` 通过。

### MRQ-02：素材自定义名称与导入命名

- 增加 `userTitle`、`displayTitle`、兼容解码和 schema 迁移。
- 接入详情原位编辑、列表右键入口、搜索、导出、RPC 和 VoiceOver。
- 验证重转写、切换 Artifact、应用重启和覆盖升级后标题不变。

退出条件：`MRQ-TAC-007～012` 通过。

### MRQ-03：录音块级耐久与故障恢复

- 引入滚动块写入和 Session Manifest；保留现有 Journal 作为会话入口。
- 改造正常停止、取消、休眠、设备变化、退出和启动恢复状态机。
- 增加 `SIGKILL`、损坏尾块、磁盘写满、数据库提交失败和双轨单边失败故障注入。
- 提供真实 Mac 强制重启手册，但自动故障注入是代码退出门禁，不能只留人工提醒。
- 已落地 10 秒 AAC 滚动块、原子 Manifest、后台哈希/提交、孤立块收编、损坏块隔离和重建；自动回归覆盖路径越界、损坏 JSON、孤立 `.committed` 与可读重建。

退出条件：自动 Manifest/重建契约与隔离子进程 `SIGKILL` 恢复契约通过；真实 Mac 的录音进程 `SIGKILL`、突然掉电、磁盘写满和双轨单边故障仍需手测。

### MRQ-04：详情加载与模型性能收口

- 完成摘要/详情分离、异步 Loader、缓存、文本视口和音频元数据缓存。
- 在 500 条素材、60 分钟原文、10,000 时间戳片段下采集 P50/P95 和 Main Thread Hang。
- 完成迁自 WCL-07 的 Qwen 固定音频准确率、300 秒、60 分钟会议、峰值内存和乱码/重复率矩阵。
- 已落地摘要投影、按 ID 异步详情读取、Job 状态投影、5 条 LRU、原文分块懒渲染和音频元数据缓存；合成基准已实测并低于预算；Qwen 公开英文样本烟测 WER 为 `0`，RTF `0.028～0.082`，峰值 RSS 约 `845 MiB`；官方中文/英文短样本自动语言烟测均返回非空结果，最新源码复验 RTF `0.057～0.125`，峰值 RSS 约 `839 MiB`。

退出条件：自动读取/缓存/合成基准通过；真实 SwiftUI 主线程 Hang、长时内存和 Qwen 模型矩阵仍需目标 Mac 验收。

### MRQ-05：发行回归与计划关闭

- 运行官网、Dev、Store 条件编译和文档门禁；Store 包继续不携带模型。
- 对旧数据库做升级、副本回滚、标题和 Artifact 不变校验。
- Qwen 只有满足质量和性能阈值后，才解锁签名 Catalog 规格中的发布步骤；Catalog 私钥缺失仍保持外部阻塞。
- 更新路线图、计划索引、进度复核和日志，将本文标记完成或列出唯一剩余阻塞。

退出条件：自动门禁 `MRQ-TAC-029～031` 通过；真实 Mac 验收 `MRQ-TAC-032` 仍是关闭计划前的必要条件。

## 7. 验收标准

### Qwen 正确性

- `MRQ-TAC-001`：跨两个及以上 token 的中文 UTF-8 字符解码为原字符，不出现 GPT-2 byte-unicode 映射残留。
- `MRQ-TAC-002`：中文、英文、中英混合、标点和 emoji token 序列与官方 tokenizer 结果一致。
- `MRQ-TAC-003`：`language ...<asr_text>`、`<|im_end|>`、`<|endoftext|>` 不进入用户原文。
- `MRQ-TAC-004`：固定截图同类音频不出现 `åk²` 型乱码；byte 残留率和替换字符数均为 0。
- `MRQ-TAC-005`：连续重复治理不删除正常的非相邻重复句；静音输出不生成 ready Artifact。
- `MRQ-TAC-006`：历史乱码记录重转写产生新 Artifact，旧 Artifact SHA/文本保持不变。

### 标题

- `MRQ-TAC-007`：导入 `季度复盘 终版.mp3` 后，无论是否完成转写，默认标题保持 `季度复盘 终版.mp3`。
- `MRQ-TAC-008`：本机录音未命名时仍可使用转写摘要；保存自定义标题后不再随转写变化。
- `MRQ-TAC-009`：空白、换行、控制字符和超过 120 字符的输入按规则处理且不产生半提交。
- `MRQ-TAC-010`：重启、覆盖升级、搜索、导出和 RPC 返回同一 `displayTitle`。
- `MRQ-TAC-011`：清空自定义标题恢复默认优先级，原始文件名不变。
- `MRQ-TAC-012`：重命名不改变音频、Transcript Artifact、任务、播放和选择状态。

### 耐久性

- `MRQ-TAC-013`：录音进程 `SIGKILL` 后，所有 `.committed` 块 100% 恢复且 SHA-256 不变。
- `MRQ-TAC-014`：任意时点故障的尾部损失不超过 10 秒，并在 UI 明示可能缺失范围。
- `MRQ-TAC-015`：双轨仅一轨有效时恢复有效轨，不伪造另一轨或会议合成。
- `MRQ-TAC-016`：Manifest 损坏、摘要不匹配和孤立 `.partial` 进入隔离，不静默删除。
- `MRQ-TAC-017`：磁盘不足、数据库提交失败或最终合成失败时保留已提交块和 Journal，可在下次启动继续恢复。
- `MRQ-TAC-018`：正常停止只有在音频校验和 SQLite 提交成功后清理临时块。
- `MRQ-TAC-019`：恢复和重试不覆盖原始音频或已有 Transcript Artifact。
- `MRQ-TAC-020`：WAL 恢复、行级事务和 recordings JSON 兼容副本在故障注入后状态一致。

### 详情性能

- `MRQ-TAC-021`：点击到选中高亮 P95 <= 50 ms。
- `MRQ-TAC-022`：点击到右侧标题/状态外壳 P95 <= 100 ms。
- `MRQ-TAC-023`：60 分钟素材点击到首屏原文 P95 <= 400 ms；缓存命中 P95 <= 120 ms。
- `MRQ-TAC-024`：500 条素材启动列表不解码完整 Transcript payload；首屏 P95 <= 500 ms。
- `MRQ-TAC-025`：10,000 个 Segment 不一次性创建视图，滚动期间无超过 100 ms 的主线程停顿。
- `MRQ-TAC-026`：快速连续选择 20 条素材，最终只显示最后选择项，无旧请求回写。
- `MRQ-TAC-027`：详情加载失败保留选中项和安全说明，可重试，不显示空白页。
- `MRQ-TAC-028`：缓存失效后显示最新标题、Transcript 版本和任务状态。

### 总门禁

- `MRQ-TAC-029`：`make test`、`make lint`、`make docs-check`、`make harness-check`、`make verify` 通过。
- `MRQ-TAC-030`：`make xcode-build-store`、`make verify-app-store` 通过，Store Bundle 仍为零模型。
- `MRQ-TAC-031`：迁移前数据库副本升级后录音数量、原始音频 SHA 和 Transcript Artifact 数量不变。
- `MRQ-TAC-032`：真实 Mac 完成一次录音中 `SIGKILL` 恢复、一次导入重命名、一次长素材首屏和一次 Qwen 中文转写；结果写入日志，不记录用户原文。

## 8. 风险与回滚

- 分块录音改变音频写入路径，是最高风险项；使用功能开关和旧 Journal 兼容读取，未通过 MRQ-03 前不删除旧录制实现。
- SQLite schema 迁移前创建数据库副本；迁移只增列/增表，不删除 `payload_json`，回滚版本仍可读取旧字段。
- Qwen 依赖升级必须固定 commit、复核许可证/Notice/SBOM 和 Runtime 文件清单；不能使用浮动 branch。
- 详情投影出错时可回退到按 ID 读取完整 `RecordingRecord`，但不得回退到同步全文布局。
- 任何质量过滤误伤都不能覆盖原始 Transcript；关闭显示投影即可回到原 Artifact。

## 9. 实施规模

| 工作包 | 复杂度 | 主要风险 |
|---|---|---|
| MRQ-00 | S | Fixture 是否代表真实长素材 |
| MRQ-01 | M | 第三方 tokenizer 修复与版本审计 |
| MRQ-02 | S-M | 标题兼容迁移与全入口一致性 |
| MRQ-03 | L | 音频容器、掉电语义、双轨恢复 |
| MRQ-04 | M-L | SQLite 投影迁移、SwiftUI/TextKit 长文本性能 |
| MRQ-05 | M | 多 Channel 回归与外部 Catalog 阻塞边界 |

## 10. 本轮执行进度（2026-09-01）

本轮已按用户明确启动本文，并完成可在当前工程自动验证的代码、基准和导入转写浮窗关闭体验；Qwen-only 重复夹具 60 分钟压力及官方中英文参考对照已收口。真实桌面/TCC、故障注入、真实会议质量、签名/安装和发行外部条件按用户要求不在本轮代验，仍未冒充完成。

| 工作包 | 当前状态 | 已完成 | 仍待完成 |
|---|---|---|---|
| MRQ-00 | 合成基线与观测点完成，真实 signpost 待 | Fixture 生成器、Qwen byte Fixture、列表/详情/音频 signpost 和 P50/P95 报告已落地 | 目标 Mac 真实应用 signpost 与用户素材对照 |
| MRQ-01 | 代码、空信号语义与自动测试完成，真实模型准入未关闭 | `QwenOutputParser` 连续 UTF-8 修复、协议前缀清理、相邻重复治理、质量拒绝；2026-09-01 用户粤语回归后又补齐 direct-high-only byte 序列、行内单字/短模式失控重复和最终跨 chunk 合并门禁，设置直接提供粤语 `yue`；无文字 chunk 可安全 no-op、整段空结果仍 fail-closed；Qwen Provider 已接入；15 项 Qwen XCTest 与模型基准判定测试通过，覆盖中文、粤语、日文、韩文和 emoji 字节序列；Qwen-only 五类 300 秒严格门禁通过（RTF <= 0.063、峰值 RSS <= 894 MiB）；重复夹具五类各 3600 秒长时执行通过（RTF <= 0.061、峰值 RSS <= 898 MiB）；固定 Qwen pack 的官方中英文参考对照通过，WER 分别为中文 `0`、英文 `0.0263`；新增固定 URL/SHA 夹具脚本 | 用户同类粤语原音频重转写、官方 Python/Swift 对照、中文/中英混合/静音/噪声真实准确率与重复率、可信 60 分钟会议参考、上游修复或最小 fork 审计；本次 60 分钟是重复夹具压力证据且 WER 为空，官方样本只覆盖中英文短音频；多模型矩阵仍暴露 Whisper 静音/噪声幻觉与中文空输出，因此暂不解锁正式 Qwen Catalog 推荐 |
| MRQ-02 | 代码、自动测试与稳定签名 A/B 覆盖安装/重开完成，TCC 与真实库升级仍待 | `userTitle`/`displayTitle`、导入文件名优先级、详情/列表重命名、JSON 兼容、搜索/Markdown/RPC/导出入口统一；v5→v6 摘要投影迁移测试已额外校验原始音频 SHA、字节数与 Transcript Artifact 数量不变；稳定签名 A/B 已实际覆盖安装，工作台重开通过，桌面隔离导入/转写通过 | 当前用户数据上的 TCC 连续性手测、真实用户数据库副本升级与真实文件重命名视觉确认 |
| MRQ-03 | 块级实现、故障保留、进程级 SIGKILL 自动恢复及多声道 AAC 兼容通过，真实长时故障矩阵待 | 10 秒 AAC 滚动块、原子 Manifest、后台哈希提交、孤立块收编、损坏隔离、重建和 FULL SQLite 已落地；Manifest 写入失败会回滚内存快照并保留已提交块；最终容器失败会保留 Journal/Manifest/块文件；SQLite 触发器故障回滚不留下 Recording、Job 或摘要半提交；隔离子进程 SIGKILL 恢复已提交块并通过 SHA 校验；双轨仅系统音频恢复会切换主引用且不伪造麦克风；真实麦克风配置变化安全停止、QuickTime 系统声音采集、48 kHz 单声道会议回放和来源分离任务均通过；3 声道交错 HAL 输入会在主文件、VAD、实时预览和恢复块共用边界规范化为 2 声道 Float32 非交错 PCM，再写入 AAC，确定性回归覆盖首帧与尾块提交 | 真实 Mac 进程 `SIGKILL`/突然断电/磁盘写满/双轨单边故障、尾部损失 SLO；目标 3 声道麦克风需由用户可见录音按钮完成一次安装包验收 |
| MRQ-04 | 摘要/详情实现与合成 P50/P95 基准完成；Qwen-only 300 秒、重复夹具 60 分钟和官方短样本参考对照通过，真实 UI/完整模型矩阵待 | 摘要投影、异步 Loader、Job 状态投影、5 条 LRU、原文分块懒渲染、音频元数据缓存；hydrate 进行中或失败时所有会改写完整素材集合的入口统一 fail-closed，并提供显式重试；500/60 分钟/10,000 段合成基准低于 400/500 ms 预算；Qwen-only 五类 300 秒严格门禁通过，RTF 0.050～0.063、峰值 RSS 约 894 MiB；重复夹具五类各 3600 秒执行通过，RTF <= 0.061、峰值 RSS <= 898 MiB；官方中英文短样本参考对照分别 WER `0`/`0.0263` | 真实主线程 Hang、目标 Mac 长时内存、真实 Qwen 中文/中英混合/静音/噪声/60 分钟准确率与重复率；本次长时输入为重复夹具且无 WER，官方短样本只覆盖两种语言；多模型矩阵仍显示 Whisper/Tiny 在静音/噪声上产生非空输出、Large 中文样本空输出；官方短样本不能替代真实会议 WER |
| MRQ-05 | 自动代码/工程门禁、稳定签名 A/B、启动/导入/麦克风/系统声音验收完成，真实发行条件未满足 | `make verify`、`make xcode-build-store`、`make verify-app-store`、数据库升级/事务回滚夹具和 Swift Testing 回归通过（另有 XCTest）；本机已完成任务重转写在取得 Lease 前显式回到 `queued`，重复点击仍由活动任务与 Lease 去重；Store Bundle 仍为零模型；Qwen 运行时加载与公开英文/中文短样本参考对照通过；稳定签名 A/B 已实际覆盖安装，工作台重开、桌面导入、WhisperKit 麦克风闭环、配置变化安全停止和 QuickTime 系统声音/会议合成通过；三声道 AAC 修复包已使用有效 Apple Development 身份覆盖安装并通过严格验签；hydrate 进行中或失败时录音、导入、重命名、删除、转写及任务写入均明确阻止，避免单条详情触发全量 SQLite 覆盖；模型库存扫描现按版本隔离损坏包，不阻塞其它已验证模型显示/切换；Qwen-only 300 秒、重复夹具 60 分钟严格信号/性能门禁、官方参考夹具 SHA 校验脚本及独立 Make 入口已验证 | 当前用户数据上的 TCC 连续性、真实长时故障/双轨单边、真实内容 Qwen 发布准入与完整模型质量矩阵、Developer ID/公证/签名 Catalog |
| MRQ-UX-01 | 代码与隔离 Journey 已完成，目标桌面手感待人工验收 | 转写运行/等待授权时显示“关闭并后台继续”，关闭不取消持久化任务，转写按钮自动路由处理页；支持 Escape、VoiceOver 和帮助文案；12 项 `MediaImportTests` 通过；测试模式可稳定呈现运行中 Sheet 并提供原件/派生音频/原文持久化断言 | 按用户决定跳过本轮自动桌面点击；仍需用户在目标安装包上真实点击“关闭并后台继续”并判断视觉手感与后续操作是否顺畅；可选脚本：`WOICE_RUN_MEDIA_IMPORT_JOURNEY=1 make acceptance-media-import-desktop` |

本轮代码变更详见[素材质量实施规格](../specs/2026-09-01-material-quality-and-naming.md)、[录音耐久与详情性能实施规格](../specs/2026-09-01-recording-durability-and-detail-performance.md)、[模型基准空信号与严格门禁规格](../specs/2026-09-01-model-benchmark-signal-gates.md)、[导入转写浮窗后台继续规格](../specs/2026-09-01-media-import-background-transcription.md)、[后台继续真实桌面验收规格](../specs/2026-09-01-media-import-background-journey.md)、[本机已完成任务重转写规格](../specs/2026-09-01-local-retranscription-completed-task.md)和 `doc/log/2026-09-01.md`；自动开发门禁已收口，剩余工作只保留真实 Mac/模型质量与发行外部门禁。
