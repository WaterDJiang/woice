import SwiftUI

enum ActionFeedbackKind: Equatable, Sendable {
  case success
  case failure
  case progress

  var systemImage: String {
    switch self {
    case .success: "checkmark.circle.fill"
    case .failure: "exclamationmark.triangle.fill"
    case .progress: "arrow.triangle.2.circlepath"
    }
  }
}

struct ActionFeedback: Identifiable, Equatable, Sendable {
  let id = UUID()
  let message: String
  let kind: ActionFeedbackKind

  static func success(_ message: String) -> ActionFeedback {
    ActionFeedback(message: message, kind: .success)
  }

  static func failure(_ message: String) -> ActionFeedback {
    ActionFeedback(message: message, kind: .failure)
  }

  static func progress(_ message: String) -> ActionFeedback {
    ActionFeedback(message: message, kind: .progress)
  }
}

struct ActionFeedbackBanner: View {
  let feedback: ActionFeedback

  var body: some View {
    Label(feedback.message, systemImage: feedback.kind.systemImage)
      .font(.callout.weight(.medium))
      .foregroundStyle(tint)
      .padding(.horizontal, 12)
      .padding(.vertical, 9)
      .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
      .overlay {
        RoundedRectangle(cornerRadius: 10)
          .strokeBorder(tint.opacity(0.24), lineWidth: 1)
      }
      .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
      .accessibilityElement(children: .combine)
      .accessibilityAddTraits(.updatesFrequently)
  }

  private var tint: Color {
    switch feedback.kind {
    case .success: .green
    case .failure: .red
    case .progress: .accentColor
    }
  }
}

/// A native Button with a brief in-place result label and a shared banner.
/// The wrapper keeps success visible without turning every small action into a modal.
struct ActionFeedbackButton<ButtonLabel: View>: View {
  @Environment(AppState.self) private var appState
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let action: () -> ActionFeedback
  @ViewBuilder let label: () -> ButtonLabel
  @State private var inlineFeedback: ActionFeedback?

  var body: some View {
    Button {
      let feedback = action()
      inlineFeedback = feedback
      appState.presentActionFeedback(feedback)
    } label: {
      HStack(spacing: 6) {
        if let inlineFeedback {
          Label(inlineFeedback.message, systemImage: inlineFeedback.kind.systemImage)
            .foregroundStyle(inlineTint(for: inlineFeedback.kind))
        } else {
          label()
        }
      }
      .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
    }
    .accessibilityValue(inlineFeedback?.message ?? "")
    .task(id: inlineFeedback?.id) {
      guard inlineFeedback != nil else { return }
      try? await Task.sleep(for: .seconds(1.8))
      guard !Task.isCancelled else { return }
      inlineFeedback = nil
    }
  }

  private func inlineTint(for kind: ActionFeedbackKind) -> Color {
    switch kind {
    case .success: .green
    case .failure: .red
    case .progress: .accentColor
    }
  }
}

struct WoiceBorderlessButtonStyle: ButtonStyle {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .padding(.horizontal, 8)
      .padding(.vertical, 6)
      .frame(minHeight: 32)
      .background(
        configuration.isPressed ? Color.accentColor.opacity(0.14) : .clear,
        in: RoundedRectangle(cornerRadius: 8)
      )
      .opacity(configuration.isPressed ? 0.82 : 1)
      .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
      .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
      .contentShape(Rectangle())
  }
}

extension ButtonStyle where Self == WoiceBorderlessButtonStyle {
  static var woiceBorderless: Self { Self() }
}

/// Compact toolbar control for icon-led actions such as clear selection or refresh.
/// It keeps a stable 32 pt target while retaining the native material around it.
struct WoiceToolbarButtonStyle: ButtonStyle {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.body.weight(.medium))
      .frame(minWidth: 32, minHeight: 32)
      .background(
        configuration.isPressed ? Color.accentColor.opacity(0.18) : .clear,
        in: RoundedRectangle(cornerRadius: 9)
      )
      .opacity(configuration.isPressed ? 0.82 : 1)
      .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
      .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
      .contentShape(RoundedRectangle(cornerRadius: 9))
  }
}

extension ButtonStyle where Self == WoiceToolbarButtonStyle {
  static var woiceToolbar: Self { Self() }
}
