import Foundation

/// A registration-based global shortcut value.
///
/// The first version of Woice persisted four enum cases.  The wire decoder
/// still accepts those strings, while new values persist a key code and a
/// small product-owned modifier mask so the UI can record any supported
/// combination without importing Carbon into the domain module.
public struct RecordingShortcut: Codable, CaseIterable, Equatable, Hashable, Sendable {
  public enum Modifier {
    public static let command: UInt32 = 1 << 0
    public static let option: UInt32 = 1 << 1
    public static let control: UInt32 = 1 << 2
    public static let shift: UInt32 = 1 << 3
    public static let all: UInt32 = command | option | control | shift
  }

  public let keyCode: UInt16?
  public let modifierMask: UInt32
  public let keyName: String?

  public init(keyCode: UInt16?, modifierMask: UInt32, keyName: String? = nil) {
    self.keyCode = keyCode
    self.modifierMask = modifierMask & Modifier.all
    self.keyName = keyName
  }

  public static let optionSpace = RecordingShortcut(
    keyCode: 49, modifierMask: Modifier.option, keyName: "Space")
  public static let controlOptionSpace = RecordingShortcut(
    keyCode: 49, modifierMask: Modifier.control | Modifier.option, keyName: "Space")
  public static let commandOptionSpace = RecordingShortcut(
    keyCode: 49, modifierMask: Modifier.command | Modifier.option, keyName: "Space")
  public static let disabled = RecordingShortcut(keyCode: nil, modifierMask: 0)

  public static var allCases: [RecordingShortcut] {
    [optionSpace, controlOptionSpace, commandOptionSpace, disabled]
  }

  public var isDisabled: Bool { keyCode == nil }

  public var hasModifier: Bool { modifierMask != 0 }

  public var isValid: Bool {
    guard keyCode != nil else { return modifierMask == 0 }
    return hasModifier
  }

  public var displayName: String {
    guard let keyCode else { return "关闭" }
    var prefix = ""
    if modifierMask & Modifier.command != 0 { prefix += "⌘" }
    if modifierMask & Modifier.control != 0 { prefix += "⌃" }
    if modifierMask & Modifier.option != 0 { prefix += "⌥" }
    if modifierMask & Modifier.shift != 0 { prefix += "⇧" }
    return prefix + (keyName ?? Self.keyName(for: keyCode))
  }

  public static func keyName(for keyCode: UInt16) -> String {
    switch keyCode {
    case 49: return "Space"
    case 36: return "Return"
    case 48: return "Tab"
    case 53: return "Escape"
    case 51: return "Delete"
    case 117: return "Forward Delete"
    case 123: return "←"
    case 124: return "→"
    case 125: return "↓"
    case 126: return "↑"
    default: return "键码 (keyCode)"
    }
  }

  private enum CodingKeys: String, CodingKey {
    case keyCode, modifierMask, keyName
  }

  public init(from decoder: Decoder) throws {
    if let legacy = try? decoder.singleValueContainer().decode(String.self) {
      switch legacy {
      case "optionSpace": self = .optionSpace
      case "controlOptionSpace": self = .controlOptionSpace
      case "commandOptionSpace": self = .commandOptionSpace
      case "disabled": self = .disabled
      default:
        throw DecodingError.dataCorruptedError(
          in: try decoder.singleValueContainer(), debugDescription: "未知录音快捷键")
      }
      return
    }
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      keyCode: try container.decodeIfPresent(UInt16.self, forKey: .keyCode),
      modifierMask: try container.decodeIfPresent(UInt32.self, forKey: .modifierMask) ?? 0,
      keyName: try container.decodeIfPresent(String.self, forKey: .keyName))
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeIfPresent(keyCode, forKey: .keyCode)
    try container.encode(modifierMask, forKey: .modifierMask)
    try container.encodeIfPresent(keyName, forKey: .keyName)
  }
}

public struct AppSettings: Codable, Equatable, Sendable {
  /// The unified ASR configuration is the persisted source of truth. The
  /// legacy properties below remain as compatibility facades for existing UI,
  /// tests and older callers.
  public var asrConfiguration = ASRProviderConfiguration.default

  /// `automatic` is retained only for decoding older settings and now has the
  /// same safe behavior as `onDevice`. External routing is always explicit.
  public var asrProviderSelection: ASRProviderSelection {
    get { asrConfiguration.selection }
    set { asrConfiguration.selection = newValue }
  }
  /// Optional explicit local model selection. A nil pair follows the
  /// atomically committed current pointer; a non-nil pair pins future jobs to
  /// the user's chosen installed pack until they choose another one.
  public var selectedLocalModelPackID: String?
  public var selectedLocalModelVersion: String?
  public var asrEndpoint: String {
    get { asrConfiguration.endpoint }
    set { asrConfiguration.endpoint = newValue }
  }
  public var asrModel: String {
    get { asrConfiguration.modelID }
    set { asrConfiguration.modelID = newValue }
  }
  /// API keys are loaded from Keychain at runtime and are never encoded by
  /// `ASRProviderConfiguration`.
  public var asrAPIKey: String {
    get { asrConfiguration.apiKey }
    set { asrConfiguration.apiKey = newValue }
  }
  public var llmEndpoint = ""
  public var llmModel = "gpt-4o-mini"
  public var llmAPIKey = ""
  /// Empty means provider-side automatic detection. A missing value in an
  /// older settings file still decodes as `zh` below for compatibility.
  public var language = ""
  public var autoCopyTranscript = true
  public var autoPasteTranscript = false
  public var exportDirectory = ""
  public var captureSystemAudio = false
  public var meetingTranscriptionMode: MeetingTranscriptionMode = .sourceSeparated
  /// Version 1 makes reliable per-track transcription the default. A missing
  /// value identifies settings written before the real dual-track regression
  /// was discovered and is migrated once during decoding.
  private var meetingTranscriptionStrategyVersion = 1
  public var includeTranscriptTimestamps = false
  public var enableLiveTranscription = false
  public var recordingShortcut: RecordingShortcut = .optionSpace

  public static let `default` = AppSettings()

  private enum CodingKeys: String, CodingKey {
    case asrConfiguration, asrProviderSelection, selectedLocalModelPackID,
      selectedLocalModelVersion, asrEndpoint, asrModel, asrAPIKey, llmEndpoint, llmModel, llmAPIKey,
      language
    case autoCopyTranscript, autoPasteTranscript, exportDirectory, captureSystemAudio,
      meetingTranscriptionMode, meetingTranscriptionStrategyVersion,
      includeTranscriptTimestamps, enableLiveTranscription,
      recordingShortcut
  }

  public init() {}

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    if let configuration = try? container.decode(
      ASRProviderConfiguration.self, forKey: .asrConfiguration)
    {
      asrConfiguration = configuration
    } else {
      asrConfiguration = ASRProviderConfiguration(
        selection: Self.normalizedASRSelection(
          (try? container.decode(
            ASRProviderSelection.self, forKey: .asrProviderSelection)) ?? .onDevice),
        endpoint: try container.decodeIfPresent(String.self, forKey: .asrEndpoint) ?? "",
        modelID: try container.decodeIfPresent(String.self, forKey: .asrModel) ?? "whisper-1",
        apiKey: try container.decodeIfPresent(String.self, forKey: .asrAPIKey) ?? "")
    }
    selectedLocalModelPackID =
      try container.decodeIfPresent(String.self, forKey: .selectedLocalModelPackID)
    selectedLocalModelVersion =
      try container.decodeIfPresent(String.self, forKey: .selectedLocalModelVersion)
    llmEndpoint = try container.decodeIfPresent(String.self, forKey: .llmEndpoint) ?? ""
    llmModel = try container.decodeIfPresent(String.self, forKey: .llmModel) ?? "gpt-4o-mini"
    llmAPIKey = try container.decodeIfPresent(String.self, forKey: .llmAPIKey) ?? ""
    language = try container.decodeIfPresent(String.self, forKey: .language) ?? "zh"
    autoCopyTranscript =
      try container.decodeIfPresent(Bool.self, forKey: .autoCopyTranscript) ?? true
    autoPasteTranscript =
      try container.decodeIfPresent(Bool.self, forKey: .autoPasteTranscript) ?? false
    exportDirectory = try container.decodeIfPresent(String.self, forKey: .exportDirectory) ?? ""
    captureSystemAudio =
      try container.decodeIfPresent(Bool.self, forKey: .captureSystemAudio) ?? false
    let decodedMeetingMode = try? container.decode(
      MeetingTranscriptionMode.self, forKey: .meetingTranscriptionMode)
    let decodedMeetingStrategyVersion = try container.decodeIfPresent(
      Int.self, forKey: .meetingTranscriptionStrategyVersion)
    meetingTranscriptionMode =
      decodedMeetingStrategyVersion == nil
      ? .sourceSeparated : (decodedMeetingMode ?? .sourceSeparated)
    meetingTranscriptionStrategyVersion = 1
    includeTranscriptTimestamps =
      try container.decodeIfPresent(Bool.self, forKey: .includeTranscriptTimestamps) ?? false
    enableLiveTranscription =
      try container.decodeIfPresent(Bool.self, forKey: .enableLiveTranscription) ?? false
    recordingShortcut =
      (try? container.decode(RecordingShortcut.self, forKey: .recordingShortcut)) ?? .optionSpace
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(asrConfiguration, forKey: .asrConfiguration)
    try container.encodeIfPresent(selectedLocalModelPackID, forKey: .selectedLocalModelPackID)
    try container.encodeIfPresent(selectedLocalModelVersion, forKey: .selectedLocalModelVersion)
    try container.encode(llmEndpoint, forKey: .llmEndpoint)
    try container.encode(llmModel, forKey: .llmModel)
    try container.encode(language, forKey: .language)
    try container.encode(autoCopyTranscript, forKey: .autoCopyTranscript)
    try container.encode(autoPasteTranscript, forKey: .autoPasteTranscript)
    try container.encode(exportDirectory, forKey: .exportDirectory)
    try container.encode(captureSystemAudio, forKey: .captureSystemAudio)
    try container.encode(meetingTranscriptionMode, forKey: .meetingTranscriptionMode)
    try container.encode(
      meetingTranscriptionStrategyVersion, forKey: .meetingTranscriptionStrategyVersion)
    try container.encode(includeTranscriptTimestamps, forKey: .includeTranscriptTimestamps)
    try container.encode(enableLiveTranscription, forKey: .enableLiveTranscription)
    try container.encode(recordingShortcut, forKey: .recordingShortcut)
  }

  private static func normalizedASRSelection(
    _ selection: ASRProviderSelection
  ) -> ASRProviderSelection {
    selection == .automatic ? .onDevice : selection
  }
}

/// The ASR route is explicit. An external endpoint is only used when the user
/// selects it; otherwise the bundled/downloaded model is the local path.
public enum ASRProviderSelection: String, Codable, CaseIterable, Equatable, Sendable {
  case automatic
  case onDevice
  case external

  public var label: String {
    switch self {
    case .automatic: "本机模型（兼容设置）"
    case .onDevice: "本机模型"
    case .external: "外部服务"
    }
  }
}

/// The single persisted description of how ASR should be reached. `apiKey` is
/// deliberately excluded from Codable: it is a runtime Keychain value and
/// never belongs in settings JSON, logs or database snapshots.
public struct ASRProviderConfiguration: Codable, Equatable, Sendable {
  public var selection: ASRProviderSelection
  public var endpoint: String
  public var modelID: String
  public var apiKey: String

  public static let `default` = ASRProviderConfiguration()

  public init(
    selection: ASRProviderSelection = .onDevice,
    endpoint: String = "",
    modelID: String = "whisper-1",
    apiKey: String = ""
  ) {
    self.selection = selection
    self.endpoint = endpoint
    self.modelID = modelID
    self.apiKey = apiKey
  }

  public var effectiveProviderID: String {
    guard usesExternalService else { return "com.woice.local-asr" }
    return "com.woice.openai-compatible-asr"
  }

  public var transport: ASRProviderTransport {
    usesExternalService ? .http : .inProcess
  }

  public var dataLocation: ASRDataLocation {
    guard usesExternalService else {
      return .onDevice
    }
    guard let url = URL(string: endpoint), let host = url.host else { return .cloud }
    let normalizedHost = host.lowercased()
    if normalizedHost == "localhost" || normalizedHost == "127.0.0.1"
      || normalizedHost == "::1" || normalizedHost.hasPrefix("192.168.")
      || normalizedHost.hasPrefix("10.") || normalizedHost.hasPrefix("172.16.")
      || normalizedHost.hasPrefix("172.17.") || normalizedHost.hasPrefix("172.18.")
      || normalizedHost.hasPrefix("172.19.") || normalizedHost.hasPrefix("172.2")
      || normalizedHost.hasPrefix("172.30.") || normalizedHost.hasPrefix("172.31.")
    {
      return .localNetwork
    }
    return .cloud
  }

  public var usesExternalService: Bool {
    switch selection {
    case .external: true
    case .onDevice, .automatic: false
    }
  }

  public var isConfigured: Bool {
    if !usesExternalService { return true }
    return !endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  public var withoutAPIKey: ASRProviderConfiguration {
    ASRProviderConfiguration(
      selection: selection, endpoint: endpoint, modelID: modelID, apiKey: "")
  }

  private enum CodingKeys: String, CodingKey {
    case selection, endpoint, modelID
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let decodedSelection =
      (try? container.decode(ASRProviderSelection.self, forKey: .selection)) ?? .onDevice
    selection = decodedSelection == .automatic ? .onDevice : decodedSelection
    endpoint = try container.decodeIfPresent(String.self, forKey: .endpoint) ?? ""
    modelID = try container.decodeIfPresent(String.self, forKey: .modelID) ?? "whisper-1"
    apiKey = ""
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(selection, forKey: .selection)
    try container.encode(endpoint, forKey: .endpoint)
    try container.encode(modelID, forKey: .modelID)
  }
}

public enum ASRDataLocation: String, Codable, Equatable, Hashable, Sendable {
  case onDevice
  case localNetwork
  case cloud

  public var label: String {
    switch self {
    case .onDevice: "这台 Mac"
    case .localNetwork: "局域网设备"
    case .cloud: "云端"
    }
  }
}

/// A stable, user-visible description of the model actually used for a
/// transcription. The version is a snapshot, not a mutable global setting.
public struct ASRModelDescriptor: Codable, Equatable, Hashable, Sendable {
  public let providerID: String
  public let modelID: String
  public let displayName: String
  public let version: String
  public let dataLocation: ASRDataLocation

  public init(
    providerID: String,
    modelID: String,
    displayName: String,
    version: String,
    dataLocation: ASRDataLocation
  ) {
    self.providerID = providerID
    self.modelID = modelID
    self.displayName = displayName
    self.version = version
    self.dataLocation = dataLocation
  }
}

public enum AudioTrackKind: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
  case microphone
  case systemAudio
  case meetingMix

  public var label: String {
    switch self {
    case .microphone: "我的麦克风"
    case .systemAudio: "电脑声音"
    case .meetingMix: "会议回放"
    }
  }
}

public enum MeetingTranscriptionMode: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
  case standardMix
  case sourceSeparated

  public var label: String {
    switch self {
    case .standardMix: "快速混音（兼容）"
    case .sourceSeparated: "完整会议（推荐）"
    }
  }

  public var description: String {
    switch self {
    case .standardMix: "合成后只转写一次；重叠说话可能漏掉其中一路。"
    case .sourceSeparated: "分别转写麦克风和电脑声音，再按时间线合并为一份原文。"
    }
  }
}

public enum LocalASRModelCatalog {
  /// macOS does not expose a separate Speech model package version. The
  /// operating-system build is the honest revision visible to the user and
  /// persisted with each transcription snapshot.
  public static var onDeviceSpeech: ASRModelDescriptor {
    let version = ProcessInfo.processInfo.operatingSystemVersion
    return ASRModelDescriptor(
      providerID: "com.apple.speech.on-device",
      modelID: "apple-speech-on-device",
      displayName: "macOS 本机语音模型",
      version: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
      dataLocation: .onDevice
    )
  }
}

public struct TranscriptSegment: Codable, Equatable, Hashable, Sendable {
  public let start: TimeInterval
  public let end: TimeInterval
  public let text: String
  public let sourceTrack: AudioTrackKind?

  public init(
    start: TimeInterval, end: TimeInterval, text: String,
    sourceTrack: AudioTrackKind? = .microphone
  ) {
    self.start = start
    self.end = end
    self.text = text
    self.sourceTrack = sourceTrack
  }

  private enum CodingKeys: String, CodingKey {
    case start, end, text, sourceTrack
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    start = try container.decode(TimeInterval.self, forKey: .start)
    end = try container.decode(TimeInterval.self, forKey: .end)
    text = try container.decode(String.self, forKey: .text)
    // Legacy segments were created from the microphone WAV before track
    // provenance existed. Keep that meaning when the field is absent.
    sourceTrack =
      try container.decodeIfPresent(AudioTrackKind.self, forKey: .sourceTrack)
      ?? .microphone
  }
}

/// An explicit, non-secret health-check fact for a loopback ASR service.
/// The snapshot is intentionally separate from AppSettings so API keys can
/// never become part of the persisted authorization continuity record.
public struct LocalASRTrustSnapshot: Codable, Equatable, Sendable {
  public let endpointIdentity: String
  public let modelID: String
  public let language: String
  public let includeTimestamps: Bool
  public let configurationHash: String
  public let verifiedAt: Date

  public init(
    endpointIdentity: String,
    modelID: String,
    language: String,
    includeTimestamps: Bool,
    configurationHash: String,
    verifiedAt: Date = Date()
  ) {
    self.endpointIdentity = endpointIdentity
    self.modelID = modelID
    self.language = language
    self.includeTimestamps = includeTimestamps
    self.configurationHash = configurationHash
    self.verifiedAt = verifiedAt
  }

  public func matches(
    endpointIdentity: String,
    modelID: String,
    language: String,
    includeTimestamps: Bool,
    configurationHash: String
  ) -> Bool {
    self.endpointIdentity == endpointIdentity
      && self.modelID == modelID
      && self.language == language
      && self.includeTimestamps == includeTimestamps
      && self.configurationHash == configurationHash
  }
}

public struct VoiceSegment: Codable, Equatable, Hashable, Sendable {
  public let start: TimeInterval
  public let end: TimeInterval

  public init(start: TimeInterval, end: TimeInterval) {
    self.start = start
    self.end = max(start, end)
  }

  public var duration: TimeInterval { max(0, end - start) }
}

/// How a material entered Woice. This extends the existing Recording model
/// instead of introducing a second media entity.
public enum RecordingSourceKind: String, Codable, Equatable, Hashable, Sendable {
  case recorded
  case importedAudio
  case importedVideo

  public var label: String {
    switch self {
    case .recorded: "录制"
    case .importedAudio: "导入音频"
    case .importedVideo: "导入视频"
    }
  }

  public var systemImage: String {
    switch self {
    case .recorded: "mic"
    case .importedAudio: "waveform"
    case .importedVideo: "film"
    }
  }
}

public enum ProcessingTaskKind: String, Codable, Equatable, Hashable, Sendable {
  case transcription
  case segmentTranscription
  case languageModel

  public var label: String {
    switch self {
    case .transcription: "语言转文字"
    case .segmentTranscription: "分段语言转文字"
    case .languageModel: "Markdown 笔记"
    }
  }
}

public enum ProcessingTaskStatus: String, Codable, Equatable, Hashable, Sendable {
  case queued
  case waitingForModel
  case awaitingAuthorization
  case running
  case completed
  case failed
  case interrupted
  case cancelled

  public var label: String {
    switch self {
    case .queued: "待处理"
    case .waitingForModel: "等待选择模型"
    case .awaitingAuthorization: "等待确认"
    case .running: "处理中"
    case .completed: "已完成"
    case .failed: "处理失败"
    case .interrupted: "上次中断"
    case .cancelled: "已取消"
    }
  }

  public var systemImage: String {
    switch self {
    case .queued: "clock"
    case .waitingForModel: "square.stack.3d.up"
    case .awaitingAuthorization: "hand.raised.fill"
    case .running: "arrow.triangle.2.circlepath"
    case .completed: "checkmark.circle.fill"
    case .failed: "exclamationmark.triangle.fill"
    case .interrupted: "pause.circle.fill"
    case .cancelled: "xmark.circle"
    }
  }

  public var isRetryable: Bool {
    switch self {
    case .failed, .interrupted, .cancelled: true
    case .queued, .waitingForModel, .awaitingAuthorization, .running, .completed: false
    }
  }
}

/// Readiness of the recording material itself. This is a projection of
/// durable audio/transcription facts, not a live in-memory processing flag.
public enum RecordingMaterialStatus: String, Codable, Equatable, Hashable, Sendable {
  case saved
  case waitingForModel
  case processing
  case ready
  case partiallyReady
  case failed

  public var label: String {
    switch self {
    case .saved: "已保存，待转写"
    case .waitingForModel: "已保存，等待模型"
    case .processing: "正在转写"
    case .ready: "素材已就绪"
    case .partiallyReady: "部分原文已就绪"
    case .failed: "转写失败，素材安全"
    }
  }

  public var systemImage: String {
    switch self {
    case .saved: "checkmark.circle"
    case .waitingForModel: "square.stack.3d.up"
    case .processing: "arrow.triangle.2.circlepath"
    case .ready: "checkmark.seal.fill"
    case .partiallyReady: "circle.lefthalf.filled"
    case .failed: "exclamationmark.triangle"
    }
  }
}

/// The runtime target used for the computer-audio track. A display captures
/// the whole desktop; window targets are an explicit degraded mode for Macs
/// that expose capturable windows but no shareable display.
public enum SystemAudioCaptureTarget: String, Codable, Equatable, Hashable, Sendable {
  case display
  case activeWindow
  case visibleWindow

  public var label: String {
    switch self {
    case .display: "全桌面系统声音"
    case .activeWindow: "活动窗口声音"
    case .visibleWindow: "窗口声音"
    }
  }

  public var systemImage: String {
    switch self {
    case .display: "rectangle.on.rectangle"
    case .activeWindow, .visibleWindow: "macwindow"
    }
  }
}

public enum ProcessingBlockReason: String, Codable, Equatable, Hashable, Sendable {
  case noModelSelected
  case modelUnavailable
  case providerUnavailable
  case authorizationRequired

  public var label: String {
    switch self {
    case .noModelSelected: "尚未选择语言转文字模型"
    case .modelUnavailable: "本机模型暂不可用"
    case .providerUnavailable: "语言转文字服务不可用"
    case .authorizationRequired: "需要允许语音识别权限"
    }
  }
}

public struct ProcessingTask: Codable, Equatable, Hashable, Sendable {
  public let kind: ProcessingTaskKind
  public let idempotencyKey: String
  public var status: ProcessingTaskStatus
  public var attempt: Int
  public let createdAt: Date
  public var updatedAt: Date
  public var lastError: String?
  public var providerID: String?
  public var modelID: String?
  public var modelVersion: String?
  public var dataLocation: ASRDataLocation?
  public var capability: ASRProviderCapability?
  public var configurationHash: String?
  public var blockReason: ProcessingBlockReason?
  public var sourceTrack: AudioTrackKind?
  public var meetingTranscriptionMode: MeetingTranscriptionMode?

  public init(
    kind: ProcessingTaskKind,
    idempotencyKey: String,
    status: ProcessingTaskStatus = .queued,
    attempt: Int = 0,
    createdAt: Date = Date(),
    updatedAt: Date = Date(),
    lastError: String? = nil,
    providerID: String? = nil,
    modelID: String? = nil,
    modelVersion: String? = nil,
    dataLocation: ASRDataLocation? = nil,
    capability: ASRProviderCapability? = nil,
    configurationHash: String? = nil,
    blockReason: ProcessingBlockReason? = nil,
    sourceTrack: AudioTrackKind? = nil,
    meetingTranscriptionMode: MeetingTranscriptionMode? = nil
  ) {
    self.kind = kind
    self.idempotencyKey = idempotencyKey
    self.status = status
    self.attempt = attempt
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.lastError = lastError
    self.providerID = providerID
    self.modelID = modelID
    self.modelVersion = modelVersion
    self.dataLocation = dataLocation
    self.capability = capability
    self.configurationHash = configurationHash
    self.blockReason = blockReason
    self.sourceTrack = sourceTrack
    self.meetingTranscriptionMode = meetingTranscriptionMode
  }
}

/// An immutable transcription result. RecordingRecord keeps a convenient
/// current projection for the UI, while this lineage preserves every
/// completed model/provider attempt without storing credentials.
public struct TranscriptArtifact: Codable, Equatable, Hashable, Sendable, Identifiable {
  public let id: UUID
  public let parentRecordingID: UUID
  public let supersedesID: UUID?
  public let createdAt: Date
  public let text: String
  public let segments: [TranscriptSegment]
  public let providerID: String?
  public let modelID: String?
  public let modelVersion: String?
  public let dataLocation: ASRDataLocation?
  public let configurationHash: String?
  public let sourceTrack: AudioTrackKind?
  public let meetingTranscriptionMode: MeetingTranscriptionMode?

  public init(
    id: UUID = UUID(),
    parentRecordingID: UUID,
    supersedesID: UUID? = nil,
    createdAt: Date = Date(),
    text: String,
    segments: [TranscriptSegment] = [],
    providerID: String? = nil,
    modelID: String? = nil,
    modelVersion: String? = nil,
    dataLocation: ASRDataLocation? = nil,
    configurationHash: String? = nil,
    sourceTrack: AudioTrackKind? = nil,
    meetingTranscriptionMode: MeetingTranscriptionMode? = nil
  ) {
    self.id = id
    self.parentRecordingID = parentRecordingID
    self.supersedesID = supersedesID
    self.createdAt = createdAt
    self.text = text
    self.segments = segments
    self.providerID = providerID
    self.modelID = modelID
    self.modelVersion = modelVersion
    self.dataLocation = dataLocation
    self.configurationHash = configurationHash
    self.sourceTrack = sourceTrack
    self.meetingTranscriptionMode = meetingTranscriptionMode
  }
}

public struct RecordingRecord: Identifiable, Codable, Hashable, Sendable {
  public let id: UUID
  public let createdAt: Date
  public let audioFileName: String
  public let systemAudioFileName: String?
  public let systemAudioBufferCount: Int?
  public let systemAudioPeakLevel: Float?
  public let systemAudioDuration: TimeInterval?
  public let systemAudioStartOffset: TimeInterval?
  public let systemAudioCaptureTarget: SystemAudioCaptureTarget?
  public let meetingMixFileName: String?
  /// Processing policy can change when the user explicitly re-transcribes a
  /// preserved recording; immutable TranscriptArtifacts still snapshot the
  /// mode actually used for each version.
  public var meetingTranscriptionMode: MeetingTranscriptionMode?
  public let sourceKind: RecordingSourceKind
  public let originalMediaFileName: String?
  public let originalMediaSHA256: String?
  public let originalMediaByteCount: Int64?
  public var duration: TimeInterval
  public var transcript: String?
  public var generatedMarkdown: String?
  public var processingError: String?
  public var systemAudioError: String?
  public var transcriptSegments: [TranscriptSegment]?
  public var transcriptArtifacts: [TranscriptArtifact]
  public var activeTranscriptArtifactID: UUID?
  public var voiceSegments: [VoiceSegment]?
  public var processingTasks: [ProcessingTask]

  public init(
    id: UUID, createdAt: Date, audioFileName: String, duration: TimeInterval, transcript: String?,
    generatedMarkdown: String?, processingError: String?, systemAudioFileName: String? = nil,
    systemAudioError: String? = nil, systemAudioBufferCount: Int? = nil,
    systemAudioPeakLevel: Float? = nil, systemAudioDuration: TimeInterval? = nil,
    systemAudioStartOffset: TimeInterval? = nil, meetingMixFileName: String? = nil,
    meetingTranscriptionMode: MeetingTranscriptionMode? = nil,
    systemAudioCaptureTarget: SystemAudioCaptureTarget? = nil,
    transcriptSegments: [TranscriptSegment]? = nil, processingTasks: [ProcessingTask] = [],
    voiceSegments: [VoiceSegment]? = nil,
    transcriptArtifacts: [TranscriptArtifact] = [], activeTranscriptArtifactID: UUID? = nil,
    sourceKind: RecordingSourceKind = .recorded, originalMediaFileName: String? = nil,
    originalMediaSHA256: String? = nil, originalMediaByteCount: Int64? = nil
  ) {
    self.id = id
    self.createdAt = createdAt
    self.audioFileName = audioFileName
    self.systemAudioFileName = systemAudioFileName
    self.systemAudioBufferCount = systemAudioBufferCount
    self.systemAudioPeakLevel = systemAudioPeakLevel
    self.systemAudioDuration = systemAudioDuration
    self.systemAudioStartOffset = systemAudioStartOffset
    self.systemAudioCaptureTarget = systemAudioCaptureTarget
    self.meetingMixFileName = meetingMixFileName
    self.meetingTranscriptionMode = meetingTranscriptionMode
    self.sourceKind = sourceKind
    self.originalMediaFileName = originalMediaFileName
    self.originalMediaSHA256 = originalMediaSHA256
    self.originalMediaByteCount = originalMediaByteCount
    self.duration = duration
    self.transcript = transcript
    self.generatedMarkdown = generatedMarkdown
    self.processingError = processingError
    self.systemAudioError = systemAudioError
    self.transcriptSegments = transcriptSegments
    self.transcriptArtifacts = transcriptArtifacts
    self.activeTranscriptArtifactID = activeTranscriptArtifactID
    self.voiceSegments = voiceSegments
    self.processingTasks = processingTasks
  }

  private enum CodingKeys: String, CodingKey {
    case id, createdAt, audioFileName, systemAudioFileName, systemAudioBufferCount,
      systemAudioPeakLevel, systemAudioDuration, systemAudioStartOffset, meetingMixFileName,
      meetingTranscriptionMode, systemAudioCaptureTarget, sourceKind, originalMediaFileName,
      originalMediaSHA256, originalMediaByteCount, duration, transcript, generatedMarkdown
    case processingError, systemAudioError, transcriptSegments, transcriptArtifacts,
      activeTranscriptArtifactID, voiceSegments, processingTasks
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    createdAt = try container.decode(Date.self, forKey: .createdAt)
    audioFileName = try container.decode(String.self, forKey: .audioFileName)
    systemAudioFileName = try container.decodeIfPresent(String.self, forKey: .systemAudioFileName)
    systemAudioBufferCount = try container.decodeIfPresent(
      Int.self, forKey: .systemAudioBufferCount)
    systemAudioPeakLevel = try container.decodeIfPresent(Float.self, forKey: .systemAudioPeakLevel)
    systemAudioDuration = try container.decodeIfPresent(
      TimeInterval.self, forKey: .systemAudioDuration)
    systemAudioStartOffset = try container.decodeIfPresent(
      TimeInterval.self, forKey: .systemAudioStartOffset)
    systemAudioCaptureTarget = try container.decodeIfPresent(
      SystemAudioCaptureTarget.self, forKey: .systemAudioCaptureTarget)
    meetingMixFileName = try container.decodeIfPresent(String.self, forKey: .meetingMixFileName)
    meetingTranscriptionMode = try container.decodeIfPresent(
      MeetingTranscriptionMode.self, forKey: .meetingTranscriptionMode)
    sourceKind =
      try container.decodeIfPresent(RecordingSourceKind.self, forKey: .sourceKind) ?? .recorded
    originalMediaFileName = try container.decodeIfPresent(
      String.self, forKey: .originalMediaFileName)
    originalMediaSHA256 = try container.decodeIfPresent(String.self, forKey: .originalMediaSHA256)
    originalMediaByteCount = try container.decodeIfPresent(
      Int64.self, forKey: .originalMediaByteCount)
    duration = try container.decode(TimeInterval.self, forKey: .duration)
    transcript = try container.decodeIfPresent(String.self, forKey: .transcript)
    generatedMarkdown = try container.decodeIfPresent(String.self, forKey: .generatedMarkdown)
    processingError = try container.decodeIfPresent(String.self, forKey: .processingError)
    systemAudioError = try container.decodeIfPresent(String.self, forKey: .systemAudioError)
    transcriptSegments =
      try container.decodeIfPresent([TranscriptSegment].self, forKey: .transcriptSegments)
    transcriptArtifacts =
      try container.decodeIfPresent([TranscriptArtifact].self, forKey: .transcriptArtifacts) ?? []
    activeTranscriptArtifactID =
      try container.decodeIfPresent(UUID.self, forKey: .activeTranscriptArtifactID)
    voiceSegments = try container.decodeIfPresent([VoiceSegment].self, forKey: .voiceSegments)
    processingTasks =
      try container.decodeIfPresent([ProcessingTask].self, forKey: .processingTasks) ?? []
  }

  public var title: String {
    if let transcript {
      let readable = TranscriptTextNormalizer.normalize(transcript)
      if !readable.isEmpty {
        return String(readable.prefix(40))
      }
    }
    if let originalMediaFileName, !originalMediaFileName.isEmpty {
      let basename = URL(fileURLWithPath: originalMediaFileName)
        .deletingPathExtension().lastPathComponent
      if sourceKind != .recorded, let marker = basename.range(of: ".source.") {
        let importedName = String(basename[marker.upperBound...])
        if !importedName.isEmpty, importedName != basename {
          return importedName
        }
      }
      return basename
    }
    return "未命名录音"
  }

  public var shortDate: String {
    createdAt.formatted(date: .abbreviated, time: .shortened)
  }

  public var materialStatus: RecordingMaterialStatus {
    let transcriptionTasks = processingTasks.filter {
      $0.kind == .transcription || $0.kind == .segmentTranscription
    }
    let hasTranscript =
      !(transcript?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    let completedCount = transcriptionTasks.filter { $0.status == .completed }.count
    let hasPending = transcriptionTasks.contains {
      switch $0.status {
      case .queued, .waitingForModel, .awaitingAuthorization, .running: true
      case .completed, .failed, .interrupted, .cancelled: false
      }
    }
    let hasFailure = transcriptionTasks.contains {
      switch $0.status {
      case .failed, .interrupted, .cancelled: true
      case .queued, .waitingForModel, .awaitingAuthorization, .running, .completed: false
      }
    }

    if hasTranscript {
      if hasPending { return completedCount > 0 ? .partiallyReady : .processing }
      if hasFailure { return .partiallyReady }
      return .ready
    }
    if transcriptionTasks.contains(where: { $0.status == .waitingForModel }) {
      return .waitingForModel
    }
    if hasPending { return .processing }
    if hasFailure || processingError != nil { return .failed }
    return .saved
  }
}

public enum ProcessingState: Equatable, Sendable {
  case ready
  case authorizing
  case recording
  case transcribing
  case generating
  case awaitingAuthorization
  case saved
  case failed(String)

  public var label: String {
    switch self {
    case .ready: "准备就绪"
    case .authorizing: "正在请求麦克风权限"
    case .recording: "正在录音"
    case .transcribing: "正在转写录音"
    case .generating: "正在生成笔记"
    case .awaitingAuthorization: "等待你确认外发"
    case .saved: "已保存"
    case .failed(let message): message
    }
  }

  public var systemImage: String {
    switch self {
    case .ready: "waveform"
    case .authorizing: "lock.open"
    case .recording: "record.circle.fill"
    case .transcribing: "text.badge.waveform"
    case .generating: "sparkles"
    case .awaitingAuthorization: "hand.raised.fill"
    case .saved: "checkmark.circle.fill"
    case .failed: "exclamationmark.triangle.fill"
    }
  }
}

public enum WoiceError: LocalizedError, Equatable, Sendable {
  case microphoneUnavailable
  case microphonePermissionDenied
  case microphoneCheckWhileRecording
  case systemAudioPermissionDenied
  case systemAudioUnavailable
  case noAudio
  case audioFileMissing
  case transcriptMissing
  case invalidEndpoint(String)
  case discoveryRequiresLocalEndpoint(String)
  case apiFailure(status: Int, body: String)
  case invalidResponse
  case insufficientStorage(required: Int64, available: Int64)
  case storageFailure(String)

  public var errorDescription: String? {
    switch self {
    case .microphoneUnavailable: return "找不到可用的麦克风。"
    case .microphonePermissionDenied: return "麦克风权限未开启，请在系统设置中允许 Woice 使用麦克风。"
    case .microphoneCheckWhileRecording: return "录音进行中，请先结束录音再测试麦克风。"
    case .systemAudioPermissionDenied:
      return
        "当前 Woice 安装实例未获得有效屏幕录制授权；请在系统设置的隐私与安全性 > 屏幕录制中允许 Woice，然后返回这里重新检查。若 Woice 已开启仍失败，请关闭旧版 Woice 授权、重新打开当前安装包后再授权。"
    case .systemAudioUnavailable:
      return "当前 Mac 没有可共享显示器或窗口形式的系统音频采集目标，请解锁桌面、退出远程桌面后重试。"
    case .noAudio: return "这次录音没有捕获到音频。"
    case .audioFileMissing: return "录音文件没有成功保存，请重试。"
    case .transcriptMissing: return "这条录音还没有转写原文，请先完成转写。"
    case .invalidEndpoint(let value): return "API 地址无效：\(value)"
    case .discoveryRequiresLocalEndpoint(let value):
      return "模型发现只允许本机或局域网地址：\(value)"
    case .apiFailure(let status, let body): return "接口返回 HTTP \(status)：\(body)"
    case .invalidResponse: return "接口返回无法识别的内容。"
    case .insufficientStorage(let required, let available):
      let requiredText = ByteCountFormatter.string(fromByteCount: required, countStyle: .file)
      let availableText = ByteCountFormatter.string(fromByteCount: available, countStyle: .file)
      return "录音保存卷空间不足：当前可用 \(availableText)，至少需要保留 \(requiredText)。请清理空间或更换文件位置后重试。"
    case .storageFailure(let message): return "本地文件保存失败：\(message)"
    }
  }
}
