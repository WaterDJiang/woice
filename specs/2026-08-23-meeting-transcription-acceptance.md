# 双轨会议转写本机验收规格

> 状态：旧版单次混音契约待替换；2026-08-24 起默认验收双轨分别转写并合并
> 日期：2026-08-23
> 关联：[会议双音轨与合并转写规格](../doc/spec/2026-08-22-dual-track-meeting-transcription.md) · [M2-08 模型接入与双版本发布计划](../doc/plan/2026-08-22-model-integration.md)

## 1. 目的

将会议转写的关键请求边界固化为可重复的本机验收命令，证明两条有效原轨都进入转写模型，且 meetingMix 只作为统一回放。

## 2. 验收范围

- 标准模式：两条原始音轨已保存并存在 `meetingMix.wav` 时，只创建/处理一条 `meetingMix` 转写任务。
- 来源分离模式：麦克风和系统音频各自创建一条任务，依次请求两次 ASR；系统 CAF 必须在发送前标准化为 RIFF WAV。
- 两种模式均使用外部 ASR 的 loopback `URLProtocol` Fixture；请求不离开测试进程，不读取真实 API Key，不写入用户历史目录。
- 传给 ASR 的每个 body 必须包含 RIFF/WAV 内容；请求均带 OpenAI-compatible 的音频转写路径和模型字段。

## 3. 明确不覆盖

- 不替代真实 Zoom/Teams/浏览器播放、ScreenCaptureKit TCC、长会议、睡眠/设备移除或崩溃 Journey。
- 不证明第三方 ASR 服务的识别准确率；真实服务连接由用户在设置页健康检查中单独确认。
- 不把 `meetingMix` 当成不可变原件；麦克风 WAV 与系统 CAF 仍是恢复和重建真相源。

## 4. 通过条件

`make acceptance-meeting-transcription` 必须在当前 SwiftPM 工程中通过，并同时满足：

1. 标准模式发送请求数为 1，来源标记为 `meetingMix`，请求音频为 RIFF/WAV。
2. 来源分离模式发送请求数为 2，来源分别为麦克风和系统音频；系统轨请求体为标准化 RIFF/WAV。
3. 两种模式的原始音频文件 SHA-256 在转写前后不变。
4. 测试只使用确定性本机 Fixture，不因未配置真实外部服务而跳过或伪造成功。
