@preconcurrency import AVFoundation

enum RecordingAudioFormat {
  static func aacSettings(sampleRate: Double, channelCount: Int, bitRate: Int) -> [String: Any] {
    [
      AVFormatIDKey: kAudioFormatMPEG4AAC,
      AVSampleRateKey: sampleRate,
      AVNumberOfChannelsKey: max(1, min(channelCount, 2)),
      AVEncoderBitRateKey: bitRate,
      AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
    ]
  }
}

enum RecordingAudioBufferNormalizationError: LocalizedError, Equatable {
  case invalidInputFormat
  case converterUnavailable
  case conversionFailed(String)
  case emptyOutput

  var errorDescription: String? {
    switch self {
    case .invalidInputFormat:
      return "麦克风输入格式无效。"
    case .converterUnavailable:
      return "无法创建麦克风声道转换器。"
    case .conversionFailed(let message):
      return "麦克风音频格式转换失败：\(message)"
    case .emptyOutput:
      return "麦克风音频格式转换没有产生可写入帧。"
    }
  }
}

private final class RecordingAudioConversionInput: @unchecked Sendable {
  let buffer: AVAudioPCMBuffer
  var isSupplied = false

  init(buffer: AVAudioPCMBuffer) {
    self.buffer = buffer
  }
}

/// Converts arbitrary HAL microphone PCM into the stable format shared by the
/// primary AAC file, VAD segments, live preview, and rolling recovery chunks.
/// AAC supports at most two channels in Woice's recording profile, so devices
/// exposing three or more channels are downmixed before any file write.
final class RecordingAudioBufferNormalizer {
  let outputFormat: AVAudioFormat

  private let inputFormat: AVAudioFormat
  private let converter: AVAudioConverter?

  init(inputFormat: AVAudioFormat) throws {
    guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
      throw RecordingAudioBufferNormalizationError.invalidInputFormat
    }
    self.inputFormat = inputFormat
    let outputChannels = min(inputFormat.channelCount, 2)
    guard
      let outputFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: inputFormat.sampleRate,
        channels: outputChannels,
        interleaved: false)
    else {
      throw RecordingAudioBufferNormalizationError.invalidInputFormat
    }
    self.outputFormat = outputFormat
    if Self.matches(inputFormat, outputFormat) {
      converter = nil
    } else {
      guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
        throw RecordingAudioBufferNormalizationError.converterUnavailable
      }
      self.converter = converter
    }
  }

  func normalize(_ buffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
    guard let converter else { return buffer }
    let ratio = outputFormat.sampleRate / inputFormat.sampleRate
    let capacity = AVAudioFrameCount(
      max(1, ceil(Double(buffer.frameLength) * ratio) + 32))
    guard
      let outputBuffer = AVAudioPCMBuffer(
        pcmFormat: outputFormat, frameCapacity: capacity)
    else {
      throw RecordingAudioBufferNormalizationError.conversionFailed(
        "无法分配输出缓冲区。")
    }

    let conversionInput = RecordingAudioConversionInput(buffer: buffer)
    var conversionError: NSError?
    let status = converter.convert(to: outputBuffer, error: &conversionError) {
      _, inputStatus in
      guard !conversionInput.isSupplied else {
        inputStatus.pointee = .noDataNow
        return nil
      }
      conversionInput.isSupplied = true
      inputStatus.pointee = .haveData
      return conversionInput.buffer
    }
    if let conversionError {
      throw RecordingAudioBufferNormalizationError.conversionFailed(
        conversionError.localizedDescription)
    }
    guard status != .error else {
      throw RecordingAudioBufferNormalizationError.conversionFailed(
        "Core Audio 转换器返回错误。")
    }
    guard outputBuffer.frameLength > 0 else {
      throw RecordingAudioBufferNormalizationError.emptyOutput
    }
    return outputBuffer
  }

  private static func matches(_ lhs: AVAudioFormat, _ rhs: AVAudioFormat) -> Bool {
    lhs.commonFormat == rhs.commonFormat
      && lhs.sampleRate == rhs.sampleRate
      && lhs.channelCount == rhs.channelCount
      && lhs.isInterleaved == rhs.isInterleaved
  }
}
