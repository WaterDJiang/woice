import CryptoKit
import Foundation
import Testing
import WoiceCore

@Test("模型 Catalog 的 Ed25519 签名可验证且篡改即拒绝")
func signedModelCatalogVerifiesAndFailsClosed() throws {
  let manifest = try catalogManifest(version: "1.0.0")
  let unsigned = try ModelCatalog(
    catalogID: "woice-test-catalog", generatedAt: Date(timeIntervalSince1970: 1_750_000_000),
    entries: [manifest])
  let privateKey = Curve25519.Signing.PrivateKey()
  let signature = try ModelPackSignature(
    algorithm: "Ed25519",
    keyID: "test-key-1",
    value: privateKey.signature(for: unsigned.unsignedPayload).base64EncodedString())
  let signed = try ModelCatalog(
    catalogID: unsigned.catalogID,
    generatedAt: unsigned.generatedAt,
    entries: unsigned.entries,
    signature: signature)

  try ModelCatalogVerifier.verify(
    signed,
    publicKeyBase64: privateKey.publicKey.rawRepresentation.base64EncodedString(),
    expectedKeyID: "test-key-1")

  let changedManifest = try catalogManifest(version: "1.0.1")
  let changed = try ModelCatalog(
    catalogID: signed.catalogID,
    generatedAt: signed.generatedAt,
    entries: [changedManifest],
    signature: signed.signature)
  #expect(throws: ModelCatalogValidationError.signatureMismatch) {
    try ModelCatalogVerifier.verify(
      changed,
      publicKeyBase64: privateKey.publicKey.rawRepresentation.base64EncodedString(),
      expectedKeyID: "test-key-1")
  }
}

@Test("模型 Catalog 拒绝缺失签名、错误 key 和重复模型包")
func modelCatalogRejectsInvalidTrustInputs() throws {
  let manifest = try catalogManifest(version: "1.0.0")
  let unsigned = try ModelCatalog(
    catalogID: "woice-test-catalog", generatedAt: Date(), entries: [manifest])
  #expect(throws: ModelCatalogValidationError.missingSignature) {
    try ModelCatalogVerifier.verify(unsigned, publicKeyBase64: "invalid")
  }

  #expect(throws: ModelCatalogValidationError.duplicatePack(manifest.packID)) {
    try ModelCatalog(
      catalogID: "woice-test-catalog", generatedAt: Date(), entries: [manifest, manifest])
  }
}

@Test("Catalog Store 只接受受信签名并拒绝版本回退")
func modelCatalogStorePersistsTrustedSnapshotAndRejectsRollback() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "woice-catalog-store-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let storageURL = root.appendingPathComponent("catalog.json")
  let privateKey = Curve25519.Signing.PrivateKey()
  let publicKey = privateKey.publicKey.rawRepresentation.base64EncodedString()
  let store = try ModelCatalogStore(
    storageURL: storageURL,
    catalogID: "woice-test-catalog",
    trustedKeys: ["test-key-1": publicKey])

  let current = try signedCatalog(version: 2, privateKey: privateKey)
  #expect(try await store.accept(current) == current)
  #expect(try await store.load() == current)

  let rollback = try signedCatalog(version: 1, privateKey: privateKey)
  do {
    try await store.accept(rollback)
    Issue.record("版本回退没有被拒绝")
  } catch let error as ModelCatalogStoreError {
    #expect(error == .rollback(current: 2, incoming: 1))
  } catch {
    Issue.record("收到意外错误：\(error)")
  }

  let otherKey = Curve25519.Signing.PrivateKey()
  let untrusted = try signedCatalog(version: 3, privateKey: otherKey, keyID: "other-key")
  do {
    try await store.accept(untrusted)
    Issue.record("未信任公钥没有被拒绝")
  } catch let error as ModelCatalogStoreError {
    #expect(error == .unknownKey("other-key"))
  } catch {
    Issue.record("收到意外错误：\(error)")
  }
}

@Test("Catalog 密钥轮换会持久化签名历史并撤销旧公钥")
func modelCatalogKeyRotationPersistsAndRevokesPreviousKey() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "woice-catalog-rotation-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let storageURL = root.appendingPathComponent("catalog.json")
  let oldKey = Curve25519.Signing.PrivateKey()
  let newKey = Curve25519.Signing.PrivateKey()
  let store = try ModelCatalogStore(
    storageURL: storageURL,
    catalogID: "woice-test-catalog",
    trustedKeys: ["old-key": oldKey.publicKey.rawRepresentation.base64EncodedString()])

  let first = try signedCatalog(version: 1, privateKey: oldKey, keyID: "old-key")
  _ = try await store.accept(first)
  let rotation = try ModelCatalogKeyRotation(
    additions: [
      try ModelCatalogTrustedKey(
        keyID: "new-key", publicKeyBase64: newKey.publicKey.rawRepresentation.base64EncodedString())
    ],
    revokedKeyIDs: ["old-key"])
  let rotated = try signedCatalog(
    version: 2, privateKey: oldKey, keyID: "old-key", keyRotation: rotation)
  _ = try await store.accept(rotated)
  let next = try signedCatalog(version: 3, privateKey: newKey, keyID: "new-key")
  _ = try await store.accept(next)
  #expect(await store.activeTrustedKeyIDs() == ["new-key"])

  let restored = try ModelCatalogStore(
    storageURL: storageURL,
    catalogID: "woice-test-catalog",
    trustedKeys: ["old-key": oldKey.publicKey.rawRepresentation.base64EncodedString()])
  #expect(try await restored.load() == next)
  #expect(await restored.activeTrustedKeyIDs() == ["new-key"])

  let oldAfterRevocation = try signedCatalog(version: 4, privateKey: oldKey, keyID: "old-key")
  do {
    try await restored.accept(oldAfterRevocation)
    Issue.record("已撤销公钥仍被接受")
  } catch let error as ModelCatalogStoreError {
    #expect(error == .revokedKey("old-key"))
  } catch {
    Issue.record("收到意外错误：\(error)")
  }

  let missingHistoryURL = root.appendingPathComponent("missing-history.json")
  let encoder = JSONEncoder()
  encoder.dateEncodingStrategy = .iso8601
  try encoder.encode(next).write(to: missingHistoryURL, options: .atomic)
  let missingHistoryStore = try ModelCatalogStore(
    storageURL: missingHistoryURL,
    catalogID: "woice-test-catalog",
    trustedKeys: ["old-key": oldKey.publicKey.rawRepresentation.base64EncodedString()])
  do {
    _ = try await missingHistoryStore.load()
    Issue.record("缺少轮换历史时仍接受了新公钥")
  } catch let error as ModelCatalogStoreError {
    #expect(error == .unknownKey("new-key"))
  } catch {
    Issue.record("收到意外错误：\(error)")
  }
}

private func catalogManifest(version: String) throws -> ModelPackManifest {
  let bytes = Data([0x61])
  let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
  let file = try ModelPackFile(relativePath: "weights.bin", byteCount: 1, sha256: digest)
  let license = try ModelPackLicense(
    identifier: "MIT", noticePath: "NOTICE", sourceURL: "https://example.test/model")
  return try ModelPackManifest(
    packID: "com.woice.test.model",
    modelID: "test-model",
    version: version,
    providerID: "com.woice.whisperkit",
    files: [file],
    license: license,
    size: 1)
}

private func signedCatalog(
  version: Int, privateKey: Curve25519.Signing.PrivateKey, keyID: String = "test-key-1",
  keyRotation: ModelCatalogKeyRotation? = nil
) throws -> ModelCatalog {
  let unsigned = try ModelCatalog(
    catalogVersion: version,
    catalogID: "woice-test-catalog",
    generatedAt: Date(timeIntervalSince1970: TimeInterval(1_750_000_000 + version)),
    entries: [try catalogManifest(version: "1.0.\(version)")], keyRotation: keyRotation)
  let signature = try ModelPackSignature(
    algorithm: "Ed25519",
    keyID: keyID,
    value: privateKey.signature(for: unsigned.unsignedPayload).base64EncodedString())
  return try ModelCatalog(
    schemaVersion: unsigned.schemaVersion,
    catalogVersion: unsigned.catalogVersion,
    catalogID: unsigned.catalogID,
    generatedAt: unsigned.generatedAt,
    entries: unsigned.entries,
    signature: signature,
    keyRotation: unsigned.keyRotation)
}
