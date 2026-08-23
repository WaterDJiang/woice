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
