import AVFoundation
import Foundation
import Testing
import WoiceCore

@testable import WoiceApp

private final class InterruptionFixtureASR: LocalASRTranscribing, @unchecked Sendable {
  let model = ASRModelDescriptor(
    providerID: "com.woice.fixture.interruption-asr",
    modelID: "fixture-interruption",
    displayName: "Fixture 中断模型",
    version: "1.0.0",
    dataLocation: .onDevice
  )

  func transcribe(audioURL: URL, language: String) async throws -> TranscriptionResult {
    guard FileManager.default.fileExists(atPath: audioURL.path) else {
      throw LocalASRError.audioMissing
    }
    return TranscriptionResult(text: "中断后素材仍可转写")
  }
}

@Test("真实 Mac 音频配置变化会安全停止录音并保留可转写素材")
@MainActor
func realRecordingStopsOnAudioConfigurationChange() async throws {
  guard ProcessInfo.processInfo.environment["WOICE_RUN_RECORDING_INTERRUPTION"] == "1" else {
    return
  }
  guard AVAudioApplication.shared.recordPermission == .granted else {
    #expect(Bool(false), "需要已授权麦克风才能运行真实录音中断验收")
    return
  }
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "woice-recording-interruption-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let state = AppState(
    store: WorkspaceStore(storageRootURL: root), localTranscription: InterruptionFixtureASR())

  state.startRecording()
  defer {
    if state.isRecording {
      Task { @MainActor in await state.stopRecording() }
    }
  }
  try await waitUntil(timeout: 8) { state.isRecording }
  #expect(state.isRecording)
  guard state.isRecording else { return }
  try await Task.sleep(for: .milliseconds(700))
  #expect(state.receivedBufferCount > 0)

  NotificationCenter.default.post(name: .AVAudioEngineConfigurationChange, object: nil)
  try await waitUntil(timeout: 8) { !state.isRecording && !state.recordings.isEmpty }
  #expect(!state.isRecording)
  let record = try #require(state.recordings.first)
  let audioURL = state.store.recordingsURL.appendingPathComponent(record.audioFileName)
  #expect(FileManager.default.fileExists(atPath: audioURL.path))
  #expect((try? AVAudioFile(forReading: audioURL).length) ?? 0 > 0)
  try await waitUntil(timeout: 8) { state.recordings.first?.transcript == "中断后素材仍可转写" }
  #expect(state.recordings.first?.transcript == "中断后素材仍可转写")
  #expect(state.store.loadRecordingSession() == nil)
}

@MainActor
private func waitUntil(
  timeout: TimeInterval, condition: @escaping @MainActor () -> Bool
) async throws {
  let deadline = Date().addingTimeInterval(timeout)
  while Date() < deadline {
    if condition() { return }
    try await Task.sleep(for: .milliseconds(100))
  }
}
