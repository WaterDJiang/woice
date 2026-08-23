import AVFoundation
import Foundation
import Testing
import WoiceCore

@testable import WoiceApp

private final class MeetingTranscriptionAcceptanceURLProtocol: URLProtocol {
  nonisolated(unsafe) static var requests: [URLRequest] = []

  override class func canInit(with request: URLRequest) -> Bool { true }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    Self.requests.append(request)
    let response = HTTPURLResponse(
      url: request.url!, statusCode: 200, httpVersion: nil,
      headerFields: ["Content-Type": "application/json"]
    )!
    let body = Data(
      #"{"text":"会议片段","segments":[{"start":0.1,"end":0.8,"text":"会议片段"}]}"#.utf8)
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: body)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

@Test("会议默认与历史混音素材都使用双轨转写且系统轨标准化")
@MainActor
func meetingTranscriptionModesUseExpectedRequestCounts() async throws {
  let configuration = URLSessionConfiguration.ephemeral
  configuration.protocolClasses = [MeetingTranscriptionAcceptanceURLProtocol.self]
  let session = URLSession(configuration: configuration)

  let standardRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
    "woice-meeting-transcription-standard-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: standardRoot) }
  let standardStore = WorkspaceStore(storageRootURL: standardRoot)
  let standardRecord = try makeMeetingRecord(
    store: standardStore, mode: .standardMix, includeMeetingMix: true)
  try standardStore.saveRecordings([standardRecord])
  MeetingTranscriptionAcceptanceURLProtocol.requests = []
  let standardState = AppState(
    store: standardStore,
    transcriptionClient: TranscriptionClient(session: session))
  configureExternalASR(standardState)
  standardState.requestTranscription(for: standardRecord)
  #expect(standardState.pendingExternalProcessingCount == 2)
  for _ in 0..<2 {
    #expect(standardState.pendingExternalProcessing != nil)
    await standardState.confirmExternalProcessing()
  }

  let standardRequests = MeetingTranscriptionAcceptanceURLProtocol.requests
  #expect(standardRequests.count == 2)
  #expect(standardRequests.allSatisfy { $0.url?.path == "/v1/audio/transcriptions" })
  #expect(
    standardRequests.allSatisfy {
      guard let body = requestBody($0) else { return false }
      return body.range(of: Data("whisper-1".utf8)) != nil
        && body.range(of: Data("RIFF".utf8)) != nil
    })
  let standardResult = try #require(standardState.recordings.first)
  #expect(standardResult.meetingTranscriptionMode == .sourceSeparated)
  #expect(standardResult.transcript?.contains("麦克风") == false)
  #expect(standardResult.transcript?.contains("电脑声音") == false)
  #expect(
    Set(standardResult.transcriptSegments?.compactMap(\.sourceTrack) ?? [])
      == Set([AudioTrackKind.microphone, .systemAudio]))

  let separatedRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
    "woice-meeting-transcription-separated-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: separatedRoot) }
  let separatedStore = WorkspaceStore(storageRootURL: separatedRoot)
  let separatedRecord = try makeMeetingRecord(
    store: separatedStore, mode: .sourceSeparated, includeMeetingMix: false)
  try separatedStore.saveRecordings([separatedRecord])
  MeetingTranscriptionAcceptanceURLProtocol.requests = []
  let separatedState = AppState(
    store: separatedStore,
    transcriptionClient: TranscriptionClient(session: session))
  configureExternalASR(separatedState)
  separatedState.requestTranscription(for: separatedRecord)
  #expect(separatedState.pendingExternalProcessingCount == 2)
  for _ in 0..<2 {
    #expect(separatedState.pendingExternalProcessing != nil)
    await separatedState.confirmExternalProcessing()
  }

  let separatedRequests = MeetingTranscriptionAcceptanceURLProtocol.requests
  #expect(separatedRequests.count == 2)
  #expect(separatedRequests.allSatisfy { $0.url?.path == "/v1/audio/transcriptions" })
  #expect(
    separatedRequests.allSatisfy {
      guard let body = requestBody($0) else { return false }
      return body.range(of: Data("whisper-1".utf8)) != nil
        && body.range(of: Data("RIFF".utf8)) != nil
    })
  let separatedResult = try #require(separatedState.recordings.first)
  #expect(
    separatedResult.processingTasks
      .filter { $0.kind == .transcription }
      .allSatisfy { $0.status == .completed })
  #expect(separatedResult.transcript?.contains("麦克风") == false)
  #expect(separatedResult.transcript?.contains("电脑声音") == false)
  #expect(
    Set(separatedResult.transcriptSegments?.compactMap(\.sourceTrack) ?? [])
      == Set([AudioTrackKind.microphone, .systemAudio]))

  let micBefore = try Data(contentsOf: separatedStore.audioURL(for: separatedRecord))
  let systemBefore = try Data(
    contentsOf: try #require(separatedStore.systemAudioURL(for: separatedRecord)))
  let micAfter = try Data(contentsOf: separatedStore.audioURL(for: separatedResult))
  let systemAfter = try Data(
    contentsOf: try #require(separatedStore.systemAudioURL(for: separatedResult)))
  #expect(micBefore == micAfter)
  #expect(systemBefore == systemAfter)
}

@MainActor
private func configureExternalASR(_ state: AppState) {
  state.settings.asrProviderSelection = .external
  state.settings.asrEndpoint = "https://example.test/v1"
  state.settings.asrAPIKey = "fixture-key"
  state.settings.asrModel = "whisper-1"
  state.settings.includeTranscriptTimestamps = true
}

@MainActor
private func makeMeetingRecord(
  store: WorkspaceStore,
  mode: MeetingTranscriptionMode,
  includeMeetingMix: Bool
) throws -> RecordingRecord {
  let id = UUID()
  let micURL = store.recordingsURL.appendingPathComponent("\(id.uuidString).wav")
  let systemURL = store.recordingsURL.appendingPathComponent("\(id.uuidString).caf")
  try writeAudioFile(to: micURL)
  try writeAudioFile(to: systemURL)

  var meetingMixFileName: String?
  if includeMeetingMix {
    let meetingMixURL = store.meetingMixURL(
      for: RecordingRecord(
        id: id,
        createdAt: Date(),
        audioFileName: micURL.lastPathComponent,
        duration: 1,
        transcript: nil,
        generatedMarkdown: nil,
        processingError: nil,
        systemAudioFileName: systemURL.lastPathComponent,
        meetingTranscriptionMode: mode))
    try writeAudioFile(to: meetingMixURL)
    meetingMixFileName = meetingMixURL.lastPathComponent
  }

  let tracks: [AudioTrackKind] =
    mode == .standardMix ? [.meetingMix] : [.microphone, .systemAudio]
  return RecordingRecord(
    id: id,
    createdAt: Date(),
    audioFileName: micURL.lastPathComponent,
    duration: 1,
    transcript: nil,
    generatedMarkdown: nil,
    processingError: nil,
    systemAudioFileName: systemURL.lastPathComponent,
    systemAudioBufferCount: 1,
    systemAudioPeakLevel: 0.1,
    systemAudioDuration: 1,
    meetingMixFileName: meetingMixFileName,
    meetingTranscriptionMode: mode,
    processingTasks: tracks.map { track in
      ProcessingTask(
        kind: .transcription,
        idempotencyKey: "\(id.uuidString.lowercased()):transcription:\(track.rawValue)",
        status: .failed,
        sourceTrack: track,
        meetingTranscriptionMode: mode)
    })
}

private func writeAudioFile(to url: URL) throws {
  let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
  let file = try AVAudioFile(forWriting: url, settings: format.settings)
  let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_600))
  buffer.frameLength = 1_600
  for frame in 0..<1_600 {
    buffer.floatChannelData![0][frame] = Float(sin(Double(frame) * 0.04)) * 0.05
  }
  try file.write(from: buffer)
}

private func requestBody(_ request: URLRequest) -> Data? {
  if let httpBody = request.httpBody { return httpBody }
  guard let stream = request.httpBodyStream else { return nil }
  stream.open()
  defer { stream.close() }
  var result = Data()
  var buffer = [UInt8](repeating: 0, count: 16_384)
  while stream.hasBytesAvailable {
    let count = stream.read(&buffer, maxLength: buffer.count)
    guard count > 0 else { break }
    result.append(contentsOf: buffer.prefix(count))
  }
  return result
}
