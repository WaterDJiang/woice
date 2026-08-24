import Foundation
import Testing
import WoiceCore

@testable import WoiceApp

struct AgentDispatchTests {
  @Test("只读权限不能创建出站 Agent 任务")
  @MainActor
  func readOnlyPermissionRejectsOutboundDispatch() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "woice-agent-permission-(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let recordingsDirectory = root.appendingPathComponent("recordings", isDirectory: true)
    try FileManager.default.createDirectory(
      at: recordingsDirectory, withIntermediateDirectories: true)
    let audioName = "fixture.wav"
    try Data("immutable-audio".utf8).write(
      to: recordingsDirectory.appendingPathComponent(audioName))
    let record = RecordingRecord(
      id: UUID(), createdAt: Date(), audioFileName: audioName, duration: 1,
      transcript: "合成权限素材", generatedMarkdown: nil, processingError: nil)
    let state = AppState(store: WorkspaceStore(storageRootURL: root))
    state.recordings = [record]
    let manifest = AgentCLIAdapterManifest(
      id: "fixture-permission", displayName: "Fixture Permission", version: "1.0.0",
      executablePath: "/bin/cat", argumentTemplate: ["{instruction_file}"],
      inputTransport: .contextPackageFile, outputTransport: .text,
      source: .external, trust: .unsigned)

    let jobID = await state.dispatchToAgent(
      record: record, manifest: manifest, instruction: "不应派发",
      permissionLevel: .readOnlyMaterials)
    #expect(jobID == nil)
    #expect(state.agentDispatchJobs.isEmpty)
    let controlJobID = await state.dispatchToAgent(
      record: record, manifest: manifest, instruction: "不应控制录音",
      permissionLevel: .controlActiveRecording)
    #expect(controlJobID == nil)
    #expect(state.agentDispatchJobs.isEmpty)
  }

  #if !WOICE_APP_STORE
    @Test("受控出站派发创建结果 Artifact 并保持原始音频不变")
    @MainActor
    func dispatchCreatesImmutableResultArtifact() async throws {
      let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "woice-agent-dispatch-\(UUID().uuidString)", isDirectory: true)
      defer { try? FileManager.default.removeItem(at: root) }
      let recordingsDirectory = root.appendingPathComponent("recordings", isDirectory: true)
      try FileManager.default.createDirectory(
        at: recordingsDirectory, withIntermediateDirectories: true)
      let audioName = "fixture.wav"
      let audioURL = recordingsDirectory.appendingPathComponent(audioName)
      let audioData = Data("immutable-audio".utf8)
      try audioData.write(to: audioURL)
      let record = RecordingRecord(
        id: UUID(),
        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
        audioFileName: audioName,
        duration: 1,
        transcript: "请整理这段录音。",
        generatedMarkdown: nil,
        processingError: nil)
      let store = WorkspaceStore(storageRootURL: root)
      let state = AppState(store: store)
      state.recordings = [record]
      let manifest = AgentCLIAdapterManifest(
        id: "fixture-echo",
        displayName: "Fixture Echo",
        version: "1.0.0",
        executablePath: "/bin/cat",
        argumentTemplate: ["{instruction_file}"],
        inputTransport: .contextPackageFile,
        outputTransport: .text,
        workingDirectoryPolicy: .none,
        timeout: 5,
        source: .external,
        trust: .unsigned)

      let jobID = try #require(
        await state.dispatchToAgent(
          record: record, manifest: manifest, instruction: "提取待办"))
      for _ in 0..<100 {
        if state.agentDispatchJobs.first(where: { $0.id == jobID })?.status == .completed {
          break
        }
        try await Task.sleep(for: .milliseconds(25))
      }
      let job = try #require(state.agentDispatchJobs.first(where: { $0.id == jobID }))
      #expect(job.status == .completed)
      let artifact = try #require(job.resultArtifact)
      #expect(artifact.connectorID == manifest.id)
      #expect(artifact.parentRecordingID == record.id)
      #expect(artifact.parentArtifactIDs.count == 1)
      #expect(
        String(data: try Data(contentsOf: store.agentResultURL(for: artifact)), encoding: .utf8)
          == "提取待办")
      #expect(try Data(contentsOf: audioURL) == audioData)
      let requestedAudit = state.agentAuditEvents.first {
        $0.action == .dispatchRequested && $0.jobID == jobID
      }
      #expect(requestedAudit?.dataTypes == [.transcript])
      #expect(
        state.agentAuditEvents.contains(where: {
          $0.action == .dispatchCompleted && $0.resultArtifactID == artifact.id
        }))
    }

    @Test("CLI 默认只有原文时也能派发且审计不包含音频")
    @MainActor
    func textOnlyDispatchDoesNotRequireAudio() async throws {
      let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "woice-agent-text-only-\(UUID().uuidString)", isDirectory: true)
      defer { try? FileManager.default.removeItem(at: root) }
      let record = RecordingRecord(
        id: UUID(), createdAt: Date(), audioFileName: "missing.wav", duration: 1,
        transcript: "只把这段文字交给 CLI。", generatedMarkdown: nil, processingError: nil)
      let state = AppState(store: WorkspaceStore(storageRootURL: root))
      state.recordings = [record]
      let manifest = AgentCLIAdapterManifest(
        id: "fixture-text-only", displayName: "Fixture Text", version: "1.0.0",
        executablePath: "/bin/cat", argumentTemplate: ["{instruction_file}"],
        inputTransport: .contextPackageFile, outputTransport: .text,
        source: .external, trust: .unsigned)

      let jobID = try #require(
        await state.dispatchToAgent(record: record, manifest: manifest, instruction: "整理文字"))
      for _ in 0..<100 {
        if state.agentDispatchJobs.first(where: { $0.id == jobID })?.status == .completed { break }
        try await Task.sleep(for: .milliseconds(25))
      }

      let job = try #require(state.agentDispatchJobs.first(where: { $0.id == jobID }))
      #expect(job.status == .completed)
      #expect(
        job.resultArtifact?.parentArtifactIDs == ["recording:\(record.id.uuidString):transcript"])
      let requested = try #require(
        state.agentAuditEvents.first { $0.action == .dispatchRequested && $0.jobID == jobID })
      #expect(requested.dataTypes == [.transcript])
      #expect(!requested.artifactIDs.contains(where: { $0.hasSuffix(":audio") }))
    }
  #endif
}
