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

  /// Splits a normalized transcript into bounded render units. The source
  /// string remains unchanged; callers can keep it for copy/export while a
  /// lazy stack only instantiates the chunks near the visible viewport.
  public static func chunks(_ text: String, maxCharacters: Int = 1_200) -> [String] {
    guard maxCharacters > 0, !text.isEmpty else { return text.isEmpty ? [] : [text] }
    let characters = Array(text)
    return stride(from: 0, to: characters.count, by: maxCharacters).map { start in
      let end = min(start + maxCharacters, characters.count)
      return String(characters[start..<end])
    }
  }
}
