import Foundation
import WhisperKit
import WoiceCore

enum WhisperKitASRError: LocalizedError, Equatable, Sendable {
  case modelDirectoryMissing
  case modelLoadFailed(String)
  case transcriptionFailed(String)

  var errorDescription: String? {
    switch self {
    case .modelDirectoryMissing: "WhisperKit 模型目录不存在；原始录音仍保存在本机。"
    case .modelLoadFailed(let message): "WhisperKit 模型加载失败：\(message)；原始录音仍保存在本机。"
    case .transcriptionFailed(let message): "WhisperKit 本机转写失败：\(message)；原始录音仍保存在本机。"
    }
  }
}

/// WhisperKit is deliberately isolated here. The SDK's top-level class is not
/// Sendable, so it never crosses into Domain, Runtime or UI.
final class WhisperKitTranscriptionService: LocalASRTranscribing, @unchecked Sendable {
  let model: ASRModelDescriptor
  private let modelFolder: URL
  private let manifest: ModelPackManifest
  private var pipeline: WhisperKit?

  init(manifest: ModelPackManifest, modelFolder: URL) throws {
    try manifest.validate()
    guard manifest.providerID == "com.woice.whisperkit" else {
      throw WhisperKitASRError.modelLoadFailed("Provider ID 不匹配：\(manifest.providerID)")
    }
    self.manifest = manifest
    self.modelFolder = modelFolder.standardizedFileURL
    self.model = ASRModelDescriptor(
      providerID: manifest.providerID,
      modelID: manifest.modelID,
      displayName: "WhisperKit \(manifest.modelID)",
      version: manifest.version,
      dataLocation: .onDevice)
  }

  func transcribe(audioURL: URL, language: String) async throws -> WoiceCore.TranscriptionResult {
    guard FileManager.default.fileExists(atPath: audioURL.path) else {
      throw LocalASRError.audioMissing
    }
    guard FileManager.default.fileExists(atPath: modelFolder.path) else {
      throw WhisperKitASRError.modelDirectoryMissing
    }

    let pipe: WhisperKit
    do {
      pipe = try await loadPipeline()
    } catch {
      throw WhisperKitASRError.modelLoadFailed(error.localizedDescription)
    }

    let languageCode = normalizedLanguage(language)
    let options = DecodingOptions(
      verbose: false,
      language: languageCode.isEmpty ? nil : languageCode,
      withoutTimestamps: false,
      chunkingStrategy: .vad)
    do {
      let results = try await pipe.transcribe(audioPath: audioURL.path, decodeOptions: options)
      let text = TranscriptTextNormalizer.normalize(results.map { $0.text }.joined(separator: " "))
      guard !text.isEmpty else { throw LocalASRError.emptyResult }
      let segments = results.flatMap { $0.segments }.compactMap { segment -> TranscriptSegment? in
        let value = TranscriptTextNormalizer.normalize(segment.text)
        guard !value.isEmpty, segment.end >= segment.start else { return nil }
        return TranscriptSegment(
          start: max(0, TimeInterval(segment.start)),
          end: max(0, TimeInterval(segment.end)),
          text: value)
      }
      return WoiceCore.TranscriptionResult(text: text, segments: segments)
    } catch {
      if let error = error as? LocalASRError { throw error }
      throw WhisperKitASRError.transcriptionFailed(error.localizedDescription)
    }
  }

  private func loadPipeline() async throws -> WhisperKit {
    if let pipeline { return pipeline }
    let config = WhisperKitConfig(
      model: manifest.modelID,
      modelFolder: modelFolder.path,
      prewarm: false,
      load: true,
      download: false)
    let loaded = try await WhisperKit(config)
    pipeline = loaded
    return loaded
  }

  private func normalizedLanguage(_ value: String) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return "" }
    return trimmed.split(separator: "-", maxSplits: 1).first.map(String.init) ?? trimmed
  }

  /// Selects an installed, atomically committed WhisperKit pack at app
  /// startup. The scanner is deliberately conservative: malformed pointers,
  /// path traversal, missing files, invalid manifests, and non-WhisperKit
  /// providers are ignored and the caller can fall back to macOS Speech.
  static func defaultProvider(
    rootURL: URL,
    bundledRootURL: URL? = nil,
    preferredPackID: String? = nil,
    preferredVersion: String? = nil
  ) -> LocalASRTranscribing {
    let automaticDefaultSelection = preferredPackID == nil
    guard
      let installed = currentInstalledProvider(
        rootURL: rootURL,
        bundledRootURL: bundledRootURL,
        preferredPackID: preferredPackID ?? WhisperKitModelCatalogEntry.frozenDefaultPackID,
        preferredVersion: preferredVersion,
        automaticDefaultSelection: automaticDefaultSelection)
    else {
      return OnDeviceSpeechTranscriptionService()
    }
    return installed
  }

  private struct CurrentPointer: Decodable {
    let packID: String
    let version: String
  }

  private static func currentInstalledProvider(
    rootURL: URL,
    bundledRootURL: URL?,
    preferredPackID: String?,
    preferredVersion: String?,
    automaticDefaultSelection: Bool
  ) -> WhisperKitTranscriptionService? {
    if let downloaded = currentDownloadedProvider(
      rootURL: rootURL,
      preferredPackID: preferredPackID,
      preferredVersion: preferredVersion,
      automaticDefaultSelection: automaticDefaultSelection)
    {
      return downloaded
    }
    return bundledProvider(
      rootURL: bundledRootURL,
      preferredPackID: preferredPackID,
      preferredVersion: preferredVersion,
      automaticDefaultSelection: automaticDefaultSelection)
  }

  private static func currentDownloadedProvider(
    rootURL: URL,
    preferredPackID: String?,
    preferredVersion: String?,
    automaticDefaultSelection: Bool
  ) -> WhisperKitTranscriptionService? {
    let fileManager = FileManager.default
    let modelsRoot = rootURL.appendingPathComponent("Models", isDirectory: true)
    guard
      let packDirectories = try? fileManager.contentsOfDirectory(
        at: modelsRoot, includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles])
    else { return nil }

    let orderedPackDirectories = packDirectories.sorted { lhs, rhs in
      if lhs.lastPathComponent == preferredPackID { return true }
      if rhs.lastPathComponent == preferredPackID { return false }
      return lhs.lastPathComponent < rhs.lastPathComponent
    }

    for packDirectory in orderedPackDirectories {
      if automaticDefaultSelection,
        ![
          WhisperKitModelCatalogEntry.frozenDefaultPackID,
          WhisperKitModelCatalogEntry.recommendedTiny.packID,
        ].contains(packDirectory.lastPathComponent)
      {
        continue
      }
      guard isDirectory(packDirectory),
        (try? ModelPackValidation.validateIdentifier(packDirectory.lastPathComponent)) != nil
      else { continue }
      let pointerURL = packDirectory.appendingPathComponent("current.json")
      guard
        let pointerData = try? Data(contentsOf: pointerURL),
        let pointer = try? JSONDecoder().decode(CurrentPointer.self, from: pointerData),
        pointer.packID == packDirectory.lastPathComponent,
        (try? ModelPackValidation.validateIdentifier(pointer.version)) != nil
      else { continue }
      let selectedVersion =
        packDirectory.lastPathComponent == preferredPackID && preferredVersion != nil
        ? preferredVersion! : pointer.version
      guard (try? ModelPackValidation.validateIdentifier(selectedVersion)) != nil else { continue }
      let versionDirectory = packDirectory.appendingPathComponent(
        selectedVersion, isDirectory: true)
      guard isDirectory(versionDirectory) else { continue }
      let manifestURL = versionDirectory.appendingPathComponent("manifest.json")
      guard
        let manifestData = try? Data(contentsOf: manifestURL),
        let manifest = try? JSONDecoder().decode(ModelPackManifest.self, from: manifestData),
        manifest.packID == packDirectory.lastPathComponent,
        manifest.version == selectedVersion,
        manifest.providerID == "com.woice.whisperkit",
        manifest.transport == .inProcess,
        manifest.capabilities.contains(.transcription),
        manifest.files.allSatisfy({ file in
          let fileURL = versionDirectory.appendingPathComponent(file.relativePath)
          guard fileManager.fileExists(atPath: fileURL.path), !isSymbolicLink(fileURL),
            let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
            let size = attributes[.size] as? NSNumber,
            size.int64Value == file.byteCount
          else { return false }
          return sha256(url: fileURL) == file.sha256.lowercased()
        })
      else { continue }
      return try? WhisperKitTranscriptionService(
        manifest: manifest, modelFolder: versionDirectory)
    }
    return nil
  }

  private static func bundledProvider(
    rootURL: URL?, preferredPackID: String?, preferredVersion: String?,
    automaticDefaultSelection: Bool
  ) -> WhisperKitTranscriptionService? {
    guard let rootURL, isDirectory(rootURL),
      let enumerator = FileManager.default.enumerator(
        at: rootURL,
        includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
        options: [.skipsHiddenFiles])
    else { return nil }
    let manifestURLs = enumerator.compactMap { item -> URL? in
      guard let url = item as? URL, url.lastPathComponent == "manifest.json" else { return nil }
      return url
    }.sorted { lhs, rhs in
      let lhsPackID = bundledPackID(for: lhs)
      let rhsPackID = bundledPackID(for: rhs)
      if lhsPackID == preferredPackID && rhsPackID != preferredPackID { return true }
      if rhsPackID == preferredPackID && lhsPackID != preferredPackID { return false }
      return lhs.path < rhs.path
    }
    for manifestURL in manifestURLs {
      let versionDirectory = manifestURL.deletingLastPathComponent()
      let packID = bundledPackID(for: manifestURL)
      if automaticDefaultSelection,
        ![
          WhisperKitModelCatalogEntry.frozenDefaultPackID,
          WhisperKitModelCatalogEntry.recommendedTiny.packID,
        ].contains(packID)
      {
        continue
      }
      guard
        let data = try? Data(contentsOf: manifestURL),
        let manifest = try? JSONDecoder().decode(ModelPackManifest.self, from: data),
        manifest.providerID == "com.woice.whisperkit",
        manifest.transport == .inProcess,
        manifest.capabilities.contains(.transcription),
        preferredVersion == nil || manifest.packID != preferredPackID
          || manifest.version == preferredVersion,
        manifest.files.allSatisfy({ file in
          let fileURL = versionDirectory.appendingPathComponent(file.relativePath)
          guard FileManager.default.fileExists(atPath: fileURL.path),
            !isSymbolicLink(fileURL),
            let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
            let size = attributes[.size] as? NSNumber,
            size.int64Value == file.byteCount
          else { return false }
          return sha256(url: fileURL) == file.sha256.lowercased()
        })
      else { continue }
      return try? WhisperKitTranscriptionService(
        manifest: manifest, modelFolder: versionDirectory)
    }
    return nil
  }

  private static func bundledPackID(for manifestURL: URL) -> String {
    manifestURL.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent
  }

  private static func isDirectory(_ url: URL) -> Bool {
    (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
  }

  private static func isSymbolicLink(_ url: URL) -> Bool {
    guard let attributes = try? fileManagerAttributes(at: url) else { return false }
    return attributes == .typeSymbolicLink
  }

  private static func fileManagerAttributes(at url: URL) throws -> FileAttributeType {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return (attributes[.type] as? FileAttributeType) ?? .typeUnknown
  }

  private static func sha256(url: URL) -> String? {
    try? FileSHA256.digest(url: url)
  }
}
