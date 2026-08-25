# M2-02 本机实时转写预览

> 状态：代码与自动门禁完成；工作台和菜单栏已显示 on-device partial，不写入原始 Transcript；真实 Speech 授权与 partial 体验只作人工提示。

## 目标

录音过程中给用户一个低延迟的本机文字预览，帮助确认麦克风确实收到声音；录音停止后的可交付原文仍由现有自定义 ASR 流程生成。

## 约束

- 只有用户在设置中开启“本机实时转写预览”后才请求 Speech 权限和启动识别。
- 强制 `requiresOnDeviceRecognition = true`；本机模型不可用、权限拒绝或识别失败时 fail-closed，不自动改用云端 Speech。
- 预览文本是可丢弃 UI 状态，不写入 `RecordingRecord.transcript`，不替代外发确认和最终 ASR。
- 录音 tap 同时写 WAV 和投递 Speech buffer；写盘失败、停止和取消都必须清理识别任务。

## 验收标准

- 开关关闭时不请求 Speech 权限、不创建识别任务，原有录音路径不变。
- 开关开启且系统支持 on-device Speech 时，录音卡显示“本机实时预览”和最近的 partial transcript；Speech 失败不会退出 Woice，录音仍可保存。
- 停止录音后，预览任务被结束/清理；最终自定义 ASR 仍按现有外发确认流程执行，原始音频和原始转录不被预览覆盖。
- 识别回调在停止或重新开始后不能覆盖 `finished`/`disabled` 状态，旧任务必须被 generation guard 丢弃。
- `Info.plist` 声明用途；单元测试覆盖关闭路径、生命周期清理和 tap buffer fan-out；真实麦克风 smoke 不回归。
- 不新增网络请求、API Key、第三方依赖或数据 Schema。
