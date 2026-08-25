import SwiftUI

struct LiveTranscriptPreviewPresentation: Equatable, Sendable {
  let title: String
  let body: String
  let systemImage: String
  let isWarning: Bool

  static func make(
    isRecording: Bool,
    isEnabled: Bool,
    capturesMicrophone: Bool,
    state: LiveTranscriptionState,
    transcript: String
  ) -> Self? {
    guard isRecording, isEnabled, capturesMicrophone else { return nil }

    let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    switch state {
    case .disabled, .finished:
      return nil
    case .requestingPermission:
      return Self(
        title: "正在准备实时文字",
        body: "正在准备本机语音识别…",
        systemImage: state.systemImage,
        isWarning: false)
    case .listening:
      return Self(
        title: "实时文字",
        body: text.isEmpty ? "正在听…" : text,
        systemImage: state.systemImage,
        isWarning: false)
    case .unavailable(let message):
      return Self(
        title: "实时文字不可用",
        body: text.isEmpty ? message : text,
        systemImage: state.systemImage,
        isWarning: true)
    }
  }
}

struct LiveTranscriptPreviewCard: View {
  let presentation: LiveTranscriptPreviewPresentation
  var isCompact = false

  var body: some View {
    VStack(alignment: .leading, spacing: isCompact ? 5 : 8) {
      Label(presentation.title, systemImage: presentation.systemImage)
        .font(isCompact ? .caption.weight(.semibold) : .callout.weight(.semibold))
        .foregroundStyle(presentation.isWarning ? Color.orange : Color.accentColor)
      Text(presentation.body)
        .font(isCompact ? .caption : .body)
        .foregroundStyle(presentation.isWarning ? Color.secondary : Color.primary)
        .lineLimit(isCompact ? 3 : 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(isCompact ? 9 : 14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: isCompact ? 9 : 12))
    .overlay {
      RoundedRectangle(cornerRadius: isCompact ? 9 : 12)
        .strokeBorder(
          presentation.isWarning ? Color.orange.opacity(0.28) : Color.accentColor.opacity(0.18))
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(presentation.title)
    .accessibilityValue(presentation.body)
  }
}
