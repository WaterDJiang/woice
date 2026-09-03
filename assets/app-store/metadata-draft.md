# Woice App Store Connect 元数据与审核资料（Build 7 候选）

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

## 0.1.4 版本更新说明（Build 7）

- 修复“检查更新”在部分网络环境下错误提示的问题
- 修复部分多声道麦克风录音无法保存的问题
- 改善粤语及多语言转写中的乱码和异常重复
- 支持素材自定义名称，并保留导入文件名
- 加强异常退出后的录音恢复与素材详情加载速度
- 支持对已完成的本机任务重新转写，同时保留旧原文

## Review Notes（英文，少于 4000 字符）

Hello App Review Team,

Thank you for the report. We reproduced the issue in Version 0.1.4 (Build 6) on a MacBook Air (15-inch, M3, 2024) running macOS 26.6.1 with an active Internet connection.

Root cause: when “检查更新” was tapped, Woice fetched its signed model catalog from GitHub Raw. GitHub returned valid JSON with the Content-Type `text/plain; charset=utf-8`. Build 6 accepted only JSON media types, so it displayed an error before catalog validation.

Resolution in Build 7:
- Accept GitHub Raw's `text/plain` response for this fixed HTTPS catalog.
- Continue to require JSON decoding, catalog ID/schema/version validation, trusted Ed25519 signature verification, host and size restrictions, and SHA-256 verification for model files.
- Continue to reject HTML, redirects, unsafe URLs, malformed, unsigned, or tampered data.

Review flow:
1. Launch Woice.
2. Open Settings > Models & Transcription.
3. Tap “检查更新” and confirm that the catalog verifies successfully without an error.
4. Record a short microphone clip, stop recording, open the saved material, and play it back.
5. If testing local transcription, choose an available verified on-device model and start transcription. Qwen3-ASR is the app's local model option when its signed catalog entry is published. Model downloads require an explicit user action.

Woice is a local-first voice recorder and transcription app. Recordings and local transcription remain on the Mac. No account or login is required. External services are GitHub Raw for the signed catalog and Hugging Face for pinned Qwen3-ASR model files. The app has no regional feature differences and no regulated functionality.

We are submitting Build 7 and have included this fix for the reported issue. We will verify the same flow on a physical supported Mac before submission.

Thank you.

审核测试账号：无需账号。

会议模式默认关闭。开启后使用 ScreenCaptureKit 捕获系统声音；App 不读取或保存屏幕图像。只有用户主动选择外部 Provider 并确认后，音频或文字才会发送到指定服务。

审核设备：macOS 14+；Apple Silicon 可测试完整本机模型流程。

## 提交前仅需账号侧确认

- 实际版权主体、审核联系人、价格/税务、年龄评级、出口合规和销售地区。
- 从最终签名 Build 采集真实 macOS 截图和审核录屏。
- 在 App Store Connect 完成 App Privacy 问卷并选择正确的 Build 7。
