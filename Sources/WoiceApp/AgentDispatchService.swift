import CryptoKit
import Foundation
import WoiceCore

#if !WOICE_APP_STORE
  #if !WOICE_APP_STORE
    enum AgentDispatchServiceError: LocalizedError, Equatable, Sendable {
      case transcriptUnavailable
      case unsupportedOutput
      case emptyOutput
      case resultWriteFailed

      var errorDescription: String? {
        switch self {
        case .transcriptUnavailable: "这条录音没有可交给 Agent 的原文。"
        case .unsupportedOutput: "当前 Agent 输出格式暂不支持创建结果 Artifact。"
        case .emptyOutput: "Agent 没有返回可保存的结果。"
        case .resultWriteFailed: "Agent 结果无法安全保存到本机。"
        }
      }
    }

    struct AgentDispatchExecution: Sendable {
      let artifact: AgentResultArtifact
    }
  #endif

  /// Collects only bounded stdout/result-file bytes into a new immutable file.
  /// It never overwrites a source recording or executes returned content.
  final class AgentResultCollector: @unchecked Sendable {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
      self.fileManager = fileManager
    }

    func collect(
      result: ControlledCLIRunResult,
      manifest: AgentCLIAdapterManifest,
      package: ContextPackageBundle,
      parentRecordingID: UUID,
      rootURL: URL
    ) throws -> AgentDispatchExecution {
      let data: Data
      let kind: AgentResultArtifactKind
      let suffix: String
      let mimeType: String
      switch manifest.outputTransport {
      case .markdown:
        kind = .markdown
        suffix = "md"
        mimeType = "text/markdown"
      case .text:
        kind = .text
        suffix = "txt"
        mimeType = "text/plain"
      case .json, .jsonl:
        kind = .json
        suffix = "json"
        mimeType = "application/json"
      case .files:
        throw AgentDispatchServiceError.unsupportedOutput
      }
      if let outputFileData = result.outputFileData, !outputFileData.isEmpty {
        data = outputFileData
      } else {
        data = result.stdout
      }
      guard !data.isEmpty, data.count <= 16 * 1024 * 1024 else {
        throw AgentDispatchServiceError.emptyOutput
      }
      if manifest.outputTransport == .json, (try? JSONSerialization.jsonObject(with: data)) == nil {
        throw AgentDispatchServiceError.unsupportedOutput
      }
      if manifest.outputTransport == .jsonl {
        let lines = String(decoding: data, as: UTF8.self)
          .split(whereSeparator: \.isNewline)
        guard !lines.isEmpty,
          lines.allSatisfy({ line in
            (try? JSONSerialization.jsonObject(with: Data(line.utf8))) != nil
          })
        else { throw AgentDispatchServiceError.unsupportedOutput }
      }

      let artifactID = UUID()
      let resultsDirectory = rootURL.appendingPathComponent("agent-results", isDirectory: true)
      let fileURL = resultsDirectory.appendingPathComponent("\(artifactID.uuidString).\(suffix)")
      do {
        try fileManager.createDirectory(at: resultsDirectory, withIntermediateDirectories: true)
        guard !fileManager.fileExists(atPath: fileURL.path) else {
          throw AgentDispatchServiceError.resultWriteFailed
        }
        try data.write(to: fileURL, options: .atomic)
        try fileManager.setAttributes(
          [.posixPermissions: NSNumber(value: Int16(0o600))], ofItemAtPath: fileURL.path)
      } catch let error as AgentDispatchServiceError {
        throw error
      } catch {
        throw AgentDispatchServiceError.resultWriteFailed
      }

      let artifact = AgentResultArtifact(
        id: artifactID,
        parentRecordingID: parentRecordingID,
        parentArtifactIDs: package.package.artifactRefs.map(\.artifactID),
        connectorID: manifest.id,
        connectorVersion: manifest.version,
        kind: kind,
        relativePath: "results/\(artifactID.uuidString).\(suffix)",
        mimeType: mimeType,
        sha256: sha256(data),
        byteCount: Int64(data.count),
        preview: String(String(decoding: data.prefix(16 * 1024), as: UTF8.self).prefix(4_096)))
      _ = try artifact.validated()
      return AgentDispatchExecution(artifact: artifact)
    }

    private func sha256(_ data: Data) -> String {
      SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
  }

  /// Coordinates one explicit, user-confirmed outbound Agent task. It is not a
  /// general-purpose agent loop: one package goes to one fixed manifest and one
  /// bounded result is collected.
  final class AgentDispatchService: @unchecked Sendable {
    private let runner: ControlledCLIRunner
    private let collector: AgentResultCollector

    init(
      runner: ControlledCLIRunner = ControlledCLIRunner(),
      collector: AgentResultCollector = AgentResultCollector()
    ) {
      self.runner = runner
      self.collector = collector
    }

    func execute(
      manifest: AgentCLIAdapterManifest,
      package: ContextPackageBundle,
      parentRecordingID: UUID,
      rootURL: URL,
      cancellation: ControlledCLICancellation
    ) throws -> AgentDispatchExecution {
      let result = try runner.run(
        manifest: manifest,
        package: package,
        configuration: ControlledCLIRunConfiguration(
          timeout: manifest.timeout,
          maxOutputBytes: 16 * 1024 * 1024,
          allowUnsigned: true,
          verifySignature: false),
        cancellation: cancellation)
      return try collector.collect(
        result: result,
        manifest: manifest,
        package: package,
        parentRecordingID: parentRecordingID,
        rootURL: rootURL)
    }
  }
#endif
