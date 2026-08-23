import AVFoundation
import CryptoKit
import Foundation
import Testing
import WoiceCore

@testable import WoiceApp

struct MediaImportTests {
  @Test("导入 Sheet 优先展示活动转写任务，避免状态卡与按钮相互矛盾")
  @MainActor
  func importSheetUsesActiveTranscriptionTask() {
    let now = Date()
    let record = RecordingRecord(
      id: UUID(), createdAt: now, audioFileName: "queued.wav", duration: 1,
      transcript: nil, generatedMarkdown: nil, processingError: nil,
      processingTasks: [
        ProcessingTask(
          kind: .transcription, idempotencyKey: "main", status: .running,
          updatedAt: now.addingTimeInterval(-10)),
        ProcessingTask(
          kind: .segmentTranscription, idempotencyKey: "segment", status: .queued,
          updatedAt: now),
      ])

    #expect(
      ProcessingTaskProjection.activeTranscriptionTask(in: record.processingTasks)?.status
        == .running)
  }

  @Test("导入音频保存不可变原件并生成 16k 单声道派生音频")
  @MainActor
  func importAudioPreservesOriginalAndPreparesTranscriptionInput() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("woice-media-import-\(UUID().uuidString)", isDirectory: true)
    let sourceURL = root.appendingPathComponent("会议样本.wav")
    let recordingsURL = root.appendingPathComponent("recordings", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Self.writeFixtureWAV(to: sourceURL, duration: 0.25)

    let expectedData = try Data(contentsOf: sourceURL)
    let expectedHash = SHA256.hash(data: expectedData).map { String(format: "%02x", $0) }.joined()
    let result = try await MediaImportService.importFile(
      sourceURL: sourceURL, recordingsDirectory: recordingsURL)

    #expect(result.sourceKind == .importedAudio)
    #expect(result.originalFileName == "会议样本.wav")
    #expect(result.originalSHA256 == expectedHash)
    #expect(result.originalByteCount == Int64(expectedData.count))
    #expect(FileManager.default.fileExists(atPath: result.originalURL.path))
    #expect(FileManager.default.fileExists(atPath: result.derivedAudioURL.path))
    let derived = try AVAudioFile(forReading: result.derivedAudioURL)
    #expect(derived.processingFormat.sampleRate == 16_000)
    #expect(derived.processingFormat.channelCount == 1)
    #expect(derived.length > 0)
    #expect(result.duration > 0)
    #expect(try Data(contentsOf: result.originalURL) == expectedData)
  }

  @Test("旧录音没有来源字段时仍按录制解释")
  func legacyRecordingDefaultsToRecordedSource() throws {
    let record = RecordingRecord(
      id: UUID(), createdAt: Date(timeIntervalSince1970: 1_700_000_000),
      audioFileName: "fixture.wav", duration: 1, transcript: nil,
      generatedMarkdown: nil, processingError: nil)
    var object = try #require(
      JSONSerialization.jsonObject(
        with: JSONEncoder.woice.encode(record), options: []) as? [String: Any])
    object.removeValue(forKey: "sourceKind")
    object.removeValue(forKey: "originalMediaFileName")
    object.removeValue(forKey: "originalMediaSHA256")
    object.removeValue(forKey: "originalMediaByteCount")
    let legacyData = try JSONSerialization.data(withJSONObject: object)
    let decoded = try JSONDecoder.woice.decode(RecordingRecord.self, from: legacyData)
    #expect(decoded.sourceKind == .recorded)
    #expect(decoded.originalMediaFileName == nil)
  }

  @Test("超过上传阈值的音频会生成连续且不重叠的分段")
  func largeAudioIsPlannedIntoOrderedChunks() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("woice-media-chunks-\(UUID().uuidString)", isDirectory: true)
    let sourceURL = root.appendingPathComponent("long.wav")
    let workingURL = root.appendingPathComponent("chunks", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Self.writeFixtureWAV(to: sourceURL, duration: 0.25)

    let chunks = try AudioChunkingService.plan(
      sourceURL: sourceURL, maximumUploadBytes: 6 * 1024)
    #expect(chunks.count > 1)
    #expect(chunks.first?.start == 0)
    #expect(chunks.last?.end ?? 0 > chunks.first?.start ?? 0)
    for pair in zip(chunks, chunks.dropFirst()) {
      #expect(pair.0.end == pair.1.start)
    }
    let urls = try AudioChunkingService.materialize(
      sourceURL: sourceURL, chunks: chunks, workingDirectory: workingURL)
    #expect(urls.count == chunks.count)
    #expect(urls.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
    #expect(urls.allSatisfy { (try? AVAudioFile(forReading: $0).length) ?? 0 > 0 })
  }

  @Test("损坏的媒体导入失败且不会留下半成品")
  @MainActor
  func corruptMediaFailsClosedWithoutArtifacts() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("woice-media-corrupt-\(UUID().uuidString)", isDirectory: true)
    let sourceURL = root.appendingPathComponent("损坏素材.mp4")
    let recordingsURL = root.appendingPathComponent("recordings", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data(repeating: 0, count: 64).write(to: sourceURL)

    do {
      _ = try await MediaImportService.importFile(
        sourceURL: sourceURL, recordingsDirectory: recordingsURL)
      Issue.record("损坏媒体不应被标记为导入成功")
    } catch {
      let files = try FileManager.default.contentsOfDirectory(
        at: recordingsURL, includingPropertiesForKeys: nil)
      #expect(files.isEmpty)
    }
  }

  @Test("损坏视频报告音轨读取失败而不是原始文件保存失败")
  @MainActor
  func corruptVideoReportsExtractionFailure() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("woice-media-corrupt-video-\(UUID().uuidString)", isDirectory: true)
    let sourceURL = root.appendingPathComponent("损坏视频.mov")
    let recordingsURL = root.appendingPathComponent("recordings", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data(repeating: 0xFF, count: 96).write(to: sourceURL)

    do {
      _ = try await MediaImportService.importFile(
        sourceURL: sourceURL, recordingsDirectory: recordingsURL)
      Issue.record("损坏视频不应被标记为导入成功")
    } catch let error as MediaImportError {
      if case .extractionFailed(let message) = error {
        #expect(message.contains("视频音轨"))
      } else {
        Issue.record("损坏视频错误分类错误：\(error.localizedDescription)")
      }
      let files = try FileManager.default.contentsOfDirectory(
        at: recordingsURL, includingPropertiesForKeys: nil)
      #expect(files.isEmpty)
    }
  }

  @Test("空文件导入失败且不会创建素材目录内容")
  @MainActor
  func emptyMediaFailsClosedWithoutArtifacts() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("woice-media-empty-\(UUID().uuidString)", isDirectory: true)
    let sourceURL = root.appendingPathComponent("空录音.wav")
    let recordingsURL = root.appendingPathComponent("recordings", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data().write(to: sourceURL)

    do {
      _ = try await MediaImportService.importFile(
        sourceURL: sourceURL, recordingsDirectory: recordingsURL)
      Issue.record("空文件不应被标记为导入成功")
    } catch let error as MediaImportError {
      #expect(error == .originalFileEmpty)
      #expect(!FileManager.default.fileExists(atPath: recordingsURL.path))
    }
  }

  @Test("AppState 导入后持久化素材与转写任务，并保持原件不可变")
  @MainActor
  func appStateImportPersistsMaterialAndTask() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("woice-app-state-import-\(UUID().uuidString)", isDirectory: true)
    let sourceURL = root.appendingPathComponent("待整理录音.wav")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Self.writeFixtureWAV(to: sourceURL, duration: 0.2)
    let sourceData = try Data(contentsOf: sourceURL)

    let store = WorkspaceStore(storageRootURL: root)
    let state = AppState(store: store)
    let importedID = await state.importMedia(from: sourceURL)
    let record = try #require(importedID.flatMap { id in state.recordings.first { $0.id == id } })

    #expect(record.sourceKind == .importedAudio)
    #expect(record.originalMediaFileName == "\(record.id.uuidString).source.待整理录音.wav")
    #expect(record.title == "待整理录音")
    #expect(record.originalMediaSHA256?.isEmpty == false)
    #expect(record.processingTasks.count == 1)
    #expect(record.processingTasks[0].kind == .transcription)
    #expect(FileManager.default.fileExists(atPath: state.audioURL(for: record).path))
    let originalURL = try #require(state.originalMediaURL(for: record))
    #expect(try Data(contentsOf: originalURL) == sourceData)
    #expect(store.loadRecordings().first?.id == record.id)

    // The picker source is not the durable copy. Mutating it must not change
    // the stored original that future transcription/export jobs reference.
    try Data("changed outside Woice".utf8).write(to: sourceURL)
    #expect(try Data(contentsOf: originalURL) == sourceData)
  }

  @Test("AppState 损坏媒体导入失败时不创建记录或残留文件")
  @MainActor
  func appStateCorruptImportLeavesNoRecordOrPartialFiles() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "woice-app-state-corrupt-import-\(UUID().uuidString)", isDirectory: true)
    let sourceURL = root.appendingPathComponent("损坏视频.mp4")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data(repeating: 0xFF, count: 96).write(to: sourceURL)

    let store = WorkspaceStore(storageRootURL: root)
    let state = AppState(store: store)
    let importedID = await state.importMedia(from: sourceURL)

    #expect(importedID == nil)
    #expect(state.recordings.isEmpty)
    #expect(state.actionFeedback?.kind == .failure)
    let recordingFiles = try FileManager.default.contentsOfDirectory(
      at: store.recordingsURL, includingPropertiesForKeys: nil)
    #expect(recordingFiles.isEmpty)
  }

  private static func writeFixtureWAV(to url: URL, duration: TimeInterval) throws {
    let format = try #require(
      AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    let frames = AVAudioFrameCount(format.sampleRate * duration)
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
    buffer.frameLength = frames
    if let samples = buffer.floatChannelData?[0] {
      for index in 0..<Int(frames) {
        samples[index] = Float(sin(Double(index) * 0.04)) * 0.1
      }
    }
    try file.write(from: buffer)
  }
}
