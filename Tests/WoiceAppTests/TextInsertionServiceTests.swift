import Foundation

#if !WOICE_APP_STORE
  import Testing

  @testable import WoiceApp

  @Test("未获辅助功能授权时粘贴动作 fail-closed")
  @MainActor
  func textInsertionRequiresExplicitAccessibilityPermission() throws {
    let service = TextInsertionService()
    guard !service.isAccessibilityTrusted else { return }
    do {
      try service.paste(text: "不会注入到其他应用")
      Issue.record("未授权时不应发送 Command-V")
    } catch TextInsertionError.accessibilityPermissionRequired {
      // 预期：原文不会被注入到前台应用。
    } catch {
      Issue.record("未授权粘贴返回了错误类型：\(error)")
    }
  }
#endif
