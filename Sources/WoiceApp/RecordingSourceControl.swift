import SwiftUI

enum RecordingSourceSelectionPresentation {
  static func summary(microphoneEnabled: Bool, systemAudioEnabled: Bool) -> String {
    switch (microphoneEnabled, systemAudioEnabled) {
    case (true, true): "麦克风 + 电脑声音"
    case (true, false): "仅麦克风"
    case (false, true): "仅电脑声音"
    case (false, false): "未选择音源"
    }
  }
}

struct RecordingSourceControl: View {
  let title: String
  let systemImage: String
  let isEnabled: Bool
  let isLocked: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 6) {
        Image(systemName: systemImage)
          .frame(width: 16)
        Text(title)
          .lineLimit(1)
        Spacer(minLength: 4)
        Image(systemName: isEnabled ? "checkmark.circle.fill" : "circle")
          .font(.caption.weight(.semibold))
          .foregroundStyle(isEnabled ? Color.accentColor : Color.secondary)
      }
      .font(.callout.weight(.medium))
      .frame(minHeight: 32)
      .frame(maxWidth: .infinity)
      .contentShape(Rectangle())
    }
    .buttonStyle(RecordingSourceControlStyle(isSelected: isEnabled))
    .disabled(isLocked)
    .accessibilityLabel(title)
    .accessibilityValue(isEnabled ? "已开启" : "已关闭")
    .accessibilityHint(isLocked ? "录音期间无法切换" : "切换下一次录音是否采集此音源")
    .help(isLocked ? "录音期间音源已锁定" : "\(isEnabled ? "关闭" : "开启")\(title)")
  }
}

private struct RecordingSourceControlStyle: ButtonStyle {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let isSelected: Bool

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .padding(.horizontal, 10)
      .background(
        backgroundColor(configuration: configuration), in: RoundedRectangle(cornerRadius: 8)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 8)
          .strokeBorder(borderColor, lineWidth: 1)
      }
      .opacity(configuration.isPressed ? 0.82 : 1)
      .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
      .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
  }

  private func backgroundColor(configuration: Configuration) -> Color {
    if configuration.isPressed {
      return Color.accentColor.opacity(0.16)
    }
    return isSelected ? Color.accentColor.opacity(0.1) : Color.primary.opacity(0.045)
  }

  private var borderColor: Color {
    isSelected ? Color.accentColor.opacity(0.32) : Color.secondary.opacity(0.18)
  }
}
