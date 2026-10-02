# 16 kHz 麦克风 AAC 录音兼容性修复规格

## 问题

- 部分 Mac 的当前麦克风硬件格式为 `16,000 Hz / 1 声道`。
- 新录音链路固定请求 `64 kbps AAC`；macOS AAC 编码器不接受该采样率与码率组合。
- Woice 因而在录音启动时返回 `com.apple.coreaudio.avfaudio error 560226676`，菜单栏统一显示为“处理未完成”。

## 目标

- 16 kHz 麦克风可以正常开始、保存和结束 M4A 录音。
- 保留 AAC/M4A、原始音频不可覆盖、双音源独立落盘和滚动恢复语义。
- 底层编码器不支持目标码率时，自动选择不超过原目标且与采样率兼容的 AAC 码率；不把可恢复的格式兼容问题误报为权限失败。

## 范围

- `RecordingAudioFormat` 的 AAC 参数选择。
- 麦克风主文件、滚动恢复块、恢复重建文件及系统音频 M4A 对该选择的复用。
- 16 kHz AAC 容器创建回归测试和真实麦克风 M4A 门禁复跑。

## 不在范围

- 不修改麦克风或屏幕录制权限流程。
- 不修改输入设备选择、采样率重采样策略、转写模型或历史 WAV/CAF 文件。
- 不删除已有录音，不覆盖任何原始 Artifact。

## 验收标准

- AC-001：`16,000 Hz / 1 声道 / 64 kbps` 生成的 AAC 设置实际降为 `48 kbps`，可创建并读取 M4A 容器。
- AC-002：`48,000 Hz` 的既有 `64 kbps` 麦克风和 `128 kbps` 系统音频目标保持不变。
- AC-003：已授权真实 Mac 上，`WOICE_REQUIRE_MIC_AUDIO=1 swift test --no-parallel --filter microphoneRecordingServiceWritesFrames` 通过；新增或定向的 M4A 启动路径不再返回 `560226676`。
- AC-004：`make test`、`make lint`、`make docs-check`、`make harness-check` 和 `git diff --check` 通过。
- AC-005：失败时仍保留既有素材安全边界；不触碰另一发行 Channel，也不提交或发布。

## 影响面与兼容迁移

- 影响 `RecordingAudioFormat.aacSettings` 的所有 M4A 写入调用方；调用方 API 不变。
- 16 kHz 新录音和恢复块的有效码率从不可创建的 `64 kbps` 变为 `48 kbps`；历史文件不迁移、不转码。
- 采样率较高且当前参数已被支持的录音保持原码率。
