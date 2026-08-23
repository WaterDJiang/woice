import Foundation
import Testing

@testable import WoiceApp

@Test("系统朗读服务拒绝空文本")
@MainActor
func speechPlaybackRejectsEmptyText() throws {
  let service = SpeechPlaybackService()
  do {
    try service.speak(text: "  \n", sourceLabel: "原文")
    Issue.record("空文本不应启动系统朗读")
  } catch SpeechPlaybackError.emptyText {
    // 预期：不创建空的朗读队列。
  } catch {
    Issue.record("空文本返回了错误类型：\(error)")
  }
}

@Test("系统朗读服务可停止并清理状态")
@MainActor
func speechPlaybackStopsAndClearsState() throws {
  let service = SpeechPlaybackService()
  try service.speak(text: "测试朗读", sourceLabel: "原文")
  #expect(service.state == .speaking)
  #expect(service.sourceLabel == "原文")
  service.stop()
  #expect(service.state == .idle)
  #expect(service.sourceLabel.isEmpty)
}

@Test("独立文字转音频服务拒绝空文本导出")
@MainActor
func speechExportRejectsEmptyText() async throws {
  let service = SpeechPlaybackService()
  let url = FileManager.default.temporaryDirectory.appendingPathComponent(
    "woice-empty-speech-\(UUID().uuidString).wav")
  do {
    try await service.exportWAV(text: "  ", to: url)
    Issue.record("空文本不应创建音频文件")
  } catch SpeechPlaybackError.emptyText {
    // 预期：独立 TTS 模块在用户点击导出前拒绝空输入。
  }
  #expect(!FileManager.default.fileExists(atPath: url.path))
}
