import CryptoKit
import Foundation
import Testing
import WoiceCore

@testable import WoiceApp

private final class ModelPackFixtureURLProtocol: URLProtocol {
  private final class State: @unchecked Sendable {
    let lock = NSLock()
    var payloads: [String: Data] = [:]
    var ranges: [String] = []
  }

  private static let state = State()

  static func configure(payloads: [String: Data]) {
    state.lock.lock()
    state.payloads = payloads
    state.ranges = []
    state.lock.unlock()
  }

  static func requestedRanges() -> [String] {
    state.lock.lock()
    defer { state.lock.unlock() }
    return state.ranges
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func stopLoading() {}

  override func startLoading() {
    guard let url = request.url, let client else { return }
    let key = url.path
    Self.state.lock.lock()
    let payload = Self.state.payloads[key]
    let range = request.value(forHTTPHeaderField: "Range")
    if let range { Self.state.ranges.append(range) }
    Self.state.lock.unlock()
    guard let payload else {
      client.urlProtocol(
        self,
        didFailWithError: NSError(domain: "ModelPackFixtureURLProtocol", code: 404))
      return
    }
    let start: Int
    if let range, let value = range.split(separator: "=").last,
      let offset = Int(value.split(separator: "-").first ?? "")
    {
      start = min(max(offset, 0), payload.count)
    } else {
      start = 0
    }
    let body = Data(payload.dropFirst(start))
    let status = start > 0 ? 206 : 200
    let response = HTTPURLResponse(
      url: url,
      statusCode: status,
      httpVersion: "HTTP/1.1",
      headerFields: [
        "Content-Length": String(body.count),
        "Content-Range": "bytes \(start)-\(max(start, payload.count - 1))/\(payload.count)",
      ])!
    client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client.urlProtocol(self, didLoad: body)
    client.urlProtocolDidFinishLoading(self)
  }
}

private func storeFixtureManifest(
  data: Data,
  version: String = "1.0.0",
  providerID: String = "com.woice.fixture.provider"
) throws -> ModelPackManifest {
  let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  let file = try ModelPackFile(
    relativePath: "weights/model.bin", byteCount: Int64(data.count), sha256: hash)
  let license = try ModelPackLicense(
    identifier: "MIT", noticePath: "LICENSE", sourceURL: "https://example.com/model")
  return try ModelPackManifest(
    packID: "com.woice.fixture.model",
    modelID: "fixture-model",
    version: version,
    providerID: providerID,
    files: [file],
    license: license,
    size: Int64(data.count))
}

@Test("模型包安装在所有校验通过后原子提交 current 指针")
func modelPackStoreInstallsAndIndexesCurrentVersion() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "woice-model-store-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let source = root.appendingPathComponent("source", isDirectory: true)
  try FileManager.default.createDirectory(
    at: source.appendingPathComponent("weights", isDirectory: true),
    withIntermediateDirectories: true)
  let bytes = Data(repeating: 0x42, count: 128)
  try bytes.write(to: source.appendingPathComponent("weights/model.bin"))
  let manifest = try storeFixtureManifest(data: bytes)
  let store = ModelPackStore(rootURL: root)

  let installedURL = try await store.install(manifest: manifest, from: source)
  #expect(
    FileManager.default.fileExists(
      atPath: installedURL.appendingPathComponent("manifest.json").path))
  let current = try await store.currentManifest(packID: manifest.packID)
  #expect(current == manifest)
  let entries = try await store.inventory()
  #expect(entries.count == 1)
  #expect(entries.first?.isCurrent == true)
  #expect(entries.first?.location == .downloaded)
  #expect(entries.first?.state == .installed)
}

@Test("模型包只允许删除非当前下载版本")
func modelPackStoreDeletesOnlyNonCurrentDownloadedVersion() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "woice-model-delete-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let modelStore = ModelPackStore(rootURL: root)

  func install(version: String, byte: UInt8) async throws -> ModelPackManifest {
    let source = root.appendingPathComponent("source-\(version)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: source.appendingPathComponent("weights", isDirectory: true),
      withIntermediateDirectories: true)
    let bytes = Data(repeating: byte, count: 32)
    try bytes.write(to: source.appendingPathComponent("weights/model.bin"))
    let manifest = try storeFixtureManifest(data: bytes, version: version)
    _ = try await modelStore.install(manifest: manifest, from: source)
    return manifest
  }

  let oldManifest = try await install(version: "1.0.0", byte: 0x31)
  let currentManifest = try await install(version: "2.0.0", byte: 0x32)
  try await modelStore.deleteDownloaded(manifest: oldManifest)
  #expect(
    try await modelStore.inventory().map { $0.manifest.version } == [currentManifest.version])
  await #expect(
    throws: ModelPackStoreError.cannotDeleteCurrent(
      currentManifest.packID + "/" + currentManifest.version)
  ) {
    try await modelStore.deleteDownloaded(manifest: currentManifest)
  }
}

@Test("模型包校验失败时不产生已安装事实")
func modelPackStoreFailsClosedOnChecksumMismatch() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "woice-model-store-fail-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let source = root.appendingPathComponent("source", isDirectory: true)
  try FileManager.default.createDirectory(
    at: source.appendingPathComponent("weights", isDirectory: true),
    withIntermediateDirectories: true)
  let bytes = Data(repeating: 0x24, count: 64)
  try bytes.write(to: source.appendingPathComponent("weights/model.bin"))
  let wrongFile = try ModelPackFile(
    relativePath: "weights/model.bin", byteCount: Int64(bytes.count),
    sha256: String(repeating: "0", count: 64))
  let license = try ModelPackLicense(
    identifier: "MIT", noticePath: "LICENSE", sourceURL: "https://example.com/model")
  let manifest = try ModelPackManifest(
    packID: "com.woice.fixture.model",
    modelID: "fixture-model",
    version: "1.0.1",
    providerID: "com.woice.fixture.provider",
    files: [wrongFile],
    license: license,
    size: Int64(bytes.count))
  let store = ModelPackStore(rootURL: root)

  await #expect(throws: ModelPackStoreError.checksumMismatch("weights/model.bin")) {
    try await store.install(manifest: manifest, from: source)
  }
  #expect(try await store.currentManifest(packID: manifest.packID) == nil)
  #expect(try await store.inventory().isEmpty)
}

@Test("模型包拒绝符号链接文件")
func modelPackStoreRejectsSymbolicLinks() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "woice-model-store-link-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let source = root.appendingPathComponent("source", isDirectory: true)
  try FileManager.default.createDirectory(
    at: source.appendingPathComponent("weights", isDirectory: true),
    withIntermediateDirectories: true)
  let realFile = root.appendingPathComponent("outside.bin")
  let bytes = Data(repeating: 0x19, count: 32)
  try bytes.write(to: realFile)
  try FileManager.default.createSymbolicLink(
    at: source.appendingPathComponent("weights/model.bin"), withDestinationURL: realFile)
  let manifest = try storeFixtureManifest(data: bytes, version: "1.0.2")
  let store = ModelPackStore(rootURL: root)

  await #expect(throws: ModelPackStoreError.symbolicLink("weights/model.bin")) {
    try await store.install(manifest: manifest, from: source)
  }
}

@Test("WhisperKit Adapter 暴露清单中的 Provider、模型和版本")
func whisperKitAdapterPreservesModelSnapshot() throws {
  let bytes = Data(repeating: 0x77, count: 16)
  let manifest = try storeFixtureManifest(data: bytes, providerID: "com.woice.whisperkit")
  let service = try WhisperKitTranscriptionService(
    manifest: manifest,
    modelFolder: FileManager.default.temporaryDirectory.appendingPathComponent("missing-model"))
  #expect(service.model.providerID == "com.woice.whisperkit")
  #expect(service.model.modelID == manifest.modelID)
  #expect(service.model.version == manifest.version)
  #expect(service.model.dataLocation == .onDevice)
}

@Test("应用启动时使用当前已安装的 WhisperKit 模型包")
@MainActor
func appStateUsesCurrentInstalledWhisperKitPack() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "woice-model-startup-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let source = root.appendingPathComponent("source", isDirectory: true)
  try FileManager.default.createDirectory(
    at: source.appendingPathComponent("weights", isDirectory: true),
    withIntermediateDirectories: true)
  let bytes = Data(repeating: 0x51, count: 96)
  try bytes.write(to: source.appendingPathComponent("weights/model.bin"))
  let manifest = try storeFixtureManifest(
    data: bytes, providerID: "com.woice.whisperkit")
  let modelStore = ModelPackStore(rootURL: root)
  try await modelStore.install(manifest: manifest, from: source)

  // Arbitrary fixture packs are not eligible for automatic default selection;
  // this test represents the persisted explicit user choice contract.
  let workspaceStore = WorkspaceStore(storageRootURL: root)
  var settings = AppSettings.default
  settings.selectedLocalModelPackID = manifest.packID
  settings.selectedLocalModelVersion = manifest.version
  try workspaceStore.saveSettings(settings)
  let state = AppState(store: workspaceStore)
  #expect(state.localASRModel.providerID == "com.woice.whisperkit")
  #expect(state.localASRModel.modelID == manifest.modelID)
  #expect(state.localASRModel.version == manifest.version)
  #expect(state.localASRModel.dataLocation == .onDevice)
}

@Test("当前 WhisperKit 模型文件被篡改时回退到本机 Speech")
@MainActor
func corruptedCurrentWhisperKitPackFailsClosed() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "woice-model-corrupt-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let source = root.appendingPathComponent("source", isDirectory: true)
  try FileManager.default.createDirectory(
    at: source.appendingPathComponent("weights", isDirectory: true),
    withIntermediateDirectories: true)
  let bytes = Data(repeating: 0x61, count: 40)
  try bytes.write(to: source.appendingPathComponent("weights/model.bin"))
  let manifest = try storeFixtureManifest(
    data: bytes, version: "1.0.9", providerID: "com.woice.whisperkit")
  let store = ModelPackStore(rootURL: root)
  let installed = try await store.install(manifest: manifest, from: source)
  try Data(repeating: 0x62, count: bytes.count).write(
    to: installed.appendingPathComponent("weights/model.bin"))

  let state = AppState(store: WorkspaceStore(storageRootURL: root))
  #expect(state.localASRModel.providerID == "com.apple.speech.on-device")
}

@Test("用户选择的旧模型版本优先于 current 指针")
@MainActor
func appStateUsesPersistedLocalModelSelection() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "woice-model-selection-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let source = root.appendingPathComponent("source", isDirectory: true)
  try FileManager.default.createDirectory(
    at: source.appendingPathComponent("weights", isDirectory: true),
    withIntermediateDirectories: true)
  let bytes = Data(repeating: 0x4A, count: 48)
  try bytes.write(to: source.appendingPathComponent("weights/model.bin"))
  let first = try storeFixtureManifest(
    data: bytes, version: "1.0.0", providerID: "com.woice.whisperkit")
  let second = try storeFixtureManifest(
    data: bytes, version: "2.0.0", providerID: "com.woice.whisperkit")
  let modelStore = ModelPackStore(rootURL: root)
  _ = try await modelStore.install(manifest: first, from: source)
  _ = try await modelStore.install(manifest: second, from: source)

  let workspace = WorkspaceStore(storageRootURL: root)
  var settings = workspace.loadSettings()
  settings.selectedLocalModelPackID = first.packID
  settings.selectedLocalModelVersion = first.version
  try workspace.saveSettings(settings)

  let state = AppState(store: workspace)
  #expect(state.localASRModel.providerID == "com.woice.whisperkit")
  #expect(state.localASRModel.version == first.version)
}

@Test("Offline bundled 模型进入库存并可作为本机 Provider")
func bundledModelPackIsDiscoverableAndRoutable() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "woice-bundled-model-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let source = root.appendingPathComponent("source", isDirectory: true)
  try FileManager.default.createDirectory(
    at: source.appendingPathComponent("weights", isDirectory: true),
    withIntermediateDirectories: true)
  let bytes = Data(repeating: 0x3D, count: 56)
  try bytes.write(to: source.appendingPathComponent("weights/model.bin"))
  let manifest = try storeFixtureManifest(
    data: bytes, version: "1.0.0", providerID: "com.woice.whisperkit")
  try JSONEncoder.woice.encode(manifest).write(to: source.appendingPathComponent("manifest.json"))
  let bundledRoot = root.appendingPathComponent("Models", isDirectory: true)
    .appendingPathComponent(manifest.packID, isDirectory: true)
    .appendingPathComponent(manifest.version, isDirectory: true)
  try FileManager.default.createDirectory(at: bundledRoot, withIntermediateDirectories: true)
  for file in manifest.files {
    let sourceURL = source.appendingPathComponent(file.relativePath)
    let destinationURL = bundledRoot.appendingPathComponent(file.relativePath)
    try FileManager.default.createDirectory(
      at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
  }
  try FileManager.default.copyItem(
    at: source.appendingPathComponent("manifest.json"),
    to: bundledRoot.appendingPathComponent("manifest.json"))

  let store = ModelPackStore(
    rootURL: root.appendingPathComponent("Storage"),
    bundledRootURL: root.appendingPathComponent("Models"))
  let entries = try await store.inventory()
  #expect(entries.count == 1)
  #expect(entries.first?.location == .bundled)
  #expect(entries.first?.isCurrent == false)
  let verified = try await store.bundledDirectory(for: manifest)
  #expect(verified == bundledRoot)
  let provider = WhisperKitTranscriptionService.defaultProvider(
    rootURL: root.appendingPathComponent("Downloaded"),
    bundledRootURL: root.appendingPathComponent("Models"),
    preferredPackID: manifest.packID)
  #expect(provider.model.providerID == "com.woice.whisperkit")
  #expect(provider.model.version == manifest.version)
}

@Test("模型包下载支持显式触发和 HTTP Range 续传")
func modelPackDownloadResumesPartialFileBeforeAtomicInstall() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "woice-model-download-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let bytes = Data((0..<32).map(UInt8.init))
  let manifest = try storeFixtureManifest(
    data: bytes, version: "2.0.0", providerID: "com.woice.fixture.download")
  ModelPackFixtureURLProtocol.configure(
    payloads: ["/models/weights/model.bin": bytes])
  let configuration = URLSessionConfiguration.ephemeral
  configuration.protocolClasses = [ModelPackFixtureURLProtocol.self]
  let session = URLSession(configuration: configuration)
  let coordinator = ModelPackDownloadCoordinator(rootURL: root, session: session)
  let staging = try await coordinator.resumableStagingDirectory(for: manifest)
  let partialURL = staging.appendingPathComponent("weights/model.bin")
  try FileManager.default.createDirectory(
    at: partialURL.deletingLastPathComponent(), withIntermediateDirectories: true)
  try bytes.prefix(7).write(to: partialURL)

  let installed = try await coordinator.download(
    manifest: manifest, baseURL: URL(string: "https://fixture.invalid/models/")!)
  #expect(FileManager.default.fileExists(atPath: installed.path))
  #expect(
    try await ModelPackStore(rootURL: root).currentManifest(packID: manifest.packID) == manifest)
  #expect(ModelPackFixtureURLProtocol.requestedRanges() == ["bytes=7-"])
}

@Test("模型包下载拒绝非 HTTP(S) 地址")
func modelPackDownloadRejectsInvalidBaseURL() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "woice-model-download-invalid-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let bytes = Data(repeating: 0x08, count: 8)
  let manifest = try storeFixtureManifest(
    data: bytes, version: "2.0.1", providerID: "com.woice.fixture.download")
  let coordinator = ModelPackDownloadCoordinator(rootURL: root)
  await #expect(throws: ModelPackDownloadError.invalidBaseURL) {
    try await coordinator.download(
      manifest: manifest, baseURL: URL(fileURLWithPath: "/tmp/model"))
  }
}

@Test("从设置导入模型包后立即切换本机转写 Provider")
@MainActor
func importingModelPackUpdatesAppStateRoute() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "woice-model-import-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let source = root.appendingPathComponent("source", isDirectory: true)
  try FileManager.default.createDirectory(
    at: source.appendingPathComponent("weights", isDirectory: true),
    withIntermediateDirectories: true)
  let bytes = Data(repeating: 0x31, count: 48)
  try bytes.write(to: source.appendingPathComponent("weights/model.bin"))
  let manifest = try storeFixtureManifest(
    data: bytes, version: "3.0.0", providerID: "com.woice.whisperkit")
  try JSONEncoder.woice.encode(manifest).write(
    to: source.appendingPathComponent("manifest.json"))
  let state = AppState(store: WorkspaceStore(storageRootURL: root))

  #expect(await state.importModelPack(from: source))
  #expect(state.localASRModel.providerID == manifest.providerID)
  #expect(state.localASRModel.version == manifest.version)
  #expect(state.modelPackInventory.contains { $0.manifest.version == manifest.version })
}
