@preconcurrency import AVFoundation
import Foundation
import WoiceCore

struct MeetingMixPreparationResult: Equatable, Sendable {
  let url: URL
  let duration: TimeInterval
  let includedTracks: Set<AudioTrackKind>
}

enum AudioPreparationError: LocalizedError, Equatable {
  case sourceMissing(AudioTrackKind)
  case sourceEmpty(AudioTrackKind)
  case unsupportedFormat(AudioTrackKind)
  case conversionFailed(String)
  case outputFailed(String)

  var errorDescription: String? {
    switch self {
    case .sourceMissing(let track): "找不到\(track.label)原始音轨。"
    case .sourceEmpty(let track): "\(track.label)原始音轨没有可用音频。"
    case .unsupportedFormat(let track): "无法读取\(track.label)的音频格式。"
    case .conversionFailed(let message): "会议音频标准化失败：\(message)"
    case .outputFailed(let message): "会议回放生成失败：\(message)"
    }
  }
}

/// Produces a disposable, deterministic ASR/replay input from immutable raw
/// tracks. The source files are never renamed, re-encoded, or deleted.
enum AudioPreparationService {
  static let targetSampleRate = 16_000.0
  static let targetChannels: AVAudioChannelCount = 1
  private static let chunkFrames: AVAudioFrameCount = 4_096

  private final class ConversionErrorBox: @unchecked Sendable {
    private let lock = NSLock()
    private var error: Error?

    func set(_ error: Error) {
      lock.lock()
      self.error = error
      lock.unlock()
    }

    func get() -> Error? {
      lock.lock()
      defer { lock.unlock() }
      return error
    }
  }

  static func prepareMeetingMix(
    microphoneURL: URL?,
    systemAudioURL: URL?,
    outputURL: URL,
    microphoneStartOffset: TimeInterval = 0,
    systemAudioStartOffset: TimeInterval = 0
  ) throws -> MeetingMixPreparationResult {
    let targetFormat = try targetFormat()
    let temporaryDirectory = outputURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(
      at: temporaryDirectory, withIntermediateDirectories: true)

    var normalizedSources: [(kind: AudioTrackKind, url: URL, offset: TimeInterval)] = []
    var temporaryURLs: [URL] = []
    defer {
      for url in temporaryURLs { try? FileManager.default.removeItem(at: url) }
    }

    if let microphoneURL {
      let normalizedURL = temporaryDirectory.appendingPathComponent(
        ".\(outputURL.deletingPathExtension().lastPathComponent)-microphone.wav")
      try normalize(
        sourceURL: microphoneURL, destinationURL: normalizedURL, targetFormat: targetFormat,
        track: .microphone)
      normalizedSources.append((.microphone, normalizedURL, max(0, microphoneStartOffset)))
      temporaryURLs.append(normalizedURL)
    }
    if let systemAudioURL {
      let normalizedURL = temporaryDirectory.appendingPathComponent(
        ".\(outputURL.deletingPathExtension().lastPathComponent)-system.wav")
      try normalize(
        sourceURL: systemAudioURL, destinationURL: normalizedURL, targetFormat: targetFormat,
        track: .systemAudio)
      normalizedSources.append((.systemAudio, normalizedURL, max(0, systemAudioStartOffset)))
      temporaryURLs.append(normalizedURL)
    }
    guard !normalizedSources.isEmpty else {
      throw AudioPreparationError.sourceEmpty(.meetingMix)
    }
    try mix(
      sources: normalizedSources, destinationURL: outputURL, targetFormat: targetFormat)
    let output = try AVAudioFile(forReading: outputURL)
    guard output.length > 0 else { throw AudioPreparationError.sourceEmpty(.meetingMix) }
    return MeetingMixPreparationResult(
      url: outputURL,
      duration: Double(output.length) / targetFormat.sampleRate,
      includedTracks: Set(normalizedSources.map(\.kind)))
  }

  static func prepareTranscriptionAudio(sourceURL: URL, outputURL: URL) throws {
    let targetFormat = try targetFormat()
    let temporaryDirectory = outputURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(
      at: temporaryDirectory, withIntermediateDirectories: true)
    try normalize(
      sourceURL: sourceURL, destinationURL: outputURL, targetFormat: targetFormat,
      track: .microphone)
  }

  private static func targetFormat() throws -> AVAudioFormat {
    guard
      let format = AVAudioFormat(
        standardFormatWithSampleRate: targetSampleRate, channels: targetChannels)
    else { throw AudioPreparationError.outputFailed("无法创建 16 kHz 单声道格式。") }
    return format
  }

  private static func normalize(
    sourceURL: URL,
    destinationURL: URL,
    targetFormat: AVAudioFormat,
    track: AudioTrackKind
  ) throws {
    guard FileManager.default.fileExists(atPath: sourceURL.path) else {
      throw AudioPreparationError.sourceMissing(track)
    }
    let source: AVAudioFile
    do {
      source = try AVAudioFile(forReading: sourceURL)
    } catch {
      throw AudioPreparationError.unsupportedFormat(track)
    }
    guard source.length > 0, source.processingFormat.sampleRate > 0 else {
      throw AudioPreparationError.sourceEmpty(track)
    }
    guard
      let converter = AVAudioConverter(
        from: source.processingFormat, to: targetFormat)
    else { throw AudioPreparationError.unsupportedFormat(track) }

    try? FileManager.default.removeItem(at: destinationURL)
    let output: AVAudioFile
    do {
      output = try AVAudioFile(forWriting: destinationURL, settings: targetFormat.settings)
    } catch {
      throw AudioPreparationError.outputFailed(error.localizedDescription)
    }
    defer {
      if #available(macOS 15.0, *) { output.close() }
    }

    while true {
      guard
        let outputBuffer = AVAudioPCMBuffer(
          pcmFormat: targetFormat, frameCapacity: chunkFrames)
      else { throw AudioPreparationError.conversionFailed("无法分配转换缓冲区。") }
      let conversionError = ConversionErrorBox()
      var status = AVAudioConverterOutputStatus.error
      status = converter.convert(to: outputBuffer, error: nil) { _, inputStatus in
        guard source.framePosition < source.length else {
          inputStatus.pointee = .endOfStream
          return nil
        }
        let remaining = source.length - source.framePosition
        let sourceCapacity = AVAudioFrameCount(
          min(Int64(8_192), max(1, remaining)))
        guard
          let inputBuffer = AVAudioPCMBuffer(
            pcmFormat: source.processingFormat, frameCapacity: sourceCapacity)
        else {
          conversionError.set(AudioPreparationError.conversionFailed("无法分配输入缓冲区。"))
          inputStatus.pointee = .endOfStream
          return nil
        }
        do {
          try source.read(into: inputBuffer, frameCount: sourceCapacity)
          inputStatus.pointee = inputBuffer.frameLength > 0 ? .haveData : .endOfStream
          return inputBuffer.frameLength > 0 ? inputBuffer : nil
        } catch {
          conversionError.set(error)
          inputStatus.pointee = .endOfStream
          return nil
        }
      }
      if let conversionError = conversionError.get() {
        throw AudioPreparationError.conversionFailed(conversionError.localizedDescription)
      }
      if outputBuffer.frameLength > 0 {
        do { try output.write(from: outputBuffer) } catch {
          throw AudioPreparationError.outputFailed(error.localizedDescription)
        }
      }
      switch status {
      case .endOfStream:
        return
      case .error:
        throw AudioPreparationError.conversionFailed("转换器返回错误。")
      case .haveData, .inputRanDry:
        if outputBuffer.frameLength == 0, source.framePosition >= source.length { return }
      @unknown default:
        throw AudioPreparationError.conversionFailed("转换器返回未知状态。")
      }
    }
  }

  private static func mix(
    sources: [(kind: AudioTrackKind, url: URL, offset: TimeInterval)],
    destinationURL: URL,
    targetFormat: AVAudioFormat
  ) throws {
    let files = try sources.map { source -> (AudioTrackKind, AVAudioFile, Int64) in
      let file: AVAudioFile
      do { file = try AVAudioFile(forReading: source.url) } catch {
        throw AudioPreparationError.unsupportedFormat(source.kind)
      }
      let offset = Int64((max(0, source.offset) * targetFormat.sampleRate).rounded())
      return (source.kind, file, offset)
    }
    let totalFrames = files.map { $0.2 + $0.1.length }.max() ?? 0
    guard totalFrames > 0 else { throw AudioPreparationError.sourceEmpty(.meetingMix) }

    try? FileManager.default.removeItem(at: destinationURL)
    let output: AVAudioFile
    do {
      output = try AVAudioFile(forWriting: destinationURL, settings: targetFormat.settings)
    } catch { throw AudioPreparationError.outputFailed(error.localizedDescription) }
    defer {
      if #available(macOS 15.0, *) { output.close() }
    }
    let gain: Float = files.count == 1 ? 1 : 0.5
    var outputPosition: Int64 = 0
    while outputPosition < totalFrames {
      let frameCount = AVAudioFrameCount(
        min(Int64(chunkFrames), totalFrames - outputPosition))
      guard
        let outputBuffer = AVAudioPCMBuffer(
          pcmFormat: targetFormat, frameCapacity: frameCount),
        let outputSamples = outputBuffer.floatChannelData?[0]
      else { throw AudioPreparationError.outputFailed("无法分配合并缓冲区。") }
      outputBuffer.frameLength = frameCount
      for index in 0..<Int(frameCount) { outputSamples[index] = 0 }

      for (_, file, offset) in files {
        let destinationOffset = max(0, offset - outputPosition)
        let sourcePosition = max(0, outputPosition - offset)
        let available = Int64(frameCount) - destinationOffset
        guard available > 0, sourcePosition < file.length else { continue }
        let readCount = AVAudioFrameCount(min(available, file.length - sourcePosition))
        file.framePosition = sourcePosition
        guard
          let inputBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat, frameCapacity: readCount),
          let inputSamples = inputBuffer.floatChannelData?[0]
        else { throw AudioPreparationError.outputFailed("无法读取标准化音轨。") }
        try file.read(into: inputBuffer, frameCount: readCount)
        for index in 0..<Int(inputBuffer.frameLength) {
          let destinationIndex = Int(destinationOffset) + index
          outputSamples[destinationIndex] = min(
            1, max(-1, outputSamples[destinationIndex] + inputSamples[index] * gain))
        }
      }
      do { try output.write(from: outputBuffer) } catch {
        throw AudioPreparationError.outputFailed(error.localizedDescription)
      }
      outputPosition += Int64(frameCount)
    }
  }
}
