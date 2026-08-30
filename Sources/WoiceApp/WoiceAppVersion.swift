import Foundation

enum WoiceAppVersion {
  static var display: String {
    display(from: Bundle.main.infoDictionary ?? [:])
  }

  static var navigationSubtitle: String {
    navigationSubtitle(from: Bundle.main.infoDictionary ?? [:])
  }

  static func display(from info: [String: Any]) -> String {
    let version = value(forKey: "CFBundleShortVersionString", in: info) ?? "开发版"
    guard let build = value(forKey: "CFBundleVersion", in: info) else {
      return version
    }
    return "\(version) (Build \(build))"
  }

  static func navigationSubtitle(from info: [String: Any]) -> String {
    let version = display(from: info)
    return version == "开发版" ? "工作台 · 开发版" : "工作台 · v\(version)"
  }

  private static func value(forKey key: String, in info: [String: Any]) -> String? {
    guard let value = info[key] as? String else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}
