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
