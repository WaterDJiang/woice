import Carbon.HIToolbox
import Foundation
import WoiceCore

enum GlobalShortcutError: LocalizedError, Equatable {
  case invalid(shortcut: String, reason: String)
  case systemReserved(shortcut: String)
  case alreadyRegistered(shortcut: String, OSStatus)
  case registerFailed(shortcut: String, OSStatus)
  case handlerFailed(shortcut: String, OSStatus)

  var errorDescription: String? {
    switch self {
    case .invalid(let shortcut, let reason):
      "\(shortcut) 不可用：\(reason)。"
    case .systemReserved(let shortcut):
      "\(shortcut) 是系统保留组合，请换一个快捷键。"
    case .alreadyRegistered(let shortcut, _):
      "\(shortcut) 已被其他应用占用，请换一个组合。"
    case .registerFailed(let shortcut, let status):
      "无法注册 \(shortcut)（系统错误 \(status)）。你仍可使用菜单栏按钮录音。"
    case .handlerFailed(let shortcut, let status):
      "无法监听 \(shortcut)（系统错误 \(status)）。你仍可使用菜单栏按钮录音。"
    }
  }
}

enum GlobalShortcutProbeResult: Equatable {
  case available
  case disabled
  case invalid(String)
  case systemReserved
  case occupied

  var title: String {
    switch self {
    case .available: "当前可注册"
    case .disabled: "快捷键已关闭"
    case .invalid: "组合不可用"
    case .systemReserved: "系统保留"
    case .occupied: "已被占用"
    }
  }

  var isAvailable: Bool {
    switch self {
    case .available, .disabled: true
    default: false
    }
  }
}

/// Native registration-based hot key. It does not install an event tap and
/// therefore does not ask for Input Monitoring permission.
final class GlobalShortcutService: @unchecked Sendable {
  static let shortcutDisplayName = "⌥Space"

  private var hotKey: EventHotKeyRef?
  private var handler: EventHandlerRef?
  private var action: (@Sendable () -> Void)?
  private(set) var currentShortcut: RecordingShortcut = .disabled
  private var nextRegistrationID: UInt32 = 1

  var isInstalled: Bool { hotKey != nil && handler != nil }

  static func probe(_ shortcut: RecordingShortcut) -> GlobalShortcutProbeResult {
    guard !shortcut.isDisabled else { return .disabled }
    switch validate(shortcut) {
    case .success: break
    case .failure(let error):
      switch error {
      case .systemReserved: return .systemReserved
      case .invalid(_, let reason): return .invalid(reason)
      default: return .invalid(error.localizedDescription)
      }
    }
    guard let keyCode = shortcut.keyCode else { return .disabled }
    let id = EventHotKeyID(signature: 0x574F_4943, id: 10_000)
    var candidate: EventHotKeyRef?
    let status = RegisterEventHotKey(
      UInt32(keyCode), carbonModifiers(for: shortcut), id,
      GetApplicationEventTarget(), 0, &candidate)
    guard status == noErr else {
      return status == eventHotKeyExistsErr ? .occupied : .invalid("系统错误 \(status)")
    }
    if let candidate { UnregisterEventHotKey(candidate) }
    return .available
  }

  static func validate(_ shortcut: RecordingShortcut) -> Result<Void, GlobalShortcutError> {
    guard !shortcut.isDisabled else { return .success(()) }
    guard shortcut.isValid, let keyCode = shortcut.keyCode else {
      return .failure(.invalid(shortcut: shortcut.displayName, reason: "至少需要一个修饰键和一个普通按键"))
    }
    if [51, 53, 117].contains(keyCode) {
      return .failure(.systemReserved(shortcut: shortcut.displayName))
    }
    return .success(())
  }

  func install(
    shortcut: RecordingShortcut = .optionSpace,
    action: @escaping @Sendable () -> Void
  ) throws {
    guard !isInstalled else { return }
    try Self.validate(shortcut).get()
    guard !shortcut.isDisabled else { return }
    self.action = action
    let candidate = try register(shortcut: shortcut)
    hotKey = candidate
    currentShortcut = shortcut
    do {
      try installHandler()
    } catch {
      UnregisterEventHotKey(candidate)
      hotKey = nil
      currentShortcut = .disabled
      self.action = nil
      throw error
    }
  }

  /// Registers the replacement before removing the old registration. If the
  /// replacement fails, the old shortcut and action remain untouched.
  func replace(
    with shortcut: RecordingShortcut,
    action: (@Sendable () -> Void)? = nil
  ) throws {
    try Self.validate(shortcut).get()
    if shortcut == currentShortcut { return }
    if shortcut.isDisabled {
      uninstall()
      return
    }
    let candidate = try register(shortcut: shortcut)
    let previous = hotKey
    if handler == nil {
      do {
        try installHandler()
      } catch {
        UnregisterEventHotKey(candidate)
        throw error
      }
    }
    if let previous { UnregisterEventHotKey(previous) }
    hotKey = candidate
    currentShortcut = shortcut
    if let action { self.action = action }
  }

  func uninstall() {
    if let handler {
      RemoveEventHandler(handler)
      self.handler = nil
    }
    if let hotKey {
      UnregisterEventHotKey(hotKey)
      self.hotKey = nil
    }
    currentShortcut = .disabled
    action = nil
  }

  private func register(shortcut: RecordingShortcut) throws -> EventHotKeyRef {
    guard let keyCode = shortcut.keyCode else {
      throw GlobalShortcutError.invalid(shortcut: shortcut.displayName, reason: "缺少普通按键")
    }
    nextRegistrationID &+= 1
    let hotKeyID = EventHotKeyID(signature: 0x574F_4943, id: nextRegistrationID)
    var reference: EventHotKeyRef?
    let status = RegisterEventHotKey(
      UInt32(keyCode), Self.carbonModifiers(for: shortcut), hotKeyID,
      GetApplicationEventTarget(), 0, &reference)
    guard status == noErr, let reference else {
      if status == eventHotKeyExistsErr {
        throw GlobalShortcutError.alreadyRegistered(shortcut: shortcut.displayName, status)
      }
      throw GlobalShortcutError.registerFailed(shortcut: shortcut.displayName, status)
    }
    return reference
  }

  private func installHandler() throws {
    var eventSpec = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard),
      eventKind: UInt32(kEventHotKeyPressed))
    let context = Unmanaged.passUnretained(self).toOpaque()
    let status = InstallEventHandler(
      GetApplicationEventTarget(),
      { _, _, userData in
        guard let userData else { return noErr }
        let service = Unmanaged<GlobalShortcutService>.fromOpaque(userData)
          .takeUnretainedValue()
        service.action?()
        return noErr
      },
      1,
      &eventSpec,
      context,
      &handler)
    guard status == noErr else {
      throw GlobalShortcutError.handlerFailed(
        shortcut: currentShortcut.displayName, status)
    }
  }

  private static func carbonModifiers(for shortcut: RecordingShortcut) -> UInt32 {
    var modifiers: UInt32 = 0
    if shortcut.modifierMask & RecordingShortcut.Modifier.command != 0 {
      modifiers |= UInt32(cmdKey)
    }
    if shortcut.modifierMask & RecordingShortcut.Modifier.option != 0 {
      modifiers |= UInt32(optionKey)
    }
    if shortcut.modifierMask & RecordingShortcut.Modifier.control != 0 {
      modifiers |= UInt32(controlKey)
    }
    if shortcut.modifierMask & RecordingShortcut.Modifier.shift != 0 {
      modifiers |= UInt32(shiftKey)
    }
    return modifiers
  }

  deinit { uninstall() }
}
