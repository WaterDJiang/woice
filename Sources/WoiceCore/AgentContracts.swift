import Foundation

public enum AgentConnectorDirection: String, Codable, Equatable, Hashable, Sendable {
  case inbound
  case outbound
  case bidirectional
}

public enum AgentConnectorCapability: String, Codable, Equatable, Hashable, Sendable {
  case readMaterials
  case receiveAudio
  case receiveText
  case returnText
  case returnFile
  case controlActiveRecording
}

/// Explicit permission tiers shared by inbound connectors and outbound dispatch UI.
/// Recording control is intentionally represented but not granted by the first-party
/// CLI manifests; a caller must never infer it from a generic connector capability.
public enum AgentPermissionLevel: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
  case readOnlyMaterials
  case createTasks
  case controlActiveRecording

  public var label: String {
    switch self {
    case .readOnlyMaterials: "只读素材"
    case .createTasks: "创建任务"
    case .controlActiveRecording: "控制正在录音"
    }
  }
}

/// Persisted grants for the local Agent boundary. The three capabilities are
/// independent switches rather than one inferred "connected" state. Read
/// access remains available by default for the local material source; creating
/// follow-up tasks is explicit but kept enabled for backwards-compatible
/// protocol behavior; active recording control is always off by default.
public struct AgentPermissionSet: Codable, Equatable, Hashable, Sendable {
  public var canReadMaterials: Bool
  public var canCreateTasks: Bool
  public var canControlActiveRecording: Bool

  public init(
    canReadMaterials: Bool = true,
    canCreateTasks: Bool = true,
    canControlActiveRecording: Bool = false
  ) {
    self.canReadMaterials = canReadMaterials
    self.canCreateTasks = canCreateTasks
    self.canControlActiveRecording = canControlActiveRecording
  }

  public static let `default` = AgentPermissionSet()

  public func allows(_ level: AgentPermissionLevel) -> Bool {
    switch level {
    case .readOnlyMaterials: canReadMaterials
    case .createTasks: canCreateTasks
    case .controlActiveRecording: canControlActiveRecording
    }
  }

  public var enabledLevels: Set<AgentPermissionLevel> {
    Set(AgentPermissionLevel.allCases.filter(allows))
  }
}

public enum ContextArtifactKind: String, Codable, Equatable, Hashable, Sendable {
  case audio
  case transcript
  case transcriptSegment
  case markdown
}

public struct ContextTimeRange: Codable, Equatable, Hashable, Sendable {
  public let start: TimeInterval
  public let end: TimeInterval

  public init(start: TimeInterval, end: TimeInterval) {
    self.start = start
    self.end = end
  }

  public func validated() throws -> Self {
    guard start.isFinite, end.isFinite, start >= 0, end >= start,
      end - start <= 24 * 60 * 60
    else { throw AgentContractValidationError.invalidTimeRange }
    return self
  }
}

public struct ContextArtifactReference: Codable, Equatable, Hashable, Sendable {
  public let artifactID: String
  public let recordingID: UUID
  public let kind: ContextArtifactKind
  public let sourceTrack: AudioTrackKind?
  public let timeRange: ContextTimeRange?

  public init(
    artifactID: String,
    recordingID: UUID,
    kind: ContextArtifactKind,
    sourceTrack: AudioTrackKind? = nil,
    timeRange: ContextTimeRange? = nil
  ) {
    self.artifactID = artifactID
    self.recordingID = recordingID
    self.kind = kind
    self.sourceTrack = sourceTrack
    self.timeRange = timeRange
  }

  public func validated() throws -> Self {
    guard !artifactID.isEmpty, artifactID.utf8.count <= 256,
      !artifactID.contains("/"), !artifactID.contains("\\"), !artifactID.contains("\0")
    else { throw AgentContractValidationError.invalidArtifactReference }
    _ = try timeRange?.validated()
    return self
  }
}

public enum ContextPackageFileRole: String, Codable, Equatable, Hashable, Sendable {
  case contextJSON
  case transcriptMarkdown
  case audio
}

public struct ContextPackageFile: Codable, Equatable, Hashable, Sendable {
  public let role: ContextPackageFileRole
  public let relativePath: String
  public let artifactID: String
  public let sha256: String

  public init(
    role: ContextPackageFileRole, relativePath: String, artifactID: String, sha256: String
  ) {
    self.role = role
    self.relativePath = relativePath
    self.artifactID = artifactID
    self.sha256 = sha256
  }

  public func validated() throws -> Self {
    guard !relativePath.isEmpty, relativePath.utf8.count <= 512,
      !relativePath.hasPrefix("/"), !relativePath.contains("\\"),
      !relativePath.split(separator: "/").contains(".."), !relativePath.contains("\0"),
      !relativePath.contains(";"), !relativePath.contains("|")
    else { throw AgentContractValidationError.invalidPackagePath }
    guard !artifactID.isEmpty, Self.isSHA256(sha256) else {
      throw AgentContractValidationError.invalidContentHash
    }
    return self
  }

  fileprivate static func isSHA256(_ value: String) -> Bool {
    value.count == 64
      && value.unicodeScalars.allSatisfy { scalar in
        (scalar.value >= 48 && scalar.value <= 57)
          || (scalar.value >= 97 && scalar.value <= 102)
      }
  }
}

public struct ContextPackage: Codable, Equatable, Hashable, Sendable, Identifiable {
  public static let currentSchemaVersion = "1"

  public let id: UUID
  public let schemaVersion: String
  public let createdAt: Date
  public let artifactRefs: [ContextArtifactReference]
  public let files: [ContextPackageFile]
  public let instruction: String
  public let contentHash: String

  public init(
    id: UUID = UUID(),
    schemaVersion: String = ContextPackage.currentSchemaVersion,
    createdAt: Date = Date(),
    artifactRefs: [ContextArtifactReference],
    files: [ContextPackageFile],
    instruction: String,
    contentHash: String
  ) {
    self.id = id
    self.schemaVersion = schemaVersion
    self.createdAt = createdAt
    self.artifactRefs = artifactRefs
    self.files = files
    self.instruction = instruction
    self.contentHash = contentHash
  }

  public func validated() throws -> Self {
    guard schemaVersion == Self.currentSchemaVersion else {
      throw AgentContractValidationError.unsupportedSchemaVersion
    }
    guard !artifactRefs.isEmpty, artifactRefs.count <= 64 else {
      throw AgentContractValidationError.invalidArtifactReference
    }
    for reference in artifactRefs { _ = try reference.validated() }
    guard Set(artifactRefs.map(\.artifactID)).count == artifactRefs.count else {
      throw AgentContractValidationError.duplicateArtifactReference
    }
    guard !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !instruction.contains("\0"), instruction.count <= 8_192
    else {
      throw AgentContractValidationError.instructionTooLong
    }
    guard !files.isEmpty, files.count <= 128 else {
      throw AgentContractValidationError.invalidPackageFile
    }
    for file in files { _ = try file.validated() }
    let artifactIDs = Set(artifactRefs.map(\.artifactID))
    guard files.allSatisfy({ artifactIDs.contains($0.artifactID) }) else {
      throw AgentContractValidationError.invalidPackageFile
    }
    guard ContextPackageFile.isSHA256(contentHash) else {
      throw AgentContractValidationError.invalidContentHash
    }
    return self
  }
}

public enum AgentCLIInputTransport: String, Codable, Equatable, Hashable, Sendable {
  case stdinJSON
  case contextPackageFile
  case instructionFile
}

public enum AgentCLIOutputTransport: String, Codable, Equatable, Hashable, Sendable {
  case json
  case jsonl
  case markdown
  case text
  case files
}

public enum AgentWorkingDirectoryPolicy: String, Codable, Equatable, Hashable, Sendable {
  case none
  case readOnly
  case readWrite
}

public struct AgentCLIAdapterManifest: Codable, Equatable, Hashable, Sendable {
  public let id: String
  public let displayName: String
  public let version: String
  public let executablePath: String
  public let versionProbeArguments: [String]
  public let argumentTemplate: [String]
  public let inputTransport: AgentCLIInputTransport
  public let outputTransport: AgentCLIOutputTransport
  public let capabilities: Set<AgentConnectorCapability>
  public let workingDirectoryPolicy: AgentWorkingDirectoryPolicy
  public let allowedEnvironmentKeys: Set<String>
  public let timeout: TimeInterval
  public let source: ProviderSource
  public let trust: ProviderTrustState

  public init(
    id: String,
    displayName: String,
    version: String,
    executablePath: String,
    versionProbeArguments: [String] = ["--version"],
    argumentTemplate: [String] = ["--context", "{context_file}"],
    inputTransport: AgentCLIInputTransport = .contextPackageFile,
    outputTransport: AgentCLIOutputTransport = .markdown,
    capabilities: Set<AgentConnectorCapability> = [.receiveText, .returnText],
    workingDirectoryPolicy: AgentWorkingDirectoryPolicy = .none,
    allowedEnvironmentKeys: Set<String> = [],
    timeout: TimeInterval = 300,
    source: ProviderSource = .external,
    trust: ProviderTrustState = .unknown
  ) {
    self.id = id
    self.displayName = displayName
    self.version = version
    self.executablePath = executablePath
    self.versionProbeArguments = versionProbeArguments
    self.argumentTemplate = argumentTemplate
    self.inputTransport = inputTransport
    self.outputTransport = outputTransport
    self.capabilities = capabilities
    self.workingDirectoryPolicy = workingDirectoryPolicy
    self.allowedEnvironmentKeys = allowedEnvironmentKeys
    self.timeout = timeout
    self.source = source
    self.trust = trust
  }

  public func validated() throws -> Self {
    guard id.range(of: #"^[A-Za-z0-9]+([.-][A-Za-z0-9]+)*$"#, options: .regularExpression) != nil
    else { throw AgentContractValidationError.invalidConnectorID }
    guard !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw AgentContractValidationError.emptyConnectorName
    }
    guard version.range(of: #"^[0-9]+\.[0-9]+\.[0-9]+$"#, options: .regularExpression) != nil
    else { throw AgentContractValidationError.invalidConnectorVersion }
    guard executablePath.hasPrefix("/"), !executablePath.split(separator: "/").contains(".."),
      !executablePath.contains("\0")
    else { throw AgentContractValidationError.invalidExecutablePath }
    guard timeout >= 1, timeout <= 60 * 60, timeout.isFinite else {
      throw AgentContractValidationError.invalidTimeout
    }
    guard versionProbeArguments.allSatisfy(Self.isSafeArgument),
      argumentTemplate.allSatisfy(Self.isSafeArgument)
    else { throw AgentContractValidationError.invalidArgumentTemplate }
    guard
      allowedEnvironmentKeys.allSatisfy({
        $0.range(of: #"^[A-Z][A-Z0-9_]{0,63}$"#, options: .regularExpression) != nil
      })
    else { throw AgentContractValidationError.invalidEnvironmentKey }
    switch (source, trust) {
    case (.bundled, .bundledSigned), (.userInstalled, .signatureVerified),
      (.userInstalled, .unsigned), (.external, .signatureVerified),
      (.external, .unsigned), (.external, .unknown):
      break
    default:
      throw AgentContractValidationError.invalidTrustState
    }
    return self
  }

  private static func isSafeArgument(_ value: String) -> Bool {
    guard !value.isEmpty, !value.contains("\0"), !value.contains("\n"), !value.contains("\r") else {
      return false
    }
    let forbidden = [";", "|", "&", ">", "<", "$", "`", "(", ")"]
    guard !forbidden.contains(where: value.contains) else { return false }
    let placeholders = [
      "{context_package}", "{context_file}", "{instruction_file}", "{result_file}", "{instruction}",
    ]
    let stripped = placeholders.reduce(value) { $0.replacingOccurrences(of: $1, with: "") }
    return !stripped.contains("{") && !stripped.contains("}")
  }
}

public enum AgentDispatchStatus: String, Codable, Equatable, Hashable, Sendable {
  case draft
  case awaitingAuthorization
  case queued
  case launching
  case running
  case collecting
  case awaitingAgentApproval
  case completed
  case failed
  case cancelled
  case interrupted
}

public enum AgentDispatchErrorCode: String, Codable, Equatable, Hashable, Sendable {
  case invalidContract
  case connectorUnavailable
  case notInstalled
  case notAuthenticated
  case timedOut
  case cancelled
  case crashed
  case outputLimitExceeded
  case invalidOutput
  case permissionDenied
}

public enum AgentAuditAction: String, Codable, Equatable, Hashable, Sendable {
  case dispatchRequested
  case dispatchStarted
  case dispatchCompleted
  case dispatchFailed
  case dispatchCancelled
  case inboundRead
}

/// Metadata-only audit entry for Agent boundaries. Prompts, transcript text,
/// audio bytes and provider secrets are deliberately not part of this value.
public struct AgentAuditEvent: Codable, Equatable, Hashable, Sendable, Identifiable {
  public let id: UUID
  public let occurredAt: Date
  public let action: AgentAuditAction
  public let caller: String
  public let connectorID: String
  public let connectorVersion: String?
  public let jobID: UUID?
  public let traceID: String
  public let parentJobID: UUID?
  public let hop: Int
  public let artifactIDs: [String]
  public let dataTypes: [ContextArtifactKind]
  public let resultArtifactID: UUID?
  public let outcomeCode: String?

  public init(
    id: UUID = UUID(),
    occurredAt: Date = Date(),
    action: AgentAuditAction,
    caller: String,
    connectorID: String,
    connectorVersion: String? = nil,
    jobID: UUID? = nil,
    traceID: String,
    parentJobID: UUID? = nil,
    hop: Int = 0,
    artifactIDs: [String] = [],
    dataTypes: [ContextArtifactKind] = [],
    resultArtifactID: UUID? = nil,
    outcomeCode: String? = nil
  ) {
    self.id = id
    self.occurredAt = occurredAt
    self.action = action
    self.caller = caller
    self.connectorID = connectorID
    self.connectorVersion = connectorVersion
    self.jobID = jobID
    self.traceID = traceID
    self.parentJobID = parentJobID
    self.hop = hop
    self.artifactIDs = artifactIDs
    self.dataTypes = dataTypes
    self.resultArtifactID = resultArtifactID
    self.outcomeCode = outcomeCode
  }

  public func validated() throws -> Self {
    guard !caller.isEmpty, caller.utf8.count <= 128,
      !connectorID.isEmpty, connectorID.utf8.count <= 128,
      !traceID.isEmpty, traceID.utf8.count <= 128,
      hop >= 0, hop <= 4,
      artifactIDs.count <= 64,
      artifactIDs.allSatisfy({
        !$0.isEmpty && $0.utf8.count <= 256 && !$0.contains("/") && !$0.contains("\\")
          && !$0.contains("\0")
      }),
      Set(artifactIDs).count == artifactIDs.count,
      dataTypes.count <= 16,
      Set(dataTypes).count == dataTypes.count,
      connectorVersion == nil
        || connectorVersion!.range(
          of: #"^[0-9]+\.[0-9]+\.[0-9]+$"#, options: .regularExpression) != nil,
      outcomeCode == nil || (outcomeCode!.utf8.count <= 128 && !outcomeCode!.contains("\0"))
    else { throw AgentContractValidationError.invalidAuditEvent }
    return self
  }
}

public enum AgentResultArtifactKind: String, Codable, Equatable, Hashable, Sendable {
  case text
  case markdown
  case json
  case file
}

/// Immutable output projection created by a successful external Agent run.
/// The bytes live in Woice's private result directory; this value only carries
/// the bounded lineage and integrity metadata needed by the UI and RPC layer.
public struct AgentResultArtifact: Codable, Equatable, Hashable, Sendable, Identifiable {
  public let id: UUID
  public let parentRecordingID: UUID
  public let parentArtifactIDs: [String]
  public let connectorID: String
  public let connectorVersion: String
  public let createdAt: Date
  public let kind: AgentResultArtifactKind
  public let relativePath: String
  public let mimeType: String
  public let sha256: String
  public let byteCount: Int64
  public let preview: String

  public init(
    id: UUID = UUID(),
    parentRecordingID: UUID,
    parentArtifactIDs: [String],
    connectorID: String,
    connectorVersion: String,
    createdAt: Date = Date(),
    kind: AgentResultArtifactKind,
    relativePath: String,
    mimeType: String,
    sha256: String,
    byteCount: Int64,
    preview: String
  ) {
    self.id = id
    self.parentRecordingID = parentRecordingID
    self.parentArtifactIDs = parentArtifactIDs
    self.connectorID = connectorID
    self.connectorVersion = connectorVersion
    self.createdAt = createdAt
    self.kind = kind
    self.relativePath = relativePath
    self.mimeType = mimeType
    self.sha256 = sha256
    self.byteCount = byteCount
    self.preview = preview
  }

  public func validated() throws -> Self {
    guard !parentArtifactIDs.isEmpty, parentArtifactIDs.count <= 64,
      Set(parentArtifactIDs).count == parentArtifactIDs.count,
      parentArtifactIDs.allSatisfy({ !$0.isEmpty && !$0.contains("/") && !$0.contains("\\") })
    else { throw AgentContractValidationError.invalidResultArtifact }
    guard
      connectorID.range(of: #"^[A-Za-z0-9]+([.-][A-Za-z0-9]+)*$"#, options: .regularExpression)
        != nil,
      connectorVersion.range(of: #"^[0-9]+\.[0-9]+\.[0-9]+$"#, options: .regularExpression)
        != nil
    else { throw AgentContractValidationError.invalidResultArtifact }
    guard !relativePath.hasPrefix("/"), !relativePath.contains("\\"),
      !relativePath.split(separator: "/").contains(".."), !relativePath.contains("\0"),
      relativePath.hasPrefix("results/")
    else { throw AgentContractValidationError.invalidResultArtifact }
    guard !mimeType.isEmpty, mimeType.utf8.count <= 128,
      sha256.count == 64,
      sha256.unicodeScalars.allSatisfy({
        ($0.value >= 48 && $0.value <= 57) || ($0.value >= 97 && $0.value <= 102)
      }),
      byteCount >= 0, byteCount <= 16 * 1024 * 1024,
      preview.utf8.count <= 4_096
    else { throw AgentContractValidationError.invalidResultArtifact }
    return self
  }
}

public struct AgentDispatchJob: Codable, Equatable, Hashable, Sendable, Identifiable {
  public let id: UUID
  public let idempotencyKey: String
  public let connectorID: String
  public let connectorVersion: String
  public let contextPackageID: UUID
  public let instructionHash: String
  public let permissionSnapshotHash: String
  public let traceID: String
  public let parentJobID: UUID?
  public let hop: Int
  public let maxHop: Int
  public var status: AgentDispatchStatus
  public var attempt: Int
  public let createdAt: Date
  public var updatedAt: Date
  public var lastErrorCode: AgentDispatchErrorCode?
  public var lastError: String?
  public var resultArtifact: AgentResultArtifact?

  public init(
    id: UUID = UUID(),
    idempotencyKey: String,
    connectorID: String,
    connectorVersion: String,
    contextPackageID: UUID,
    instructionHash: String,
    permissionSnapshotHash: String,
    traceID: String,
    parentJobID: UUID? = nil,
    hop: Int = 0,
    maxHop: Int = 1,
    status: AgentDispatchStatus = .draft,
    attempt: Int = 0,
    createdAt: Date = Date(),
    updatedAt: Date = Date(),
    lastErrorCode: AgentDispatchErrorCode? = nil,
    lastError: String? = nil,
    resultArtifact: AgentResultArtifact? = nil
  ) {
    self.id = id
    self.idempotencyKey = idempotencyKey
    self.connectorID = connectorID
    self.connectorVersion = connectorVersion
    self.contextPackageID = contextPackageID
    self.instructionHash = instructionHash
    self.permissionSnapshotHash = permissionSnapshotHash
    self.traceID = traceID
    self.parentJobID = parentJobID
    self.hop = hop
    self.maxHop = maxHop
    self.status = status
    self.attempt = attempt
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.lastErrorCode = lastErrorCode
    self.lastError = lastError
    self.resultArtifact = resultArtifact
  }

  public func validated() throws -> Self {
    guard
      connectorID.range(of: #"^[A-Za-z0-9]+([.-][A-Za-z0-9]+)*$"#, options: .regularExpression)
        != nil
    else { throw AgentContractValidationError.invalidConnectorID }
    guard
      connectorVersion.range(of: #"^[0-9]+\.[0-9]+\.[0-9]+$"#, options: .regularExpression)
        != nil
    else { throw AgentContractValidationError.invalidConnectorVersion }
    guard !idempotencyKey.isEmpty, idempotencyKey.utf8.count <= 256,
      !idempotencyKey.contains("\0"), !traceID.isEmpty, traceID.utf8.count <= 128,
      ContextPackageFile.isSHA256(instructionHash),
      ContextPackageFile.isSHA256(permissionSnapshotHash)
    else { throw AgentContractValidationError.invalidDispatchIdentity }
    guard maxHop >= 1, maxHop <= 4, hop >= 0, hop <= maxHop else {
      throw AgentContractValidationError.hopLimitExceeded
    }
    guard parentJobID == nil || (parentJobID != id && hop > 0) else {
      throw AgentContractValidationError.invalidParentJob
    }
    guard attempt >= 0 else { throw AgentContractValidationError.invalidDispatchIdentity }
    if let resultArtifact { _ = try resultArtifact.validated() }
    return self
  }
}

public enum AgentContractValidationError: LocalizedError, Equatable, Sendable {
  case unsupportedSchemaVersion
  case invalidTimeRange
  case invalidArtifactReference
  case duplicateArtifactReference
  case instructionTooLong
  case invalidPackageFile
  case invalidPackagePath
  case invalidContentHash
  case invalidConnectorID
  case emptyConnectorName
  case invalidConnectorVersion
  case invalidExecutablePath
  case invalidArgumentTemplate
  case invalidEnvironmentKey
  case invalidTimeout
  case invalidTrustState
  case invalidDispatchIdentity
  case hopLimitExceeded
  case invalidParentJob
  case invalidResultArtifact
  case invalidAuditEvent

  public var errorDescription: String? {
    switch self {
    case .unsupportedSchemaVersion: "Context Package 版本不受支持。"
    case .invalidTimeRange: "素材时间范围无效或超过 24 小时。"
    case .invalidArtifactReference: "Artifact 引用无效或包含不允许的路径字符。"
    case .duplicateArtifactReference: "Context Package 包含重复 Artifact。"
    case .instructionTooLong: "任务说明为空、过长或包含非法字符。"
    case .invalidPackageFile: "Context Package 文件清单无效。"
    case .invalidPackagePath: "Context Package 文件路径必须是安全的相对路径。"
    case .invalidContentHash: "Context Package 内容哈希不是合法的 SHA-256。"
    case .invalidConnectorID: "Connector ID 不是稳定的安全标识。"
    case .emptyConnectorName: "Connector 显示名称不能为空。"
    case .invalidConnectorVersion: "Connector 版本必须是三段式语义版本。"
    case .invalidExecutablePath: "CLI 可执行文件必须是安全的绝对路径。"
    case .invalidArgumentTemplate: "CLI 参数模板包含 Shell 片段或未知占位符。"
    case .invalidEnvironmentKey: "CLI 环境变量白名单包含非法键名。"
    case .invalidTimeout: "CLI 超时必须在 1 秒至 1 小时之间。"
    case .invalidTrustState: "Connector 来源与信任状态不匹配。"
    case .invalidDispatchIdentity: "Agent 派发任务身份或哈希无效。"
    case .hopLimitExceeded: "Agent 派发链超过最大 hop。"
    case .invalidParentJob: "Agent 派发任务的父子链关系无效。"
    case .invalidResultArtifact: "Agent 结果 Artifact 的来源、路径或完整性信息无效。"
    case .invalidAuditEvent: "Agent 审计事件包含越界或敏感字段。"
    }
  }
}
