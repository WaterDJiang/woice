import AVFoundation
import Foundation
import Network
import Testing
import WoiceCore

@testable import WoiceApp

private final class LoopbackASRHTTPServer: @unchecked Sendable {
  struct Request: Sendable {
    let requestLine: String
    let headers: String
    let body: Data
  }

  private let listener: NWListener
  private let queue = DispatchQueue(label: "com.woice.tests.loopback-asr")
  private let ready = DispatchSemaphore(value: 0)
  private let received = DispatchSemaphore(value: 0)
  private let lock = NSLock()
  private let responseBody: Data
  private let responseStatusCode: Int
  private var request: Request?

  init(responseBody: Data, responseStatusCode: Int = 200) throws {
    self.responseBody = responseBody
    self.responseStatusCode = responseStatusCode
    listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: 0)!)
    listener.stateUpdateHandler = { [weak self] state in
      if case .ready = state { self?.ready.signal() }
    }
    listener.newConnectionHandler = { [weak self] connection in
      self?.accept(connection)
    }
    listener.start(queue: queue)
    guard ready.wait(timeout: .now() + 2) == .success else {
      listener.cancel()
      throw WoiceError.invalidResponse
    }
  }

  var port: UInt16 { listener.port?.rawValue ?? 0 }

  func waitForRequest() -> Request? {
    guard received.wait(timeout: .now() + 2) == .success else { return nil }
    lock.lock()
    defer { lock.unlock() }
    return request
  }

  func stop() { listener.cancel() }

  private func accept(_ connection: NWConnection) {
    connection.start(queue: queue)
    receive(connection, buffer: Data())
  }

  private func receive(_ connection: NWConnection, buffer: Data) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 2_000_000) {
      [weak self] data, _, isComplete, error in
      guard let self else {
        connection.cancel()
        return
      }
      var combined = buffer
      if let data { combined.append(data) }
      guard let headerRange = combined.range(of: Data("\r\n\r\n".utf8)) else {
        if isComplete || error != nil {
          connection.cancel()
        } else {
          self.receive(connection, buffer: combined)
        }
        return
      }

      let headerData = combined[..<headerRange.lowerBound]
      let headerText = String(decoding: headerData, as: UTF8.self)
      let headerLines = headerText.split(separator: "\r\n", omittingEmptySubsequences: false)
      let requestLine = headerLines.first.map(String.init) ?? ""
      let contentLength =
        headerLines.dropFirst().first { line in
          line.lowercased().hasPrefix("content-length:")
        }.flatMap {
          Int(
            $0.split(separator: ":", maxSplits: 1).last?.trimmingCharacters(in: .whitespaces) ?? "")
        }
        ?? 0
      let bodyStart = headerRange.upperBound
      guard combined.count >= bodyStart + contentLength else {
        if isComplete || error != nil {
          connection.cancel()
        } else {
          self.receive(connection, buffer: combined)
        }
        return
      }

      let body = Data(combined[bodyStart..<(bodyStart + contentLength)])
      lock.lock()
      request = Request(requestLine: requestLine, headers: headerText, body: body)
      lock.unlock()
      received.signal()
      let reason = responseStatusCode == 204 ? "No Content" : "OK"
      let responseText = String(decoding: responseBody, as: UTF8.self)
      let response = Data(
        "HTTP/1.1 \(responseStatusCode) \(reason)\r\nContent-Type: application/json\r\nContent-Length: \(responseBody.count)\r\nConnection: close\r\n\r\n\(responseText)"
          .utf8
      )
      connection.send(
        content: response,
        completion: .contentProcessed { _ in
          connection.cancel()
        })
    }
  }
}

@Test("ASR 配置健康检查通过真实 loopback HTTP 且只要求 HTTP 成功")
func transcriptionClientHealthCheckUsesRealLoopbackHTTP() async throws {
  let server = try LoopbackASRHTTPServer(responseBody: Data(), responseStatusCode: 204)
  defer { server.stop() }

  let url = FileManager.default.temporaryDirectory.appendingPathComponent(
    "woice-loopback-asr-health.wav")
  try? FileManager.default.removeItem(at: url)
  defer { try? FileManager.default.removeItem(at: url) }
  let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
  var file: AVAudioFile? = try AVAudioFile(forWriting: url, settings: format.settings)
  let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 800)!
  buffer.frameLength = 800
  try file?.write(from: buffer)
  if #available(macOS 15.0, *) {
    file?.close()
  }
  file = nil

  let result = try await TranscriptionClient().checkConfiguration(
    audioURL: url,
    endpoint: "http://127.0.0.1:\(server.port)/v1",
    apiKey: "health-loopback-key",
    model: "whisper-health-loopback",
    language: "zh"
  )
  #expect(result.statusCode == 204)
  #expect(result.responseBytes == 0)

  let request = try #require(server.waitForRequest())
  #expect(request.requestLine.hasPrefix("POST /v1/audio/transcriptions HTTP/1.1"))
  #expect(request.headers.lowercased().contains("authorization: bearer health-loopback-key"))
  #expect(request.body.range(of: Data("RIFF".utf8)) != nil)
  #expect(request.body.range(of: Data("whisper-health-loopback".utf8)) != nil)
  #expect(request.body.range(of: Data("zh".utf8)) != nil)
}

@Test("自定义 ASR 通过真实 loopback HTTP 收到 WAV multipart")
func transcriptionClientUsesRealLoopbackHTTP() async throws {
  let server = try LoopbackASRHTTPServer(responseBody: Data(#"{"text":"回环转写成功"}"#.utf8))
  defer { server.stop() }

  let url = FileManager.default.temporaryDirectory.appendingPathComponent(
    "woice-loopback-asr.wav")
  try? FileManager.default.removeItem(at: url)
  defer { try? FileManager.default.removeItem(at: url) }
  let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
  var file: AVAudioFile? = try AVAudioFile(forWriting: url, settings: format.settings)
  let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_600)!
  buffer.frameLength = 1_600
  try file?.write(from: buffer)
  if #available(macOS 15.0, *) {
    file?.close()
  }
  file = nil

  let endpoint = "http://127.0.0.1:\(server.port)/v1"
  let text = try await TranscriptionClient().transcribe(
    audioURL: url,
    endpoint: endpoint,
    apiKey: "loopback-key",
    model: "whisper-loopback",
    language: "zh"
  )
  #expect(text == "回环转写成功")

  let request = try #require(server.waitForRequest())
  #expect(request.requestLine.hasPrefix("POST /v1/audio/transcriptions HTTP/1.1"))
  #expect(request.headers.lowercased().contains("authorization: bearer loopback-key"))
  #expect(request.body.range(of: Data("RIFF".utf8)) != nil)
  #expect(request.body.range(of: Data("whisper-loopback".utf8)) != nil)
  #expect(request.body.range(of: Data("zh".utf8)) != nil)
}

@Test("真实麦克风录音经 loopback ASR 完成 AppState 转写")
@MainActor
func appStateRecordingTranscribesWithRealLoopbackHTTP() async throws {
  guard ProcessInfo.processInfo.environment["WOICE_RUN_APPSTATE_LOOPBACK"] == "1" else {
    return
  }
  guard AVAudioApplication.shared.recordPermission == .granted else { return }

  let server = try LoopbackASRHTTPServer(responseBody: Data(#"{"text":"真实回环录音转写成功"}"#.utf8))
  defer { server.stop() }

  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "woice-app-state-loopback-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let store = WorkspaceStore(storageRootURL: root)
  let state = AppState(store: store)
  state.settings.asrProviderSelection = .external
  state.settings.asrEndpoint = "http://127.0.0.1:\(server.port)/v1"
  state.settings.asrAPIKey = "loopback-key"
  state.settings.language = "zh"
  state.settings.asrModel = "whisper-loopback"

  state.startRecording()
  try await Task.sleep(for: .seconds(2))
  #expect(state.isRecording)
  await state.stopRecording()

  let pending = try #require(state.pendingExternalProcessing)
  #expect(pending.endpoint == "http://127.0.0.1:\(server.port)/v1")
  await state.confirmExternalProcessing()

  let record = try #require(state.recordings.first)
  #expect(record.duration > 0)
  #expect(state.elapsed > 0)
  #expect(record.transcript == "真实回环录音转写成功")
  #expect(state.audioFileExists(for: record))
  let playback = AudioPlaybackService()
  playback.play(url: state.audioURL(for: record))
  #expect(playback.duration > 0)
  playback.seek(to: min(0.25, playback.duration))
  #expect(playback.currentTime >= 0)
  playback.stop()

  let request = try #require(server.waitForRequest())
  #expect(request.requestLine.hasPrefix("POST /v1/audio/transcriptions HTTP/1.1"))
  #expect(request.headers.lowercased().contains("authorization: bearer loopback-key"))
  #expect(request.body.range(of: Data("RIFF".utf8)) != nil)
  #expect(request.body.range(of: Data("whisper-loopback".utf8)) != nil)
  #expect(request.body.range(of: Data("zh".utf8)) != nil)
}
