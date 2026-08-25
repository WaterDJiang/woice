import CryptoKit
import Foundation

public enum ASRProviderTransport: String, Codable, Equatable, Hashable, Sendable {
  case inProcess
  case http
  case controlledProcess

  public var label: String {
    switch self {
    case .inProcess: "内置"
    case .http: "HTTP 服务"
    case .controlledProcess: "受控进程"
    }
  }
}

public enum ASRProviderCapability: String, Codable, Equatable, Hashable, Sendable {
  case transcription
  case timestamps
  case streaming

  public var label: String {
    switch self {
    case .transcription: "语言转文字"
    case .timestamps: "时间戳"
    case .streaming: "实时预览"
    }
  }
}

public enum ASRProviderHealth: String, Codable, Equatable, Hashable, Sendable {
  case unconfigured
  case waitingForModel
  case downloading
  case verifying
  case ready
  case authorizationRequired
  case modelMissing
  case unavailable
  case incompatible
  case untrusted
  case disabled

  public var label: String {
    switch self {
    case .unconfigured: "未配置"
    case .waitingForModel: "等待选择模型"
    case .downloading: "下载中"
    case .verifying: "校验中"
    case .ready: "已就绪"
    case .authorizationRequired: "需要授权"
    case .modelMissing: "模型缺失"
    case .unavailable: "服务不可达"
    case .incompatible: "能力不兼容"
    case .untrusted: "来源不可信"
    case .disabled: "已停用"
    }
  }
}

/// A stable, UI-safe description of an ASR implementation. It contains no
/// credentials and no executable paths; process-provider trust remains owned
/// by the existing Provider SDK boundary.
public struct ASRProviderDescriptor: Codable, Equatable, Hashable, Sendable {
  public let providerID: String
  public let displayName: String
  public let transport: ASRProviderTransport
  public let dataLocation: ASRDataLocation
  public let capabilities: [ASRProviderCapability]
  public var health: ASRProviderHealth

  public init(
    providerID: String,
    displayName: String,
    transport: ASRProviderTransport,
    dataLocation: ASRDataLocation,
    capabilities: [ASRProviderCapability],
    health: ASRProviderHealth
  ) {
    self.providerID = providerID
    self.displayName = displayName
    self.transport = transport
    self.dataLocation = dataLocation
    self.capabilities = capabilities
    self.health = health
  }

  public func supports(_ capability: ASRProviderCapability) -> Bool {
    capabilities.contains(capability)
  }

  public static let builtIns: [ASRProviderDescriptor] = [
    ASRProviderDescriptor(
      providerID: "com.apple.speech.on-device",
      displayName: "macOS 本机语音模型",
      transport: .inProcess,
      dataLocation: .onDevice,
      capabilities: [.transcription],
      health: .waitingForModel),
    ASRProviderDescriptor(
      providerID: "com.woice.whisperkit",
      displayName: "WhisperKit 本机模型",
      transport: .inProcess,
      dataLocation: .onDevice,
      capabilities: [.transcription, .timestamps],
      health: .waitingForModel),
    ASRProviderDescriptor(
      providerID: "com.woice.qwen3-asr",
      displayName: "Qwen3-ASR 本机模型",
      transport: .inProcess,
      dataLocation: .onDevice,
      capabilities: [.transcription, .timestamps],
      health: .waitingForModel),
    ASRProviderDescriptor(
      providerID: "com.woice.openai-compatible-asr",
      displayName: "OpenAI-compatible ASR",
      transport: .http,
      dataLocation: .cloud,
      capabilities: [.transcription, .timestamps],
      health: .unconfigured),
  ]
}

public enum ASRProviderRegistryError: LocalizedError, Equatable, Sendable {
  case duplicateProvider(String)
  case providerNotFound(String)
  case capabilityUnavailable(String, ASRProviderCapability)

  public var errorDescription: String? {
    switch self {
    case .duplicateProvider(let id): "ASR Provider 已注册：" + id
    case .providerNotFound(let id): "找不到 ASR Provider：" + id
    case .capabilityUnavailable(let id, let capability):
      "ASR Provider " + id + " 不支持 " + capability.label + "。"
    }
  }
}

/// Runtime-owned registry for the finite set of trusted ASR implementations.
/// It never discovers or loads arbitrary code; callers explicitly register
/// only providers already admitted by the App composition root.
public actor ASRProviderRegistry {
  private var entries: [String: ASRProviderDescriptor]

  public init(descriptors: [ASRProviderDescriptor] = ASRProviderDescriptor.builtIns) {
    var unique: [String: ASRProviderDescriptor] = [:]
    for descriptor in descriptors where unique[descriptor.providerID] == nil {
      unique[descriptor.providerID] = descriptor
    }
    entries = unique
  }

  public func register(_ descriptor: ASRProviderDescriptor) throws {
    guard entries[descriptor.providerID] == nil else {
      throw ASRProviderRegistryError.duplicateProvider(descriptor.providerID)
    }
    entries[descriptor.providerID] = descriptor
  }

  public func updateHealth(
    providerID: String, health: ASRProviderHealth
  ) throws {
    guard var descriptor = entries[providerID] else {
      throw ASRProviderRegistryError.providerNotFound(providerID)
    }
    descriptor.health = health
    entries[providerID] = descriptor
  }

  public func snapshot() -> [ASRProviderDescriptor] {
    entries.values.sorted { $0.providerID < $1.providerID }
  }

  public func descriptor(for providerID: String) -> ASRProviderDescriptor? {
    entries[providerID]
  }

  /// Resolves the current ASR configuration without changing it. The caller
  /// supplies whether a verified local model is available because loading a
  /// model is intentionally outside the registry and must not happen here.
  public func resolve(
    configuration: ASRProviderConfiguration,
    localModelAvailable: Bool,
    capability: ASRProviderCapability = .transcription,
    localProviderID: String? = nil
  ) throws -> ASRProviderDescriptor {
    let providerID: String
    if configuration.usesExternalService {
      providerID = "com.woice.openai-compatible-asr"
    } else if localModelAvailable {
      providerID = localProviderID ?? "com.woice.whisperkit"
    } else {
      providerID = "com.apple.speech.on-device"
    }
    guard var descriptor = entries[providerID] else {
      throw ASRProviderRegistryError.providerNotFound(providerID)
    }
    guard descriptor.supports(capability) else {
      throw ASRProviderRegistryError.capabilityUnavailable(providerID, capability)
    }
    if configuration.usesExternalService {
      descriptor.health = configuration.isConfigured ? .ready : .unconfigured
    } else {
      descriptor.health = localModelAvailable ? .ready : .waitingForModel
    }
    return descriptor
  }
}

public enum ModelInstallationState: String, Codable, Equatable, Hashable, Sendable {
  case available
  case awaitingConfirmation
  case preflighting
  case downloading
  case verifying
  case installing
  case activating
  case installed
  case paused
  case failed
  case cancelled

  public var label: String {
    switch self {
    case .available: "可安装"
    case .awaitingConfirmation: "等待确认"
    case .preflighting: "准备中"
    case .downloading: "下载中"
    case .verifying: "校验中"
    case .installing: "安装中"
    case .activating: "启用中"
    case .installed: "已安装"
    case .paused: "已暂停"
    case .failed: "失败"
    case .cancelled: "已取消"
    }
  }
}

/// The visible product entry that requested a model installation. The intent
/// is durable metadata only; it never carries audio bytes or executable paths.
public enum ModelInstallEntryPoint: String, Codable, Equatable, Hashable, Sendable {
  case workspace
  case material
  case settings
}

public struct ModelInstallIntent: Codable, Equatable, Hashable, Sendable {
  public let id: UUID
  public let entryPoint: ModelInstallEntryPoint
  public let recordingID: UUID?
  public let sourceTrack: AudioTrackKind?
  public let createdAt: Date

  public init(
    id: UUID = UUID(),
    entryPoint: ModelInstallEntryPoint,
    recordingID: UUID? = nil,
    sourceTrack: AudioTrackKind? = nil,
    createdAt: Date = Date()
  ) {
    self.id = id
    self.entryPoint = entryPoint
    self.recordingID = recordingID
    self.sourceTrack = sourceTrack
    self.createdAt = createdAt
  }
}

/// Durable metadata for a user-triggered model download. The downloaded
/// bytes remain in the filesystem staging directory; this record is the
/// restart-safe explanation of what Woice is doing with them.
public struct ModelDownloadTask: Codable, Equatable, Hashable, Sendable {
  public let id: UUID
  public let packID: String
  public let version: String
  public var state: ModelInstallationState
  public var completedBytes: Int64
  public let totalBytes: Int64
  public var stagingPath: String?
  public var lastError: String?
  public var intents: [ModelInstallIntent]
  public let createdAt: Date
  public var updatedAt: Date

  public init(
    id: UUID = UUID(),
    packID: String,
    version: String,
    state: ModelInstallationState = .awaitingConfirmation,
    completedBytes: Int64 = 0,
    totalBytes: Int64,
    stagingPath: String? = nil,
    lastError: String? = nil,
    intents: [ModelInstallIntent] = [],
    createdAt: Date = Date(),
    updatedAt: Date = Date()
  ) throws {
    try ModelPackValidation.validateIdentifier(packID)
    guard !version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw ModelPackValidationError.invalidIdentifier(version)
    }
    guard totalBytes > 0, completedBytes >= 0, completedBytes <= totalBytes else {
      throw ModelPackValidationError.invalidByteCount("<download>")
    }
    self.id = id
    self.packID = packID
    self.version = version
    self.state = state
    self.completedBytes = completedBytes
    self.totalBytes = totalBytes
    self.stagingPath = stagingPath
    self.lastError = lastError
    self.intents = intents
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }

  public var fractionCompleted: Double {
    guard totalBytes > 0 else { return 0 }
    return min(1, max(0, Double(completedBytes) / Double(totalBytes)))
  }
}

public enum DistributionFlavor: String, Codable, Equatable, Hashable, Sendable {
  case core
  case offline
  case store

  public var label: String {
    switch self {
    case .core: "轻量版"
    case .offline: "离线版"
    case .store: "App Store 版"
    }
  }
}

public struct ModelPackFile: Codable, Equatable, Hashable, Sendable {
  public let relativePath: String
  public let byteCount: Int64
  public let sha256: String

  public init(relativePath: String, byteCount: Int64, sha256: String) throws {
    self.relativePath = relativePath
    self.byteCount = byteCount
    self.sha256 = sha256.lowercased()
    try ModelPackValidation.validateFile(
      relativePath: relativePath, byteCount: byteCount, sha256: sha256)
  }

  private enum CodingKeys: String, CodingKey {
    case relativePath, byteCount, sha256
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      relativePath: container.decode(String.self, forKey: .relativePath),
      byteCount: container.decode(Int64.self, forKey: .byteCount),
      sha256: container.decode(String.self, forKey: .sha256))
  }
}

public struct ModelPackLicense: Codable, Equatable, Hashable, Sendable {
  public let identifier: String
  public let noticePath: String
  public let sourceURL: String

  public init(identifier: String, noticePath: String, sourceURL: String) throws {
    guard !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !noticePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !sourceURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { throw ModelPackValidationError.invalidLicense }
    guard ModelPackValidation.isSafeRelativePath(noticePath) else {
      throw ModelPackValidationError.pathTraversal(noticePath)
    }
    self.identifier = identifier
    self.noticePath = noticePath
    self.sourceURL = sourceURL
  }

  private enum CodingKeys: String, CodingKey {
    case identifier, noticePath, sourceURL
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      identifier: container.decode(String.self, forKey: .identifier),
      noticePath: container.decode(String.self, forKey: .noticePath),
      sourceURL: container.decode(String.self, forKey: .sourceURL))
  }
}

/// Provenance for a derived model format. Store-compatible packs must retain
/// this chain so a downloaded data package can be audited without executing a
/// conversion tool or contacting an untrusted source at runtime.
public struct ModelPackProvenance: Codable, Equatable, Hashable, Sendable {
  public let upstreamModelID: String
  public let upstreamRevision: String
  public let sourceURL: String
  public let derivedFormat: String
  public let conversionTool: String
  public let conversionRevision: String
  public let upstreamSHA256: String?

  public init(
    upstreamModelID: String,
    upstreamRevision: String,
    sourceURL: String,
    derivedFormat: String,
    conversionTool: String,
    conversionRevision: String,
    upstreamSHA256: String? = nil
  ) throws {
    let required = [
      upstreamModelID, upstreamRevision, sourceURL, derivedFormat, conversionTool,
      conversionRevision,
    ]
    guard required.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    else { throw ModelPackValidationError.invalidProvenance }
    guard let url = URL(string: sourceURL), url.scheme?.lowercased() == "https",
      url.user == nil, url.password == nil, url.host?.isEmpty == false
    else { throw ModelPackValidationError.invalidProvenance }
    if let upstreamSHA256 {
      guard upstreamSHA256.range(of: #"^[0-9a-fA-F]{64}$"#, options: .regularExpression) != nil
      else { throw ModelPackValidationError.invalidProvenance }
    }
    self.upstreamModelID = upstreamModelID
    self.upstreamRevision = upstreamRevision
    self.sourceURL = sourceURL
    self.derivedFormat = derivedFormat
    self.conversionTool = conversionTool
    self.conversionRevision = conversionRevision
    self.upstreamSHA256 = upstreamSHA256?.lowercased()
  }

  private enum CodingKeys: String, CodingKey {
    case upstreamModelID, upstreamRevision, sourceURL, derivedFormat, conversionTool,
      conversionRevision, upstreamSHA256
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      upstreamModelID: container.decode(String.self, forKey: .upstreamModelID),
      upstreamRevision: container.decode(String.self, forKey: .upstreamRevision),
      sourceURL: container.decode(String.self, forKey: .sourceURL),
      derivedFormat: container.decode(String.self, forKey: .derivedFormat),
      conversionTool: container.decode(String.self, forKey: .conversionTool),
      conversionRevision: container.decode(String.self, forKey: .conversionRevision),
      upstreamSHA256: container.decodeIfPresent(String.self, forKey: .upstreamSHA256))
  }
}

public struct ModelPackSignature: Codable, Equatable, Hashable, Sendable {
  public let algorithm: String
  public let keyID: String
  public let value: String

  public init(algorithm: String, keyID: String, value: String) throws {
    guard !algorithm.isEmpty, !keyID.isEmpty, !value.isEmpty else {
      throw ModelPackValidationError.invalidSignature
    }
    self.algorithm = algorithm
    self.keyID = keyID
    self.value = value
  }
}

public struct ModelCatalogTrustedKey: Codable, Equatable, Hashable, Sendable {
  public let keyID: String
  public let publicKeyBase64: String

  public init(keyID: String, publicKeyBase64: String) throws {
    try ModelPackValidation.validateIdentifier(keyID)
    guard let data = Data(base64Encoded: publicKeyBase64), data.count == 32 else {
      throw ModelCatalogValidationError.invalidPublicKey
    }
    self.keyID = keyID
    self.publicKeyBase64 = publicKeyBase64
  }
}

public struct ModelCatalogKeyRotation: Codable, Equatable, Sendable {
  public let additions: [ModelCatalogTrustedKey]
  public let revokedKeyIDs: [String]

  public init(
    additions: [ModelCatalogTrustedKey] = [], revokedKeyIDs: [String] = []
  ) throws {
    let additionIDs = additions.map(\.keyID)
    guard Set(additionIDs).count == additionIDs.count else {
      throw ModelCatalogValidationError.invalidKeyRotation("新增公钥重复")
    }
    guard Set(revokedKeyIDs).count == revokedKeyIDs.count else {
      throw ModelCatalogValidationError.invalidKeyRotation("撤销公钥重复")
    }
    for keyID in revokedKeyIDs {
      try ModelPackValidation.validateIdentifier(keyID)
    }
    guard Set(additionIDs).isDisjoint(with: revokedKeyIDs) else {
      throw ModelCatalogValidationError.invalidKeyRotation("同一轮不能同时新增并撤销同一个公钥")
    }
    self.additions = additions
    self.revokedKeyIDs = revokedKeyIDs
  }

  public var isEmpty: Bool { additions.isEmpty && revokedKeyIDs.isEmpty }
}

public struct ModelCatalog: Codable, Equatable, Sendable {
  public let schemaVersion: Int
  public let catalogVersion: Int
  public let catalogID: String
  public let generatedAt: Date
  public let entries: [ModelPackManifest]
  public let signature: ModelPackSignature?
  public let keyRotation: ModelCatalogKeyRotation?

  public init(
    schemaVersion: Int = 1,
    catalogVersion: Int = 1,
    catalogID: String,
    generatedAt: Date,
    entries: [ModelPackManifest],
    signature: ModelPackSignature? = nil,
    keyRotation: ModelCatalogKeyRotation? = nil
  ) throws {
    guard schemaVersion == 1 else {
      throw ModelCatalogValidationError.unsupportedSchemaVersion(schemaVersion)
    }
    guard catalogVersion > 0 else {
      throw ModelCatalogValidationError.invalidCatalogVersion(catalogVersion)
    }
    do {
      try ModelPackValidation.validateIdentifier(catalogID)
    } catch {
      throw ModelCatalogValidationError.invalidCatalogID
    }
    guard !entries.isEmpty else { throw ModelCatalogValidationError.emptyEntries }
    var seen: Set<String> = []
    for entry in entries {
      guard seen.insert(entry.packID).inserted else {
        throw ModelCatalogValidationError.duplicatePack(entry.packID)
      }
      try entry.validate()
    }
    self.schemaVersion = schemaVersion
    self.catalogVersion = catalogVersion
    self.catalogID = catalogID
    self.generatedAt = generatedAt
    self.entries = entries
    self.signature = signature
    self.keyRotation = keyRotation
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion, catalogVersion, catalogID, generatedAt, entries, signature, keyRotation
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      schemaVersion: container.decode(Int.self, forKey: .schemaVersion),
      catalogVersion: container.decodeIfPresent(Int.self, forKey: .catalogVersion) ?? 1,
      catalogID: container.decode(String.self, forKey: .catalogID),
      generatedAt: container.decode(Date.self, forKey: .generatedAt),
      entries: container.decode([ModelPackManifest].self, forKey: .entries),
      signature: container.decodeIfPresent(ModelPackSignature.self, forKey: .signature),
      keyRotation: container.decodeIfPresent(ModelCatalogKeyRotation.self, forKey: .keyRotation))
  }

  public var unsignedPayload: Data {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys]
    return
      (try? encoder.encode(
        UnsignedModelCatalog(
          schemaVersion: schemaVersion,
          catalogVersion: catalogVersion,
          catalogID: catalogID,
          generatedAt: generatedAt,
          entries: entries,
          keyRotation: keyRotation))) ?? Data()
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(schemaVersion, forKey: .schemaVersion)
    try container.encode(catalogVersion, forKey: .catalogVersion)
    try container.encode(catalogID, forKey: .catalogID)
    try container.encode(generatedAt, forKey: .generatedAt)
    try container.encode(entries, forKey: .entries)
    try container.encodeIfPresent(signature, forKey: .signature)
    try container.encodeIfPresent(keyRotation, forKey: .keyRotation)
  }

  private struct UnsignedModelCatalog: Codable {
    let schemaVersion: Int
    let catalogVersion: Int
    let catalogID: String
    let generatedAt: Date
    let entries: [ModelPackManifest]
    let keyRotation: ModelCatalogKeyRotation?
  }
}

public enum ModelCatalogValidationError: LocalizedError, Equatable, Sendable {
  case unsupportedSchemaVersion(Int)
  case invalidCatalogVersion(Int)
  case invalidCatalogID
  case emptyEntries
  case duplicatePack(String)
  case missingSignature
  case unsupportedAlgorithm(String)
  case invalidPublicKey
  case invalidSignatureEncoding
  case signatureMismatch
  case invalidKeyRotation(String)

  public var errorDescription: String? {
    switch self {
    case .unsupportedSchemaVersion(let version): "不支持的模型 Catalog Schema 版本：" + String(version)
    case .invalidCatalogVersion(let version): "模型 Catalog 版本无效：" + String(version)
    case .invalidCatalogID: "模型 Catalog ID 无效。"
    case .emptyEntries: "模型 Catalog 不能没有模型条目。"
    case .duplicatePack(let packID): "模型 Catalog 重复模型包：" + packID
    case .missingSignature: "模型 Catalog 缺少签名。"
    case .unsupportedAlgorithm(let algorithm): "模型 Catalog 不支持签名算法：" + algorithm
    case .invalidPublicKey: "模型 Catalog 公钥无效。"
    case .invalidSignatureEncoding: "模型 Catalog 签名编码无效。"
    case .signatureMismatch: "模型 Catalog 签名校验失败。"
    case .invalidKeyRotation(let reason): "模型 Catalog 密钥轮换无效：" + reason
    }
  }
}

public enum ModelCatalogVerifier {
  public static func verify(
    _ catalog: ModelCatalog,
    publicKeyBase64: String,
    expectedKeyID: String? = nil
  ) throws {
    guard let signature = catalog.signature else {
      throw ModelCatalogValidationError.missingSignature
    }
    guard signature.algorithm == "Ed25519" else {
      throw ModelCatalogValidationError.unsupportedAlgorithm(signature.algorithm)
    }
    if let expectedKeyID, signature.keyID != expectedKeyID {
      throw ModelCatalogValidationError.signatureMismatch
    }
    guard let publicKeyData = Data(base64Encoded: publicKeyBase64),
      let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)
    else {
      throw ModelCatalogValidationError.invalidPublicKey
    }
    guard let signatureData = Data(base64Encoded: signature.value) else {
      throw ModelCatalogValidationError.invalidSignatureEncoding
    }
    guard publicKey.isValidSignature(signatureData, for: catalog.unsignedPayload) else {
      throw ModelCatalogValidationError.signatureMismatch
    }
  }
}

/// Errors raised when a signed Catalog is admitted to or read from the local
/// trusted snapshot. A Catalog is never accepted merely because it decodes:
/// its key ID must be present in the app's explicit trust roots and its
/// version must not move backwards.
public enum ModelCatalogStoreError: LocalizedError, Equatable, Sendable {
  case unknownKey(String)
  case revokedKey(String)
  case catalogMismatch(expected: String, actual: String)
  case rollback(current: Int, incoming: Int)
  case sameVersionDifferentPayload(Int)
  case invalidTrustHistory(String)
  case noActiveKey
  case persistenceFailure(String)

  public var errorDescription: String? {
    switch self {
    case .unknownKey(let keyID): "模型 Catalog 使用了未信任的公钥：" + keyID
    case .revokedKey(let keyID): "模型 Catalog 使用了已撤销的公钥：" + keyID
    case .catalogMismatch(let expected, let actual):
      "模型 Catalog ID 不匹配：期待 " + expected + "，收到 " + actual
    case .rollback(let current, let incoming):
      "模型 Catalog 版本回退：当前 " + String(current) + "，收到 " + String(incoming)
    case .sameVersionDifferentPayload(let version):
      "模型 Catalog 同一版本的内容不一致：" + String(version)
    case .invalidTrustHistory(let reason): "模型 Catalog 信任历史无效：" + reason
    case .noActiveKey: "模型 Catalog 轮换后没有可用的受信公钥。"
    case .persistenceFailure(let message): "模型 Catalog 保存失败：" + message
    }
  }
}

public enum ModelCatalogTransportError: LocalizedError, Equatable, Sendable {
  case disallowedURL(String)
  case redirected(from: String, to: String)
  case responseTooLarge(Int)
  case httpFailure(Int)
  case invalidResponse
  case invalidContentType(String)

  public var errorDescription: String? {
    switch self {
    case .disallowedURL(let url): "模型 Catalog 地址不在允许范围：" + url
    case .redirected(let from, let to): "模型 Catalog 发生不允许的重定向：" + from + " -> " + to
    case .responseTooLarge(let bytes): "模型 Catalog 响应过大：" + String(bytes) + " bytes"
    case .httpFailure(let status): "模型 Catalog 请求失败：HTTP " + String(status)
    case .invalidResponse: "模型 Catalog 响应无效。"
    case .invalidContentType(let value): "模型 Catalog 响应不是 JSON：" + value
    }
  }
}

public struct ModelCatalogFetchPolicy: Equatable, Sendable {
  public let allowedHosts: Set<String>
  public let maxResponseBytes: Int
  public let timeout: TimeInterval

  public init(
    allowedHosts: Set<String>, maxResponseBytes: Int = 2 * 1024 * 1024,
    timeout: TimeInterval = 10
  ) {
    self.allowedHosts = Set(allowedHosts.map { $0.lowercased() })
    self.maxResponseBytes = max(1, maxResponseBytes)
    self.timeout = min(max(timeout, 0.1), 10)
  }

  public func allows(_ url: URL) -> Bool {
    guard url.scheme?.lowercased() == "https",
      let host = url.host?.lowercased(), allowedHosts.contains(host),
      url.user == nil, url.password == nil
    else { return false }
    return true
  }
}

/// Explicit, bounded Catalog transport. It never runs automatically and does
/// not carry credentials; callers must invoke it after a visible user action.
public struct ModelCatalogFetcher: @unchecked Sendable {
  private let session: URLSession

  public init(session: URLSession = .shared) {
    self.session = session
  }

  public func fetch(from url: URL, policy: ModelCatalogFetchPolicy) async throws -> Data {
    guard policy.allows(url) else {
      throw ModelCatalogTransportError.disallowedURL(url.absoluteString)
    }
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.timeoutInterval = policy.timeout
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw ModelCatalogTransportError.invalidResponse
    }
    if let finalURL = response.url, finalURL != url {
      throw ModelCatalogTransportError.redirected(
        from: url.absoluteString, to: finalURL.absoluteString)
    }
    if let contentLength = http.value(forHTTPHeaderField: "Content-Length"),
      let bytes = Int(contentLength), bytes > policy.maxResponseBytes
    {
      throw ModelCatalogTransportError.responseTooLarge(bytes)
    }
    guard (200..<300).contains(http.statusCode) else {
      throw ModelCatalogTransportError.httpFailure(http.statusCode)
    }
    guard data.count <= policy.maxResponseBytes else {
      throw ModelCatalogTransportError.responseTooLarge(data.count)
    }
    if let contentType = http.value(forHTTPHeaderField: "Content-Type") {
      let mediaType =
        contentType.split(separator: ";", maxSplits: 1).first.map {
          $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        } ?? ""
      guard mediaType == "application/json" || mediaType.hasSuffix("+json") else {
        throw ModelCatalogTransportError.invalidContentType(contentType)
      }
    }
    return data
  }
}

/// Local-first Catalog admission and rollback guard. Network fetching remains
/// outside this type: callers fetch bytes explicitly, then pass the signed
/// payload here. Trust roots are supplied by the signed app build and are not
/// read from the Catalog or downloaded at runtime.
public actor ModelCatalogStore {
  private struct PersistedModelCatalogHistory: Codable {
    let catalogs: [ModelCatalog]
  }

  private let storageURL: URL
  private let catalogID: String
  private let initialTrustedKeys: [String: String]
  private let fileManager: FileManager
  private var activeTrustedKeys: [String: String]
  private var revokedKeyIDs: Set<String> = []
  private var history: [ModelCatalog] = []
  private var cachedCatalog: ModelCatalog?
  private var loaded = false

  public init(
    storageURL: URL,
    catalogID: String,
    trustedKeys: [String: String],
    fileManager: FileManager = .default
  ) throws {
    try ModelPackValidation.validateIdentifier(catalogID)
    guard !trustedKeys.isEmpty else {
      throw ModelCatalogStoreError.unknownKey("<empty>")
    }
    var validatedKeys: [String: String] = [:]
    for (keyID, publicKeyBase64) in trustedKeys {
      let key = try ModelCatalogTrustedKey(keyID: keyID, publicKeyBase64: publicKeyBase64)
      validatedKeys[key.keyID] = key.publicKeyBase64
    }
    self.storageURL = storageURL.standardizedFileURL
    self.catalogID = catalogID
    self.initialTrustedKeys = validatedKeys
    self.activeTrustedKeys = validatedKeys
    self.fileManager = fileManager
  }

  /// Loads the persisted snapshot and verifies it again on every cold read.
  /// A corrupted or unsigned snapshot is an error, never an empty success.
  public func load() throws -> ModelCatalog? {
    if loaded { return cachedCatalog }
    guard fileManager.fileExists(atPath: storageURL.path) else { return nil }
    let previousKeys = activeTrustedKeys
    let previousRevoked = revokedKeyIDs
    let previousHistory = history
    let previousCached = cachedCatalog
    do {
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .iso8601
      let data = try Data(contentsOf: storageURL)
      guard data.count <= 16 * 1024 * 1024 else {
        throw ModelCatalogStoreError.persistenceFailure("Catalog 快照超过 16 MiB")
      }
      let catalogs = try decodeHistory(data: data, decoder: decoder)
      guard !catalogs.isEmpty else {
        throw ModelCatalogStoreError.invalidTrustHistory("快照没有 Catalog")
      }
      activeTrustedKeys = initialTrustedKeys
      revokedKeyIDs = []
      history = []
      cachedCatalog = nil
      for catalog in catalogs {
        guard catalog.catalogID == catalogID else {
          throw ModelCatalogStoreError.catalogMismatch(
            expected: catalogID, actual: catalog.catalogID)
        }
        if let previous = history.last, catalog.catalogVersion <= previous.catalogVersion {
          throw ModelCatalogStoreError.invalidTrustHistory("Catalog 版本没有严格递增")
        }
        try admit(catalog)
        try apply(rotation: catalog.keyRotation)
        history.append(catalog)
      }
      cachedCatalog = history.last
      loaded = true
      return cachedCatalog
    } catch let error as ModelCatalogStoreError {
      activeTrustedKeys = previousKeys
      revokedKeyIDs = previousRevoked
      history = previousHistory
      cachedCatalog = previousCached
      loaded = false
      throw error
    } catch {
      activeTrustedKeys = previousKeys
      revokedKeyIDs = previousRevoked
      history = previousHistory
      cachedCatalog = previousCached
      loaded = false
      throw ModelCatalogStoreError.persistenceFailure(error.localizedDescription)
    }
  }

  /// Decodes and admits a fetched payload. The caller controls when a fetch
  /// occurs; this method does not perform network I/O or trigger downloads.
  @discardableResult
  public func accept(data: Data) throws -> ModelCatalog {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    do {
      return try accept(try decoder.decode(ModelCatalog.self, from: data))
    } catch let error as ModelCatalogStoreError {
      throw error
    } catch {
      throw ModelCatalogStoreError.persistenceFailure(error.localizedDescription)
    }
  }

  @discardableResult
  public func accept(_ catalog: ModelCatalog) throws -> ModelCatalog {
    if !loaded { _ = try load() }
    try admit(catalog)
    let current = cachedCatalog
    if let current {
      if catalog.catalogVersion < current.catalogVersion {
        throw ModelCatalogStoreError.rollback(
          current: current.catalogVersion, incoming: catalog.catalogVersion)
      }
      if catalog.catalogVersion == current.catalogVersion,
        catalog.unsignedPayload != current.unsignedPayload
      {
        throw ModelCatalogStoreError.sameVersionDifferentPayload(catalog.catalogVersion)
      }
      if catalog.catalogVersion == current.catalogVersion { return current }
    }
    let previousKeys = activeTrustedKeys
    let previousRevoked = revokedKeyIDs
    let previousHistory = history
    let previousCached = cachedCatalog
    do {
      try apply(rotation: catalog.keyRotation)
      let updatedHistory = history + [catalog]
      try persist(updatedHistory)
      history = updatedHistory
      cachedCatalog = catalog
      loaded = true
      return catalog
    } catch let error as ModelCatalogStoreError {
      activeTrustedKeys = previousKeys
      revokedKeyIDs = previousRevoked
      history = previousHistory
      cachedCatalog = previousCached
      throw error
    } catch {
      activeTrustedKeys = previousKeys
      revokedKeyIDs = previousRevoked
      history = previousHistory
      cachedCatalog = previousCached
      throw ModelCatalogStoreError.persistenceFailure(error.localizedDescription)
    }
  }

  public func snapshot() -> ModelCatalog? { cachedCatalog }

  public func activeTrustedKeyIDs() -> [String] {
    activeTrustedKeys.keys.filter { !revokedKeyIDs.contains($0) }.sorted()
  }

  private func decodeHistory(data: Data, decoder: JSONDecoder) throws -> [ModelCatalog] {
    if let persisted = try? decoder.decode(PersistedModelCatalogHistory.self, from: data) {
      return persisted.catalogs
    }
    return [try decoder.decode(ModelCatalog.self, from: data)]
  }

  private func persist(_ catalogs: [ModelCatalog]) throws {
    try fileManager.createDirectory(
      at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let snapshot = PersistedModelCatalogHistory(catalogs: catalogs)
    try encoder.encode(snapshot).write(to: storageURL, options: .atomic)
  }

  private func admit(_ catalog: ModelCatalog) throws {
    guard catalog.catalogID == catalogID else {
      throw ModelCatalogStoreError.catalogMismatch(expected: catalogID, actual: catalog.catalogID)
    }
    guard let signature = catalog.signature else {
      throw ModelCatalogStoreError.unknownKey("<missing>")
    }
    guard !revokedKeyIDs.contains(signature.keyID) else {
      throw ModelCatalogStoreError.revokedKey(signature.keyID)
    }
    guard let publicKey = activeTrustedKeys[signature.keyID] else {
      throw ModelCatalogStoreError.unknownKey(signature.keyID)
    }
    try ModelCatalogVerifier.verify(
      catalog, publicKeyBase64: publicKey, expectedKeyID: signature.keyID)
  }

  private func apply(rotation: ModelCatalogKeyRotation?) throws {
    guard let rotation, !rotation.isEmpty else { return }
    var proposedKeys = activeTrustedKeys
    var proposedRevoked = revokedKeyIDs
    for addition in rotation.additions {
      guard !proposedRevoked.contains(addition.keyID) else {
        throw ModelCatalogValidationError.invalidKeyRotation("不能重新添加已撤销公钥：" + addition.keyID)
      }
      if let existing = proposedKeys[addition.keyID], existing != addition.publicKeyBase64 {
        throw ModelCatalogValidationError.invalidKeyRotation("公钥 ID 已绑定不同内容：" + addition.keyID)
      }
      proposedKeys[addition.keyID] = addition.publicKeyBase64
    }
    for keyID in rotation.revokedKeyIDs {
      guard proposedKeys[keyID] != nil else {
        throw ModelCatalogValidationError.invalidKeyRotation("不能撤销未知公钥：" + keyID)
      }
      proposedRevoked.insert(keyID)
    }
    guard proposedKeys.keys.contains(where: { !proposedRevoked.contains($0) }) else {
      throw ModelCatalogStoreError.noActiveKey
    }
    activeTrustedKeys = proposedKeys
    revokedKeyIDs = proposedRevoked
  }
}

public enum ModelPackValidationError: LocalizedError, Equatable, Sendable {
  case unsupportedSchemaVersion(Int)
  case invalidIdentifier(String)
  case invalidPlatform(String)
  case invalidArchitecture(String)
  case invalidMinimumOS
  case emptyCapabilities
  case duplicateCapability(ASRProviderCapability)
  case invalidFileCount
  case duplicateFile(String)
  case pathTraversal(String)
  case invalidByteCount(String)
  case invalidSHA256(String)
  case invalidLicense
  case invalidProvenance
  case missingStoreProvenance
  case invalidTransportForStore
  case missingStoreRuntime
  case invalidDownloadBaseURL
  case invalidSignature
  case coreCannotBundleModels
  case duplicateBundledPack(String)

  public var errorDescription: String? {
    switch self {
    case .unsupportedSchemaVersion(let version): "不支持的模型清单 Schema 版本：\(version)"
    case .invalidIdentifier(let value): "模型清单标识无效：\(value)"
    case .invalidPlatform(let value): "不支持的平台：\(value)"
    case .invalidArchitecture(let value): "不支持的架构：\(value)"
    case .invalidMinimumOS: "模型清单缺少最低 macOS 版本。"
    case .emptyCapabilities: "模型清单至少需要声明一个能力。"
    case .duplicateCapability(let capability): "模型清单重复声明能力：\(capability.rawValue)"
    case .invalidFileCount: "模型清单至少需要一个模型文件。"
    case .duplicateFile(let path): "模型清单重复文件：\(path)"
    case .pathTraversal(let path): "模型清单路径不安全：\(path)"
    case .invalidByteCount(let path): "模型文件大小无效：\(path)"
    case .invalidSHA256(let path): "模型文件 SHA-256 无效：\(path)"
    case .invalidLicense: "模型清单许可证信息不完整或路径不安全。"
    case .invalidProvenance: "模型来源与格式转换信息不完整或不安全。"
    case .missingStoreProvenance: "App Store 模型必须记录上游版本与格式转换链。"
    case .invalidTransportForStore: "App Store 模型必须使用随 App 签名的内置 Runtime。"
    case .missingStoreRuntime: "App Store 模型缺少内置 Runtime 标识。"
    case .invalidDownloadBaseURL: "模型清单下载地址必须是无凭据的 HTTPS 地址。"
    case .invalidSignature: "模型清单签名信息不完整。"
    case .coreCannotBundleModels: "Core 发行清单不能声明随包模型。"
    case .duplicateBundledPack(let packID): "发行清单重复模型包：\(packID)"
    }
  }
}

public struct ModelPackManifest: Codable, Equatable, Hashable, Sendable {
  public let schemaVersion: Int
  public let packID: String
  public let modelID: String
  public let version: String
  public let providerID: String
  public let transport: ASRProviderTransport
  public let capabilities: [ASRProviderCapability]
  public let platform: String
  public let architecture: String
  public let minimumOS: String
  public let files: [ModelPackFile]
  public let license: ModelPackLicense
  public let provenance: ModelPackProvenance?
  public let size: Int64
  public let displayName: String?
  public let isRecommended: Bool
  public let storeCompatible: Bool
  /// Stable in-process runtime admission key. It is metadata only and never
  /// points at a downloaded executable or dynamic library.
  public let runtimeID: String?
  /// The signed, directory-like root used by the generic multi-file downloader.
  /// It is optional for bundled/imported packs and legacy manifests.
  public let downloadBaseURL: String?
  public let signature: ModelPackSignature?

  public init(
    schemaVersion: Int = 1,
    packID: String,
    modelID: String,
    version: String,
    providerID: String,
    transport: ASRProviderTransport = .inProcess,
    capabilities: [ASRProviderCapability] = [.transcription],
    platform: String = "macOS",
    architecture: String = "arm64",
    minimumOS: String = "14.0",
    files: [ModelPackFile],
    license: ModelPackLicense,
    size: Int64,
    provenance: ModelPackProvenance? = nil,
    displayName: String? = nil,
    isRecommended: Bool = false,
    storeCompatible: Bool = false,
    runtimeID: String? = nil,
    downloadBaseURL: String? = nil,
    signature: ModelPackSignature? = nil
  ) throws {
    self.schemaVersion = schemaVersion
    self.packID = packID
    self.modelID = modelID
    self.version = version
    self.providerID = providerID
    self.transport = transport
    self.capabilities = capabilities
    self.platform = platform
    self.architecture = architecture
    self.minimumOS = minimumOS
    self.files = files
    self.license = license
    self.size = size
    self.provenance = provenance
    self.displayName = displayName
    self.isRecommended = isRecommended
    self.storeCompatible = storeCompatible
    self.runtimeID = runtimeID
    self.downloadBaseURL = downloadBaseURL
    self.signature = signature
    try validate()
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion, packID, modelID, version, providerID, transport, capabilities, platform
    case architecture, minimumOS, files, license, size, provenance, displayName, isRecommended,
      storeCompatible, runtimeID, downloadBaseURL, signature
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
    self.packID = try container.decode(String.self, forKey: .packID)
    self.modelID = try container.decode(String.self, forKey: .modelID)
    self.version = try container.decode(String.self, forKey: .version)
    self.providerID = try container.decode(String.self, forKey: .providerID)
    self.transport = try container.decode(ASRProviderTransport.self, forKey: .transport)
    self.capabilities = try container.decode([ASRProviderCapability].self, forKey: .capabilities)
    self.platform = try container.decode(String.self, forKey: .platform)
    self.architecture = try container.decode(String.self, forKey: .architecture)
    self.minimumOS = try container.decode(String.self, forKey: .minimumOS)
    self.files = try container.decode([ModelPackFile].self, forKey: .files)
    self.license = try container.decode(ModelPackLicense.self, forKey: .license)
    self.size = try container.decode(Int64.self, forKey: .size)
    self.provenance = try container.decodeIfPresent(ModelPackProvenance.self, forKey: .provenance)
    self.displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
    self.isRecommended = try container.decodeIfPresent(Bool.self, forKey: .isRecommended) ?? false
    self.storeCompatible =
      try container.decodeIfPresent(Bool.self, forKey: .storeCompatible) ?? false
    self.runtimeID = try container.decodeIfPresent(String.self, forKey: .runtimeID)
    self.downloadBaseURL = try container.decodeIfPresent(String.self, forKey: .downloadBaseURL)
    self.signature = try container.decodeIfPresent(ModelPackSignature.self, forKey: .signature)
    try validate()
  }

  public func validate() throws {
    guard schemaVersion == 1 else {
      throw ModelPackValidationError.unsupportedSchemaVersion(schemaVersion)
    }
    try ModelPackValidation.validateIdentifier(packID)
    try ModelPackValidation.validateIdentifier(modelID)
    try ModelPackValidation.validateIdentifier(providerID)
    guard !version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw ModelPackValidationError.invalidIdentifier(version)
    }
    guard platform == "macOS" else { throw ModelPackValidationError.invalidPlatform(platform) }
    guard architecture == "arm64" else {
      throw ModelPackValidationError.invalidArchitecture(architecture)
    }
    guard !minimumOS.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw ModelPackValidationError.invalidMinimumOS
    }
    guard !capabilities.isEmpty else { throw ModelPackValidationError.emptyCapabilities }
    var capabilitySet = Set<ASRProviderCapability>()
    for capability in capabilities where !capabilitySet.insert(capability).inserted {
      throw ModelPackValidationError.duplicateCapability(capability)
    }
    guard !files.isEmpty else { throw ModelPackValidationError.invalidFileCount }
    var fileSet = Set<String>()
    for file in files {
      guard fileSet.insert(file.relativePath).inserted else {
        throw ModelPackValidationError.duplicateFile(file.relativePath)
      }
    }
    guard size > 0 else { throw ModelPackValidationError.invalidByteCount("<pack>") }
    let fileSize = files.reduce(Int64(0)) { $0 + $1.byteCount }
    guard fileSize <= size else { throw ModelPackValidationError.invalidByteCount("<pack>") }
    if let displayName {
      guard !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw ModelPackValidationError.invalidIdentifier("<displayName>")
      }
    }
    if storeCompatible {
      guard transport == .inProcess else {
        throw ModelPackValidationError.invalidTransportForStore
      }
      guard let runtimeID, !runtimeID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw ModelPackValidationError.missingStoreRuntime
      }
      guard provenance != nil else { throw ModelPackValidationError.missingStoreProvenance }
    }
    if let downloadBaseURL {
      guard let url = URL(string: downloadBaseURL), url.scheme?.lowercased() == "https",
        url.user == nil, url.password == nil, url.host?.isEmpty == false,
        !downloadBaseURL.contains("\\")
      else { throw ModelPackValidationError.invalidDownloadBaseURL }
    }
  }
}

public struct DistributionManifest: Codable, Equatable, Hashable, Sendable {
  public let schemaVersion: Int
  public let flavor: DistributionFlavor
  public let appVersion: String
  public let buildVersion: String
  public let bundledModelPackIDs: [String]

  public init(
    schemaVersion: Int = 1,
    flavor: DistributionFlavor,
    appVersion: String,
    buildVersion: String,
    bundledModelPackIDs: [String] = []
  ) throws {
    self.schemaVersion = schemaVersion
    self.flavor = flavor
    self.appVersion = appVersion
    self.buildVersion = buildVersion
    self.bundledModelPackIDs = bundledModelPackIDs
    try validate()
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion, flavor, appVersion, buildVersion, bundledModelPackIDs
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
    flavor = try container.decode(DistributionFlavor.self, forKey: .flavor)
    appVersion = try container.decode(String.self, forKey: .appVersion)
    buildVersion = try container.decode(String.self, forKey: .buildVersion)
    bundledModelPackIDs =
      try container.decodeIfPresent([String].self, forKey: .bundledModelPackIDs) ?? []
    try validate()
  }

  public func validate() throws {
    guard schemaVersion == 1 else {
      throw ModelPackValidationError.unsupportedSchemaVersion(schemaVersion)
    }
    guard !appVersion.isEmpty, !buildVersion.isEmpty else {
      throw ModelPackValidationError.invalidIdentifier("发行版本")
    }
    var seen = Set<String>()
    for packID in bundledModelPackIDs {
      try ModelPackValidation.validateIdentifier(packID)
      guard seen.insert(packID).inserted else {
        throw ModelPackValidationError.duplicateBundledPack(packID)
      }
    }
    if flavor == .core, !bundledModelPackIDs.isEmpty {
      throw ModelPackValidationError.coreCannotBundleModels
    }
  }
}

public enum ModelPackValidation {
  public static func validateIdentifier(_ value: String) throws {
    guard value.range(of: #"^[a-z0-9]+(?:[.-][a-z0-9]+)*$"#, options: .regularExpression) != nil
    else {
      throw ModelPackValidationError.invalidIdentifier(value)
    }
  }

  public static func isSafeRelativePath(_ path: String) -> Bool {
    guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\") else { return false }
    let components = path.split(separator: "/", omittingEmptySubsequences: false)
    return !components.isEmpty
      && components.allSatisfy { component in
        !component.isEmpty && component != "." && component != ".."
      }
  }

  public static func validateFile(relativePath: String, byteCount: Int64, sha256: String) throws {
    guard isSafeRelativePath(relativePath) else {
      throw ModelPackValidationError.pathTraversal(relativePath)
    }
    guard byteCount > 0 else { throw ModelPackValidationError.invalidByteCount(relativePath) }
    guard sha256.range(of: #"^[0-9a-fA-F]{64}$"#, options: .regularExpression) != nil else {
      throw ModelPackValidationError.invalidSHA256(relativePath)
    }
  }
}
