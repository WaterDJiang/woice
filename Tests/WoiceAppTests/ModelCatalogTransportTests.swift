import Foundation
import Testing
import WoiceCore

private final class CatalogStubURLProtocol: URLProtocol {
  nonisolated(unsafe) static var response: (HTTPURLResponse, Data) = {
    let url = URL(string: "https://catalog.example.test/models.json")!
    return (
      HTTPURLResponse(
        url: url, statusCode: 200, httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
      )!,
      Data(#"{"catalog":true}"#.utf8)
    )
  }()
  nonisolated(unsafe) static var lastRequest: URLRequest?

  override class func canInit(with request: URLRequest) -> Bool { true }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    Self.lastRequest = request
    let (response, data) = Self.response
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: data)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

@Suite(.serialized)
struct ModelCatalogTransportTests {
  @Test("Catalog Fetcher 只发送受限 HTTPS GET")
  func fetcherUsesBoundedHTTPSRequest() async throws {
    let url = URL(string: "https://catalog.example.test/models.json")!
    CatalogStubURLProtocol.response = (
      HTTPURLResponse(
        url: url, statusCode: 200, httpVersion: nil,
        headerFields: ["Content-Type": "application/json; charset=utf-8"]
      )!,
      Data(#"{"catalog":true}"#.utf8)
    )
    CatalogStubURLProtocol.lastRequest = nil
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [CatalogStubURLProtocol.self]
    let session = URLSession(configuration: configuration)

    let data = try await ModelCatalogFetcher(session: session).fetch(
      from: url, policy: ModelCatalogFetchPolicy(allowedHosts: ["catalog.example.test"]))

    #expect(data == Data(#"{"catalog":true}"#.utf8))
    let request = try #require(CatalogStubURLProtocol.lastRequest)
    #expect(request.httpMethod == "GET")
    #expect(request.httpBody == nil)
    #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
  }

  @Test("Catalog Fetcher 兼容 GitHub Raw 的 text/plain JSON")
  func fetcherAcceptsGitHubRawContentType() async throws {
    let url = URL(string: "https://raw.githubusercontent.com/example/catalog.json")!
    CatalogStubURLProtocol.response = (
      HTTPURLResponse(
        url: url, statusCode: 200, httpVersion: nil,
        headerFields: ["Content-Type": "text/plain; charset=utf-8"]
      )!,
      Data(#"{"catalog":true}"#.utf8)
    )
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [CatalogStubURLProtocol.self]
    let client = ModelCatalogFetcher(session: URLSession(configuration: configuration))

    let data = try await client.fetch(
      from: url, policy: ModelCatalogFetchPolicy(allowedHosts: ["raw.githubusercontent.com"]))

    #expect(data == Data(#"{"catalog":true}"#.utf8))
  }

  @Test("Catalog Fetcher 拒绝不安全地址、凭据和未允许主机")
  func fetcherRejectsUnsafeURLsWithoutRequest() async {
    let policy = ModelCatalogFetchPolicy(allowedHosts: ["catalog.example.test"])
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [CatalogStubURLProtocol.self]
    let client = ModelCatalogFetcher(session: URLSession(configuration: configuration))
    CatalogStubURLProtocol.lastRequest = nil

    await #expect(
      throws: ModelCatalogTransportError.disallowedURL("http://catalog.example.test/models.json")
    ) {
      try await client.fetch(
        from: URL(string: "http://catalog.example.test/models.json")!, policy: policy)
    }
    await #expect(
      throws: ModelCatalogTransportError.disallowedURL("https://other.example.test/models.json")
    ) {
      try await client.fetch(
        from: URL(string: "https://other.example.test/models.json")!, policy: policy)
    }
    await #expect(
      throws: ModelCatalogTransportError.disallowedURL(
        "https://user:pass@catalog.example.test/models.json")
    ) {
      try await client.fetch(
        from: URL(string: "https://user:pass@catalog.example.test/models.json")!, policy: policy)
    }
    #expect(CatalogStubURLProtocol.lastRequest == nil)
  }

  @Test("Catalog Fetcher 拒绝重定向、非 JSON 和超限响应")
  func fetcherFailsClosedOnResponseBoundary() async {
    let url = URL(string: "https://catalog.example.test/models.json")!
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [CatalogStubURLProtocol.self]
    let client = ModelCatalogFetcher(session: URLSession(configuration: configuration))
    let policy = ModelCatalogFetchPolicy(
      allowedHosts: ["catalog.example.test"], maxResponseBytes: 4)

    CatalogStubURLProtocol.response = (
      HTTPURLResponse(
        url: URL(string: "https://other.example.test/models.json")!, statusCode: 200,
        httpVersion: nil, headerFields: ["Content-Type": "application/json"]
      )!,
      Data("{}".utf8)
    )
    await #expect(
      throws: ModelCatalogTransportError.redirected(
        from: url.absoluteString, to: "https://other.example.test/models.json")
    ) {
      try await client.fetch(from: url, policy: policy)
    }

    CatalogStubURLProtocol.response = (
      HTTPURLResponse(
        url: url, statusCode: 200, httpVersion: nil,
        headerFields: ["Content-Type": "text/html", "Content-Length": "2"]
      )!,
      Data("{}".utf8)
    )
    await #expect(throws: ModelCatalogTransportError.invalidContentType("text/html")) {
      try await client.fetch(from: url, policy: policy)
    }

    CatalogStubURLProtocol.response = (
      HTTPURLResponse(
        url: url, statusCode: 200, httpVersion: nil,
        headerFields: ["Content-Type": "application/json", "Content-Length": "5"]
      )!,
      Data("12345".utf8)
    )
    await #expect(throws: ModelCatalogTransportError.responseTooLarge(5)) {
      try await client.fetch(from: url, policy: policy)
    }
  }
}
