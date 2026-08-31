import Foundation
import Testing

@testable import WoiceApp

struct WoiceAppChannelTests {
  @Test("Bundle channel deterministically separates Dev release and Store")
  func resolvesBundleChannels() {
    #expect(WoiceAppChannel.resolve(from: ["WOICEAppChannel": "dev"]) == .development)
    #expect(WoiceAppChannel.resolve(from: ["WOICEAppChannel": "release"]) == .release)
    #expect(WoiceAppChannel.resolve(from: ["WOICEAppChannel": "store"]) == .store)
    #expect(
      WoiceAppChannel.resolve(from: ["CFBundleIdentifier": "com.water.woice"]) == .store)
    #expect(WoiceAppChannel.resolve(from: ["WOICEAppChannel": "unknown"]) == .release)
  }

  @Test("Dev and formal channels use isolated storage and Keychain services")
  func isolatesRuntimePathsAndSecrets() {
    let applicationSupport = URL(fileURLWithPath: "/tmp/Application Support", isDirectory: true)
    let devRoot = WoiceAppChannel.development.workspaceRoot(in: applicationSupport)
    let releaseRoot = WoiceAppChannel.release.workspaceRoot(in: applicationSupport)

    #expect(devRoot.lastPathComponent == "Woice Dev")
    #expect(releaseRoot.lastPathComponent == "Woice")
    #expect(devRoot != releaseRoot)
    #expect(WoiceAppChannel.development.keychainService == "com.woice.app.dev")
    #expect(WoiceAppChannel.release.keychainService == "com.woice.app")
    #expect(WoiceAppChannel.store.keychainService == "com.water.woice")
    #expect(
      Set(WoiceAppChannel.allKeychainServices).count
        == WoiceAppChannel.allKeychainServices.count)
  }
}

extension WoiceAppChannel {
  fileprivate static var allKeychainServices: [String] {
    [development, release, store].map(\.keychainService)
  }
}
