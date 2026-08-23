import Testing

@testable import WoiceApp

@Test("本机实时转写预览默认关闭且可安全结束")
func liveTranscriptionPreviewLifecycleIsFailSafe() {
  let service = LiveTranscriptionService()
  #expect(service.snapshot() == LiveTranscriptionSnapshot(state: .disabled, text: ""))
  #expect(service.finish() == LiveTranscriptionSnapshot(state: .finished, text: ""))
  service.cancel()
  #expect(service.snapshot() == LiveTranscriptionSnapshot(state: .disabled, text: ""))
}
