import AVFoundation
import CryptoKit
import Foundation
import Testing
import WoiceCore

@testable import WoiceApp

@Test("素材导出提供音频、TXT、时间戳 JSON 和 Markdown，且不改变原始录音")
@MainActor
func materialExportsKeepOriginalRecordingImmutable() throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "woice-material-export-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }

  let store = WorkspaceStore(storageRootURL: root)
  let audioURL = store.recordingsURL.appendingPathComponent("export-source.wav")
  try writeFixtureAudio(to: audioURL)
  let recordID = UUID()
  let artifactID = UUID()
  let record = RecordingRecord(
    id: recordID,
    createdAt: Date(timeIntervalSince1970: 1_750_000_000),
    audioFileName: audioURL.lastPathComponent,
    duration: 1,
    transcript: "<|startoftranscript|><|zh|><|transcribe|><|0.00|>你好 Woice<|1.00|>",
    generatedMarkdown: "# 笔记\n\n- 保留原文",
    processingError: nil,
    transcriptSegments: [
      TranscriptSegment(start: 0, end: 1, text: "<|0.00|>你好 Woice<|1.00|>")
    ],
    transcriptArtifacts: [
      TranscriptArtifact(
        id: artifactID,
        parentRecordingID: recordID,
        text: "你好 Woice",
        segments: [TranscriptSegment(start: 0, end: 1, text: "你好 Woice")],
        providerID: "com.woice.fixture.local-asr",
        modelID: "fixture-speech",
        modelVersion: "1.0.0",
        dataLocation: .onDevice)
    ],
    activeTranscriptArtifactID: artifactID)
  try store.saveRecordings([record])

  let state = AppState(store: store)
  let sourceBefore = try Data(contentsOf: audioURL)
  let hashBefore = SHA256.hash(data: sourceBefore)

  let exportDirectory = root.appendingPathComponent("user-selected", isDirectory: true)
  try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
  let audioExport = try #require(
    state.exportMaterial(
      for: record, kind: .microphoneAudio,
      to: exportDirectory.appendingPathComponent("audio.wav")))
  let textExport = try #require(
    state.exportMaterial(
      for: record, kind: .transcriptText,
      to: exportDirectory.appendingPathComponent("transcript.txt")))
  let jsonExport = try #require(
    state.exportMaterial(
      for: record, kind: .transcriptJSON,
      to: exportDirectory.appendingPathComponent("transcript.json")))
  let markdownExport = try #require(
    state.exportMaterial(
      for: record, kind: .markdown,
      to: exportDirectory.appendingPathComponent("note.md")))
  let audioExportData = try Data(contentsOf: audioExport)

  #expect(FileManager.default.fileExists(atPath: audioExport.path))
  #expect(audioExportData == sourceBefore)
  #expect(String(data: try Data(contentsOf: textExport), encoding: .utf8) == "你好 Woice")

  let json = try #require(
    JSONSerialization.jsonObject(with: Data(contentsOf: jsonExport)) as? [String: Any])
  #expect(json["id"] as? String == record.id.uuidString)
  #expect(json["transcript"] as? String == "你好 Woice")
  #expect((json["segments"] as? [[String: Any]])?.count == 1)
  #expect(json["activeTranscriptArtifactID"] as? String == artifactID.uuidString)
  #expect((json["transcriptArtifacts"] as? [[String: Any]])?.count == 1)
  #expect(
    ((json["transcriptArtifacts"] as? [[String: Any]])?.first?["modelVersion"] as? String)
      == "1.0.0")
  #expect(
    String(data: try Data(contentsOf: markdownExport), encoding: .utf8)?.contains("你好 Woice")
      == true)
  #expect(SHA256.hash(data: try Data(contentsOf: audioURL)) == hashBefore)
  #expect(state.recordings.first?.id == record.id)
}

@Test("没有原文时文本类导出给出明确失败")
@MainActor
func materialTextExportsRequireTranscript() throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "woice-material-export-empty-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }

  let store = WorkspaceStore(storageRootURL: root)
  let record = RecordingRecord(
    id: UUID(), createdAt: Date(), audioFileName: "missing.wav", duration: 1,
    transcript: nil, generatedMarkdown: nil, processingError: nil)
  try store.saveRecordings([record])
  let state = AppState(store: store)

  #expect(
    state.exportMaterial(
      for: record, kind: .transcriptText,
      to: root.appendingPathComponent("transcript.txt")) == nil)
  #expect(state.errorMessage == WoiceError.transcriptMissing.localizedDescription)
}

#if WOICE_APP_STORE
  @Test("Store 版无用户选定位置时禁止向容器导出用户文件")
  @MainActor
  func storeMaterialExportRequiresUserSelectedDestination() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "woice-store-export-gate-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let store = WorkspaceStore(storageRootURL: root)
    let record = RecordingRecord(
      id: UUID(), createdAt: Date(), audioFileName: "unused.wav", duration: 1,
      transcript: "需要用户选择位置", generatedMarkdown: nil, processingError: nil)
    try store.saveRecordings([record])
    let state = AppState(store: store)

    #expect(state.exportMaterial(for: record, kind: .transcriptText) == nil)
    #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("exports").path))
  }
#endif

@Test("外部打开素材对缺失文件 fail-closed")
@MainActor
func openingMissingMaterialFailsClosed() throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "woice-material-open-missing-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }

  let store = WorkspaceStore(storageRootURL: root)
  let record = RecordingRecord(
    id: UUID(), createdAt: Date(), audioFileName: "missing.wav", duration: 1,
    transcript: nil, generatedMarkdown: nil, processingError: nil)
  try store.saveRecordings([record])
  let state = AppState(store: store)

  #expect(!state.openMaterialFile(for: record, track: .microphone))
  #expect(!state.revealMaterialFiles(for: record))
  #expect(state.recordings.first?.id == record.id)
}

private func writeFixtureAudio(to url: URL) throws {
  let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
  let file = try AVAudioFile(forWriting: url, settings: format.settings)
  let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000))
  buffer.frameLength = 16_000
  for frame in 0..<16_000 {
    buffer.floatChannelData![0][frame] = sin(Float(frame) * 2 * .pi * 440 / 16_000) * 0.02
  }
  try file.write(from: buffer)
}
