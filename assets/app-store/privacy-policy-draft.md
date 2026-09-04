# Woice 隐私政策发布核对稿

> 正式公开页面为仓库根目录 [`PRIVACY.md`](../../PRIVACY.md)，当前 URL：
> `https://github.com/WaterDJiang/woice/blob/main/PRIVACY.md`。
> 本文件用于 App Store Connect 内容核对；法律主体仍需确认最终发布责任和联系方式。

## 收集与处理

- Woice 默认把录音、原始音频、转录和任务状态保存在本机 App Container。
- 本机转写使用 macOS Speech 或随应用/用户导入的已验证模型，不要求登录或 API Key。
- 只有用户主动选择外部 ASR/LLM 服务并确认外发时，Woice 才发送相应的文字或音频；目标、数据类型和任务状态会在界面中显示。
- API Key 只保存到 macOS Keychain，不写入录音、转录、数据库、日志或外部任务包。
- 系统声音模式只在用户主动开启会议模式并开始录音后运行。ScreenCaptureKit 只注册音频输出，不捕获或保存屏幕像素、截图、视频、窗口文本、键盘输入或鼠标操作。
- 系统声音仅用于本机保存、回放、合成和用户选择的转录。默认不共享给第三方；只有用户配置外部转录服务、选择素材并确认发送后才会外发。

## 保存、删除与导出

- 原始音频和原始转录不可原位覆盖；重转录、编辑和外部结果会创建新的版本或 Artifact。
- App Store 版导出音频、转录、JSON 或 Markdown 时，用户必须通过 macOS 标准“另存为”面板选择可访问位置。删除优先使用可恢复方式。
- 用户导入的模型复制到应用容器，并在校验通过后注册；Woice 不下载或加载任意可执行代码。

## 第三方服务

- 外部服务的名称、地址、数据处理和保存期限以用户配置的服务商隐私政策为准。
- Woice 不读取外部 Agent 的登录凭据，也不会自动执行 Agent 返回的命令。

## 联系方式

- 隐私问题：通过 [Woice GitHub Issues](https://github.com/WaterDJiang/woice/issues) 联系项目维护者。
- 提醒用户不要在 Issue 中提交真实录音、完整转录、API Key 或其他敏感信息。

## 发布前核对

- App Store Connect 的隐私政策 URL 与上方公开 URL 完全一致。
- 若法律主体要求正式邮箱或公司地址，先更新根目录 `PRIVACY.md`，再更新商店资料；不得只在后台填写与公开政策不一致的信息。
- 若增加账户、遥测、崩溃分析、广告或默认云端转写，必须同步更新本政策和 App Privacy 答卷。
