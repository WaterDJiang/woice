@preconcurrency import AVFoundation
import Foundation

/// Keeps AVAudioFile short reads inside a model chunk and protects the pinned
/// Qwen feature extractor's 160-sample hop without extending source timestamps.
final class QwenAudioChunkReader {
  struct Chunk {
    let samples: [Float]
    let sourceFrameCount: Int
    let startFrame: AVAudioFramePosition
    let isTrailing: Bool

    var start: TimeInterval { Double(startFrame) / 16_000 }
    var end: TimeInterval { Double(startFrame + Int64(sourceFrameCount)) / 16_000 }
  }

  private let file: AVAudioFile
  private let maximumFrames = 480_000
  private let minimumFrames = 160

  init(file: AVAudioFile) throws {
    guard file.length > 0 else { throw Qwen3ASRError.audioReadFailed("音频没有可用帧") }
    guard file.processingFormat.sampleRate == 16_000,
      file.processingFormat.channelCount == 1,
      file.processingFormat.commonFormat == .pcmFormatFloat32
    else { throw Qwen3ASRError.audioReadFailed("需要 16 kHz 单声道浮点音频") }
    self.file = file
  }

  func next() throws -> Chunk? {
    let startFrame = file.framePosition
    let remaining = file.length - startFrame
    guard remaining > 0 else { return nil }
    var target = Int(min(Int64(maximumFrames), remaining))
    let tail = remaining - Int64(target)
    if tail > 0, tail < minimumFrames {
      target -= minimumFrames - Int(tail)
    }
    var samples: [Float] = []
    samples.reserveCapacity(max(minimumFrames, target))
    while samples.count < target {
      let requested = AVAudioFrameCount(target - samples.count)
      guard
        let buffer = AVAudioPCMBuffer(
          pcmFormat: file.processingFormat, frameCapacity: requested)
      else { throw Qwen3ASRError.audioReadFailed("无法分配音频缓冲区") }
      try file.read(into: buffer, frameCount: requested)
      guard buffer.frameLength > 0, let channel = buffer.floatChannelData?.pointee else {
        throw Qwen3ASRError.audioReadFailed("音频尚未结束却无法读取帧")
      }
      samples.append(
        contentsOf: UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
    }
    let sourceFrameCount = samples.count
    if sourceFrameCount < minimumFrames {
      samples.append(contentsOf: repeatElement(0, count: minimumFrames - sourceFrameCount))
    }
    return Chunk(
      samples: samples, sourceFrameCount: sourceFrameCount, startFrame: startFrame,
      isTrailing: file.framePosition >= file.length)
  }
}
