import Foundation

/// Creates a readable projection of provider output without changing the
/// persisted source transcript or its timestamp segments.
public enum TranscriptTextNormalizer {
  private static let whisperTokenPattern = #"<\|[^|\r\n]*\|>"#
  private static let horizontalWhitespacePattern = #"[ \t]+"#

  public static func normalize(_ text: String) -> String {
    let withoutWhisperTokens = text.replacingOccurrences(
      of: whisperTokenPattern,
      with: "",
      options: .regularExpression
    )
    let lines =
      withoutWhisperTokens
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
      .components(separatedBy: "\n")
      .map { line in
        line
          .replacingOccurrences(
            of: horizontalWhitespacePattern,
            with: " ",
            options: .regularExpression
          )
          .trimmingCharacters(in: .whitespacesAndNewlines)
      }

    return
      lines
      .filter { !$0.isEmpty }
      .joined(separator: "\n")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
