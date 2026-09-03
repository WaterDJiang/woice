import Foundation

struct QwenOutputQuality: Equatable, Sendable {
  let replacementCharacterCount: Int
  let byteLevelResidualCount: Int
  let controlTokenCount: Int
  let repeatedLineCount: Int
  let repeatedPatternCount: Int

  var isAcceptable: Bool {
    replacementCharacterCount == 0 && byteLevelResidualCount == 0
  }
}

struct QwenParsedOutput: Equatable, Sendable {
  let text: String
  let quality: QwenOutputQuality
}

enum QwenOutputParserError: LocalizedError, Equatable, Sendable {
  case emptyOutput
  case qualityRejected(QwenOutputQuality)

  var errorDescription: String? {
    switch self {
    case .emptyOutput:
      return "Qwen3-ASR 没有返回可读文字。"
    case .qualityRejected(let quality):
      return
        "Qwen3-ASR 输出质量未通过：替换字符 \(quality.replacementCharacterCount) 个，"
        + "byte 乱码残留 \(quality.byteLevelResidualCount) 个，"
        + "协议控制 token \(quality.controlTokenCount) 个，"
        + "连续重复 \(quality.repeatedPatternCount) 处。"
    }
  }
}

/// Normalizes the text boundary exposed by the Qwen runtime. The pinned
/// runtime used by Woice can return a byte-level token sequence that contains
/// an incomplete UTF-8 character at a token boundary. Repairing the complete
/// returned string here keeps the dependency boundary small and prevents a
/// malformed result from being persisted as a ready Transcript Artifact.
enum QwenOutputParser {
  /// An individual chunk with no readable text is a normal no-op in a long
  /// recording. The caller still fails closed when every chunk is empty; only
  /// quality-rejected output is allowed to abort the whole transcription.
  static func shouldSkipEmptyChunk(for error: QwenOutputParserError) -> Bool {
    if case .emptyOutput = error { return true }
    return false
  }

  static func parse(_ raw: String) throws -> QwenParsedOutput {
    let repaired = repairByteLevelText(raw)
    let controlTokenCount = countControlTokens(in: repaired)
    let protocolFree = stripProtocol(from: repaired)
    let deduplicated = removeDeterministicAdjacentDuplicates(from: protocolFree)
    let quality = QwenOutputQuality(
      replacementCharacterCount: deduplicated.text.filter { $0 == "�" }.count,
      byteLevelResidualCount: suspiciousByteLevelResidualCount(in: deduplicated.text),
      controlTokenCount: controlTokenCount,
      repeatedLineCount: deduplicated.repeatedLineCount,
      repeatedPatternCount: deduplicated.repeatedPatternCount)

    guard !deduplicated.text.isEmpty else { throw QwenOutputParserError.emptyOutput }
    guard quality.isAcceptable else { throw QwenOutputParserError.qualityRejected(quality) }
    return QwenParsedOutput(text: deduplicated.text, quality: quality)
  }

  /// Reconstructs byte-level BPE output across token boundaries. A run is
  /// committed only when its mapped bytes form valid UTF-8; otherwise the
  /// original characters are retained instead of silently replacing them.
  static func repairByteLevelText(_ text: String) -> String {
    let unicodeToByte = Self.unicodeToByte
    var result = String()
    var mappedHighByteRun = String()

    func flush(_ run: inout String, into output: inout String) {
      guard !run.isEmpty else { return }
      let bytes = run.unicodeScalars.compactMap { unicodeToByte[$0] }
      // UTF-8 continuation bytes are always >= 0x80, so ASCII is a safe run
      // boundary. Decode only a complete multi-byte run. A valid single Latin
      // scalar such as `é` does not form valid UTF-8 by itself and is retained.
      // This also covers direct-only byte spellings such as `ä½¢`, which the
      // previous direct+fallback heuristic missed.
      if bytes.count >= 2,
        bytes.count == run.unicodeScalars.count,
        let decoded = String(bytes: bytes, encoding: .utf8)
      {
        output.append(decoded)
      } else {
        output.append(run)
      }
      run.removeAll(keepingCapacity: true)
    }

    for scalar in text.unicodeScalars {
      if let byte = unicodeToByte[scalar], byte >= 0x80 {
        mappedHighByteRun.unicodeScalars.append(scalar)
      } else {
        flush(&mappedHighByteRun, into: &result)
        result.unicodeScalars.append(scalar)
      }
    }
    flush(&mappedHighByteRun, into: &result)
    return result
  }

  private static func stripProtocol(from text: String) -> String {
    var value = text
    value = value.replacingOccurrences(
      of: #"<\|[^|\r\n]*\|>"#, with: "", options: .regularExpression)
    if let marker = value.range(of: "<asr_text>") {
      value = String(value[marker.upperBound...])
    }
    value = value.replacingOccurrences(
      of: #"^\s*language\s+[A-Za-z][A-Za-z-]*\s*"#,
      with: "",
      options: .regularExpression)
    return value
  }

  private static func countControlTokens(in text: String) -> Int {
    guard let expression = try? NSRegularExpression(pattern: #"<\|[^|\r\n]*\|>"#) else {
      return 0
    }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    return expression.numberOfMatches(in: text, range: range)
  }

  private static func suspiciousByteLevelResidualCount(in text: String) -> Int {
    // These are the most common visible GPT-2 byte-unicode residues. Keep the
    // check narrow so legitimate Latin text (for example German umlauts) is
    // not rejected after a successful UTF-8 decode.
    // Do not classify a single fallback-looking scalar such as Polish `ł` as
    // corruption: it is a valid user-visible Unicode character. Complete
    // byte-level runs are repaired above; this narrow residual check only
    // catches protocol glyphs that should never survive parsing.
    let suspicious: Set<UnicodeScalar> = ["Ġ", "Ċ", "ĉ"]
    return text.unicodeScalars.filter { suspicious.contains($0) }.count
  }

  private struct DeduplicatedText {
    let text: String
    let repeatedLineCount: Int
    let repeatedPatternCount: Int
  }

  private static func removeDeterministicAdjacentDuplicates(from text: String) -> DeduplicatedText {
    let lines =
      text
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
      .split(separator: "\n", omittingEmptySubsequences: false)
      .map(String.init)
    var result: [String] = []
    var repeated = 0
    for line in lines {
      let normalized = line.trimmingCharacters(in: .whitespacesAndNewlines)
      if !normalized.isEmpty,
        result.last?.trimmingCharacters(in: .whitespacesAndNewlines) == normalized
      {
        repeated += 1
        continue
      }
      result.append(line)
    }
    let lineDeduplicatedText =
      result
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .joined(separator: "\n")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let patternDeduplicated = collapseRunawayRepeatedPatterns(in: lineDeduplicatedText)
    return DeduplicatedText(
      text: patternDeduplicated.text,
      repeatedLineCount: repeated,
      repeatedPatternCount: patternDeduplicated.removedOccurrenceCount)
  }

  private struct PatternDeduplicatedText {
    let text: String
    let removedOccurrenceCount: Int
  }

  /// Removes only repetitions far beyond plausible verbatim emphasis. One
  /// character needs eight consecutive copies; a 2...16 character pattern
  /// needs five. The first copy is preserved and non-adjacent repetition is
  /// untouched.
  private static func collapseRunawayRepeatedPatterns(in text: String)
    -> PatternDeduplicatedText
  {
    let characters = Array(text)
    var output: [Character] = []
    output.reserveCapacity(characters.count)
    var removedOccurrenceCount = 0
    var index = 0

    while index < characters.count {
      let remaining = characters.count - index
      let maxPatternLength = min(16, remaining / 5)
      var matchedLength: Int?
      var matchedCount = 0

      if maxPatternLength > 0 {
        for patternLength in 1...maxPatternLength {
          let threshold = patternLength == 1 ? 8 : 5
          guard remaining >= patternLength * threshold else { continue }
          var occurrenceCount = 1
          while index + (occurrenceCount + 1) * patternLength <= characters.count {
            let lhsStart = index
            let rhsStart = index + occurrenceCount * patternLength
            var isEqual = true
            for offset in 0..<patternLength
            where characters[lhsStart + offset] != characters[rhsStart + offset] {
              isEqual = false
              break
            }
            guard isEqual else { break }
            occurrenceCount += 1
          }
          if occurrenceCount >= threshold {
            matchedLength = patternLength
            matchedCount = occurrenceCount
            break
          }
        }
      }

      if let patternLength = matchedLength {
        output.append(contentsOf: characters[index..<(index + patternLength)])
        removedOccurrenceCount += matchedCount - 1
        index += patternLength * matchedCount
      } else {
        output.append(characters[index])
        index += 1
      }
    }

    return PatternDeduplicatedText(
      text: String(output),
      removedOccurrenceCount: removedOccurrenceCount)
  }

  private static let unicodeToByte: [UnicodeScalar: UInt8] = {
    var mapping: [UnicodeScalar: UInt8] = [:]
    var n: UInt32 = 0
    let directRanges: [ClosedRange<UInt8>] = [
      UInt8(ascii: "!")...UInt8(ascii: "~"),
      0xA1...0xAC,
      0xAE...0xFF,
    ]
    for range in directRanges {
      for byte in range {
        mapping[UnicodeScalar(byte)] = byte
      }
    }
    for byte in UInt8.min...UInt8.max where mapping[UnicodeScalar(byte)] == nil {
      mapping[UnicodeScalar(0x100 + n)!] = byte
      n += 1
    }
    return mapping
  }()
}
