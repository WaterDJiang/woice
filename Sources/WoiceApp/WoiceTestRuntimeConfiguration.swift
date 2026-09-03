import Foundation

/// 仅为桌面验收 Journey 提供隔离配置；普通启动不会读取这些参数。
enum WoiceTestRuntimeConfiguration {
  private static let environment = ProcessInfo.processInfo.environment
  private static let arguments = ProcessInfo.processInfo.arguments

  static var isEnabled: Bool {
    environment["WOICE_TEST_MODE"] == "1" || arguments.contains("--woice-test-mode")
  }

  static var storageRoot: URL? {
    guard isEnabled else { return nil }
    if let rawRoot = environment["WOICE_TEST_STORAGE_ROOT"], !rawRoot.isEmpty {
      return URL(fileURLWithPath: rawRoot, isDirectory: true).standardizedFileURL
    }
    guard let rawRoot = argumentValue(for: "--woice-test-storage-root"), !rawRoot.isEmpty else {
      return nil
    }
    return URL(fileURLWithPath: rawRoot, isDirectory: true).standardizedFileURL
  }

  static var usesFixtureTranscription: Bool {
    guard isEnabled else { return false }
    return environment["WOICE_TEST_TRANSCRIPTION"] == "fixture"
      || argumentValue(for: "--woice-test-transcription") == "fixture"
  }

  /// Test-only switch used by the isolated media-import desktop Journey. A
  /// normal launch never presents an import sheet from command-line state.
  static var shouldPresentImportSheet: Bool {
    guard isEnabled else { return false }
    return environment["WOICE_TEST_PRESENT_IMPORT_SHEET"] == "1"
      || arguments.contains("--woice-test-present-import-sheet")
  }

  /// Keeps the fixture task in a visible running state long enough for the
  /// desktop Journey to exercise the background-close action. This value is
  /// deliberately bounded and ignored unless the fixture Provider is active.
  static var fixtureTranscriptionDelaySeconds: TimeInterval {
    guard isEnabled, usesFixtureTranscription else { return 0 }
    let raw =
      environment["WOICE_TEST_TRANSCRIPTION_DELAY_SECONDS"]
      ?? argumentValue(for: "--woice-test-transcription-delay")
    guard let raw, let value = TimeInterval(raw), value.isFinite, value > 0 else { return 0 }
    return min(value, 60)
  }

  static var importSource: URL? {
    guard isEnabled else { return nil }
    let rawSource =
      environment["WOICE_TEST_IMPORT_SOURCE"]
      ?? argumentValue(for: "--woice-test-import-source")
    guard let rawSource, !rawSource.isEmpty else { return nil }
    return URL(fileURLWithPath: rawSource).standardizedFileURL
  }

  static var shouldTranscribeImportedSource: Bool {
    guard isEnabled else { return false }
    return environment["WOICE_TEST_TRANSCRIBE"] == "1"
      || arguments.contains("--woice-test-transcribe")
  }

  private static func argumentValue(for flag: String) -> String? {
    guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
      return nil
    }
    return arguments[index + 1]
  }
}
