import AVFoundation
import CryptoKit
import Foundation
import Testing
import WoiceCore

@testable import WoiceApp

@Test("录音写入异常时保留可读取的部分音频或系统音轨")
func partialRecordingPreservationPolicy() {
  #expect(
    AppState.shouldPreserveRecording(microphoneFileIsUsable: true, systemAudioIsUsable: false))
  #expect(
    AppState.shouldPreserveRecording(microphoneFileIsUsable: false, systemAudioIsUsable: true))
  #expect(
    !AppState.shouldPreserveRecording(microphoneFileIsUsable: false, systemAudioIsUsable: false))
}

@Test("启动时恢复有 Journal 的有效 WAV 且不触碰原始字节")
@MainActor
func interruptedRecordingJournalRecoversAudio() throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "woice-session-recovery-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let store = WorkspaceStore(storageRootURL: root)
  let id = UUID()
  let audioURL = store.recordingsURL.appendingPathComponent("\(id.uuidString).wav")
  try writeRecoveryFixture(to: audioURL)
  let before = SHA256.hash(data: try Data(contentsOf: audioURL))
  try store.saveRecordingSession(
    RecordingSessionJournal(
      id: id,
      createdAt: Date(timeIntervalSince1970: 1_750_000_000),
      audioFileName: audioURL.lastPathComponent,
      systemAudioFileName: nil,
      captureSystemAudio: false,
      meetingTranscriptionMode: .standardMix))

  let state = AppState(store: store)
  let record = try #require(state.recordings.first)
  #expect(record.id == id)
  #expect(record.duration > 0)
  #expect(record.processingError?.contains("上次录音未正常结束") == true)
  #expect(record.processingTasks.isEmpty)
  #expect(store.loadRecordingSession() == nil)
  #expect(SHA256.hash(data: try Data(contentsOf: audioURL)) == before)
}

@Test("异常退出恢复双轨素材时重建会议回放并使用可靠双轨语义")
@MainActor
func interruptedDualTrackRecordingRecoversMeetingMix() throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "woice-session-recovery-dual-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let store = WorkspaceStore(storageRootURL: root)
  let id = UUID()
  let microphoneURL = store.recordingsURL.appendingPathComponent("\(id.uuidString).wav")
  let systemURL = store.recordingsURL.appendingPathComponent("\(id.uuidString).caf")
  try writeRecoveryFixture(to: microphoneURL)
  try writeRecoveryFixture(to: systemURL)
  let microphoneBefore = SHA256.hash(data: try Data(contentsOf: microphoneURL))
  let systemBefore = SHA256.hash(data: try Data(contentsOf: systemURL))
  try store.saveRecordingSession(
    RecordingSessionJournal(
      id: id,
      createdAt: Date(timeIntervalSince1970: 1_750_000_050),
      audioFileName: microphoneURL.lastPathComponent,
      systemAudioFileName: systemURL.lastPathComponent,
      captureSystemAudio: true,
      meetingTranscriptionMode: .standardMix))

  let state = AppState(store: store)
  let record = try #require(state.recordings.first)
  #expect(record.meetingTranscriptionMode == .sourceSeparated)
  #expect(record.meetingMixFileName != nil)
  #expect(state.meetingMixFileExists(for: record))
  #expect(SHA256.hash(data: try Data(contentsOf: microphoneURL)) == microphoneBefore)
  #expect(SHA256.hash(data: try Data(contentsOf: systemURL)) == systemBefore)
}

@Test("异常退出恢复系统音频单轨时不伪造麦克风或会议合成")
@MainActor
func interruptedSystemOnlyRecordingPreservesSourceSemantics() throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "woice-session-recovery-system-only-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let store = WorkspaceStore(storageRootURL: root)
  let id = UUID()
  let systemURL = store.recordingsURL.appendingPathComponent("\(id.uuidString).system.m4a")
  try writeRecoveryFixture(to: systemURL)
  try store.saveRecordingSession(
    RecordingSessionJournal(
      id: id,
      createdAt: Date(timeIntervalSince1970: 1_750_000_075),
      audioFileName: systemURL.lastPathComponent,
      systemAudioFileName: systemURL.lastPathComponent,
      captureMicrophone: false,
      captureSystemAudio: true,
      meetingTranscriptionMode: .standardMix))

  let state = AppState(store: store)
  let record = try #require(state.recordings.first)
  #expect(!state.microphoneAudioFileExists(for: record))
  #expect(state.systemAudioFileExists(for: record))
  #expect(record.meetingMixFileName == nil)
  #expect(record.meetingTranscriptionMode == nil)
}

@Test("Journal 存在但没有可读音频时不创建伪造录音")
@MainActor
func invalidInterruptedRecordingJournalFailsClosed() throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "woice-session-recovery-invalid-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let store = WorkspaceStore(storageRootURL: root)
  try store.saveRecordingSession(
    RecordingSessionJournal(
      id: UUID(), createdAt: Date(), audioFileName: "missing.wav", systemAudioFileName: nil,
      captureSystemAudio: false, meetingTranscriptionMode: .standardMix))

  let state = AppState(store: store)
  #expect(state.recordings.isEmpty)
  #expect(store.loadRecordingSession() == nil)
}

@Test("后台转写 sidecar 在会话恢复时保留部分原文并清理 sidecar")
@MainActor
func interruptedRecordingRestoresBackgroundTranscriptJournal() throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "woice-background-recovery-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let store = WorkspaceStore(storageRootURL: root)
  let id = UUID()
  let audioURL = store.recordingsURL.appendingPathComponent("\(id.uuidString).wav")
  try writeRecoveryFixture(to: audioURL)
  let before = SHA256.hash(data: try Data(contentsOf: audioURL))
  try store.saveRecordingSession(
    RecordingSessionJournal(
      id: id,
      createdAt: Date(timeIntervalSince1970: 1_750_000_100),
      audioFileName: audioURL.lastPathComponent,
      systemAudioFileName: nil,
      captureSystemAudio: false,
      meetingTranscriptionMode: .standardMix))
  try store.saveBackgroundTranscriptionJournal(
    BackgroundTranscriptionJournal(
      recordID: id,
      results: [
        0: [TranscriptSegment(start: 0.2, end: 0.8, text: "已完成片段")]
      ],
      failedSegmentIndexes: [1],
      providerID: "com.woice.whisperkit",
      modelID: "openai-whisper-tiny",
      modelVersion: "test-revision",
      dataLocation: .onDevice))

  let state = AppState(store: store)
  let record = try #require(state.recordings.first)
  #expect(record.transcript == "已完成片段")
  #expect(record.transcriptSegments?.count == 1)
  #expect(record.materialStatus == .partiallyReady)
  #expect(record.processingTasks.first?.status == .interrupted)
  #expect(store.loadBackgroundTranscriptionJournal(for: id) == nil)
  #expect(SHA256.hash(data: try Data(contentsOf: audioURL)) == before)
}

@Test("损坏的后台转写 sidecar fail-closed")
@MainActor
func invalidBackgroundTranscriptionJournalFailsClosed() throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "woice-background-invalid-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let store = WorkspaceStore(storageRootURL: root)
  let id = UUID()
  let invalid = BackgroundTranscriptionJournal(
    recordID: id,
    results: [-1: [TranscriptSegment(start: 0, end: 1, text: "不应读取")]])
  let data = try JSONEncoder.woice.encode(invalid)
  try data.write(to: store.backgroundTranscriptionURL(for: id), options: .atomic)
  #expect(store.loadBackgroundTranscriptionJournal(for: id) == nil)
}

private func writeRecoveryFixture(to url: URL) throws {
  let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
  let file = try AVAudioFile(forWriting: url, settings: format.settings)
  let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000))
  buffer.frameLength = 16_000
  for frame in 0..<16_000 {
    buffer.floatChannelData![0][frame] = 0.02
  }
  try file.write(from: buffer)
}
