import Foundation
import WoiceCore

#if !WOICE_APP_STORE
  #if !WOICE_APP_STORE
    struct AgentConnectorDescriptor: Equatable, Hashable, Identifiable, Sendable {
      let displayName: String
      let executablePath: String
      let manifest: AgentCLIAdapterManifest
      let versionOutput: String
      let isUnsigned: Bool

      var version: String { manifest.version }

      var id: String { manifest.id }
    }

    enum AgentCLIConnectionStatus: Equatable, Hashable, Sendable {
      case notInstalled
      case versionDetected(String)
      case versionProbeFailed
      case unsupportedVersion

      var label: String {
        switch self {
        case .notInstalled: "未安装"
        case .versionDetected(let version): "版本 \(version)；登录状态未检查"
        case .versionProbeFailed: "版本探针失败"
        case .unsupportedVersion: "版本不兼容"
        }
      }

      var systemImage: String {
        switch self {
        case .notInstalled: "minus.circle"
        case .versionDetected: "checkmark.circle"
        case .versionProbeFailed, .unsupportedVersion: "exclamationmark.triangle"
        }
      }
    }
  #endif

  struct AgentCLIDiagnostic: Equatable, Hashable, Identifiable, Sendable {
    let connectorID: String
    let displayName: String
    let status: AgentCLIConnectionStatus

    var id: String { connectorID }
  }

  enum AgentCLIAdapterCatalogError: LocalizedError, Equatable, Sendable {
    case versionProbeFailed(String)
    case unsupportedVersion(String)

    var errorDescription: String? {
      switch self {
      case .versionProbeFailed(let message): "无法读取 Agent CLI 版本：\(message)"
      case .unsupportedVersion(let output): "Agent CLI 版本格式不受支持：\(output)"
      }
    }
  }

  /// The catalog is deliberately explicit: it contains only adapters whose
  /// non-interactive invocation and safety flags have been reviewed. It does not
  /// scan the user's PATH or install anything.
  final class AgentCLIAdapterCatalog: @unchecked Sendable {
    /// User-facing labels intentionally carry the Beta marker. Connector IDs
    /// remain stable protocol identifiers and must not be renamed for UI copy.
    static func userFacingDisplayName(for connectorID: String) -> String {
      switch connectorID {
      case Candidate.codex.id: Candidate.codex.displayName
      case Candidate.claude.id: Candidate.claude.displayName
      default: connectorID
      }
    }

    struct Candidate: Sendable {
      let id: String
      let displayName: String
      let executableNames: [String]
      let argumentTemplate: [String]
      let inputTransport: AgentCLIInputTransport
      let outputTransport: AgentCLIOutputTransport
      let capabilities: Set<AgentConnectorCapability>

      static let codex = Candidate(
        id: "codex-cli",
        displayName: "Codex CLI · Beta",
        executableNames: ["codex"],
        argumentTemplate: [
          "exec", "--ephemeral", "--skip-git-repo-check", "--sandbox", "read-only",
          "--ignore-user-config", "--ignore-rules", "--color", "never", "-C", "{context_package}",
          "--output-last-message", "{result_file}", "-",
        ],
        inputTransport: .instructionFile,
        outputTransport: .markdown,
        capabilities: [.receiveAudio, .receiveText, .returnText])

      static let claude = Candidate(
        id: "claude-cli",
        displayName: "Claude Code CLI · Beta",
        executableNames: ["claude"],
        argumentTemplate: [
          "--no-session-persistence", "--permission-mode", "plan", "--add-dir",
          "{context_package}", "--output-format", "text", "-p", "{instruction}",
        ],
        inputTransport: .contextPackageFile,
        outputTransport: .text,
        capabilities: [.receiveAudio, .receiveText, .returnText])

      static let all: [Candidate] = [codex, claude]
    }

    let runner: ControlledCLIRunner
    let fileManager: FileManager

    init(runner: ControlledCLIRunner = ControlledCLIRunner(), fileManager: FileManager = .default) {
      self.runner = runner
      self.fileManager = fileManager
    }

    func discover() -> [AgentConnectorDescriptor] {
      guard StoreCapabilityProfile.current.allowsExternalAgentConnector else { return [] }
      return Candidate.all.compactMap { discover(candidate: $0) }
    }

    /// Returns explicit local diagnostics without claiming that a CLI is logged
    /// in. Woice does not read or copy a CLI's credentials; login remains the
    /// target CLI's responsibility and is intentionally shown as unchecked.
    func diagnostics() -> [AgentCLIDiagnostic] {
      guard StoreCapabilityProfile.current.allowsExternalAgentConnector else { return [] }
      return Candidate.all.map { candidate in
        guard let path = executablePath(for: candidate) else {
          return AgentCLIDiagnostic(
            connectorID: candidate.id, displayName: candidate.displayName, status: .notInstalled)
        }
        let provisional = manifest(candidate: candidate, path: path, version: "0.0.0")
        do {
          let output = try runner.probeVersion(
            manifest: provisional,
            configuration: ControlledCLIRunConfiguration(
              timeout: 15, maxOutputBytes: 16 * 1024, allowUnsigned: true, verifySignature: false))
          guard let version = Self.semanticVersion(in: output) else {
            return AgentCLIDiagnostic(
              connectorID: candidate.id,
              displayName: candidate.displayName,
              status: .unsupportedVersion)
          }
          return AgentCLIDiagnostic(
            connectorID: candidate.id,
            displayName: candidate.displayName,
            status: .versionDetected(version))
        } catch {
          return AgentCLIDiagnostic(
            connectorID: candidate.id,
            displayName: candidate.displayName,
            status: .versionProbeFailed)
        }
      }
    }

    private func discover(candidate: Candidate) -> AgentConnectorDescriptor? {
      guard let path = executablePath(for: candidate) else { return nil }
      let provisional = manifest(candidate: candidate, path: path, version: "0.0.0")
      do {
        let output = try runner.probeVersion(
          manifest: provisional,
          configuration: ControlledCLIRunConfiguration(
            timeout: 15, maxOutputBytes: 16 * 1024, allowUnsigned: true, verifySignature: false))
        guard let version = Self.semanticVersion(in: output) else {
          return nil
        }
        let resolved = manifest(candidate: candidate, path: path, version: version)
        return AgentConnectorDescriptor(
          displayName: candidate.displayName,
          executablePath: path,
          manifest: resolved,
          versionOutput: output,
          isUnsigned: true)
      } catch {
        return nil
      }
    }

    private func executablePath(for candidate: Candidate) -> String? {
      let pathCandidates = candidate.executableNames.flatMap { name in
        [
          "/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)", "/usr/bin/\(name)",
          "/bin/\(name)",
        ]
      }
      return pathCandidates.first(where: { fileManager.isExecutableFile(atPath: $0) })
    }

    private func manifest(candidate: Candidate, path: String, version: String)
      -> AgentCLIAdapterManifest
    {
      AgentCLIAdapterManifest(
        id: candidate.id,
        displayName: candidate.displayName,
        version: version,
        executablePath: path,
        versionProbeArguments: ["--version"],
        argumentTemplate: candidate.argumentTemplate,
        inputTransport: candidate.inputTransport,
        outputTransport: candidate.outputTransport,
        capabilities: candidate.capabilities,
        workingDirectoryPolicy: .readOnly,
        timeout: 15 * 60,
        source: .userInstalled,
        trust: .unsigned)
    }

    static func semanticVersion(in output: String) -> String? {
      let pattern = #"[0-9]+\.[0-9]+\.[0-9]+"#
      return output.range(of: pattern, options: .regularExpression).map { String(output[$0]) }
    }
  }
#endif
