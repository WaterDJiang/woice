@preconcurrency import AVFoundation
import CryptoKit
import Foundation
import WoiceCore
import XCTest

@testable import WoiceApp

final class QwenAudioCrashAcceptanceTests: XCTestCase {
  func testRealQwenAudible64FrameInputDoesNotCrash() async throws {
    let service = try makeService()
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("qwen-64-\(UUID()).wav")
    defer { try? FileManager.default.removeItem(at: url) }
    let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
    do {
      let file = try AVAudioFile(forWriting: url, settings: format.settings)
      let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 64))
      buffer.frameLength = 64
      for i in 0..<64 { buffer.floatChannelData![0][i] = 0.04 }
      try file.write(from: buffer)
    }
    do {
      _ = try await service.transcribe(audioURL: url, language: "zh")
    } catch LocalASRError.emptyResult {
      // Four milliseconds need not produce text, but must not terminate the process.
    }
  }

  func testRealQwenOriginalAudioCompletesWithoutChangingSource() async throws {
    let service = try makeService()
    guard let source = ProcessInfo.processInfo.environment["WOICE_QWEN_CRASH_AUDIO"] else {
      throw XCTSkip("Set WOICE_QWEN_CRASH_AUDIO for private source acceptance")
    }
    let url = URL(fileURLWithPath: source)
    let before = SHA256.hash(data: try Data(contentsOf: url))
    let audio = try AVAudioFile(forReading: url)
    let duration = Double(audio.length) / audio.processingFormat.sampleRate
    let result = try await service.transcribe(audioURL: url, language: "zh")
    XCTAssertFalse(result.text.isEmpty)
    XCTAssertFalse(result.segments.isEmpty)
    XCTAssertTrue(result.segments.allSatisfy { $0.start >= 0 && $0.end <= duration + 0.001 })
    XCTAssertEqual(before, SHA256.hash(data: try Data(contentsOf: url)))
  }

  private func makeService() throws -> Qwen3ASRTranscriptionService {
    guard let folder = ProcessInfo.processInfo.environment["WOICE_QWEN_CRASH_MODEL"] else {
      throw XCTSkip("Set WOICE_QWEN_CRASH_MODEL to explicitly run the installed real model")
    }
    return try Qwen3ASRTranscriptionService(
      manifest: Qwen3ASRModelCatalogEntry.recommended.manifest,
      modelFolder: URL(fileURLWithPath: folder))
  }
}
