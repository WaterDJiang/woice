import Foundation
import Testing
import WoiceCore

@testable import WoiceApp

private let fixtureFile = try! ModelPackFile(
  relativePath: "weights/model.bin",
  byteCount: 128,
  sha256: String(repeating: "a", count: 64))

private let fixtureLicense = try! ModelPackLicense(
  identifier: "MIT",
  noticePath: "LICENSES/WhisperKit.txt",
  sourceURL: "https://example.com/model")

private func fixtureManifest() throws -> ModelPackManifest {
  try ModelPackManifest(
    packID: "com.woice.whisper.large-v3",
    modelID: "large-v3",
    version: "20240930",
    providerID: "com.woice.whisperkit",
    capabilities: [.transcription, .timestamps],
    files: [fixtureFile],
    license: fixtureLicense,
    size: 128)
}

@Test("模型包清单可编码解码并保留模型版本与能力")
func modelPackManifestRoundTrips() throws {
  let manifest = try fixtureManifest()
  let data = try JSONEncoder.woice.encode(manifest)
  let decoded = try JSONDecoder.woice.decode(ModelPackManifest.self, from: data)
  #expect(decoded == manifest)
  #expect(decoded.version == "20240930")
  #expect(decoded.capabilities.contains(.timestamps))
}

@Test("模型包清单拒绝路径穿越、重复文件和错误哈希")
func modelPackManifestRejectsUnsafeFiles() throws {
  #expect(throws: ModelPackValidationError.pathTraversal("../weights.bin")) {
    try ModelPackFile(
      relativePath: "../weights.bin", byteCount: 1, sha256: String(repeating: "a", count: 64))
  }
  #expect(throws: ModelPackValidationError.invalidSHA256("weights.bin")) {
    try ModelPackFile(relativePath: "weights.bin", byteCount: 1, sha256: "not-a-hash")
  }
  let duplicateFiles = [fixtureFile, fixtureFile]
  #expect(throws: ModelPackValidationError.duplicateFile("weights/model.bin")) {
    try ModelPackManifest(
      packID: "com.woice.whisper.large-v3",
      modelID: "large-v3",
      version: "20240930",
      providerID: "com.woice.whisperkit",
      files: duplicateFiles,
      license: fixtureLicense,
      size: 256)
  }
}

@Test("模型文件可携带同一受信主机的逐文件 HTTPS 下载地址")
func modelPackFileSupportsDirectDownloadURL() throws {
  let file = try ModelPackFile(
    relativePath: "weights/model.bin",
    byteCount: 128,
    sha256: String(repeating: "a", count: 64),
    downloadURL: "https://huggingface.co/example/model/resolve/revision/weights/model.bin")
  let decoded = try JSONDecoder.woice.decode(
    ModelPackFile.self,
    from: JSONEncoder.woice.encode(file))
  #expect(decoded == file)
  #expect(decoded.downloadURL?.hasPrefix("https://huggingface.co/") == true)

  #expect(throws: ModelPackValidationError.invalidDownloadURL("http://huggingface.co/model")) {
    try ModelPackFile(
      relativePath: "weights/model.bin",
      byteCount: 128,
      sha256: String(repeating: "a", count: 64),
      downloadURL: "http://huggingface.co/model")
  }
}

@Test("发行清单区分 Core 与 Offline 且禁止 Core 随包模型")
func distributionManifestValidatesFlavor() throws {
  let core = try DistributionManifest(
    flavor: .core, appVersion: "1.0.0", buildVersion: "1", bundledModelPackIDs: [])
  #expect(core.flavor == .core)
  #expect(throws: ModelPackValidationError.coreCannotBundleModels) {
    try DistributionManifest(
      flavor: .core,
      appVersion: "1.0.0",
      buildVersion: "1",
      bundledModelPackIDs: ["com.woice.whisper.large-v3"])
  }
  let offline = try DistributionManifest(
    flavor: .offline,
    appVersion: "1.0.0",
    buildVersion: "1",
    bundledModelPackIDs: ["com.woice.whisper.large-v3"])
  #expect(offline.bundledModelPackIDs.count == 1)
  let store = try DistributionManifest(
    flavor: .store,
    appVersion: "1.0.0",
    buildVersion: "1",
    bundledModelPackIDs: ["com.woice.whisper.large-v3"])
  #expect(store.flavor == .store)
}

@Test("Store 模型清单必须保留来源与格式转换链")
func storeModelManifestRequiresProvenance() throws {
  #expect(throws: ModelPackValidationError.missingStoreProvenance) {
    try ModelPackManifest(
      packID: "com.woice.store.model",
      modelID: "store-model",
      version: "1.0.0",
      providerID: "com.woice.store.runtime",
      files: [fixtureFile],
      license: fixtureLicense,
      size: fixtureFile.byteCount,
      storeCompatible: true,
      runtimeID: "com.woice.store.runtime")
  }
}

@Test("Runtime admission 允许受信 Qwen，并拒绝非进程模型")
func modelRuntimeAdmissionChecksTransportAndCapability() throws {
  let qwen = try ModelPackManifest(
    packID: "com.woice.qwen.fixture",
    modelID: "qwen3-asr",
    version: "fixture",
    providerID: "com.woice.qwen3-asr",
    transport: .inProcess,
    capabilities: [.transcription, .timestamps],
    files: [fixtureFile],
    license: fixtureLicense,
    size: fixtureFile.byteCount,
    provenance: try ModelPackProvenance(
      upstreamModelID: "Qwen/Qwen3-ASR-0.6B-hf",
      upstreamRevision: "fixture-revision",
      sourceURL: "https://huggingface.co/Qwen/Qwen3-ASR-0.6B-hf",
      derivedFormat: "fixture",
      conversionTool: "fixture-converter",
      conversionRevision: "1"),
    storeCompatible: true,
    runtimeID: "com.woice.qwen3-asr")
  #expect(ModelRuntimeRegistry.admission(for: qwen).isAdmitted)

  let externalWhisper = try ModelPackManifest(
    packID: "com.woice.whisper.external",
    modelID: "whisper",
    version: "fixture",
    providerID: "com.woice.whisperkit",
    transport: .controlledProcess,
    files: [fixtureFile],
    license: fixtureLicense,
    size: fixtureFile.byteCount)
  #expect(!ModelRuntimeRegistry.admission(for: externalWhisper).isAdmitted)
}

@Test("Qwen3-ASR 模型清单固定派生来源、SHA 和本机 Runtime")
func qwen3ModelCatalogManifestIsPinned() throws {
  let manifest = Qwen3ASRModelCatalogEntry.recommended.manifest
  #expect(manifest.packID == Qwen3ASRModelCatalogEntry.packID)
  #expect(manifest.version == Qwen3ASRModelCatalogEntry.derivedRevision)
  #expect(manifest.providerID == "com.woice.qwen3-asr")
  #expect(manifest.license.identifier == "Apache-2.0")
  #expect(manifest.storeCompatible)
  #expect(manifest.runtimeID == "com.woice.qwen3-asr")
  #expect(manifest.size == Qwen3ASRModelCatalogEntry.estimatedBytes)
  #expect(manifest.provenance?.upstreamRevision == Qwen3ASRModelCatalogEntry.upstreamRevision)
  let files = Dictionary(uniqueKeysWithValues: manifest.files.map { ($0.relativePath, $0) })
  #expect(files.count == 5)
  #expect(files["model.safetensors"]?.byteCount == 708_236_945)
  #expect(
    files["model.safetensors"]?.sha256
      == "70c7e67e588062adce4f10796e47ad42ead51c6671eda61a0987eae38ca95ddf")
  #expect(files["merges.txt"]?.byteCount == 1_671_853)
  #expect(files["vocab.json"]?.byteCount == 2_776_833)
  #expect(files["tokenizer_config.json"]?.byteCount == 12_487)
  #expect(files["README.md"]?.byteCount == 1_008)
  #expect(ModelRuntimeRegistry.admission(for: manifest).isAdmitted)
}

@Test("旧任务解码时新增模型能力和配置快照保持可选")
func processingTaskModelSnapshotRemainsBackwardCompatible() throws {
  let data = Data(
    #"{"kind":"transcription","idempotencyKey":"legacy","status":"queued","attempt":0,"createdAt":"2026-08-22T00:00:00Z","updatedAt":"2026-08-22T00:00:00Z"}"#
      .utf8)
  let task = try JSONDecoder.woice.decode(ProcessingTask.self, from: data)
  #expect(task.capability == nil)
  #expect(task.configurationHash == nil)
  #expect(task.status == .queued)
}
