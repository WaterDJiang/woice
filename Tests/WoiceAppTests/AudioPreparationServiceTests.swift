import AVFoundation
import Foundation
import Testing
import WoiceCore

@testable import WoiceApp

@Test("会议合成音频保留双轨并按统一格式输出")
func meetingMixIsDeterministicAndKeepsSources() throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "woice-meeting-mix-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

  let microphoneURL = root.appendingPathComponent("microphone.wav")
  let systemURL = root.appendingPathComponent("system.caf")
  let outputURL = root.appendingPathComponent("meeting-mix.wav")
  try writeTone(to: microphoneURL, frequency: 440, amplitude: 0.2)
  try writeTone(to: systemURL, frequency: 880, amplitude: 0.2, sampleRate: 48_000, channels: 2)
  let microphoneBytesBefore = try Data(contentsOf: microphoneURL)
  let systemBytesBefore = try Data(contentsOf: systemURL)

  let result = try AudioPreparationService.prepareMeetingMix(
    microphoneURL: microphoneURL,
    systemAudioURL: systemURL,
    outputURL: outputURL,
    systemAudioStartOffset: 0.1
  )

  #expect(result.includedTracks == [.microphone, .systemAudio])
  #expect(result.duration >= 0.9)
  let output = try AVAudioFile(forReading: outputURL)
  #expect(output.processingFormat.sampleRate == 16_000)
  #expect(output.processingFormat.channelCount == 1)
  #expect(output.length > 0)
  let samples = try readMonoSamples(from: output)
  #expect(toneMagnitude(samples: samples, sampleRate: 16_000, frequency: 440) > 0.03)
  #expect(toneMagnitude(samples: samples, sampleRate: 16_000, frequency: 880) > 0.03)
  #expect(try Data(contentsOf: microphoneURL) == microphoneBytesBefore)
  #expect(try Data(contentsOf: systemURL) == systemBytesBefore)
}

private func readMonoSamples(from file: AVAudioFile) throws -> [Float] {
  file.framePosition = 0
  let frameCount = AVAudioFrameCount(file.length)
  let buffer = try #require(
    AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameCount))
  try file.read(into: buffer, frameCount: frameCount)
  let channel = try #require(buffer.floatChannelData?[0])
  return Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
}

private func toneMagnitude(samples: [Float], sampleRate: Double, frequency: Double) -> Double {
  guard !samples.isEmpty else { return 0 }
  var cosine = 0.0
  var sine = 0.0
  for (index, sample) in samples.enumerated() {
    let phase = 2 * Double.pi * frequency * Double(index) / sampleRate
    cosine += Double(sample) * cos(phase)
    sine += Double(sample) * sin(phase)
  }
  return 2 * hypot(cosine, sine) / Double(samples.count)
}

private func writeTone(
  to url: URL,
  frequency: Double,
  amplitude: Float,
  sampleRate: Double = 16_000,
  channels: AVAudioChannelCount = 1
) throws {
  let format = try #require(
    AVAudioFormat(
      commonFormat: .pcmFormatFloat32,
      sampleRate: sampleRate,
      channels: channels,
      interleaved: false
    ))
  let file = try AVAudioFile(forWriting: url, settings: format.settings)
  let frameCount = AVAudioFrameCount(sampleRate)
  let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount))
  buffer.frameLength = frameCount
  for channel in 0..<Int(channels) {
    guard let samples = buffer.floatChannelData?[channel] else { continue }
    for frame in 0..<Int(frameCount) {
      samples[frame] = sin(Float(frame) * 2 * .pi * Float(frequency / sampleRate)) * amplitude
    }
  }
  try file.write(from: buffer)
  if #available(macOS 15.0, *) { file.close() }
}
