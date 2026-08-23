import AVFoundation
import Foundation
import Testing
import WoiceCore

private final class StubURLProtocol: URLProtocol {
  nonisolated(unsafe) static var response: (HTTPURLResponse, Data) = {
    let response = HTTPURLResponse(
      url: URL(string: "https://example.test")!, statusCode: 200, httpVersion: nil,
      headerFields: ["Content-Type": "application/json"]
    )!
    return (response, Data())
  }()
  nonisolated(unsafe) static var lastRequest: URLRequest?
  nonisolated(unsafe) static var lastBody: Data?

  override class func canInit(with request: URLRequest) -> Bool { true }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    Self.lastRequest = request
    Self.lastBody = bodyData(for: request)
    let (response, data) = Self.response
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: data)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

@Suite(.serialized)
struct APIClientTests {
  @Test("ASR 客户端发送 multipart 音频、模型、语言和授权头")
  func transcriptionRequestContract() async throws {
    let response = HTTPURLResponse(
      url: URL(string: "https://example.test/v1/audio/transcriptions")!, statusCode: 200,
      httpVersion: nil, headerFields: ["Content-Type": "application/json"]
    )!
    StubURLProtocol.response = (response, Data(#"{"text":"你好 Woice"}"#.utf8))
    StubURLProtocol.lastRequest = nil
    StubURLProtocol.lastBody = nil
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    let session = URLSession(configuration: configuration)
    let audioURL = FileManager.default.temporaryDirectory.appendingPathComponent("woice-test.wav")
    try Data([0, 1, 2, 3]).write(to: audioURL)
    defer { try? FileManager.default.removeItem(at: audioURL) }

    let text = try await TranscriptionClient(session: session).transcribe(
      audioURL: audioURL,
      endpoint: "https://example.test/v1/audio/transcriptions",
      apiKey: "test-secret",
      model: "whisper-test",
      language: "zh"
    )

    #expect(text == "你好 Woice")
    let request = try #require(StubURLProtocol.lastRequest)
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-secret")
    let body = String(data: try #require(StubURLProtocol.lastBody), encoding: .utf8) ?? ""
    #expect(body.contains("name=\"model\""))
    #expect(body.contains("whisper-test"))
    #expect(body.contains("name=\"language\""))
    #expect(body.contains("name=\"file\""))
  }

  @Test("ASR 客户端接受服务根地址并补全转写路径")
  func transcriptionRootEndpointContract() async throws {
    let response = HTTPURLResponse(
      url: URL(string: "https://example.test/v1/audio/transcriptions")!, statusCode: 200,
      httpVersion: nil, headerFields: ["Content-Type": "application/json"]
    )!
    StubURLProtocol.response = (response, Data(#"{"text":"根地址也能转写"}"#.utf8))
    StubURLProtocol.lastRequest = nil
    StubURLProtocol.lastBody = nil
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    let session = URLSession(configuration: configuration)
    let audioURL = FileManager.default.temporaryDirectory.appendingPathComponent("woice-root.wav")
    try Data([0, 1, 2, 3]).write(to: audioURL)
    defer { try? FileManager.default.removeItem(at: audioURL) }

    let text = try await TranscriptionClient(session: session).transcribe(
      audioURL: audioURL,
      endpoint: "https://example.test/v1",
      apiKey: "",
      model: "whisper-test",
      language: "zh"
    )

    #expect(text == "根地址也能转写")
    let request = try #require(StubURLProtocol.lastRequest)
    #expect(request.url?.path == "/v1/audio/transcriptions")
  }

  @Test("ASR 配置健康检查验证 HTTP 响应但不要求生成原文")
  func transcriptionConfigurationHealthCheck() async throws {
    let response = HTTPURLResponse(
      url: URL(string: "https://example.test/v1/audio/transcriptions")!, statusCode: 204,
      httpVersion: nil, headerFields: nil
    )!
    StubURLProtocol.response = (response, Data())
    StubURLProtocol.lastRequest = nil
    StubURLProtocol.lastBody = nil
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    let session = URLSession(configuration: configuration)
    let audioURL = FileManager.default.temporaryDirectory.appendingPathComponent(
      "woice-health-check.wav")
    try Data([0, 1, 2, 3]).write(to: audioURL)
    defer { try? FileManager.default.removeItem(at: audioURL) }

    let result = try await TranscriptionClient(session: session).checkConfiguration(
      audioURL: audioURL,
      endpoint: "https://example.test/v1",
      apiKey: "health-secret",
      model: "whisper-health",
      language: "zh"
    )

    #expect(result.statusCode == 204)
    #expect(result.responseBytes == 0)
    let request = try #require(StubURLProtocol.lastRequest)
    #expect(request.url?.path == "/v1/audio/transcriptions")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer health-secret")
    let body = String(data: try #require(StubURLProtocol.lastBody), encoding: .utf8) ?? ""
    #expect(body.contains("whisper-health"))
  }

  @Test("模型发现只访问本机/局域网 models 端点并解析模型列表")
  func localModelDiscoveryContract() async throws {
    let response = HTTPURLResponse(
      url: URL(string: "http://127.0.0.1:9000/v1/models")!, statusCode: 200,
      httpVersion: nil, headerFields: ["Content-Type": "application/json"]
    )!
    StubURLProtocol.response = (
      response,
      Data(
        #"{"data":[{"id":"whisper-large","owned_by":"local"},{"id":"  ","owned_by":"bad"}]}"#.utf8)
    )
    StubURLProtocol.lastRequest = nil
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    let models = try await TranscriptionClient(
      session: URLSession(configuration: configuration)
    ).discoverModels(
      endpoint: "http://127.0.0.1:9000/v1", apiKey: "discovery-secret")

    #expect(models == [ASRDiscoveredModel(id: "whisper-large", ownedBy: "local")])
    let request = try #require(StubURLProtocol.lastRequest)
    #expect(request.httpMethod == "GET")
    #expect(request.url?.path == "/v1/models")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer discovery-secret")
  }

  @Test("模型发现拒绝公网 Endpoint 且不发请求")
  func modelDiscoveryRejectsPublicEndpoint() async throws {
    StubURLProtocol.lastRequest = nil
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    await #expect(
      throws: WoiceError.discoveryRequiresLocalEndpoint("https://api.example.test/v1")
    ) {
      try await TranscriptionClient(session: URLSession(configuration: configuration))
        .discoverModels(endpoint: "https://api.example.test/v1", apiKey: "secret")
    }
    #expect(StubURLProtocol.lastRequest == nil)
    #expect(ASRServiceDiscoveryPolicy.allows("http://localhost:8000/v1"))
    #expect(ASRServiceDiscoveryPolicy.allows("http://192.168.1.10:8000/v1"))
    #expect(!ASRServiceDiscoveryPolicy.allows("https://api.example.test/v1"))
  }

  @Test("ASR verbose_json 响应解析时间戳片段")
  func transcriptionVerboseJSONSegments() async throws {
    let response = HTTPURLResponse(
      url: URL(string: "https://example.test/v1/audio/transcriptions")!, statusCode: 200,
      httpVersion: nil, headerFields: ["Content-Type": "application/json"]
    )!
    StubURLProtocol.response = (
      response,
      Data(
        #"""
        {"text":"<|startoftranscript|><|zh|><|0.00|>你好世界<|1.40|><|endoftext|>",
        "segments":[{"start":0.2,"end":1.4,"text":"<|0.20|>你好世界<|1.40|>"}]}
        """#.utf8
      )
    )
    StubURLProtocol.lastRequest = nil
    StubURLProtocol.lastBody = nil
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    let session = URLSession(configuration: configuration)
    let audioURL = FileManager.default.temporaryDirectory.appendingPathComponent(
      "woice-segments.wav")
    try Data([0, 1, 2, 3]).write(to: audioURL)
    defer { try? FileManager.default.removeItem(at: audioURL) }

    let result = try await TranscriptionClient(session: session).transcribeDetailed(
      audioURL: audioURL,
      endpoint: "https://example.test/v1",
      apiKey: "",
      model: "whisper-test",
      language: "zh",
      includeSegments: true
    )

    #expect(result.text == "你好世界")
    #expect(result.segments == [TranscriptSegment(start: 0.2, end: 1.4, text: "你好世界")])
    let body = String(data: try #require(StubURLProtocol.lastBody), encoding: .utf8) ?? ""
    #expect(body.contains("name=\"response_format\""))
    #expect(body.contains("verbose_json"))
  }

  @Test("ASR 空响应被视为失败而不是成功保存空原文")
  func transcriptionEmptyResponseFailsClosed() async throws {
    let response = HTTPURLResponse(
      url: URL(string: "https://example.test/v1/audio/transcriptions")!, statusCode: 200,
      httpVersion: nil, headerFields: ["Content-Type": "application/json"]
    )!
    StubURLProtocol.response = (response, Data(#"{"text":"  "}"#.utf8))
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    let session = URLSession(configuration: configuration)
    let audioURL = FileManager.default.temporaryDirectory.appendingPathComponent("woice-empty.wav")
    try Data([0, 1, 2, 3]).write(to: audioURL)
    defer { try? FileManager.default.removeItem(at: audioURL) }

    do {
      _ = try await TranscriptionClient(session: session).transcribe(
        audioURL: audioURL,
        endpoint: "https://example.test/v1",
        apiKey: "",
        model: "whisper-test",
        language: "zh"
      )
      Issue.record("空 ASR 响应不应被当成成功结果")
    } catch WoiceError.invalidResponse {
      // 预期：空原文必须 fail-closed，避免生成“成功但无内容”的 Artifact。
    } catch {
      Issue.record("空 ASR 响应返回了错误类型：\(error)")
    }
  }

  @Test("LLM 客户端发送 OpenAI-compatible JSON 并读取 Markdown")
  func llmRequestContract() async throws {
    let response = HTTPURLResponse(
      url: URL(string: "https://example.test/v1/chat/completions")!, statusCode: 200,
      httpVersion: nil, headerFields: ["Content-Type": "application/json"]
    )!
    StubURLProtocol.response = (
      response,
      Data(
        "{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"# 要点\\n\\n- 完成\"}}]}".utf8
      )
    )
    StubURLProtocol.lastRequest = nil
    StubURLProtocol.lastBody = nil
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    let session = URLSession(configuration: configuration)

    let markdown = try await LLMClient(session: session).generateMarkdown(
      transcript: "原始口述",
      endpoint: "https://example.test/v1",
      apiKey: "llm-secret",
      model: "gpt-test"
    )

    #expect(markdown.contains("完成"))
    let request = try #require(StubURLProtocol.lastRequest)
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer llm-secret")
    #expect(request.url?.path == "/v1/chat/completions")
    let body =
      try JSONSerialization.jsonObject(with: try #require(bodyData(for: request))) as? [String: Any]
    #expect(body?["model"] as? String == "gpt-test")
    #expect(
      (body?["messages"] as? [[String: Any]])?.contains { $0["content"] as? String == "原始口述" }
        == true)
  }

  @Test("Markdown 导出同时保留原文和 AI 笔记")
  func markdownKeepsRawTranscript() {
    let markdown = MarkdownRenderer.render(
      title: "测试录音", transcript: "原始口述不可覆盖", generatedMarkdown: "- AI 要点")
    #expect(markdown.contains("## 原文\n\n原始口述不可覆盖"))
    #expect(markdown.contains("## AI 笔记\n\n- AI 要点"))
  }

  @Test("Markdown 导出清理 Whisper 协议 token")
  func markdownProjectionRemovesWhisperTokens() {
    let markdown = MarkdownRenderer.render(
      title: "测试录音",
      transcript: "<|startoftranscript|><|0.00|>原文<|2.00|><|endoftext|>",
      generatedMarkdown: nil
    )
    #expect(markdown.contains("## 原文\n\n原文"))
    #expect(!markdown.contains("<|"))
  }

  @Test("转写 Fixture 是可读取的 WAV")
  func transcriptionFixtureIsReadableWAV() throws {
    let url = try makeFixtureWAV(named: "woice-valid-fixture.wav")
    defer { try? FileManager.default.removeItem(at: url) }
    let file = try AVAudioFile(forReading: url)
    #expect(file.fileFormat.sampleRate == 44_100)
    #expect(file.length > 4_000)
  }
}

private func bodyData(for request: URLRequest) -> Data? {
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

private func makeFixtureWAV(named name: String) throws -> URL {
  let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
  try? FileManager.default.removeItem(at: url)
  let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
  let file = try AVAudioFile(forWriting: url, settings: format.settings)
  let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_410))
  buffer.frameLength = 4_410
  for frame in 0..<4_410 {
    buffer.floatChannelData![0][frame] = Float(sin(Double(frame) * 0.02)) * 0.05
  }
  try file.write(from: buffer)
  return url
}
