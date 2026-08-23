import CryptoKit
import Foundation
import Testing
import WoiceCore

@testable import WoiceApp

private final class ModelCatalogDownloadStubURLProtocol: URLProtocol {
  nonisolated(unsafe) static var files: [String: Data] = [:]

  override class func canInit(with request: URLRequest) -> Bool { true }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    let path = request.url?.path ?? ""
    guard let data = Self.files[path], let url = request.url,
      let response = HTTPURLResponse(
        url: url, statusCode: 200, httpVersion: nil,
        headerFields: ["Content-Type": "application/octet-stream"])
    else {
      client?.urlProtocol(
        self, didFailWithError: NSError(domain: "ModelCatalogDownloadStub", code: 404))
      return
    }
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: data)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

@Suite(.serialized)
struct ModelCatalogDownloadTests {
  @Test("已验证 Catalog 条目按多文件 manifest 下载并原子安装")
  func catalogEntryDownloadsMultipleFiles() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("woice-catalog-download-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let first = Data("first-model-file".utf8)
    let second = Data("second-model-file".utf8)
    ModelCatalogDownloadStubURLProtocol.files = [
      "/packs/weights.bin": first,
      "/packs/config.json": second,
    ]
    let firstFile = try ModelPackFile(
      relativePath: "weights.bin", byteCount: Int64(first.count), sha256: digest(first))
    let secondFile = try ModelPackFile(
      relativePath: "config.json", byteCount: Int64(second.count), sha256: digest(second))
    let manifest = try ModelPackManifest(
      packID: "com.woice.test.catalog",
      modelID: "test-model",
      version: "v1",
      providerID: "com.woice.whisperkit",
      files: [firstFile, secondFile],
      license: ModelPackLicense(
        identifier: "MIT", noticePath: "config.json", sourceURL: "https://example.test/source"),
      size: Int64(first.count + second.count),
      downloadBaseURL: "https://models.example.test/packs")
    let catalog = try ModelCatalog(
      catalogID: "com.woice.test.catalog",
      generatedAt: Date(),
      entries: [manifest])
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ModelCatalogDownloadStubURLProtocol.self]
    let downloader = ModelCatalogDownloadCoordinator(
      rootURL: root, session: URLSession(configuration: configuration))
    let staging = root.appendingPathComponent(
      "downloads/\(manifest.packID)-\(manifest.version).partial", isDirectory: true)
    try FileManager.default.createDirectory(
      at: staging, withIntermediateDirectories: true)
    try Data(repeating: 0, count: first.count).write(
      to: staging.appendingPathComponent("weights.bin"))

    let installed = try await downloader.download(
      catalog: catalog,
      packID: manifest.packID,
      version: manifest.version,
      allowedHosts: ["models.example.test"])

    #expect(
      FileManager.default.fileExists(atPath: installed.appendingPathComponent("weights.bin").path))
    #expect(
      FileManager.default.fileExists(atPath: installed.appendingPathComponent("config.json").path))
    let inventory = try await ModelPackStore(rootURL: root).inventory()
    #expect(inventory.count == 1)
    #expect(inventory.first?.manifest == manifest)
  }

  @Test("Catalog 模型下载拒绝缺失地址和未允许主机")
  func catalogEntryFailsClosedBeforeNetwork() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("woice-catalog-download-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let data = Data("model".utf8)
    let file = try ModelPackFile(
      relativePath: "weights.bin", byteCount: Int64(data.count), sha256: digest(data))
    #expect(throws: ModelPackValidationError.invalidDownloadBaseURL) {
      _ = try ModelPackManifest(
        packID: "com.woice.test.http",
        modelID: "test-model",
        version: "v1",
        providerID: "com.woice.whisperkit",
        files: [file],
        license: ModelPackLicense(
          identifier: "MIT", noticePath: "weights.bin", sourceURL: "https://example.test/source"),
        size: Int64(data.count),
        downloadBaseURL: "http://models.example.test/packs")
    }
    let base = try ModelPackManifest(
      packID: "com.woice.test.catalog",
      modelID: "test-model",
      version: "v1",
      providerID: "com.woice.whisperkit",
      files: [file],
      license: ModelPackLicense(
        identifier: "MIT", noticePath: "weights.bin", sourceURL: "https://example.test/source"),
      size: Int64(data.count))
    let unsafeHost = try ModelPackManifest(
      packID: base.packID,
      modelID: base.modelID,
      version: base.version,
      providerID: base.providerID,
      files: base.files,
      license: base.license,
      size: base.size,
      downloadBaseURL: "https://other.example.test/packs")
    let missingCatalog = try ModelCatalog(
      catalogID: "com.woice.test.catalog", generatedAt: Date(), entries: [base])
    let unsafeCatalog = try ModelCatalog(
      catalogID: "com.woice.test.catalog", generatedAt: Date(), entries: [unsafeHost])
    let downloader = ModelCatalogDownloadCoordinator(rootURL: root)

    await #expect(throws: ModelCatalogDownloadError.missingDownloadBaseURL(base.packID)) {
      try await downloader.download(
        catalog: missingCatalog, packID: base.packID, allowedHosts: ["models.example.test"])
    }
    await #expect(throws: ModelCatalogDownloadError.disallowedDownloadHost("other.example.test")) {
      try await downloader.download(
        catalog: unsafeCatalog, packID: base.packID, allowedHosts: ["models.example.test"])
    }
    #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Models").path))
  }

  private func digest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}
