import Foundation

public struct TranscriptionResult: Equatable, Sendable {
  public let text: String
  public let segments: [TranscriptSegment]

  public init(text: String, segments: [TranscriptSegment] = []) {
    self.text = text
    self.segments = segments
  }
}

public struct ASRHealthCheckResult: Equatable, Sendable {
  public let statusCode: Int
  public let responseBytes: Int

  public init(statusCode: Int, responseBytes: Int) {
    self.statusCode = statusCode
    self.responseBytes = responseBytes
  }
}

public struct ASRDiscoveredModel: Codable, Equatable, Hashable, Sendable {
  public let id: String
  public let ownedBy: String?

  public init(id: String, ownedBy: String? = nil) {
    self.id = id
    self.ownedBy = ownedBy
  }
}

public enum ASRServiceDiscoveryPolicy {
  public static func allows(_ endpoint: String) -> Bool {
    guard let url = URL(string: endpoint.trimmingCharacters(in: .whitespacesAndNewlines)),
      let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
      let host = url.host?.lowercased()
    else { return false }
    if host == "localhost" || host == "127.0.0.1" || host == "::1" { return true }
    let parts = host.split(separator: ".").compactMap { Int($0) }
    guard parts.count == 4 else { return false }
    guard parts.allSatisfy({ (0...255).contains($0) }) else { return false }
    if parts[0] == 10 || parts[0] == 192 && parts[1] == 168 {
      return true
    }
    if parts[0] == 172 && (16...31).contains(parts[1]) {
      return true
    }
    return parts[0] == 169 && parts[1] == 254
  }
}

/// A UI-only starting point for common local OpenAI-compatible ASR servers.
/// Choosing a preset never proves that a server is installed or reachable.
public struct ASRServicePreset: Codable, Equatable, Hashable, Identifiable, Sendable {
  public let id: String
  public let displayName: String
  public let description: String
  public let endpoint: String
  public let model: String

  public init(
    id: String,
    displayName: String,
    description: String,
    endpoint: String,
    model: String
  ) {
    self.id = id
    self.displayName = displayName
    self.description = description
    self.endpoint = endpoint
    self.model = model
  }

  public var isSafeLocalEndpoint: Bool {
    guard let url = URL(string: endpoint),
      let scheme = url.scheme?.lowercased(),
      ["http", "https"].contains(scheme),
      url.user == nil,
      url.password == nil,
      url.query == nil,
      url.fragment == nil,
      let host = url.host?.lowercased()
    else { return false }
    return host == "localhost" || host == "127.0.0.1" || host == "::1"
  }

  /// Applies only the external ASR draft fields. Runtime settings and
  /// Keychain values are changed only when the caller later saves the draft.
  public func applying(to settings: AppSettings) -> AppSettings {
    var updated = settings
    updated.asrProviderSelection = .external
    updated.asrEndpoint = endpoint
    updated.asrModel = model
    return updated
  }

  public static let builtIns: [ASRServicePreset] = [
    ASRServicePreset(
      id: "generic-openai-compatible",
      displayName: "通用 OpenAI-compatible",
      description: "适用于提供 OpenAI-compatible /v1/audio/transcriptions 的本机服务",
      endpoint: "http://127.0.0.1:8000/v1",
      model: "whisper-1"),
    ASRServicePreset(
      id: "whisper-cpp-server",
      displayName: "whisper.cpp Server",
      description: "需要服务端启用 OpenAI-compatible HTTP 接口",
      endpoint: "http://127.0.0.1:8080/v1",
      model: "whisper-1"),
    ASRServicePreset(
      id: "faster-whisper-server",
      displayName: "faster-whisper Server",
      description: "需要服务端提供 OpenAI-compatible 转写路径",
      endpoint: "http://127.0.0.1:8000/v1",
      model: "whisper-1"),
    ASRServicePreset(
      id: "funasr-localai",
      displayName: "FunASR / LocalAI",
      description: "按服务实际模型 ID 修改后，再执行 OpenAI-compatible 健康检查",
      endpoint: "http://127.0.0.1:8080/v1",
      model: "whisper-1"),
  ]
}

public struct TranscriptionClient: @unchecked Sendable {
  private let session: URLSession

  public init(session: URLSession = .shared) {
    self.session = session
  }

  public func transcribe(
    audioURL: URL, endpoint: String, apiKey: String, model: String, language: String
  ) async throws -> String {
    try await transcribeDetailed(
      audioURL: audioURL, endpoint: endpoint, apiKey: apiKey, model: model, language: language,
      includeSegments: false
    ).text
  }

  public func transcribeDetailed(
    audioURL: URL, endpoint: String, apiKey: String, model: String, language: String,
    includeSegments: Bool
  ) async throws -> TranscriptionResult {
    let request = try makeTranscriptionRequest(
      audioURL: audioURL, endpoint: endpoint, apiKey: apiKey, model: model, language: language,
      includeSegments: includeSegments)
    let (data, response) = try await session.data(for: request)
    try validate(response: response, data: data)
    if let result = try? JSONDecoder().decode(TranscriptionResponse.self, from: data) {
      let segments = (result.segments ?? []).compactMap { segment -> TranscriptSegment? in
        let text = TranscriptTextNormalizer.normalize(segment.text)
        guard !text.isEmpty, segment.end >= segment.start else { return nil }
        return TranscriptSegment(start: max(0, segment.start), end: max(0, segment.end), text: text)
      }
      let text = TranscriptTextNormalizer.normalize(result.text)
      guard !text.isEmpty else { throw WoiceError.invalidResponse }
      return TranscriptionResult(
        text: text, segments: segments)
    }
    if let plain = String(data: data, encoding: .utf8) {
      let text = TranscriptTextNormalizer.normalize(plain)
      guard !text.isEmpty else { throw WoiceError.invalidResponse }
      return TranscriptionResult(text: text)
    }
    throw WoiceError.invalidResponse
  }

  public func checkConfiguration(
    audioURL: URL, endpoint: String, apiKey: String, model: String, language: String
  ) async throws -> ASRHealthCheckResult {
    let request = try makeTranscriptionRequest(
      audioURL: audioURL, endpoint: endpoint, apiKey: apiKey, model: model, language: language,
      includeSegments: false)
    let (data, response) = try await session.data(for: request)
    try validate(response: response, data: data)
    guard let http = response as? HTTPURLResponse else {
      throw WoiceError.invalidResponse
    }
    return ASRHealthCheckResult(statusCode: http.statusCode, responseBytes: data.count)
  }

  public func discoverModels(
    endpoint: String, apiKey: String, timeout: TimeInterval = 5
  ) async throws -> [ASRDiscoveredModel] {
    guard ASRServiceDiscoveryPolicy.allows(endpoint) else {
      throw WoiceError.discoveryRequiresLocalEndpoint(endpoint)
    }
    let url = try resolvedEndpoint(endpoint, suffix: "/models")
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.timeoutInterval = min(max(timeout, 0.1), 5)
    if !apiKey.isEmpty {
      request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    }
    let (data, response) = try await session.data(for: request)
    try validate(response: response, data: data)
    let payload = try JSONDecoder().decode(ASRModelsResponse.self, from: data)
    let models = payload.data.compactMap { item -> ASRDiscoveredModel? in
      let id = item.id.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !id.isEmpty else { return nil }
      return ASRDiscoveredModel(id: id, ownedBy: item.ownedBy)
    }
    guard !models.isEmpty else { throw WoiceError.invalidResponse }
    return models
  }

  private func makeTranscriptionRequest(
    audioURL: URL, endpoint: String, apiKey: String, model: String, language: String,
    includeSegments: Bool
  ) throws -> URLRequest {
    let url = try resolvedEndpoint(endpoint, suffix: "/audio/transcriptions")
    let boundary = "WoiceBoundary-\(UUID().uuidString)"
    var body = Data()
    appendField(name: "model", value: model, boundary: boundary, to: &body)
    if !language.isEmpty {
      appendField(name: "language", value: language, boundary: boundary, to: &body)
    }
    if includeSegments {
      appendField(name: "response_format", value: "verbose_json", boundary: boundary, to: &body)
    }
    let audioData = try Data(contentsOf: audioURL)
    appendFile(
      name: "file", filename: audioURL.lastPathComponent, mimeType: "audio/wav", data: audioData,
      boundary: boundary, to: &body)
    body.append(Data("--\(boundary)--\r\n".utf8))

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.httpBody = body
    request.timeoutInterval = 120
    request.setValue(
      "multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    if !apiKey.isEmpty { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
    return request
  }

  private func appendField(name: String, value: String, boundary: String, to body: inout Data) {
    body.append(Data("--\(boundary)\r\n".utf8))
    body.append(
      Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
  }

  private func appendFile(
    name: String, filename: String, mimeType: String, data: Data, boundary: String,
    to body: inout Data
  ) {
    body.append(Data("--\(boundary)\r\n".utf8))
    body.append(
      Data("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".utf8))
    body.append(Data("Content-Type: \(mimeType)\r\n\r\n".utf8))
    body.append(data)
    body.append(Data("\r\n".utf8))
  }
}

private struct ASRModelsResponse: Decodable {
  let data: [ASRModelResponse]
}

private struct ASRModelResponse: Decodable {
  let id: String
  let ownedBy: String?

  private enum CodingKeys: String, CodingKey {
    case id
    case ownedBy = "owned_by"
  }
}

public struct LLMClient: @unchecked Sendable {
  private let session: URLSession

  public init(session: URLSession = .shared) {
    self.session = session
  }

  public func generateMarkdown(
    transcript: String, endpoint: String, apiKey: String, model: String
  ) async throws -> String {
    let url = try resolvedEndpoint(endpoint, suffix: "/chat/completions")
    let payload = ChatRequest(
      model: model,
      messages: [
        .init(
          role: "system",
          content:
            "你是一个克制的会议记录助手。请把原文整理为 Markdown，保留事实，不编造信息。输出标题、三条以内要点和待办；没有待办时写‘暂无’。"),
        .init(role: "user", content: transcript),
      ],
      temperature: 0.2
    )
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 120
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    if !apiKey.isEmpty { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
    request.httpBody = try JSONEncoder().encode(payload)
    let (data, response) = try await session.data(for: request)
    try validate(response: response, data: data)
    let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
    guard let content = decoded.choices.first?.message.content, !content.isEmpty else {
      throw WoiceError.invalidResponse
    }
    return content.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

private struct TranscriptionResponse: Decodable {
  let text: String
  let segments: [TranscriptionSegmentResponse]?
}

private struct TranscriptionSegmentResponse: Decodable {
  let start: TimeInterval
  let end: TimeInterval
  let text: String
}

private struct ChatRequest: Encodable {
  let model: String
  let messages: [ChatMessage]
  let temperature: Double
}

private struct ChatMessage: Codable {
  let role: String
  let content: String
}

private struct ChatResponse: Decodable {
  struct Choice: Decodable {
    let message: ChatMessage
  }

  let choices: [Choice]
}

private func resolvedEndpoint(_ endpoint: String, suffix: String) throws -> URL {
  let value = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
  guard let url = URL(string: value),
    let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
    url.host != nil
  else {
    throw WoiceError.invalidEndpoint(endpoint)
  }

  let path = url.path.hasSuffix("/") ? String(url.path.dropLast()) : url.path
  guard !path.hasSuffix(suffix) else { return url }
  guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
    throw WoiceError.invalidEndpoint(endpoint)
  }
  components.path = path + suffix
  guard let resolved = components.url else { throw WoiceError.invalidEndpoint(endpoint) }
  return resolved
}

private func validate(response: URLResponse, data: Data) throws {
  guard let http = response as? HTTPURLResponse else { throw WoiceError.invalidResponse }
  guard (200..<300).contains(http.statusCode) else {
    let body = String(data: data, encoding: .utf8) ?? "无法读取错误内容"
    throw WoiceError.apiFailure(status: http.statusCode, body: String(body.prefix(500)))
  }
}
