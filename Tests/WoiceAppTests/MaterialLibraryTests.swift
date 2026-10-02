import CryptoKit
import Foundation
import Testing
import WoiceCore

@testable import WoiceApp

@Test("用户选定素材文件夹后迁移容器录音并保持哈希")
@MainActor
func selectedMaterialLibraryMigratesLegacyFilesWithoutMutation() throws {
  let base = temporaryMaterialLibraryTestDirectory("migration")
  defer { try? FileManager.default.removeItem(at: base) }
  let root = base.appendingPathComponent("container", isDirectory: true)
  let destination = base.appendingPathComponent("Documents/Woice 素材", isDirectory: true)
  let store = WorkspaceStore(
    storageRootURL: root,
    requiresUserSelectedMaterialLibrary: true)
  let source = store.internalRecordingsURL.appendingPathComponent("voice.wav")
  let chunks = store.internalRecordingsURL.appendingPathComponent("voice.chunks", isDirectory: true)
  try FileManager.default.createDirectory(at: chunks, withIntermediateDirectories: true)
  try Data("immutable-audio".utf8).write(to: source)
  try Data("chunk-0".utf8).write(to: chunks.appendingPathComponent("0000.wav"))
  let sourceHash = SHA256.hash(data: try Data(contentsOf: source))

  try store.configureUserSelectedMaterialLibrary(at: destination)

  let migrated = destination.appendingPathComponent("voice.wav")
  #expect(try urlsReferenceSameFile(store.recordingsURL, destination))
  #expect(try urlsReferenceSameFile(store.userSelectedMaterialLibraryURL, destination))
  #expect(store.hasUserSelectedMaterialLibrary)
  #expect(FileManager.default.fileExists(atPath: migrated.path))
  #expect(
    FileManager.default.fileExists(
      atPath: destination.appendingPathComponent("voice.chunks/0000.wav").path))
  let record = RecordingRecord(
    id: UUID(), createdAt: Date(), audioFileName: "voice.wav", duration: 1,
    transcript: nil, generatedMarkdown: nil, processingError: nil)
  #expect(try urlsReferenceSameFile(store.audioURL(for: record), migrated))
  #expect(
    store.recordingManifestURL(for: record.id).deletingLastPathComponent().path
      == store.recordingsURL.path)
  #expect(
    store.backgroundTranscriptionURL(for: record.id).deletingLastPathComponent().path
      == store.recordingsURL.path)
  #expect(SHA256.hash(data: try Data(contentsOf: migrated)) == sourceHash)
  #expect(!FileManager.default.fileExists(atPath: store.internalRecordingsURL.path))
  #expect(FileManager.default.fileExists(atPath: store.materialLibraryBookmarkURL.path))

  let reopened = WorkspaceStore(
    storageRootURL: root,
    requiresUserSelectedMaterialLibrary: true)
  #expect(reopened.hasUserSelectedMaterialLibrary)
  #expect(try urlsReferenceSameFile(reopened.recordingsURL, destination))
  #expect(
    try Data(contentsOf: reopened.recordingsURL.appendingPathComponent("voice.wav"))
      == Data("immutable-audio".utf8))
}

@Test("素材文件夹同名冲突时不覆盖且保留原文件")
@MainActor
func selectedMaterialLibraryConflictFailsClosed() throws {
  let base = temporaryMaterialLibraryTestDirectory("conflict")
  defer { try? FileManager.default.removeItem(at: base) }
  let root = base.appendingPathComponent("container", isDirectory: true)
  let destination = base.appendingPathComponent("Documents/Woice 素材", isDirectory: true)
  let store = WorkspaceStore(
    storageRootURL: root,
    requiresUserSelectedMaterialLibrary: true)
  try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
  let source = store.internalRecordingsURL.appendingPathComponent("voice.wav")
  let existing = destination.appendingPathComponent("voice.wav")
  try Data("source".utf8).write(to: source)
  try Data("different destination".utf8).write(to: existing)

  #expect(throws: MaterialLibraryError.conflictingItem("voice.wav")) {
    try store.configureUserSelectedMaterialLibrary(at: destination)
  }

  #expect(try Data(contentsOf: source) == Data("source".utf8))
  #expect(try Data(contentsOf: existing) == Data("different destination".utf8))
  #expect(!store.hasUserSelectedMaterialLibrary)
  #expect(store.recordingsURL == store.internalRecordingsURL)
}

@Test("素材文件夹不得选在 App Container 内")
@MainActor
func selectedMaterialLibraryRejectsContainerLocation() throws {
  let base = temporaryMaterialLibraryTestDirectory("container-location")
  defer { try? FileManager.default.removeItem(at: base) }
  let root = base.appendingPathComponent("container", isDirectory: true)
  let store = WorkspaceStore(
    storageRootURL: root,
    requiresUserSelectedMaterialLibrary: true)
  let source = store.internalRecordingsURL.appendingPathComponent("voice.wav")
  try Data("source".utf8).write(to: source)

  #expect(throws: MaterialLibraryError.containerLocationNotAllowed) {
    try store.configureUserSelectedMaterialLibrary(
      at: root.appendingPathComponent("User Materials", isDirectory: true))
  }

  #expect(FileManager.default.fileExists(atPath: source.path))
  #expect(!store.hasUserSelectedMaterialLibrary)
}

@Test("用户取消素材文件夹面板时保持 fail-closed")
@MainActor
func cancelledMaterialLibrarySelectionDoesNotEnableRecordingStorage() {
  let base = temporaryMaterialLibraryTestDirectory("cancel")
  defer { try? FileManager.default.removeItem(at: base) }
  let store = WorkspaceStore(
    storageRootURL: base.appendingPathComponent("container", isDirectory: true),
    requiresUserSelectedMaterialLibrary: true)
  var selectionCount = 0
  let state = AppState(
    store: store,
    materialLibrarySelector: {
      selectionCount += 1
      return nil
    })

  #expect(selectionCount == 0)
  #expect(state.isShowingOnboarding)
  #expect(!state.requestUserSelectedMaterialLibraryIfNeeded())
  #expect(selectionCount == 1)
  #expect(state.needsUserSelectedMaterialLibrary)
  #expect(!store.hasUserSelectedMaterialLibrary)
}

private func temporaryMaterialLibraryTestDirectory(_ suffix: String) -> URL {
  FileManager.default.temporaryDirectory.appendingPathComponent(
    "woice-material-library-\(suffix)-\(UUID().uuidString)",
    isDirectory: true)
}

private func urlsReferenceSameFile(_ lhs: URL?, _ rhs: URL) throws -> Bool {
  guard let lhs else { return false }
  let keys: Set<URLResourceKey> = [.fileResourceIdentifierKey]
  let leftIdentifier = try lhs.resourceValues(forKeys: keys).fileResourceIdentifier as? NSObject
  let rightIdentifier = try rhs.resourceValues(forKeys: keys).fileResourceIdentifier as? NSObject
  return leftIdentifier != nil && leftIdentifier == rightIdentifier
}
