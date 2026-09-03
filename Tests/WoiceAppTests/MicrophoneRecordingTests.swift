import AVFoundation
import Foundation
import Testing
import WoiceCore

@testable import WoiceApp

@Test("录音磁盘空间低于安全线时 fail-closed")
func recordingStoragePolicyRejectsLowCapacity() {
  let error = RecordingStoragePolicy.validationError(
    availableBytes: RecordingStoragePolicy.minimumAvailableBytes - 1)
  #expect(
    error
      == .insufficientStorage(
        required: RecordingStoragePolicy.minimumAvailableBytes,
        available: RecordingStoragePolicy.minimumAvailableBytes - 1))
  #expect(error?.localizedDescription.contains("空间不足") == true)
}

@Test("录音磁盘空间预检对正常和未知容量保持兼容")
func recordingStoragePolicyAllowsNormalOrUnknownCapacity() {
  #expect(
    RecordingStoragePolicy.validationError(
      availableBytes: RecordingStoragePolicy.minimumAvailableBytes) == nil)
  #expect(RecordingStoragePolicy.validationError(availableBytes: nil) == nil)
}

@Test("麦克风首帧门禁使用有限等待")
func microphoneCapturePolicyIsBounded() {
  #expect(MicrophoneCapturePolicy.firstBufferTimeout == .seconds(1))
  #expect(MicrophoneCapturePolicy.firstBufferPollInterval == .milliseconds(50))
}

@Test("无音频错误说明下一步检查")
func microphoneCaptureFailureExplainsNextAction() {
  #expect(WoiceError.noAudio.localizedDescription.contains("检查麦克风或系统音频输入"))
}

@Test("三声道交错麦克风缓冲可规范化后写入 AAC")
func threeChannelInterleavedMicrophoneBufferWritesAAC() throws {
  let channelLayout = try #require(
    AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_MPEG_3_0_A))
  let inputFormat = AVAudioFormat(
    commonFormat: .pcmFormatFloat32,
    sampleRate: 48_000,
    interleaved: true,
    channelLayout: channelLayout)
  let normalizer = try RecordingAudioBufferNormalizer(inputFormat: inputFormat)
  #expect(normalizer.outputFormat.sampleRate == 48_000)
  #expect(normalizer.outputFormat.channelCount == 2)
  #expect(!normalizer.outputFormat.isInterleaved)

  let input = try #require(
    AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: 4_096))
  input.frameLength = 4_096
  let output = try normalizer.normalize(input)
  #expect(output.frameLength > 0)
  #expect(output.format.channelCount == 2)
  #expect(!output.format.isInterleaved)

  let url = FileManager.default.temporaryDirectory.appendingPathComponent(
    "woice-three-channel-aac-\(UUID().uuidString).m4a")
  defer { try? FileManager.default.removeItem(at: url) }
  let file = try AVAudioFile(
    forWriting: url,
    settings: RecordingAudioFormat.aacSettings(
      sampleRate: output.format.sampleRate,
      channelCount: Int(output.format.channelCount),
      bitRate: 64_000),
    commonFormat: output.format.commonFormat,
    interleaved: output.format.isInterleaved)
  try file.write(from: output)
  if #available(macOS 15.0, *) { file.close() }
  #expect(try AVAudioFile(forReading: url).length > 0)

  let chunkDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
    "woice-three-channel-chunks-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: chunkDirectory) }
  let chunkWriter = try RollingPCMChunkWriter(
    sessionID: UUID(),
    track: .microphone,
    directoryURL: chunkDirectory,
    format: output.format,
    chunkDuration: 1)
  #expect(try chunkWriter.append(output).isEmpty)
  let commits = try chunkWriter.finish()
  #expect(commits.count == 1)
  #expect(try AVAudioFile(forReading: commits[0].url).length > 0)
}

@Test("退出时只要有音频资源就必须先执行清理")
func terminationPolicyRequiresAudioCleanup() {
  #expect(
    RecordingTerminationPolicy.requiresAudioCleanup(
      isRecording: false, isSystemAudioCapturing: false) == false)
  #expect(
    RecordingTerminationPolicy.requiresAudioCleanup(
      isRecording: true, isSystemAudioCapturing: false))
  #expect(
    RecordingTerminationPolicy.requiresAudioCleanup(
      isRecording: false, isSystemAudioCapturing: true))
}

@Test("麦克风状态暴露权限和可用输入格式")
@MainActor
func microphoneStatusReportsUsableInput() async {
  let recorder = RecordingService()
  let status = await recorder.refreshMicrophoneStatus()
  guard AVAudioApplication.shared.recordPermission == .granted else {
    #expect(status.permission != .granted)
    return
  }
  #expect(status.permission == .granted)
  #expect(status.hasUsableInput)
  #expect(status.sampleRate > 0)
  #expect(status.channelCount > 0)
}

@Test("麦克风输入自检写入临时 WAV 并返回帧")
@MainActor
func microphoneInputCheckReportsCapturedFrames() async throws {
  guard ProcessInfo.processInfo.environment["WOICE_REQUIRE_MIC_AUDIO"] == "1" else { return }
  guard AVAudioApplication.shared.recordPermission == .granted else { return }
  let result = try await RecordingService().runMicrophoneCheck()
  #expect(result.bufferCount > 0)
  #expect(result.duration > 0)
  if ProcessInfo.processInfo.environment["WOICE_REQUIRE_MIC_AUDIO"] == "1" {
    #expect(result.peakLevel > 0.0001)
  }
}

private final class RecordingTranscriptionURLProtocol: URLProtocol {
  nonisolated(unsafe) static var body: Data?

  override class func canInit(with request: URLRequest) -> Bool { true }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    Self.body = requestBodyData(request)
    let response = HTTPURLResponse(
      url: request.url!, statusCode: 200, httpVersion: nil,
      headerFields: ["Content-Type": "application/json"]
    )!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(#"{"text":"测试录音转写成功"}"#.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

private func requestBodyData(_ request: URLRequest) -> Data? {
  if let httpBody = request.httpBody { return httpBody }
  guard let stream = request.httpBodyStream else { return nil }
  stream.open()
  defer { stream.close() }
  var data = Data()
  var buffer = [UInt8](repeating: 0, count: 4_096)
  while stream.hasBytesAvailable {
    let count = stream.read(&buffer, maxLength: buffer.count)
    guard count > 0 else { break }
    data.append(buffer, count: count)
  }
  return data
}

private final class AudioBufferCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var value = 0

  func increment() {
    lock.lock()
    value += 1
    lock.unlock()
  }

  var count: Int {
    lock.lock()
    defer { lock.unlock() }
    return value
  }
}

@Test("AVAudioEngine 麦克风录音服务在已授权 Mac 上可写入帧")
@MainActor
func microphoneRecordingServiceWritesFrames() async throws {
  guard ProcessInfo.processInfo.environment["WOICE_REQUIRE_MIC_AUDIO"] == "1" else { return }
  guard AVAudioApplication.shared.recordPermission == .granted else { return }
  let url = FileManager.default.temporaryDirectory.appendingPathComponent(
    "woice-microphone-smoke.wav")
  try? FileManager.default.removeItem(at: url)
  defer { try? FileManager.default.removeItem(at: url) }

  let recorder = RecordingService()
  try await recorder.start(to: url)
  try await Task.sleep(for: .milliseconds(700))
  let activityBeforeStop = recorder.activity
  let result = recorder.stop()
  #expect(result.bufferCount > 0)
  #expect(result.duration > 0)
  for segment in result.capturedSegments {
    #expect(FileManager.default.fileExists(atPath: segment.url.path))
    #expect((try? AVAudioFile(forReading: segment.url).length) ?? 0 > 0)
  }
  let file = try AVAudioFile(forReading: url)
  #expect(file.length > 0)
  let configuration = URLSessionConfiguration.ephemeral
  configuration.protocolClasses = [RecordingTranscriptionURLProtocol.self]
  let session = URLSession(configuration: configuration)
  RecordingTranscriptionURLProtocol.body = nil
  let text = try await TranscriptionClient(session: session).transcribe(
    audioURL: url,
    endpoint: "https://example.test/v1",
    apiKey: "test-key",
    model: "whisper-test",
    language: "zh"
  )
  #expect(text == "测试录音转写成功")
  #expect(RecordingTranscriptionURLProtocol.body?.range(of: Data("RIFF".utf8)) != nil)
  if ProcessInfo.processInfo.environment["WOICE_REQUIRE_MIC_AUDIO"] == "1" {
    #expect(result.peakLevel > 0.0001)
    #expect(activityBeforeStop.totalFrameCount > 0)
  }
}

@Test("麦克风录音停止后重新创建输入 Engine 仍可收帧")
@MainActor
func microphoneRecordingServiceRecreatesInputEngine() async throws {
  guard ProcessInfo.processInfo.environment["WOICE_REQUIRE_MIC_AUDIO"] == "1" else { return }
  guard AVAudioApplication.shared.recordPermission == .granted else { return }

  let recorder = RecordingService()
  for index in 0..<2 {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      "woice-microphone-restart-" + String(index) + ".wav")
    try? FileManager.default.removeItem(at: url)
    defer { try? FileManager.default.removeItem(at: url) }

    try await recorder.start(to: url)
    try await Task.sleep(for: .milliseconds(350))
    let result = recorder.stop()
    #expect(result.bufferCount > 0)
    #expect(result.duration > 0)
    #expect(try AVAudioFile(forReading: url).length > 0)
  }
}

@Test("麦克风 tap 可将同一帧安全投递给实时预览")
@MainActor
func microphoneRecordingServiceFansOutAudioBuffers() async throws {
  guard ProcessInfo.processInfo.environment["WOICE_REQUIRE_MIC_AUDIO"] == "1" else { return }
  guard AVAudioApplication.shared.recordPermission == .granted else { return }

  let url = FileManager.default.temporaryDirectory.appendingPathComponent(
    "woice-microphone-preview-fanout.wav")
  try? FileManager.default.removeItem(at: url)
  defer { try? FileManager.default.removeItem(at: url) }

  let counter = AudioBufferCounter()
  let recorder = RecordingService()
  try await recorder.start(to: url) { _ in counter.increment() }
  try await Task.sleep(for: .milliseconds(350))
  let result = recorder.stop()
  #expect(result.bufferCount > 0)
  #expect(counter.count > 0)
}
