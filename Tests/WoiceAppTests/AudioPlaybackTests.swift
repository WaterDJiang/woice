import AVFoundation
import Foundation
import Testing
import WoiceCore

@testable import WoiceApp

@Test("播放器加载 WAV、显示时长并支持跳转")
@MainActor
func audioPlaybackLoadsWAVAndSeeks() throws {
  let url = FileManager.default.temporaryDirectory.appendingPathComponent("woice-playback.wav")
  try? FileManager.default.removeItem(at: url)
  defer { try? FileManager.default.removeItem(at: url) }

  let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
  do {
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100))
    buffer.frameLength = 44_100
    for frame in 0..<44_100 {
      buffer.floatChannelData![0][frame] = Float(sin(Double(frame) * 0.02)) * 0.05
    }
    try file.write(from: buffer)
  }

  let playback = AudioPlaybackService()
  playback.play(url: url)
  #expect(playback.duration > 0.9)
  playback.pause()
  playback.seek(to: 0.4)
  #expect(abs(playback.currentTime - 0.4) < 0.02)
  playback.stop()
  #expect(playback.currentTime == 0)
}

@Test("播放器预加载已提交 WAV 的真实时长但不自动播放")
@MainActor
func audioPlaybackPreparesWAVMetadata() throws {
  let url = FileManager.default.temporaryDirectory.appendingPathComponent(
    "woice-playback-prepare.wav")
  try? FileManager.default.removeItem(at: url)
  defer { try? FileManager.default.removeItem(at: url) }

  let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
  do {
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100))
    buffer.frameLength = 44_100
    try file.write(from: buffer)
  }

  let playback = AudioPlaybackService()
  playback.prepare(url: url)
  #expect(playback.duration > 0.9)
  #expect(playback.currentTime == 0)
  #expect(!playback.isPlaying)
}

@Test("播放器对缺失文件返回可读错误")
@MainActor
func audioPlaybackReportsMissingFile() {
  let playback = AudioPlaybackService()
  playback.play(url: URL(fileURLWithPath: "/private/tmp/woice-file-does-not-exist.wav"))
  #expect(playback.errorMessage == "找不到原始录音文件。")
}

@Test("声音片段抽取保留原始录音并生成可复听 WAV")
@MainActor
func audioSegmentExtractorWritesIndependentWAV() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
    "woice-segment-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let sourceURL = directory.appendingPathComponent("source.wav")
  let segmentURL = directory.appendingPathComponent("segment.wav")
  let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
  do {
    let file = try AVAudioFile(forWriting: sourceURL, settings: format.settings)
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100))
    buffer.frameLength = 44_100
    for frame in 0..<44_100 {
      buffer.floatChannelData![0][frame] = Float(sin(Double(frame) * 0.02)) * 0.05
    }
    try file.write(from: buffer)
  }
  let originalLength = try AVAudioFile(forReading: sourceURL).length

  try AudioSegmentExtractor.extract(
    sourceURL: sourceURL,
    segment: VoiceSegment(start: 0.25, end: 0.75),
    destinationURL: segmentURL
  )
  #expect(try AVAudioFile(forReading: sourceURL).length == originalLength)
  let extracted = try AVAudioFile(forReading: segmentURL)
  #expect(abs(Double(extracted.length) / extracted.processingFormat.sampleRate - 0.5) < 0.03)
  let playback = AudioPlaybackService()
  playback.play(url: segmentURL)
  #expect(playback.duration > 0.45)
  playback.stop()
}
