import SwiftUI

struct FirstRunSetupStepCard<Content: View>: View {
  let number: Int?
  let title: String
  let status: String
  let isComplete: Bool
  let detail: String
  let content: Content

  init(
    number: Int?,
    title: String,
    status: String,
    isComplete: Bool,
    detail: String,
    @ViewBuilder content: () -> Content
  ) {
    self.number = number
    self.title = title
    self.status = status
    self.isComplete = isComplete
    self.detail = detail
    self.content = content()
  }

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
        .font(.title3)
        .foregroundStyle(isComplete ? Color.green : Color.orange)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 7) {
        HStack(alignment: .firstTextBaseline) {
          Text(number.map { "\($0). \(title)" } ?? title)
            .font(.headline)
          Spacer()
          Text(status)
            .font(.caption.weight(.semibold))
            .foregroundStyle(isComplete ? Color.green : Color.orange)
        }
        Text(detail)
          .font(.callout)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        VStack(alignment: .leading, spacing: 8) { content }
      }
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
    .overlay {
      RoundedRectangle(cornerRadius: 12)
        .strokeBorder((isComplete ? Color.green : Color.orange).opacity(0.18), lineWidth: 1)
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("\(title)，\(status)。\(detail)")
  }
}
