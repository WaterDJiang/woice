# 音频回调写入并发边界

> 状态：已采用  
> 日期：2026-08-22

## 决策

AVAudioEngine tap 和 ScreenCaptureKit output 都由系统实时队列回调，不能把回调直接标记为 MainActor。回调只调用带 `NSLock` 的文件写入器；ScreenCaptureKit 额外使用单独串行队列。`@unchecked Sendable` 仅用于这两个锁保护的回调边界类型，不向 UI 或 Domain 泄漏 SDK 对象。

## 取舍

- 不在实时回调中 `await` Actor，避免丢帧和执行器隔离崩溃。
- 不把 `CMSampleBuffer` 放进无界队列；每个回调同步完成文件写入和帧统计。
- 停止时先停止采集、再读取锁保护快照；失败原因与已写入帧数一并返回。

## 证据

- `WOICE_REQUIRE_MIC_AUDIO=1 swift test --filter microphoneRecordingServiceWritesFrames`：真实麦克风回调写入非静音 WAV。
- `WOICE_REQUIRE_SYSTEM_AUDIO=1 swift test --filter systemAudioStreamStartsAndStops`：真实系统音频回调写入可读 CAF。
- `make verify`：并发检查、格式检查和全部测试通过。
