@preconcurrency import AVFoundation
import Foundation
import WoiceCore

struct AudioChunkDescriptor: Equatable, Sendable {
  let index: Int
  let start: TimeInterval
  let end: TimeInterval
}

enum AudioChunkingError: LocalizedError, Equatable {
  case sourceMissing
  case unreadableSource
  case unsupportedFormat
  case unableToDetermineChunkSize

  var errorDescription: String? {
    switch self {
    case .sourceMissing: "找不到待分段的音频文件。"
    case .unreadableSource: "无法读取待分段的音频文件。"
    case .unsupportedFormat: "音频格式不支持长文件分段。"
    case .unableToDetermineChunkSize: "无法计算安全的音频分段大小。"
    }
  }
}

/// Keeps OpenAI-compatible multipart uploads below the common 25 MiB limit.
/// A safety margin is intentional because multipart headers and provider-side
/// wrappers add bytes that are not represented by the audio file itself.
enum AudioChunkingService {
  static let defaultMaximumUploadBytes: Int64 = 20 * 1024 * 1024
  private static let containerSafetyMargin: Int64 = 4 * 1024

  static func plan(
    sourceURL: URL,
    maximumUploadBytes: Int64 = defaultMaximumUploadBytes
  ) throws -> [AudioChunkDescriptor] {
    guard FileManager.default.fileExists(atPath: sourceURL.path) else {
      throw AudioChunkingError.sourceMissing
    }
    guard maximumUploadBytes > containerSafetyMargin else {
      throw AudioChunkingError.unableToDetermineChunkSize
    }
    let fileSize = try fileSize(of: sourceURL)
    guard fileSize > maximumUploadBytes else { return [] }

    let source: AVAudioFile
    do {
      source = try AVAudioFile(forReading: sourceURL)
    } catch {
      throw AudioChunkingError.unreadableSource
    }
    let sampleRate = source.processingFormat.sampleRate
    guard source.length > 0, sampleRate > 0 else {
      throw AudioChunkingError.unreadableSource
    }
    guard let bytesPerFrame = bytesPerFrame(for: source), bytesPerFrame > 0 else {
      throw AudioChunkingError.unsupportedFormat
    }
    let payloadBytes = maximumUploadBytes - containerSafetyMargin
    let framesPerChunk = AVAudioFramePosition(payloadBytes / bytesPerFrame)
    guard framesPerChunk > 0 else { throw AudioChunkingError.unableToDetermineChunkSize }

    var chunks: [AudioChunkDescriptor] = []
    var startFrame: AVAudioFramePosition = 0
    var index = 0
    while startFrame < source.length {
      let endFrame = min(source.length, startFrame + framesPerChunk)
      chunks.append(
        AudioChunkDescriptor(
          index: index,
          start: Double(startFrame) / sampleRate,
          end: Double(endFrame) / sampleRate))
      startFrame = endFrame
      index += 1
    }
    return chunks
  }

  static func materialize(
    sourceURL: URL,
    chunks: [AudioChunkDescriptor],
    workingDirectory: URL
  ) throws -> [URL] {
    guard !chunks.isEmpty else { return [] }
    try FileManager.default.createDirectory(
      at: workingDirectory, withIntermediateDirectories: true)
    return try chunks.map { chunk in
      let chunkName = String(format: "%04d", chunk.index)
      let outputURL = workingDirectory.appendingPathComponent("chunk-\(chunkName).wav")
      try? FileManager.default.removeItem(at: outputURL)
      try AudioSegmentExtractor.extract(
        sourceURL: sourceURL,
        segment: VoiceSegment(start: chunk.start, end: chunk.end),
        destinationURL: outputURL)
      return outputURL
    }
  }

  private static func fileSize(of url: URL) throws -> Int64 {
    let values = try url.resourceValues(forKeys: [.fileSizeKey])
    guard let size = values.fileSize, size > 0 else {
      throw AudioChunkingError.unreadableSource
    }
    return Int64(size)
  }

  private static func bytesPerFrame(for file: AVAudioFile) -> Int64? {
    let description = file.processingFormat.streamDescription.pointee
    if description.mBytesPerFrame > 0 {
      return Int64(description.mBytesPerFrame)
    }
    let channels = Int64(max(1, file.processingFormat.channelCount))
    return channels * 4
  }
}
