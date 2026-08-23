import Foundation
import Testing
import WoiceCore

@testable import WoiceApp

/// Real external calls are opt-in. The fixture contains no user recording,
/// credentials, or API key; it only proves the installed CLI can read a
/// Context Package and return a bounded result Artifact.
struct RealAgentJourneyTests {
  @Test("真实 Codex 与 Claude CLI 完成素材派发并回收结果 Artifact")
  @MainActor
  func realAgentCLIsDispatchAndCollectArtifacts() async throws {
    guard ProcessInfo.processInfo.environment["WOICE_RUN_REAL_AGENT"] == "1" else {
      return
    }

    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "woice-real-agent-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let recordingsDirectory = root.appendingPathComponent("recordings", isDirectory: true)
    try FileManager.default.createDirectory(
      at: recordingsDirectory, withIntermediateDirectories: true)
    let audioName = "fixture.wav"
    let audioURL = recordingsDirectory.appendingPathComponent(audioName)
    let audioData = Self.fixtureWAV()
    try audioData.write(to: audioURL, options: .atomic)
    let record = RecordingRecord(
      id: UUID(),
      createdAt: Date(timeIntervalSince1970: 1_700_000_000),
      audioFileName: audioName,
      duration: 0.25,
      transcript: "这是 Woice 的合成验收素材。请返回一句确认，说明你读取了 transcript.md。",
      generatedMarkdown: nil,
      processingError: nil)
    let store = WorkspaceStore(storageRootURL: root)
    let state = AppState(store: store)
    state.recordings = [record]

    let requestedIDs = Set(
      (ProcessInfo.processInfo.environment["WOICE_REAL_AGENT_IDS"] ?? "codex-cli,claude-cli")
        .split(separator: ",")
        .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty })
    let descriptors = Dictionary(
      uniqueKeysWithValues: AgentCLIAdapterCatalog().discover().map { ($0.id, $0) })
    let missing = requestedIDs.subtracting(descriptors.keys)
    guard missing.isEmpty else {
      Issue.record("真实 Agent 验收缺少 CLI：\(missing.sorted().joined(separator: ", "))")
      return
    }

    for id in requestedIDs.sorted() {
      let descriptor = try #require(descriptors[id])
      let jobID = try #require(
        await state.dispatchToAgent(
          record: record,
          manifest: descriptor.manifest,
          instruction: "只读取 Context Package 中的 transcript.md，返回一句简短确认；不要执行任何命令。"))
      let deadline = Date().addingTimeInterval(10 * 60)
      var completedJob: AgentDispatchJob?
      while Date() < deadline {
        completedJob = state.agentDispatchJobs.first(where: { $0.id == jobID })
        if let completedJob,
          [.completed, .failed, .cancelled, .interrupted].contains(completedJob.status)
        {
          break
        }
        try await Task.sleep(for: .seconds(1))
      }
      let job = try #require(completedJob)
      guard job.status == .completed else {
        Issue.record(
          "真实 \(id) Journey 未完成：\(job.status.rawValue)，\(job.lastError ?? "无错误详情")")
        continue
      }
      let artifact = try #require(job.resultArtifact)
      #expect(artifact.connectorID == id)
      #expect(artifact.parentRecordingID == record.id)
      #expect(artifact.byteCount > 0)
      #expect(FileManager.default.fileExists(atPath: store.agentResultURL(for: artifact).path))
      #expect(try Data(contentsOf: audioURL) == audioData)
    }
  }

  private static func fixtureWAV() -> Data {
    var data = Data()
    data.append(contentsOf: Array("RIFF".utf8))
    data.append(contentsOf: UInt32(36).littleEndianBytes)
    data.append(contentsOf: Array("WAVE".utf8))
    data.append(contentsOf: Array("fmt ".utf8))
    data.append(contentsOf: UInt32(16).littleEndianBytes)
    data.append(contentsOf: UInt16(1).littleEndianBytes)
    data.append(contentsOf: UInt16(1).littleEndianBytes)
    data.append(contentsOf: UInt32(16_000).littleEndianBytes)
    data.append(contentsOf: UInt32(32_000).littleEndianBytes)
    data.append(contentsOf: UInt16(2).littleEndianBytes)
    data.append(contentsOf: UInt16(16).littleEndianBytes)
    data.append(contentsOf: Array("data".utf8))
    data.append(contentsOf: UInt32(0).littleEndianBytes)
    return data
  }
}

extension FixedWidthInteger {
  var littleEndianBytes: [UInt8] {
    withUnsafeBytes(of: littleEndian) { Array($0) }
  }
}
