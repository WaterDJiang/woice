import Foundation
import Testing
import WoiceCore

@testable import WoiceApp

@Test("素材搜索覆盖原文、状态、日期和音轨来源并使用 AND 语义")
func recordingSearchUsesSharedProjection() {
  var record = RecordingRecord(
    id: UUID(), createdAt: Date(), audioFileName: "meeting.wav", duration: 2,
    transcript: "产品 讨论", generatedMarkdown: "- 下一步", processingError: nil,
    systemAudioFileName: "meeting.caf", meetingMixFileName: "meeting-mix.wav")
  record.processingTasks = [
    ProcessingTask(kind: .transcription, idempotencyKey: "ready", status: .completed)
  ]

  #expect(recordingMatchesSearchQuery(record, query: "产品"))
  #expect(recordingMatchesSearchQuery(record, query: "电脑声音"))
  #expect(recordingMatchesSearchQuery(record, query: "会议回放"))
  #expect(recordingMatchesSearchQuery(record, query: "产品 下一步"))
  #expect(!recordingMatchesSearchQuery(record, query: "产品 不存在"))
  #expect(recordingMatchesSearchQuery(record, query: "   "))
}
