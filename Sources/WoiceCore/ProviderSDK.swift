import Foundation

public enum ProcessProviderKind: String, Codable, Equatable, Hashable, Sendable {
  case asr
  case languageModel
  case tts
}

public enum ProviderSource: String, Codable, Equatable, Hashable, Sendable {
  case bundled
  case userInstalled
  case external
}

public enum ProviderTrustState: String, Codable, Equatable, Hashable, Sendable {
  case bundledSigned
  case signatureVerified
  case unsigned
  case rejected
  case unknown
}

public struct ProcessProviderManifest: Codable, Equatable, Hashable, Sendable {
  public let id: String
  public let displayName: String
  public let version: String
  public let kind: ProcessProviderKind
  public let executablePath: String
  public let arguments: [String]
  public let capabilities: [String]
  public let source: ProviderSource
  public let trust: ProviderTrustState

  public init(
    id: String,
    displayName: String,
    version: String,
    kind: ProcessProviderKind,
    executablePath: String,
    arguments: [String] = [],
    capabilities: [String] = [],
    source: ProviderSource,
    trust: ProviderTrustState
  ) {
    self.id = id
    self.displayName = displayName
    self.version = version
    self.kind = kind
    self.executablePath = executablePath
    self.arguments = arguments
    self.capabilities = capabilities
    self.source = source
    self.trust = trust
  }

  public func validated() throws -> Self {
    try ProcessProviderManifestValidator.validate(self)
    return self
  }
}

public enum ProcessProviderManifestError: LocalizedError, Equatable, Sendable {
  case invalidIdentifier
  case emptyDisplayName
  case invalidVersion
  case relativeExecutablePath
  case executablePathTraversal
  case invalidTrustState

  public var errorDescription: String? {
    switch self {
    case .invalidIdentifier: "Provider ID 必须是稳定的反向域名或短横线标识。"
    case .emptyDisplayName: "Provider 显示名称不能为空。"
    case .invalidVersion: "Provider 版本必须使用三段式语义版本。"
    case .relativeExecutablePath: "Provider 可执行文件必须使用绝对路径。"
    case .executablePathTraversal: "Provider 可执行文件路径不能包含路径穿越。"
    case .invalidTrustState: "Provider 来源与信任状态不匹配，已拒绝加载。"
    }
  }
}

public enum ProcessProviderManifestValidator {
  public static func validate(_ manifest: ProcessProviderManifest) throws {
    let identifier = manifest.id.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !identifier.isEmpty,
      identifier.range(of: #"^[A-Za-z0-9]+([.-][A-Za-z0-9]+)*$"#, options: .regularExpression)
        != nil
    else { throw ProcessProviderManifestError.invalidIdentifier }
    guard !manifest.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw ProcessProviderManifestError.emptyDisplayName
    }
    guard
      manifest.version.range(of: #"^[0-9]+\.[0-9]+\.[0-9]+$"#, options: .regularExpression) != nil
    else { throw ProcessProviderManifestError.invalidVersion }

    let path = manifest.executablePath
    guard path.hasPrefix("/") else { throw ProcessProviderManifestError.relativeExecutablePath }
    let rawComponents = path.split(separator: "/", omittingEmptySubsequences: false)
    guard !rawComponents.contains("..") else {
      throw ProcessProviderManifestError.executablePathTraversal
    }
    switch (manifest.source, manifest.trust) {
    case (.bundled, .bundledSigned), (.userInstalled, .signatureVerified),
      (.userInstalled, .unsigned), (.external, .signatureVerified), (.external, .unsigned),
      (.external, .unknown):
      return
    default:
      throw ProcessProviderManifestError.invalidTrustState
    }
  }
}
