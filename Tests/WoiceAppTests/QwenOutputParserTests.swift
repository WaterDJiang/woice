import XCTest

@testable import WoiceApp

final class QwenOutputParserTests: XCTestCase {
  func testAudioSignalDetectorRejectsConverterPaddingTail() {
    var tail = [Float](repeating: 0, count: 768)
    tail[0] = 0.006
    XCTAssertFalse(
      QwenAudioSignalDetector.hasUsableSignal(tail))
    XCTAssertTrue(
      QwenAudioSignalDetector.shouldSkipTrailingChunk(tail, isTrailingChunk: true))
    XCTAssertFalse(
      QwenAudioSignalDetector.shouldSkipTrailingChunk(tail, isTrailingChunk: false))
    XCTAssertTrue(
      QwenAudioSignalDetector.hasUsableSignal([Float](repeating: 0.02, count: 768)))
  }

  func testAudioSignalDetectorRejectsNonZeroConverterPaddingTail() {
    let padding = [Float](repeating: 0.0034, count: 768)

    XCTAssertTrue(QwenAudioSignalDetector.hasUsableSignal(padding))
    XCTAssertTrue(
      QwenAudioSignalDetector.shouldSkipTrailingChunk(padding, isTrailingChunk: true))
  }

  func testAudioSignalDetectorKeepsQuietButAudibleChunk() {
    var samples = [Float](repeating: 0, count: 768)
    samples[100] = 0.012
    XCTAssertTrue(QwenAudioSignalDetector.hasUsableSignal(samples))
  }

  func testRepairsChineseByteSequenceSplitAcrossTokens() throws {
    // GPT-2 byte-unicode spelling of UTF-8 bytes E4 BD A0 E5 A5 BD.
    let parsed = try QwenOutputParser.parse("ä½łå¥½")

    XCTAssertEqual(parsed.text, "你好")
    XCTAssertTrue(parsed.quality.isAcceptable)
  }

  func testRepairsDirectHighByteCantoneseSequence() throws {
    // UTF-8 E4 BD A2 can be surfaced as three direct byte-unicode scalars.
    let parsed = try QwenOutputParser.parse("ä½¢係边个")

    XCTAssertEqual(parsed.text, "佢係边个")
    XCTAssertTrue(parsed.quality.isAcceptable)
  }

  func testRepairsFourByteUnicodeAndLeavesRegularUnicodeUntouched() throws {
    let parsed = try QwenOutputParser.parse("ä½ł 𠀀 Café")

    XCTAssertEqual(parsed.text, "你 𠀀 Café")
  }

  func testRepairsJapaneseKoreanAndEmojiByteSequences() throws {
    let parsed = try QwenOutputParser.parse(
      "ãģĵãĤĵãģ«ãģ¡ãģ¯ ìķĪëħķíķĺìĦ¸ìļĶ ä½łå¥½ðŁĻĤ")

    XCTAssertEqual(parsed.text, "こんにちは 안녕하세요 你好🙂")
    XCTAssertTrue(parsed.quality.isAcceptable)
  }

  func testLeavesValidFallbackLookingUnicodeUntouched() throws {
    let parsed = try QwenOutputParser.parse("Zażółć gęślą jaźń")

    XCTAssertEqual(parsed.text, "Zażółć gęślą jaźń")
    XCTAssertTrue(parsed.quality.isAcceptable)
  }

  func testStripsQwenProtocolPrefixAndSpecialTokens() throws {
    let parsed = try QwenOutputParser.parse(
      "language Chinese<asr_text>你好<|im_end|><|endoftext|>")

    XCTAssertEqual(parsed.text, "你好")
    XCTAssertEqual(parsed.quality.controlTokenCount, 2)
  }

  func testRejectsLanguageOnlyProtocolOutput() {
    XCTAssertThrowsError(
      try QwenOutputParser.parse("language None<asr_text>")
    ) { error in
      guard case QwenOutputParserError.emptyOutput = error else {
        return XCTFail("expected empty protocol output rejection, got \(error)")
      }
    }
  }

  func testRemovesOnlyAdjacentDuplicateLines() throws {
    let parsed = try QwenOutputParser.parse("第一句\n第一句\n第二句\n第一句")

    XCTAssertEqual(parsed.text, "第一句\n第二句\n第一句")
    XCTAssertEqual(parsed.quality.repeatedLineCount, 1)
  }

  func testCollapsesRunawaySingleCharacterAndShortPhraseRepetition() throws {
    let parsed = try QwenOutputParser.parse(
      "讲讲讲讲讲讲讲讲讲讲\n唔该，唔该，唔该，唔该，唔该，唔该，")

    XCTAssertEqual(parsed.text, "讲\n唔该，")
    XCTAssertEqual(parsed.quality.repeatedPatternCount, 14)
  }

  func testKeepsNormalShortAndNonAdjacentRepetition() throws {
    let parsed = try QwenOutputParser.parse("哈哈哈，第一句。第二句。第一句。")

    XCTAssertEqual(parsed.text, "哈哈哈，第一句。第二句。第一句。")
    XCTAssertEqual(parsed.quality.repeatedPatternCount, 0)
  }

  func testRejectsReplacementCharacterOutput() {
    XCTAssertThrowsError(try QwenOutputParser.parse("你好�")) { error in
      guard case QwenOutputParserError.qualityRejected(let quality) = error else {
        return XCTFail("expected quality rejection, got \(error)")
      }
      XCTAssertEqual(quality.replacementCharacterCount, 1)
    }
  }

  func testEmptyChunkIsNoOpButQualityRejectionIsFatal() {
    XCTAssertTrue(QwenOutputParser.shouldSkipEmptyChunk(for: .emptyOutput))
    XCTAssertFalse(
      QwenOutputParser.shouldSkipEmptyChunk(
        for: .qualityRejected(
          QwenOutputQuality(
            replacementCharacterCount: 1,
            byteLevelResidualCount: 0,
            controlTokenCount: 0,
            repeatedLineCount: 0,
            repeatedPatternCount: 0))))
  }
}
