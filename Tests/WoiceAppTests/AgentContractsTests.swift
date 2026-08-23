import Foundation
import Testing
import WoiceCore

@testable import WoiceApp

struct AgentContractsTests {
  private let hash = String(repeating: "a", count: 64)

  @Test("Agent 权限层级稳定且录音控制不默认开放")
  func permissionLevelsStayExplicit() throws {
    #expect(
      AgentPermissionLevel.allCases.map(\.rawValue) == [
        "readOnlyMaterials", "createTasks", "controlActiveRecording",
      ])
    #expect(AgentPermissionLevel.controlActiveRecording.label == "控制正在录音")
    let data = try JSONEncoder.woice.encode(AgentPermissionLevel.createTasks)
    #expect(try JSONDecoder.woice.decode(AgentPermissionLevel.self, from: data) == .createTasks)
  }

  @Test("CLI 用户可见名称保留稳定 ID 并明确标注 Beta")
  func cliUserFacingNamesKeepStableIDs() {
    #expect(AgentCLIAdapterCatalog.userFacingDisplayName(for: "codex-cli") == "Codex CLI · Beta")
    #expect(
      AgentCLIAdapterCatalog.userFacingDisplayName(for: "claude-cli") == "Claude Code CLI · Beta")
    #expect(AgentCLIAdapterCatalog.userFacingDisplayName(for: "fixture-cli") == "fixture-cli")
  }

  private func package() -> ContextPackage {
    let recordingID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
    let reference = ContextArtifactReference(
      artifactID: "recording:\(recordingID.uuidString)",
      recordingID: recordingID,
      kind: .transcript,
      timeRange: ContextTimeRange(start: 0, end: 12.5))
    let file = ContextPackageFile(
      role: .transcriptMarkdown,
      relativePath: "transcript.md",
      artifactID: reference.artifactID,
      sha256: hash)
    return ContextPackage(
      id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
      createdAt: Date(timeIntervalSince1970: 1_700_000_000),
      artifactRefs: [reference],
      files: [file],
      instruction: "整理成开发任务",
      contentHash: hash)
  }

  @Test("Context Package v1 保留多素材引用、时间范围和安全文件清单")
  func contextPackageRoundTripsAndValidates() throws {
    let original = package()
    #expect(try original.validated() == original)
    let data = try JSONEncoder.woice.encode(original)
    let decoded = try JSONDecoder.woice.decode(ContextPackage.self, from: data)
    #expect(decoded == original)
  }

  @Test("Context Package 拒绝重复 Artifact、非法时间范围和路径穿越")
  func contextPackageRejectsUnsafeInputs() {
    let valid = package()
    let reference = valid.artifactRefs[0]
    let duplicate = ContextPackage(
      artifactRefs: [reference, reference],
      files: valid.files,
      instruction: valid.instruction,
      contentHash: hash)
    #expect(throws: AgentContractValidationError.duplicateArtifactReference) {
      try duplicate.validated()
    }

    let invalidRange = ContextArtifactReference(
      artifactID: "recording:invalid-range",
      recordingID: reference.recordingID,
      kind: .transcript,
      timeRange: ContextTimeRange(start: 9, end: 2))
    #expect(throws: AgentContractValidationError.invalidTimeRange) {
      try invalidRange.validated()
    }

    let escaped = ContextPackageFile(
      role: .audio, relativePath: "../audio.wav", artifactID: reference.artifactID, sha256: hash)
    #expect(throws: AgentContractValidationError.invalidPackagePath) {
      try escaped.validated()
    }
  }

  @Test("Agent CLI Manifest 只允许固定参数、占位符和环境键")
  func cliManifestValidatesSafeBoundary() throws {
    let manifest = AgentCLIAdapterManifest(
      id: "com.example.codex",
      displayName: "Example Agent",
      version: "1.2.3",
      executablePath: "/usr/bin/cat",
      argumentTemplate: ["--context", "{context_file}"],
      allowedEnvironmentKeys: ["LANG"],
      source: .external,
      trust: .unknown)
    #expect(try manifest.validated() == manifest)

    let shell = AgentCLIAdapterManifest(
      id: "com.example.shell",
      displayName: "Unsafe",
      version: "1.0.0",
      executablePath: "/usr/bin/cat",
      argumentTemplate: ["$(whoami)"],
      source: .external,
      trust: .unknown)
    #expect(throws: AgentContractValidationError.invalidArgumentTemplate) {
      try shell.validated()
    }

    let environment = AgentCLIAdapterManifest(
      id: "com.example.env",
      displayName: "Unsafe Environment",
      version: "1.0.0",
      executablePath: "/usr/bin/cat",
      allowedEnvironmentKeys: ["API_KEY=secret"],
      source: .external,
      trust: .unknown)
    #expect(throws: AgentContractValidationError.invalidEnvironmentKey) {
      try environment.validated()
    }
  }

  @Test("Agent Dispatch Job 拒绝 hop 超限和自循环父任务")
  func dispatchJobValidatesChain() throws {
    let packageID = package().id
    let job = AgentDispatchJob(
      idempotencyKey: "agent:\(packageID.uuidString):com.example.codex",
      connectorID: "com.example.codex",
      connectorVersion: "1.2.3",
      contextPackageID: packageID,
      instructionHash: hash,
      permissionSnapshotHash: hash,
      traceID: "trace-1")
    #expect(try job.validated() == job)

    let overLimit = AgentDispatchJob(
      idempotencyKey: "agent:over-limit",
      connectorID: "com.example.codex",
      connectorVersion: "1.2.3",
      contextPackageID: packageID,
      instructionHash: hash,
      permissionSnapshotHash: hash,
      traceID: "trace-1",
      hop: 2,
      maxHop: 1)
    #expect(throws: AgentContractValidationError.hopLimitExceeded) {
      try overLimit.validated()
    }

    let selfParentID = UUID()
    let selfParent = AgentDispatchJob(
      id: selfParentID,
      idempotencyKey: "agent:self-parent",
      connectorID: "com.example.codex",
      connectorVersion: "1.2.3",
      contextPackageID: packageID,
      instructionHash: hash,
      permissionSnapshotHash: hash,
      traceID: "trace-1",
      parentJobID: selfParentID,
      hop: 1)
    #expect(throws: AgentContractValidationError.invalidParentJob) {
      try selfParent.validated()
    }
  }

  @Test("Context Package Builder 只复制显式素材并生成只读文件与稳定哈希")
  func contextPackageBuilderCreatesBoundedBundle() throws {
    let fileManager = FileManager.default
    let sourceRoot = fileManager.temporaryDirectory.appendingPathComponent(
      "woice-agent-source-\(UUID().uuidString)", isDirectory: true)
    let outputRoot = fileManager.temporaryDirectory.appendingPathComponent(
      "woice-agent-output-\(UUID().uuidString)", isDirectory: true)
    let secondOutputRoot = fileManager.temporaryDirectory.appendingPathComponent(
      "woice-agent-output-\(UUID().uuidString)", isDirectory: true)
    defer {
      try? fileManager.removeItem(at: sourceRoot)
      try? fileManager.removeItem(at: outputRoot)
      try? fileManager.removeItem(at: secondOutputRoot)
    }
    try fileManager.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: outputRoot, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: secondOutputRoot, withIntermediateDirectories: true)
    let source = sourceRoot.appendingPathComponent("original.wav")
    let sourceBytes = Data("original-audio".utf8)
    try sourceBytes.write(to: source)

    let recordingID = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
    let item = ContextPackageBuildItem(
      reference: ContextArtifactReference(
        artifactID: "recording:\(recordingID.uuidString):audio",
        recordingID: recordingID,
        kind: .audio,
        sourceTrack: .microphone,
        timeRange: ContextTimeRange(start: 1, end: 3)),
      text: "会议预算需要在周五前确认。",
      sourceURL: source)
    let packageID = UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!
    let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
    let builder = ContextPackageBuilder(fileManager: fileManager)
    let first = try builder.build(
      items: [item], instruction: "提取待办", packageID: packageID, createdAt: createdAt,
      rootURL: outputRoot)
    let second = try builder.build(
      items: [item], instruction: "提取待办", packageID: packageID, createdAt: createdAt,
      rootURL: secondOutputRoot)

    #expect(try first.package.validated() == first.package)
    #expect(first.package.contentHash == second.package.contentHash)
    #expect(try Data(contentsOf: first.transcriptURL) == Data(contentsOf: second.transcriptURL))
    #expect(try Data(contentsOf: source) == sourceBytes)
    #expect(fileManager.fileExists(atPath: first.contextURL.path))
    #expect(first.audioURLs.count == 1)
    let permissions =
      try fileManager.attributesOfItem(atPath: first.audioURLs[0].path)[.posixPermissions]
      as? NSNumber
    #expect((permissions?.intValue ?? 0) & 0o222 == 0)
  }

  @Test("Context Package Builder 对缺失音频 fail-closed 且不留下临时目录")
  func contextPackageBuilderRejectsMissingSource() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appendingPathComponent(
      "woice-agent-missing-\(UUID().uuidString)", isDirectory: true)
    defer { try? fileManager.removeItem(at: root) }
    try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    let packageID = UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!
    let item = ContextPackageBuildItem(
      reference: ContextArtifactReference(
        artifactID: "recording:\(packageID.uuidString):audio", recordingID: packageID, kind: .audio),
      text: "文本",
      sourceURL: root.appendingPathComponent("missing.wav"))
    #expect(throws: ContextPackageBuilderError.sourceMissing) {
      try ContextPackageBuilder(fileManager: fileManager).build(
        items: [item], instruction: "处理", packageID: packageID,
        createdAt: Date(timeIntervalSince1970: 1_700_000_000), rootURL: root)
    }
    #expect(
      !fileManager.fileExists(
        atPath: root.appendingPathComponent(
          "woice-context-\(packageID.uuidString)"
        ).path))
  }
}
