import Foundation
import Testing
import WoiceCore

@Test("生产模型 Catalog 可由 Store 内置公钥验签")
func productionModelCatalogVerifies() throws {
  let projectRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let catalogURL =
    projectRoot
    .appendingPathComponent("Resources/ModelCatalog/model-catalog.json")
  let data = try Data(contentsOf: catalogURL)
  let decoder = JSONDecoder()
  decoder.dateDecodingStrategy = .iso8601
  let catalog = try decoder.decode(ModelCatalog.self, from: data)
  #expect(catalog.catalogID == "woice-model-catalog")
  #expect(catalog.catalogVersion == 1)
  #expect(
    catalog.entries.map { $0.packID } == [
      "com.woice.whisperkit.large-v3",
      "com.woice.whisperkit.tiny",
    ])
  #expect(catalog.entries.allSatisfy { $0.storeCompatible })
  #expect(catalog.entries.allSatisfy { $0.runtimeID == "com.woice.whisperkit" })
  #expect(catalog.entries.allSatisfy { $0.files.allSatisfy { $0.downloadURL != nil } })
  try ModelCatalogVerifier.verify(
    catalog,
    publicKeyBase64: "oQOBwsn6Q2EkL3yTuEzz3+PvYHvDI62BsRzhOMXFQpU=",
    expectedKeyID: "woice-release-2026-08")
}
