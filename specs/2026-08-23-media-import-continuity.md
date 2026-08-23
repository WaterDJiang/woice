# 音视频导入与连续转写实现规格

> 状态（2026-08-23）：代码、失败边界测试和隔离桌面 Journey 已通过；正常音频、损坏视频和无音轨视频均已验证，真实用户文件、长文件和第三方 Provider 仍按手册验收。

## 目标

- 在统一工作台中导入 WAV、MP3、M4A、AAC、AIFF、CAF、FLAC、MP4、MOV、M4V。
- 原始文件复制到 Woice 受控目录并保持不可变；保存 SHA-256、字节数和来源类型。
- 生成 16 kHz 单声道派生 WAV，复用现有 ASR、ProcessingTask、Transcript Artifact 和失败重试。
- 外部 OpenAI-compatible ASR 超过 20 MiB 安全阈值时，按音频帧边界分段上传并合并相对时间戳；分段文件只存在于工作目录。
- 导入后不自动外发；同一个工作区 Sheet 明确提供“转文字”“稍后处理”和“打开原件”。
- 导入 Sheet 的状态图标、状态说明、主按钮标题和禁用态必须由同一个活动转写任务投影；存在运行中任务时，不得同时显示“转文字/点击后开始处理”。

## 领域边界

- 继续使用 `RecordingRecord`，新增 `RecordingSourceKind` 和原件元数据，不新增第二套 Material 模型。
- 缺少来源字段的旧记录按 `recorded` 解码。
- `originalMediaFileName` 指向不可变导入原件；`audioFileName` 指向 ASR 派生 WAV。
- 删除素材时同时删除派生音频和导入原件；原始录音规则不变。

## 失败安全

- 不支持、空文件、损坏音频、视频无音轨或无法解码时，不创建 Recording，不留下临时文件。
- 容器无法打开或视频音轨读取失败时，错误必须归类为“视频音轨/媒体解析失败”，不能误报为“原始文件保存失败”；错误文案不得泄露本机路径。
- 导入成功但未转写时，素材状态为真实待处理事实；关闭 Sheet 不会丢失原件。
- 本机 Provider 失败只显示失败并保留原件，不隐式切换云端。
- 外部 Provider 的单段失败会让同一转写任务失败并保留原件，不静默截断或无限重试。

## 验收

- MediaImportTests 还验证大文件分段的时间连续性；acceptance-media-import-transcription 覆盖该代码门禁。
- `swift test --filter MediaImportTests` 验证原件字节不变、SHA-256、来源元数据和派生格式。
- `MediaImportTests` 还覆盖空文件和损坏视频的 fail-closed 清理，以及损坏容器的稳定错误分类。
- `make acceptance-media-import-transcription` 验证导入契约和测试门禁；`acceptance-media-import-desktop` 验证安装包启动后的桌面导入、转写与持久化闭环。
- `WOICE_RUN_MEDIA_IMPORT_JOURNEY=1 WOICE_MEDIA_IMPORT_EXPECT_FAILURE=1` 让桌面脚本验证损坏/无音轨文件的可见失败和无半成品落盘；不把预期失败误记为成功导入。
- 真实 Mac 仍需人工验证音频/视频选择、真实 Provider 长文件上传、无音轨视频、失败重试和成功自动打开详情。
- UI 状态契约还必须覆盖主转写与声音片段任务同时存在的旧记录，优先表达运行中、等待确认或排队中的活动任务，避免按钮与状态卡相互矛盾。

## 桌面验收数据隔离

- 桌面 Journey 默认使用 `open -a` 启动安装包和临时测试存储，不写入用户的正式 Woice 素材库；源文件通过仅测试参数注入，避免把 macOS 独立 Open Panel 服务的脚本点击结果当作产品证据。
- `.fileImporter` 仍由 `MediaImportSheet` 持有，真实用户选择路径和失败反馈由 UI 负责；测试注入只验证导入后的持久化、详情路由和 Fixture 本机转写。
- 仅在 `WOICE_TEST_MODE=1` 时读取 `WOICE_TEST_STORAGE_ROOT`、`WOICE_TEST_IMPORT_SOURCE` 和 Fixture 转写参数；这些参数同时隔离元数据、原件、派生音频和单实例锁，普通启动不会读取。
- 测试进程退出后删除临时根目录；正式 App 启动没有这两个变量时继续使用 `~/Library/Application Support/Woice`。

## 外部转写等待态

- 导入页必须区分“正在转写”和“等待外发确认”。外部 Provider 创建的任务在用户确认前只落盘任务与原件，不应显示为已开始转写。
- 任务进入 `awaitingAuthorization` 后，导入页显示“等待你确认外发；原始文件已安全保存在本机”，并禁用重复的“转文字”操作。
- 外发确认仍由菜单栏状态卡/确认弹窗承载；取消确认后素材继续保留，可稍后从处理任务重试。
