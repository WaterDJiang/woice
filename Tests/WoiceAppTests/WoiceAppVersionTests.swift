import Testing

@testable import WoiceApp

struct WoiceAppVersionTests {
  @Test("版本显示包含产品版本和 Build")
  func formatsVersionAndBuild() {
    let info: [String: Any] = [
      "CFBundleShortVersionString": "0.1.3",
      "CFBundleVersion": "2",
    ]

    #expect(WoiceAppVersion.display(from: info) == "0.1.3 (Build 2)")
    #expect(WoiceAppVersion.navigationSubtitle(from: info) == "工作台 · v0.1.3 (Build 2)")
  }

  @Test("缺少版本字段时安全回退到开发版")
  func fallsBackWhenBundleMetadataIsMissing() {
    #expect(WoiceAppVersion.display(from: [:]) == "开发版")
    #expect(WoiceAppVersion.navigationSubtitle(from: [:]) == "工作台 · 开发版")
  }
}
