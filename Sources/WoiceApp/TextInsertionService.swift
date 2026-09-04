#if !WOICE_APP_STORE
  import AppKit
  import ApplicationServices
  import Observation

  enum TextInsertionError: LocalizedError {
    case emptyText
    case accessibilityPermissionRequired
    case eventDeliveryFailed

    var errorDescription: String? {
      switch self {
      case .emptyText:
        "没有可粘贴的原文。"
      case .accessibilityPermissionRequired:
        "需要辅助功能权限才能粘贴到当前应用；原文仍已保存在 Woice。"
      case .eventDeliveryFailed:
        "系统没有接收粘贴操作；原文仍已复制到剪贴板。"
      }
    }
  }

  @MainActor
  @Observable
  final class TextInsertionService {
    private(set) var isAccessibilityTrusted = false

    init() {
      refreshPermission()
    }

    func refreshPermission() {
      isAccessibilityTrusted = AXIsProcessTrusted()
    }

    func requestPermission() {
      // 使用文档公开的 CFString 值，避免 Swift 6 将 ApplicationServices 的 C 全局变量
      // 视为跨并发域的可变状态。
      let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
      isAccessibilityTrusted = AXIsProcessTrustedWithOptions(options)
      if !isAccessibilityTrusted {
        openAccessibilitySettings()
      }
    }

    func openAccessibilitySettings() {
      guard
        let url = URL(
          string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
      else { return }
      NSWorkspace.shared.open(url)
    }

    func paste(text: String) throws {
      let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !value.isEmpty else { throw TextInsertionError.emptyText }
      refreshPermission()
      guard isAccessibilityTrusted else {
        throw TextInsertionError.accessibilityPermissionRequired
      }

      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(value, forType: .string)
      guard
        let source = CGEventSource(stateID: .hidSystemState),
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
      else {
        throw TextInsertionError.eventDeliveryFailed
      }
      keyDown.flags = .maskCommand
      keyUp.flags = .maskCommand
      keyDown.post(tap: .cghidEventTap)
      keyUp.post(tap: .cghidEventTap)
    }
  }
#endif
