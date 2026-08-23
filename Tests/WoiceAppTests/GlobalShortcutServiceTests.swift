import Foundation
import Testing
import WoiceCore

@testable import WoiceApp

@Test("全局快捷键服务在未安装时可安全清理")
func globalShortcutServiceCanBeUninstalledBeforeInstall() {
  let service = GlobalShortcutService()
  #expect(!service.isInstalled)
  service.uninstall()
  #expect(!service.isInstalled)
  #expect(GlobalShortcutService.shortcutDisplayName == "⌥Space")
}

@Test("快捷键选择有稳定文案且关闭选项不会注册系统快捷键")
func recordingShortcutOptionsAreStable() throws {
  #expect(RecordingShortcut.optionSpace.displayName == "⌥Space")
  #expect(RecordingShortcut.controlOptionSpace.displayName == "⌃⌥Space")
  #expect(RecordingShortcut.commandOptionSpace.displayName == "⌘⌥Space")
  #expect(RecordingShortcut.disabled.displayName == "关闭")

  let service = GlobalShortcutService()
  try service.install(shortcut: .disabled) {}
  #expect(!service.isInstalled)
}

@Test("快捷键值模型支持自定义组合、禁用键和旧字符串迁移")
func recordingShortcutValueModelSupportsCustomInput() throws {
  let custom = RecordingShortcut(
    keyCode: 0, modifierMask: RecordingShortcut.Modifier.command, keyName: "A")
  #expect(custom.isValid)
  #expect(custom.displayName == "⌘A")
  #expect(GlobalShortcutService.probe(.disabled) == .disabled)
  #expect(
    {
      if case .invalid = GlobalShortcutService.probe(RecordingShortcut(keyCode: 0, modifierMask: 0))
      {
        return true
      }
      return false
    }())

  let legacy = try JSONDecoder.woice.decode(
    RecordingShortcut.self, from: Data(#""optionSpace""#.utf8))
  #expect(legacy == .optionSpace)
  let encoded = try JSONEncoder.woice.encode(custom)
  let roundTrip = try JSONDecoder.woice.decode(RecordingShortcut.self, from: encoded)
  #expect(roundTrip == custom)
}
