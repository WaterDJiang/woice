# 真实会议录音验收脚本

> 状态：可见 QuickTime 声源的 `make acceptance-meeting` 已通过；当前安装包的 TCC/真实会议应用 Journey 仍需用户完成重新授权后复验

## 目的

把当前可在本机无隐私 Fixture 复跑的系统声音验收固化为项目命令，验证 ScreenCaptureKit 采集到真实非静音系统输出，并与麦克风 WAV 一起提交。

## 命令

```bash
make acceptance-meeting
```

脚本先把 `/System/Library/Sounds/Funk.aiff` 扩展成短时本地音频文件，再交给可见的 QuickTime Player 循环播放，运行 `AppState` 会议模式测试，并要求：

- 麦克风录音状态和时长有效。
- 系统音频 CAF 有 buffer、可听信号和可读取文件。
- 标准模式生成 16 kHz 单声道 meetingMix。
- 只创建一条 `meetingMix` 转写任务。

窗口级回退的验收源必须有可捕获的应用窗口；不能只用无窗口的 `afplay` 进程，因为它可能产生有效音频 buffer 但无法提供可听峰值。QuickTime 无法启动或当前用户会话被锁定时，脚本必须响亮失败，不把静音 buffer 当作通过。

## 边界

该脚本不替代真实视频/会议应用、休眠/设备拔出、30/60/120 分钟长录音、崩溃和 TCC 变更 Journey；这些仍必须在真实桌面矩阵中记录日期、设备和结果。
