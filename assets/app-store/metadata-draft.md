# Woice App Store Connect 元数据与审核资料（Build 8 候选）

> 语言：简体中文主版本；Review Notes 使用英文。
> 状态：代码和本机 Store 预检已完成；账号主体、版权、价格/税务、年龄评级、出口合规、实机截图/录屏和后台提交动作必须在 App Store Connect 逐项确认。

## 基础字段

| 字段 | 草案 |
|---|---|
| App Name | `Woice` |
| Subtitle | `录音、转写与语音素材库` |
| Primary Category | `Productivity` |
| Secondary Category | `Utilities` |
| Privacy Policy URL | `https://github.com/WaterDJiang/woice/blob/main/PRIVACY.md` |
| Support URL | `https://github.com/WaterDJiang/woice/issues` |
| Marketing URL | `https://wattter.cn/woice`（可选；提交前确认页面内容和可访问性） |
| Copyright | `<提交前填写实际年份与法律主体>` |

## 描述草案

把说过的话，留下来，之后找得到。

Woice 是一款面向 macOS 的本地优先录音与语音素材工具：可靠保存声音，在本机或经你明确授权的转写服务中生成文字，并把音频、原始转录和时间戳沉淀为可复听、可搜索、可复制、可导出的语音素材。

你可以用 Woice：

- 用快捷键或菜单栏按钮开始和结束录音
- 保存原始音频，之后复听并定位时间位置
- 使用本机模型或已授权的转写服务生成文字
- 搜索、复制和导出录音与转录素材
- 为素材自定义名称；导入音频时保留原文件名

Woice 无需账户即可完成录音、复听、素材管理和本机转写。原始音频和原始转录不会被自动覆盖；重转写会形成可追溯的新版本。会议模式只捕获你主动开启后的系统声音，不保存屏幕画面。

## Promotional Text

把声音变成以后找得到、用得上的素材。

## Keywords

`录音,转写,语音,素材,会议,备忘,搜索,音频,本机,上下文`

## 0.1.4 版本更新说明（Build 8）

- 修复“检查更新”在部分网络环境下错误提示的问题
- 修复部分多声道麦克风录音无法保存的问题
- 改善粤语及多语言转写中的乱码和异常重复
- 支持素材自定义名称，并保留导入文件名
- 加强异常退出后的录音恢复与素材详情加载速度
- 支持对已完成的本机任务重新转写，同时保留旧原文
- App Store 版导出统一使用 macOS 标准“另存为”面板
- App Store 版移除辅助功能权限请求和自动粘贴功能

## Review Notes（英文，少于 4000 字符）

Hello App Review Team,

Thank you for the review. We addressed both Guideline 2.4.5 issues in Version 0.1.4 (Build 8):

- User files: every audio, transcript, JSON, or Markdown export in the App Store build now uses the standard macOS Save panel. The user selects an accessible destination. The App Store UI no longer opens or reveals internal container files. The container is used only for the app-managed recording library, database, recovery state, caches, and settings.
- Accessibility: the App Store build no longer includes automatic paste, simulated keyboard events, Accessibility permission prompts, or links to Accessibility Settings. The Accessibility implementation is excluded at compile time. Woice does not request Accessibility access.

Screen recording / system audio answers:

1. Feature: optional Meeting Mode can record system audio together with microphone audio. It is off by default and runs only after the user enables it and starts recording.
2. Data collected: Woice registers only ScreenCaptureKit audio output and receives PCM audio samples from the user-selected display or visible window. It may store minimal recording metadata: start time, duration, and selected source type. It does not capture or store screen pixels, screenshots, video, window text, keystrokes, or pointer activity.
3. Purpose: local recording, playback, meeting-track mixing, and transcription explicitly selected by the user. There are no advertising, tracking, profiling, monitoring, or analytics uses.
4. Third parties: no system audio is shared by default. It is sent only if the user explicitly configures an external transcription service, selects the material, and confirms sending it. Local transcription does not share it.
5. Storage and retention: audio and minimal metadata are stored locally in the app-managed library and retained until the user deletes the material. User exports are saved only to the location selected in the standard Save panel. API keys remain in Keychain.
6. Privacy policy: see “麦克风与系统声音” and “系统声音的使用、共享与保留” at https://github.com/WaterDJiang/woice/blob/main/PRIVACY.md

Exact policy language: “Woice registers only the audio output of ScreenCaptureKit after the user explicitly enables Meeting Mode and starts recording. Woice does not capture, read, or store screen pixels, screenshots, video, window text, keystrokes, or pointer activity. System-audio samples are stored locally in the app-managed library for playback, mixing, and user-selected transcription, and are not shared with a third party unless the user explicitly configures an external transcription service, selects the material, and confirms sending it.”

No account or login is required. The app functions consistently in all regions and has no regulated functionality. Please review Build 8.

Thank you.

## 提交前仅需账号侧确认

- 实际版权主体、审核联系人、价格/税务、年龄评级、出口合规和销售地区。
- 从最终签名 Build 采集真实 macOS 截图和审核录屏。
- 在 App Store Connect 完成 App Privacy 问卷并选择正确的 Build 8。
