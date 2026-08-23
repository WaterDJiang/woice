import AppKit
import SwiftUI
import WoiceCore

struct ShortcutRecorderEditor: View {
  @Binding var shortcut: RecordingShortcut
  let activeShortcut: RecordingShortcut
  let runtimeError: String?
  @State private var isCapturing = false
  @State private var probeResult: GlobalShortcutProbeResult = .available

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        ShortcutRecorderField(
          shortcut: $shortcut,
          isCapturing: $isCapturing,
          onCancel: { isCapturing = false }
        )
        .frame(minWidth: 150, minHeight: 32)
        Button(isCapturing ? "取消" : "重新输入") {
          isCapturing.toggle()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        Button("关闭") {
          isCapturing = false
          shortcut = .disabled
        }
        .buttonStyle(.woiceBorderless)
        .controlSize(.small)
      }
      HStack(spacing: 6) {
        Image(
          systemName: probeResult.isAvailable
            ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
        )
        .foregroundStyle(probeResult.isAvailable ? Color.green : Color.orange)
        Text(probeMessage)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      if let runtimeError, !runtimeError.isEmpty, shortcut == activeShortcut {
        Label(runtimeError, systemImage: "info.circle")
          .font(.caption)
          .foregroundStyle(.orange)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .onAppear(perform: updateProbe)
    .onChange(of: shortcut) { _, _ in updateProbe() }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("录音快捷键")
    .accessibilityValue(isCapturing ? "正在等待快捷键" : shortcut.displayName)
    .accessibilityHint("聚焦输入框后按下带修饰键的组合")
  }

  private var probeMessage: String {
    if isCapturing { return "正在等待快捷键…" }
    switch probeResult {
    case .available: return "\(shortcut.displayName) 当前可注册，保存本页后生效。"
    case .disabled: return "快捷键已关闭；仍可使用菜单栏按钮录音。"
    case .invalid(let reason): return reason
    case .systemReserved: return "系统保留组合，请换一个快捷键。"
    case .occupied: return "已被其他应用占用，请换一个组合。"
    }
  }

  private func updateProbe() {
    if shortcut == activeShortcut {
      probeResult = shortcut.isDisabled ? .disabled : .available
    } else {
      probeResult = GlobalShortcutService.probe(shortcut)
    }
  }
}

private struct ShortcutRecorderField: NSViewRepresentable {
  @Binding var shortcut: RecordingShortcut
  @Binding var isCapturing: Bool
  let onCancel: () -> Void

  func makeNSView(context: Context) -> ShortcutRecorderNSView {
    let view = ShortcutRecorderNSView()
    view.onShortcut = { shortcut in
      self.shortcut = shortcut
      self.isCapturing = false
    }
    view.onCancel = {
      self.isCapturing = false
      self.onCancel()
    }
    view.shortcut = shortcut
    view.isCapturing = isCapturing
    return view
  }

  func updateNSView(_ nsView: ShortcutRecorderNSView, context: Context) {
    nsView.shortcut = shortcut
    nsView.isCapturing = isCapturing
    nsView.onShortcut = { shortcut in
      self.shortcut = shortcut
      self.isCapturing = false
    }
    nsView.onCancel = {
      self.isCapturing = false
      self.onCancel()
    }
    if isCapturing, nsView.window?.firstResponder !== nsView {
      nsView.window?.makeFirstResponder(nsView)
    }
  }
}

private final class ShortcutRecorderNSView: NSView {
  var shortcut = RecordingShortcut.disabled { didSet { needsDisplay = true } }
  var isCapturing = false { didSet { needsDisplay = true } }
  var onShortcut: ((RecordingShortcut) -> Void)?
  var onCancel: (() -> Void)?

  override var acceptsFirstResponder: Bool { true }

  override func draw(_ dirtyRect: NSRect) {
    let bounds = bounds.insetBy(dx: 1, dy: 1)
    let path = NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7)
    (isCapturing
      ? NSColor.controlAccentColor.withAlphaComponent(0.14) : NSColor.controlBackgroundColor)
      .setFill()
    path.fill()
    (isCapturing ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
    path.lineWidth = isCapturing ? 2 : 1
    path.stroke()
    let text = isCapturing ? "正在等待快捷键…" : shortcut.displayName
    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 13, weight: .medium),
      .foregroundColor: NSColor.labelColor,
    ]
    let size = text.size(withAttributes: attributes)
    text.draw(
      at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2),
      withAttributes: attributes)
    setAccessibilityRole(.button)
    setAccessibilityLabel("录音快捷键")
    setAccessibilityValue(text)
  }

  override func mouseDown(with event: NSEvent) {
    isCapturing = true
    window?.makeFirstResponder(self)
    needsDisplay = true
  }

  override func keyDown(with event: NSEvent) {
    guard isCapturing else { return }
    if event.keyCode == 53 {
      isCapturing = false
      onCancel?()
      return
    }
    if event.keyCode == 51 || event.keyCode == 117 {
      shortcut = .disabled
      isCapturing = false
      onShortcut?(.disabled)
      return
    }
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    let mask = modifierMask(for: flags)
    guard mask != 0 else { return }
    let name = keyName(for: event)
    let candidate = RecordingShortcut(keyCode: event.keyCode, modifierMask: mask, keyName: name)
    guard candidate.isValid else { return }
    shortcut = candidate
    isCapturing = false
    onShortcut?(candidate)
  }

  override func cancelOperation(_ sender: Any?) {
    isCapturing = false
    onCancel?()
  }

  private func modifierMask(for flags: NSEvent.ModifierFlags) -> UInt32 {
    var mask: UInt32 = 0
    if flags.contains(.command) { mask |= RecordingShortcut.Modifier.command }
    if flags.contains(.option) { mask |= RecordingShortcut.Modifier.option }
    if flags.contains(.control) { mask |= RecordingShortcut.Modifier.control }
    if flags.contains(.shift) { mask |= RecordingShortcut.Modifier.shift }
    return mask
  }

  private func keyName(for event: NSEvent) -> String {
    if let characters = event.charactersIgnoringModifiers?.uppercased(), !characters.isEmpty {
      switch event.keyCode {
      case 49: return "Space"
      case 36: return "Return"
      case 48: return "Tab"
      case 123: return "←"
      case 124: return "→"
      case 125: return "↓"
      case 126: return "↑"
      default: return characters
      }
    }
    return RecordingShortcut.keyName(for: event.keyCode)
  }
}
