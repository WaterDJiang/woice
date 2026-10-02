# Woice App Store Connect 元数据与审核资料（0.1.5 已获 Apple 批准 / 0.1.6 下一版本候选）

> 语言：简体中文主版本；Review Notes 使用英文。
> 状态：0.1.5 已获 Apple 批准；`0.1.6 (Build 11)` 为本次更新候选。已批准版本的描述、关键词和截图在 App Store Connect 中不可编辑，以下资料随下一版本提交。

## 基础字段

| 字段 | 草案 |
|---|---|
| App Name | `Woice` |
| Subtitle | `本地录音与离线转写` |
| Primary Category | `Productivity` |
| Secondary Category | `Utilities` |
| Privacy Policy URL | `https://github.com/WaterDJiang/woice/blob/main/PRIVACY.md` |
| Support URL | `https://github.com/WaterDJiang/woice/issues` |
| Marketing URL | `https://wattter.cn/woice`（可选；提交前确认页面内容和可访问性） |
| Copyright | `<提交前填写实际年份与法律主体>` |

## 描述草案

让声音留在你的 Mac。

Woice 是一款本地优先的 macOS 语音素材工具。录音、转写、复听、搜索和管理都可以在本机完成；本机模型下载完成后，无需联网也能继续转写。无需注册账号，音频和文字默认不会上传云端。

为什么选择 Woice：

- 本地处理：可选择 WhisperKit Tiny、Qwen3-ASR 或 WhisperKit Large-v3，在 Mac 上完成语音转文字
- 私有可控：素材保存在你选定的 Mac 文件夹，随时可在 Finder 中查看、备份和带走
- 下载后离线：本机模型安装完成后，断网也能录音、转写、复听和搜索
- 原始内容不覆盖：原始音频和原始转录保持不变，重转写会创建可追溯的新版本
- 会议声音可选：只在你主动开启后录制麦克风和电脑声音，不捕获或保存屏幕画面
- 自由导出：支持复制文字，并导出音频、TXT、带时间戳 JSON 和 Markdown

Woice 不要求登录，也不会在本机处理失败时自动把素材发送到云端。只有当你主动配置外部转写服务、选择素材并确认发送后，相应内容才会离开设备。

适合整理口述灵感、会议内容、采访素材和长期语音资料，也适合重视隐私与离线使用的人。

## Promotional Text

让声音留在你的 Mac。录音、转写、搜索与管理都可在本机完成；模型下载后无需联网，无需账号，音频和文字默认不上传云端。

## Keywords

`本地转写,离线转写,录音转文字,会议录音,语音备忘,隐私,音频,搜索,Whisper,Qwen`

## 已发布版本的编辑边界

- 0.1.4 的推广文本可独立修改，已保存并从 App Store Connect 回读确认。
- 0.1.4 的描述、关键词和截图处于只读状态；必须创建下一版本后再填写和上传。
- 下一版本提交前先从对应最终签名 Build 采集真实界面；不得使用旧 Build、生成图或静态宣传页冒充产品界面。

## 0.1.6 版本更新说明（Build 11）

- 修复 16 kHz 单声道麦克风录音无法开始的问题，改用兼容当前采样率的 AAC 编码参数
- 工作台展开后，录音中始终显示“结束并保存”停止入口
- 保留原始音频与原始转录，重转写生成可追溯的新版本
- 继续支持本地录音、离线转写、复听、搜索和导出

## Review Notes（英文，少于 4000 字符）

Hello App Review Team,

Thank you for reviewing Version 0.1.6 (Build 11). This update improves recording reliability and makes the stop action continuously available in the expanded workspace:

- On first launch, the standard macOS Save panel asks the user to create an accessible "Woice Materials" folder.
- All user audio files are written there: microphone/system recordings, meeting mixes, imported originals, derived audio, chunks, and sidecars.
- Woice stores a security-scoped bookmark so the same user-selected folder remains available after relaunch.
- Build 8 audio is copied and SHA-256 verified before its container copy is removed. Conflicts stop without overwriting files.
- Settings shows the Materials Folder and "Show in Finder." The hidden container is not presented as a file location.
- The container holds only app-operational data: SQLite index, settings, models, caches, recovery state, and the bookmark—not user audio documents.

Review steps:
1. Launch Build 11 and create "Woice Materials" in the Save panel.
2. Start and stop a recording.
3. Open the expanded workspace while recording; click "结束并保存" to stop and save.
4. Open Settings > Files & Privacy > Show in Finder; the recording is visible there.
5. Import media; its original and derived audio appear in the same folder.

Accessibility: the Store build excludes automatic paste, simulated keyboard events, permission prompts, and Accessibility Settings links at compile time. It does not request Accessibility access.

Screen recording / system audio answers:

1. Feature: optional Meeting Mode can record system audio together with microphone audio. It is off by default and runs only after the user enables it and starts recording.
2. Data collected: Woice registers only ScreenCaptureKit audio output and receives PCM audio samples from the user-selected display or visible window. It may store minimal recording metadata: start time, duration, and selected source type. It does not capture or store screen pixels, screenshots, video, window text, keystrokes, or pointer activity.
3. Purpose: local recording, playback, meeting-track mixing, and transcription explicitly selected by the user. There are no advertising, tracking, profiling, monitoring, or analytics uses.
4. Third parties: no system audio is shared by default. It is sent only if the user explicitly configures an external transcription service, selects the material, and confirms sending it. Local transcription does not share it.
5. Storage and retention: audio is stored locally in the user-selected Materials folder and retained until the user deletes it. Minimal metadata is stored in the local app database. User exports are saved only to locations selected in standard Save panels. API keys remain in Keychain.
6. Privacy policy: see “麦克风与系统声音” and “系统声音的使用、共享与保留” at https://github.com/WaterDJiang/woice/blob/main/PRIVACY.md

Exact policy language: “Woice registers only the audio output of ScreenCaptureKit after the user explicitly enables Meeting Mode and starts recording. Woice does not capture, read, or store screen pixels, screenshots, video, window text, keystrokes, or pointer activity. System-audio samples are stored locally in the user-selected material folder for playback, mixing, and user-selected transcription, and are not shared with a third party unless the user explicitly configures an external transcription service, selects the material, and confirms sending it.”

No account or login is required. The app functions consistently in all regions and has no regulated functionality. Please review Build 11.

Thank you.

## 下一版本提交前确认

- 实际版权主体、审核联系人、价格/税务、年龄评级、出口合规和销售地区。
- 从 `0.1.6 (Build 11)` 的最终签名 Build 采集真实 macOS 截图和必要的审核录屏。
- 在 App Store Connect 复核 App Privacy 问卷，并选择 `0.1.6 (Build 11)`。
