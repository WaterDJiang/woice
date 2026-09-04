# Woice 隐私政策

生效日期：2026 年 9 月 4 日

Woice 是一款本地优先的 macOS 录音、转写与语音素材管理工具。本政策说明 Woice 如何处理录音、转录、模型和配置数据。

## 本机处理与保存

- Woice 不要求注册或登录，也不包含广告、跨 App 跟踪或用户行为分析服务。
- 录音、系统声音、转录、任务状态和设置默认保存在你的 Mac 上。
- 本机转写使用 macOS 提供的语音识别能力，或由你主动下载、导入并校验的本机模型。
- API Key 只保存在 macOS Keychain，不写入录音、转录、数据库、日志或导出文件。

## 麦克风与系统声音

- Woice 只会在你点击可见按钮或使用已配置快捷键后开始录音。
- 会议模式默认关闭。只有你主动开启会议模式并开始录音后，Woice 才使用 ScreenCaptureKit 获取所选显示器或可见窗口正在播放的系统声音。
- Woice 只注册 ScreenCaptureKit 的音频输出。它不捕获、读取或保存屏幕像素、截图、视频、窗口文本、键盘输入或鼠标操作。
- 系统声音数据是录音期间的本机 PCM 音频样本。Woice 仅用它来本机保存、回放、合成会议音轨和执行用户选择的转录。
- 麦克风和系统声音可作为独立原始音轨保存；统一回放文件和重转录结果属于可重新生成的派生内容。

## 系统声音的使用、共享与保留

- 系统声音和最小必要的录音元数据（如开始时间、时长和用户选择的声音来源类型）保存在 Woice 的本机 App Container 中，作为 App 管理的素材库和恢复数据，直到你在 App 内删除它们。
- App Store 版中，导出音频、转录、JSON 或 Markdown 时，你必须通过 macOS 标准“另存为”面板选择可访问的保存位置。
- Woice 默认不向任何第三方共享系统声音。只有你主动配置外部转录服务、选择相应素材并确认发送后，所选音频才会发送到你指定的服务；该服务的处理和保留受其隐私政策约束。

**Screen/system-audio disclosure for App Review:** "Woice registers only the audio output of ScreenCaptureKit after the user explicitly enables Meeting Mode and starts recording. Woice does not capture, read, or store screen pixels, screenshots, video, window text, keystrokes, or pointer activity. System-audio samples are stored locally in the app-managed library for playback, mixing, and user-selected transcription, and are not shared with a third party unless the user explicitly configures an external transcription service, selects the material, and confirms sending it."

## 模型下载与外部服务

- 你主动下载本机模型时，Woice 会连接模型目录或文件托管服务，并在安装前验证清单、签名和文件摘要。服务提供方可能按其政策处理完成网络连接所需的标准技术信息，例如 IP 地址和请求时间。
- Woice 不会在本机转写失败时自动把音频或文字发送到云端。
- 只有你主动配置外部转写服务并确认发送时，Woice 才会把所选音频或文字发送到你指定的服务。该服务如何保存和处理数据，由其隐私政策决定。

## 导出、删除与保留

- 你可以复制或导出自己的录音和转录素材。
- 你可以在 App 内删除素材；默认删除流程优先使用可恢复方式。
- 原始音频和原始转录不会被后续处理原位覆盖。重转录、编辑或其他处理会创建带来源关系的新版本，直到你主动删除相关素材。

## 数据共享

Woice 不出售个人数据。除你主动选择的模型下载服务、外部转写服务或导出目标外，Woice 不会把录音、转录或 API Key 分享给第三方。

## 政策更新

如果 Woice 的数据处理方式发生变化，本政策会更新生效日期并说明相应变化。新增账户、遥测、默认云端处理或其他新的数据用途前，会同步更新 App 内说明和 App Store 隐私信息。

## 联系我们

如有隐私问题，请通过 [Woice GitHub Issues](https://github.com/WaterDJiang/woice/issues) 联系项目维护者。提交 Issue 时请勿附上真实录音、完整转录、API Key 或其他敏感信息。
