import Foundation

/// Persistence boundary for the three user-facing settings areas.
///
/// This belongs to the settings domain rather than SwiftUI so Runtime/AppState
/// can scope a save without depending on a view type.
public enum AppSettingsScope: String, CaseIterable, Equatable, Sendable {
  case recording
  case services
  case files
  case agents

  /// Applies only this scope from `draft` to an already committed settings value.
  public func applying(_ draft: AppSettings, to base: AppSettings) -> AppSettings {
    var result = base
    switch self {
    case .recording:
      result.language = draft.language
      result.autoCopyTranscript = draft.autoCopyTranscript
      result.autoPasteTranscript = draft.autoPasteTranscript
      result.includeTranscriptTimestamps = draft.includeTranscriptTimestamps
      result.enableLiveTranscription = draft.enableLiveTranscription
      result.recordingShortcut = draft.recordingShortcut
      result.captureMicrophone = draft.captureMicrophone
      result.captureSystemAudio = draft.captureSystemAudio
      result.meetingTranscriptionMode = draft.meetingTranscriptionMode
    case .services:
      result.asrConfiguration = draft.asrConfiguration
      result.selectedLocalModelPackID = draft.selectedLocalModelPackID
      result.selectedLocalModelVersion = draft.selectedLocalModelVersion
      result.llmEndpoint = draft.llmEndpoint
      result.llmModel = draft.llmModel
      result.llmAPIKey = draft.llmAPIKey
    case .files:
      result.exportDirectory = draft.exportDirectory
    case .agents:
      result.agentPermissions = draft.agentPermissions
    }
    return result
  }
}

/// User-facing language choices for the transcription setting. The persisted
/// AppSettings value remains a provider-compatible BCP-47-ish string so older
/// settings and external adapters do not need a schema migration.
public struct TranscriptionLanguageOption: Hashable, Identifiable, Sendable {
  public let code: String
  public let displayName: String
  public let detail: String

  public var id: String { code.isEmpty ? "auto" : code }

  public var isAutomatic: Bool { code.isEmpty }

  public static let automatic = TranscriptionLanguageOption(
    code: "", displayName: "自动检测", detail: "推荐")

  public static let common: [TranscriptionLanguageOption] = [
    automatic,
    .init(code: "zh", displayName: "简体中文", detail: "zh"),
    .init(code: "zh-TW", displayName: "繁體中文", detail: "zh-TW"),
    .init(code: "yue", displayName: "粤语", detail: "yue"),
    .init(code: "en", displayName: "English", detail: "en"),
    .init(code: "ja", displayName: "日本語", detail: "ja"),
    .init(code: "ko", displayName: "한국어", detail: "ko"),
    .init(code: "es", displayName: "Español", detail: "es"),
    .init(code: "fr", displayName: "Français", detail: "fr"),
    .init(code: "de", displayName: "Deutsch", detail: "de"),
  ]

  public init(code: String, displayName: String, detail: String) {
    self.code = code
    self.displayName = displayName
    self.detail = detail
  }

  /// Projects a legacy or provider-facing code into a readable option. An
  /// unknown non-empty value is preserved as a custom option instead of being
  /// silently changed to a guessed language.
  public static func forCode(_ value: String) -> Self {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return automatic }
    let normalized = trimmed.lowercased()
    switch normalized {
    case "zh", "zh-cn", "zh-hans", "cmn":
      return common[1]
    case "zh-tw", "zh-hk", "zh-hant":
      return common[2]
    case "yue", "zh-yue", "cantonese":
      return common[3]
    case "en", "en-us", "en-gb":
      return common[4]
    case "ja", "ja-jp":
      return common[5]
    case "ko", "ko-kr":
      return common[6]
    case "es", "es-es", "es-419":
      return common[7]
    case "fr", "fr-fr":
      return common[8]
    case "de", "de-de":
      return common[9]
    default:
      return .init(code: trimmed, displayName: "当前配置", detail: trimmed)
    }
  }

  /// Keeps an unknown legacy code visible in the Picker without adding it to
  /// the normal first-level language list.
  public static func pickerOptions(currentCode: String) -> [Self] {
    let current = forCode(currentCode)
    guard !current.isAutomatic, !common.contains(current) else { return common }
    return common + [current]
  }

  /// Returns the value used by providers that require one locale even when
  /// the user selected automatic detection. The empty value itself remains
  /// the persisted contract for providers that support automatic detection.
  public static func providerLanguageCode(for value: String) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.isEmpty else { return trimmed }
    return Locale.preferredLanguages.first ?? "en-US"
  }
}
