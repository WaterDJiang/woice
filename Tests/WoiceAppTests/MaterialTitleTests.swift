import Foundation
import Testing
import WoiceCore

@testable import WoiceApp

@Test("导入素材默认使用原始文件名并保留扩展名")
func importedMaterialUsesOriginalFilenameForDisplayTitle() {
  let record = RecordingRecord(
    id: UUID(), createdAt: Date(), audioFileName: "derived.wav", duration: 1,
    transcript: "转写内容不应覆盖文件名", generatedMarkdown: nil, processingError: nil,
    sourceKind: .importedAudio, originalMediaFileName: "abc.source.季度复盘 终版.mp3")

  #expect(record.displayTitle == "季度复盘 终版.mp3")
  #expect(record.title == record.displayTitle)
}

@Test("自定义素材名称稳定覆盖默认投影并可清空恢复")
func customMaterialTitleIsStable() throws {
  var record = RecordingRecord(
    id: UUID(), createdAt: Date(), audioFileName: "recording.wav", duration: 1,
    transcript: "第一版原文", generatedMarkdown: nil, processingError: nil)
  record.userTitle = try RecordingRecord.normalizedUserTitle("  项目复盘  ")
  record.transcript = "重转写后的内容"

  #expect(record.displayTitle == "项目复盘")
  record.userTitle = try RecordingRecord.normalizedUserTitle("   ")
  #expect(record.displayTitle == "重转写后的内容")
}

@Test("素材名称拒绝换行和超长输入")
func materialTitleValidationIsFailClosed() {
  #expect(throws: RecordingTitleError.invalidCharacters) {
    try RecordingRecord.normalizedUserTitle("项目\n复盘")
  }
  #expect(throws: RecordingTitleError.tooLong) {
    try RecordingRecord.normalizedUserTitle(String(repeating: "字", count: 121))
  }
}

@Test("AppState 重命名只更新标题字段并持久化")
@MainActor
func appStateRenamePersistsWithoutChangingArtifacts() throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("woice-title-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let store = WorkspaceStore(storageRootURL: root)
  let recordID = UUID()
  let artifact = TranscriptArtifact(
    parentRecordingID: recordID, text: "原文", segments: [], providerID: "fixture")
  let record = RecordingRecord(
    id: recordID, createdAt: Date(), audioFileName: "recording.wav", duration: 2,
    transcript: "原文", generatedMarkdown: nil, processingError: nil,
    processingTasks: [ProcessingTask(kind: .transcription, idempotencyKey: "title-test")],
    transcriptArtifacts: [artifact], activeTranscriptArtifactID: artifact.id)
  try store.saveRecordings([record])
  let state = AppState(store: store)

  #expect(state.renameRecording(recordID: recordID, title: "复盘会议"))
  let renamed = try #require(state.recordings.first)
  #expect(renamed.displayTitle == "复盘会议")
  #expect(renamed.transcriptArtifacts.count == record.transcriptArtifacts.count)
  #expect(renamed.transcriptArtifacts.first?.id == record.transcriptArtifacts.first?.id)
  #expect(renamed.transcriptArtifacts.first?.text == record.transcriptArtifacts.first?.text)
  #expect(renamed.audioFileName == record.audioFileName)
  #expect(store.loadRecordings().first?.displayTitle == "复盘会议")
}
