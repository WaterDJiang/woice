import Testing

@testable import WoiceApp

struct DistributionCapabilitiesTests {
  @Test("官网能力保留完整录音与 Agent 组合")
  func websiteProfileKeepsCoreAndAgentCapabilities() {
    let profile = StoreCapabilityProfile.website
    #expect(profile.edition == .website)
    #expect(profile.allowsProcessProviders)
    #expect(profile.allowsExternalAgentConnector)
    #expect(profile.allowsSelfUpdater)
    #expect(profile.allowsAutomaticPaste)
    #expect(profile.allowsUserProvidedExecutables)
    #expect(profile.allowsModelImport)
    #expect(profile.allowsHTTPProviders)
  }

  @Test("Store 能力关闭外部进程和 Agent，但保留录音转写所需能力")
  func appStoreProfileClosesExternalExecution() {
    let profile = StoreCapabilityProfile.appStore
    #expect(profile.edition == .appStore)
    #expect(!profile.allowsProcessProviders)
    #expect(!profile.allowsExternalAgentConnector)
    #expect(!profile.allowsSelfUpdater)
    #expect(!profile.allowsAutomaticPaste)
    #expect(!profile.allowsUserProvidedExecutables)
    #expect(profile.allowsModelImport)
    #expect(profile.allowsHTTPProviders)
  }

  @Test("当前编译配置只允许一个明确发行版")
  func currentProfileIsADeclaredEdition() {
    #expect(
      StoreCapabilityProfile.current == .website
        || StoreCapabilityProfile.current == .appStore)
  }
}
