import Foundation
import Testing
import WoiceCore

@testable import WoiceApp

@MainActor
struct RecordingSidebarLifecycleTests {
  @Test("已落盘会话在正式素材提交前持续可见，提交后不重复")
  func sessionRemainsVisibleUntilCommit() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = WorkspaceStore(storageRootURL: root)
    let state = AppState(store: store)
    let journal = RecordingSessionJournal(
      id: UUID(), createdAt: Date(), audioFileName: "test.m4a",
      systemAudioFileName: nil, captureSystemAudio: false, meetingTranscriptionMode: .standardMix)
    try store.saveRecordingSession(journal)
    state.sidebarRecordingSession = journal
    state.processingState = .authorizing
    #expect(state.visibleRecordingSession?.id == journal.id)
    #expect(state.recordingSessionStatus == "正在准备录音")
    state.processingState = .recording
    #expect(state.recordingSessionStatus == "正在录音")
    state.isFinalizingRecording = true
    #expect(state.recordingSessionStatus == "正在保存并整理转写")
    #expect(!state.canStartRecording)
    state.isFinalizingRecording = false
    state.processingState = .failed("保存失败，音频块等待恢复")
    #expect(state.visibleRecordingSession?.id == journal.id)
    #expect(state.recordingSessionStatus == "保存失败，音频块等待恢复")
    let record = RecordingRecord(
      id: journal.id, createdAt: journal.createdAt,
      audioFileName: journal.audioFileName, duration: 3, transcript: nil,
      generatedMarkdown: nil, processingError: nil)
    state.recordingSummaries = [RecordingSummary(record: record)]
    #expect(state.visibleRecordingSession == nil)
  }
}
