import XCTest

@testable import WoiceCore

final class TranscriptTextNormalizerTests: XCTestCase {
  func testRemovesWhisperControlAndTimestampTokensFromScreenshotFixture() {
    let raw = """
      <|startoftranscript|><|zh|><|transcribe|><|0.00|>现在出去试一条，看看到底效果怎么样<|3.44|>
      <|3.44|>如果觉得今天的录音还不错的话呢<|7.88|>
      <|7.88|>你就给我点个赞吧，可以吗<|10.00|>
      <|10.00|>好，谢谢你的时间<|11.84|>
      <|startoftranscript|><|zh|><|transcribe|><|0.00|>OK<|1.16|><|endoftext|>
      """

    let normalized = TranscriptTextNormalizer.normalize(raw)

    XCTAssertEqual(
      normalized,
      "现在出去试一条，看看到底效果怎么样\n如果觉得今天的录音还不错的话呢\n你就给我点个赞吧，可以吗\n好，谢谢你的时间\nOK"
    )
    XCTAssertFalse(normalized.contains("<|"))
  }

  func testEmptyAndWhitespaceOnlyTokenOutputStaysEmpty() {
    XCTAssertEqual(
      TranscriptTextNormalizer.normalize("<|startoftranscript|><|0.00|><|endoftext|>"), "")
  }

  func testChunksPreserveNormalizedTranscriptAndBoundRenderUnits() {
    let normalized = String(repeating: "中文内容。", count: 17)
    let chunks = TranscriptTextNormalizer.chunks(normalized, maxCharacters: 10)

    XCTAssertEqual(chunks.joined(), normalized)
    XCTAssertTrue(chunks.allSatisfy { $0.count <= 10 })
    XCTAssertGreaterThan(chunks.count, 1)
  }
}
