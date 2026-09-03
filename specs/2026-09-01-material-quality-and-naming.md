# 素材质量与命名修复规格

> 对应计划：`doc/plan/2026-09-01-material-naming-durability-detail-performance-qwen-quality.md`
> 本轮范围：MRQ-01 输出质量边界、MRQ-02 素材标题真相源

## 变更记录（2026-09-01）

- 真实 Qwen 回归发现：同一 24 kHz WAV 标准化后的 16 kHz 文件可读出完整主块，随后还会暴露 `512～768` 帧的短尾静音块；Qwen 将该尾块当作独立输入时可能返回空文字或静音幻觉，阻断整段转写。
- 本次修复范围扩展为“转写前音频标准化可重复且保留有效采样”，并在 Provider 侧过滤短的最终静音尾块；不改变原始音频，必须覆盖不同采样率、重复调用和振幅非零回归。
- Qwen 分块读取必须跳过标准化容器产生的短尾静音，不能把静音尾块送入贪心生成后以空结果阻断整段转写；整段均为静音时仍按空结果失败，不伪造已就绪文字。
- 2026-09-01 真实粤语回归再次暴露两个缺口：仅由 direct-high byte 组成的 `ä½¢` 未被旧规则修复，行内的单字和短语连续重复也不在“相邻重复行”逻辑内。修复必须使用确定性阈值，不得将正常短重复或非相邻重复删除。
- 真实麦克风验收发现 SwiftPM 测试宿主没有 App 的语音识别 Usage Description；当用户历史设置开启实时预览时，测试会被 TCC 以 `SIGABRT` 终止。验收必须显式关闭非目标实时预览，并注入已安装的 WhisperKit Provider，不读取或改写用户当前模型选择。

## 目标

- Qwen3-ASR 输出在进入 Transcript Artifact 前修复跨 BPE token 的 UTF-8 字节序列，并移除协议控制内容。
- 对确定性的重复/异常输出 fail-closed，保留原始音频，不把不可读结果标记为已就绪。
- 质量残留检测必须避免把合法 Unicode（例如波兰语 `ł`）误判为 byte-level 乱码。
- 为 `RecordingRecord` 增加可选 `userTitle`，让导入文件名和用户名称不再被转写文本覆盖。
- 详情页提供原位重命名，素材列表提供右键重命名；重命名不影响音频、Transcript、任务和播放状态。

## 范围

- `QwenOutputParser`：byte-level 输出修复、协议前缀清理、重复/质量信号。
- `RecordingRecord`：向后兼容 Codable 字段、`displayTitle` 统一投影和标题校验。
- `AppState.renameRecording`：主 actor 内原子更新与失败回滚。
- `RecordingDetailView`、`WorkspaceRecordingRow`：键盘可用的编辑入口。
- 模型质量基准：在显式环境下复用已安装、已校验的本机 Provider，报告 Qwen/WhisperKit 的耗时、RTF、峰值内存、空输出、错误和可选 WER；默认测试不得下载或加载模型。
- 单元/集成测试与文档日志。

## 非目标

- 不修改第三方 Runtime 的源码或在运行时下载动态库。
- 不批量改写历史 Transcript；历史乱码只能通过显式重新转写产生新 Artifact。
- 不实现滚动音频块、SQLite 摘要投影或模型性能基准；这些由 MRQ-03/MRQ-04 后续工作包承接。

## 真实 Mac 录音验收边界

- `installedWhisperKitRecordsAndTranscribes` 只验证“真实麦克风录音 → 已选 Provider 转写 → 本地素材持久化”，不同时验收 macOS Speech 实时预览或系统音频采集。
- 测试从本机已安装且已校验的 WhisperKit 清单取得 Provider，并使用隔离临时 Workspace；不得因为用户设置当前选择了 Qwen 或外部服务而改变测试语义，也不得覆盖用户数据库。
- 录音验收显式关闭实时预览和系统音频，避免引入无关的 Speech/ScreenCaptureKit TCC 依赖；生产 App 的权限文案仍由正式 Bundle 的 `Info.plist` 负责。

验收失败时必须保留原始错误、退出信号和诊断报告；不得把 TCC 宿主崩溃标记为录音或模型通过。

## 验收标准

- 跨 token 的中文、日文、韩文和四字节 Unicode 经过连续字节解码后恢复原字符；无法恢复的字节不被静默替换。
- `<|im_end|>`、`<|endoftext|>`、`language Chinese<asr_text>` 等协议内容不进入用户原文。
- 连续完全重复行被拒绝或去重；单字连续 8 次、长度 2～16 的短模式连续 5 次时只保留一份；未达阈值和非相邻的正常重复保持不变；空/异常质量结果抛出可诊断错误。
- `ä½¢` 这类不含 GPT-2 fallback scalar、但完整字节可严格解码为 UTF-8 的连续高字节序列必须恢复为原字符；无法严格解码的序列不得静默替换。
- 设置中必须直接提供粤语 `yue` 选项；Qwen 传入 `Cantonese`，不迫使粤语用户选“简体中文”。自动检测仍为首项。
- 合法 Unicode 字符（含 `ł` 等落在 GPT-2 byte 映射表中的字符）保持原样，不因单字符出现而拒绝。
- 旧 JSON 没有 `userTitle` 时仍能解码；导入记录默认显示原始文件名（保留扩展名），本机录音继续使用转写摘要回退。
- 用户标题去首尾空白，拒绝换行、控制字符和超过 120 个可见字符；清空恢复默认名称。
- 重命名保存后重启、重转写、切换 Transcript 版本、搜索、导出和只读 RPC 均使用同一 `displayTitle`。
- `make test`、`make lint`、`make docs-check`、`make harness-check` 和 `git diff --check` 通过。
- `WOICE_BENCHMARK_INCLUDE_QWEN=1` 只在显式质量验收时启用 Qwen；模型目录必须来自已安装清单，缺失时 fail-closed，不得伪造通过。
