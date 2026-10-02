@preconcurrency import AVFoundation
import Foundation
import XCTest

@testable import WoiceApp

final class QwenAudioChunkReaderTests: XCTestCase {
  func testShortReadsPreserveEverySampleAndContinuousTimestamps() throws {
    let count = 480_064
    let samples = (0..<count).map { Float($0 % 113) / 128 }
    try withAudio(samples) { file in
      let reader = try QwenAudioChunkReader(file: file)
      var restored: [Float] = []
      var previousEnd: TimeInterval = 0
      var lengths: [Int] = []
      while let chunk = try reader.next() {
        XCTAssertEqual(chunk.start, previousEnd)
        XCTAssertGreaterThanOrEqual(chunk.samples.count, 160)
        XCTAssertLessThanOrEqual(chunk.samples.count, 480_000)
        restored.append(contentsOf: chunk.samples.prefix(chunk.sourceFrameCount))
        lengths.append(chunk.sourceFrameCount)
        previousEnd = chunk.end
      }
      XCTAssertEqual(restored, samples)
      XCTAssertEqual(lengths, [479_904, 160])
      XCTAssertEqual(previousEnd, Double(count) / 16_000)
    }
  }

  func testShortStandaloneInputIsPaddedOnlyForModelAndKeepsAudibleTail() throws {
    for count in [1, 64, 159, 160] {
      let samples = [Float](repeating: 0.04, count: count)
      try withAudio(samples) { file in
        let reader = try QwenAudioChunkReader(file: file)
        let chunk = try XCTUnwrap(reader.next())
        XCTAssertEqual(chunk.sourceFrameCount, count)
        XCTAssertEqual(chunk.samples.count, 160)
        XCTAssertEqual(Array(chunk.samples.prefix(count)), samples)
        XCTAssertTrue(chunk.samples.dropFirst(count).allSatisfy { $0 == 0 })
        XCTAssertEqual(chunk.end, Double(count) / 16_000)
        XCTAssertTrue(chunk.isTrailing)
        XCTAssertFalse(
          QwenAudioSignalDetector.shouldSkipTrailingChunk(chunk.samples, isTrailingChunk: true))
        XCTAssertNil(try reader.next())
      }
    }
  }

  func testExactThirtySecondBoundaryDoesNotCreateExtraChunk() throws {
    try withAudio([Float](repeating: 0.02, count: 480_000)) { file in
      let reader = try QwenAudioChunkReader(file: file)
      let chunk = try XCTUnwrap(reader.next())
      XCTAssertEqual(chunk.sourceFrameCount, 480_000)
      XCTAssertEqual(chunk.end, 30)
      XCTAssertTrue(chunk.isTrailing)
      XCTAssertNil(try reader.next())
    }
  }

  func testEmptyAudioFailsBeforeInference() throws {
    try withAudio([]) { file in
      XCTAssertThrowsError(try QwenAudioChunkReader(file: file))
    }
  }

  func testWrongSampleRateFailsBeforeInference() throws {
    try withAudio([0.04], sampleRate: 48_000) { file in
      XCTAssertThrowsError(try QwenAudioChunkReader(file: file))
    }
  }

  private func withAudio(
    _ samples: [Float], sampleRate: Double = 16_000,
    body: (AVAudioFile) throws -> Void
  ) throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      "qwen-chunks-\(UUID()).wav")
    defer { try? FileManager.default.removeItem(at: url) }
    let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1))
    do {
      let output = try AVAudioFile(forWriting: url, settings: format.settings)
      if !samples.isEmpty {
        let buffer = try XCTUnwrap(
          AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)))
        buffer.frameLength = buffer.frameCapacity
        for i in samples.indices { buffer.floatChannelData![0][i] = samples[i] }
        try output.write(from: buffer)
      }
    }
    try body(AVAudioFile(forReading: url))
  }
}
