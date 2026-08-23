@preconcurrency import AVFoundation
import Foundation
import WoiceCore

enum AudioSegmentExtractorError: LocalizedError, Equatable {
  case sourceMissing
  case emptyRange
  case readFailed

  var errorDescription: String? {
    switch self {
    case .sourceMissing: "找不到原始录音，无法抽取声音片段。"
    case .emptyRange: "声音片段时间范围无效。"
    case .readFailed: "原始录音片段读取失败。"
    }
  }
}

enum AudioSegmentExtractor {
  static func extract(
    sourceURL: URL, segment: VoiceSegment, destinationURL: URL
  ) throws {
    guard FileManager.default.fileExists(atPath: sourceURL.path) else {
      throw AudioSegmentExtractorError.sourceMissing
    }
    let source = try AVAudioFile(forReading: sourceURL)
    let sampleRate = source.processingFormat.sampleRate
    guard sampleRate > 0 else { throw AudioSegmentExtractorError.emptyRange }
    let startFrame = max(0, min(source.length, AVAudioFramePosition(segment.start * sampleRate)))
    let endFrame = max(
      startFrame, min(source.length, AVAudioFramePosition(segment.end * sampleRate)))
    let frameCount = endFrame - startFrame
    guard frameCount > 0, frameCount <= AVAudioFramePosition(UInt32.max) else {
      throw AudioSegmentExtractorError.emptyRange
    }
    source.framePosition = startFrame
    guard
      let buffer = AVAudioPCMBuffer(
        pcmFormat: source.processingFormat, frameCapacity: AVAudioFrameCount(frameCount))
    else { throw AudioSegmentExtractorError.readFailed }
    try source.read(into: buffer, frameCount: AVAudioFrameCount(frameCount))
    guard buffer.frameLength > 0 else { throw AudioSegmentExtractorError.readFailed }
    let output = try AVAudioFile(forWriting: destinationURL, settings: source.fileFormat.settings)
    try output.write(from: buffer)
  }
}
