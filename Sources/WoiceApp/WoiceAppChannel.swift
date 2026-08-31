import Foundation

enum WoiceAppChannel: String, Sendable {
  case development = "dev"
  case release
  case store

  static let infoKey = "WOICEAppChannel"

  static var current: WoiceAppChannel {
    resolve(from: Bundle.main.infoDictionary ?? [:])
  }

  static func resolve(from info: [String: Any]) -> WoiceAppChannel {
    if let rawValue = info[infoKey] as? String,
      let channel = WoiceAppChannel(rawValue: rawValue)
    {
      return channel
    }
    if info["CFBundleIdentifier"] as? String == "com.water.woice" {
      return .store
    }
    return .release
  }

  var displayName: String {
    switch self {
    case .development: "Woice (Dev)"
    case .release, .store: "Woice"
    }
  }

  var applicationSupportDirectoryName: String {
    switch self {
    case .development: "Woice Dev"
    case .release, .store: "Woice"
    }
  }

  var keychainService: String {
    switch self {
    case .development: "com.woice.app.dev"
    case .release: "com.woice.app"
    case .store: "com.water.woice"
    }
  }

  func workspaceRoot(in applicationSupport: URL) -> URL {
    applicationSupport.appendingPathComponent(applicationSupportDirectoryName, isDirectory: true)
  }
}
