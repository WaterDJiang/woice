# 音频资源生命周期与状态探测

## 状态

代码与核心/Store 自动门禁完成；真实 TCC/VoiceOver 仅作提醒。

## 目标

- 录音状态、设置摘要和窗口渲染不得在主线程同步探测 `AVAudioEngine.inputNode`。
- 录音服务在正常退出时先结束录音、固化音频并释放 Engine/tap；若退出过程被中断，录音会话 journal 保留给下次启动恢复。
- 音频输入状态探测必须是用户可触发、可丢弃的异步诊断，不改变录音和素材真相源。

## 范围

- `RecordingService` 的麦克风状态缓存、异步输入格式探测和现有首帧门禁。
- `AppState` 的退出清理：录音、系统音频、实时转写、后台任务、全局快捷键和本地 Connector。
- `WoiceApp` 的 AppKit 异步终止确认。
- 确定性状态策略测试；不改变双轨格式、模型路由、权限语义或原始 Artifact 不可覆盖规则。

## 不在范围

- 不重置 TCC、不切换系统默认音频设备、不终止用户已安装的旧进程。
- 不把 CoreAudio IPC 挂起伪装成产品成功；真实麦克风、系统音频和 Store 签名运行仍需真实 Mac 回归。

## 验收标准

- `microphoneStatus` 为 O(1) 缓存读取，不创建 `AVAudioEngine`，设置页面渲染不直接触发 CoreAudio IPC。
- 用户点击刷新或进入麦克风诊断时才启动异步探测；探测失败保留权限状态并返回可行动错误，不改变录音状态。
- 退出时若正在录音，音频文件先完成写入并保留会话 journal；Connector、快捷键和音频捕获资源随后释放。
- 正常退出路径具有确定性测试；原始 WAV/系统音频未覆盖，下一次启动仍可恢复中断会话。
- 在音频宿主恢复后运行 `make acceptance-core`、`make verify` 和 `make store-capability-check`，不得以跳过测试替代。
