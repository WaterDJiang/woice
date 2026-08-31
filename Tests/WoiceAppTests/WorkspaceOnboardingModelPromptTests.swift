import Testing

@testable import WoiceApp

@Test("首启明确提示转写前需要下载模型")
func onboardingExplainsModelDownloadBoundary() {
  #expect(WorkspaceOnboardingModelPrompt.title.contains("需要先下载"))
  #expect(WorkspaceOnboardingModelPrompt.detail.contains("App Store 安装包不携带模型"))
  #expect(WorkspaceOnboardingModelPrompt.detail.contains("下载由你确认"))
}
