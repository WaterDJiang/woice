import AVFoundation

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
