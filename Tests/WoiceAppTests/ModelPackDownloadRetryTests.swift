import CryptoKit
import Foundation
import Testing
import WoiceCore

@testable import WoiceApp

private final class RetryingModelPackURLProtocol: URLProtocol {
  private final class State: @unchecked Sendable {
    let lock = NSLock()
    var payload = Data()
    var failuresRemaining = 0
    var requestCount = 0
  }

  private static let state = State()

  static func configure(payload: Data, failures: Int) {
    state.lock.lock()
    state.payload = payload
    state.failuresRemaining = failures
    state.requestCount = 0
    state.lock.unlock()
  }

  static func requestCount() -> Int {
    state.lock.lock()
    defer { state.lock.unlock() }
    return state.requestCount
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func stopLoading() {}

  override func startLoading() {
    guard let client else { return }
    Self.state.lock.lock()
    Self.state.requestCount += 1
    let shouldFail = Self.state.failuresRemaining > 0
    if shouldFail { Self.state.failuresRemaining -= 1 }
    let payload = Self.state.payload
    Self.state.lock.unlock()

    if shouldFail {
      client.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
      return
    }

    let response = HTTPURLResponse(
      url: request.url!,
      statusCode: 200,
      httpVersion: "HTTP/1.1",
      headerFields: ["Content-Length": String(payload.count)])!
    client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client.urlProtocol(self, didLoad: payload)
    client.urlProtocolDidFinishLoading(self)
  }
}

@Test("模型包传输错误会重试并继续原子安装")
func modelPackDownloadRetriesTransientTransportFailure() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "woice-model-download-retry-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }

  let payload = Data((0..<64).map(UInt8.init))
  let hash = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
  let file = try ModelPackFile(
    relativePath: "weights/model.bin", byteCount: Int64(payload.count), sha256: hash)
  let manifest = try ModelPackManifest(
    packID: "com.woice.fixture.retry",
    modelID: "fixture-retry-model",
    version: "1.0.0",
    providerID: "com.woice.fixture.download",
    files: [file],
    license: try ModelPackLicense(
      identifier: "MIT", noticePath: "LICENSE", sourceURL: "https://example.com/model"),
    size: Int64(payload.count))

  RetryingModelPackURLProtocol.configure(payload: payload, failures: 1)
  let configuration = URLSessionConfiguration.ephemeral
  configuration.protocolClasses = [RetryingModelPackURLProtocol.self]
  let coordinator = ModelPackDownloadCoordinator(
    rootURL: root, session: URLSession(configuration: configuration))

  let installed = try await coordinator.download(
    manifest: manifest, baseURL: URL(string: "https://fixture.invalid/models/")!)

  #expect(FileManager.default.fileExists(atPath: installed.path))
  #expect(RetryingModelPackURLProtocol.requestCount() == 2)
  #expect(
    try await ModelPackStore(rootURL: root).currentManifest(packID: manifest.packID) == manifest)
}
