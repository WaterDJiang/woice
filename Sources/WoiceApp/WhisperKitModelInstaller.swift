import Foundation
import WhisperKit
import WoiceCore

struct WhisperKitModelCatalogEntry: Equatable, Sendable {
  let packID: String
  let modelID: String
  let displayName: String
  let modelFolderName: String
  let modelRepository: String
  let modelRevision: String
  let tokenizerRepository: String
  let tokenizerRevision: String
  let tokenizerFolderName: String
  let estimatedBytes: Int64

  var sourceURL: String {
    "https://huggingface.co/\(modelRepository)/tree/\(modelRevision)/\(modelFolderName)"
  }

  /// Small multilingual model for the first real local inference loop. The
  /// revisions are pinned so a later repository update cannot silently change
  /// the model behind an existing version label.
  static let recommendedTiny = WhisperKitModelCatalogEntry(
    packID: "com.woice.whisperkit.tiny",
    modelID: "openai-whisper-tiny",
    displayName: "WhisperKit Tiny（多语言）",
    modelFolderName: "openai_whisper-tiny",
    modelRepository: "argmaxinc/whisperkit-coreml",
    modelRevision: "0f63a7800b00dd0226abd051b906c246e1907482",
    tokenizerRepository: "openai/whisper-tiny",
    tokenizerRevision: "169d4a4341b33bc18d8881c4b69c2e104e1cc0af",
    tokenizerFolderName: "whisper-tiny",
    estimatedBytes: 79_400_945)

  /// The accuracy candidate from the M2-08 plan. It is catalogued and can be
  /// downloaded explicitly, but remains unselected until the benchmark gate
  /// freezes it as the default.
  static let candidateLargeV3 = WhisperKitModelCatalogEntry(
    packID: "com.woice.whisperkit.large-v3",
    modelID: "openai-whisper-large-v3-v20240930-626mb",
    displayName: "WhisperKit Large-v3（高准确率候选）",
    modelFolderName: "openai_whisper-large-v3-v20240930_626MB",
    modelRepository: "argmaxinc/whisperkit-coreml",
    modelRevision: "0f63a7800b00dd0226abd051b906c246e1907482",
    tokenizerRepository: "openai/whisper-large-v3",
    tokenizerRevision: "06f233fe06e710322aca913c1bc4249a0d71fce1",
    tokenizerFolderName: "whisper-large-v3",
    estimatedBytes: 626_000_000)

  /// Frozen after the M2-08i five-category, five-minute performance gate.
  /// Users can still explicitly select Tiny or another installed version.
  static let frozenDefaultPackID = candidateLargeV3.packID
}

enum WhisperKitModelInstallerError: LocalizedError, Equatable, Sendable {
  case modelFolderMissing
  case tokenizerFilesMissing
  case modelFilesMissing
  case symbolicLink(String)
  case noFiles

  var errorDescription: String? {
    switch self {
    case .modelFolderMissing:
      "官方 WhisperKit 模型目录没有返回；模型尚未安装。"
    case .tokenizerFilesMissing:
      "WhisperKit tokenizer 文件不完整；模型尚未安装。"
    case .modelFilesMissing:
      "WhisperKit 模型文件不完整；模型尚未安装。"
    case .symbolicLink(let path):
      "模型下载包含不允许的符号链接：\(path)"
    case .noFiles:
      "模型包没有可安装的文件。"
    }
  }
}

/// Downloads a pinned official WhisperKit model and converts it into Woice's
/// own model-pack format. The Hub cache is only a resumable source cache; it
/// never becomes an installed-provider fact until ModelPackStore verifies and
/// atomically commits the generated manifest.
actor WhisperKitModelInstaller {
  private let rootURL: URL
  private let modelStore: ModelPackStore
  private let fileManager: FileManager

  init(rootURL: URL, modelStore: ModelPackStore? = nil, fileManager: FileManager = .default) {
    self.rootURL = rootURL.standardizedFileURL
    self.modelStore = modelStore ?? ModelPackStore(rootURL: rootURL)
    self.fileManager = fileManager
  }

  @discardableResult
  func install(
    entry: WhisperKitModelCatalogEntry,
    progress: (@Sendable (ModelPackDownloadProgress) -> Void)? = nil
  ) async throws -> (manifest: ModelPackManifest, installedURL: URL) {
    let downloadsRoot = rootURL.appendingPathComponent("downloads", isDirectory: true)
    try fileManager.createDirectory(at: downloadsRoot, withIntermediateDirectories: true)

    let cacheRoot = downloadsRoot.appendingPathComponent(
      "\(entry.packID)-\(entry.modelRevision).hub-cache", isDirectory: true)
    let packageRoot = downloadsRoot.appendingPathComponent(
      "\(entry.packID)-\(entry.modelRevision).partial", isDirectory: true)
    try? fileManager.removeItem(at: packageRoot)
    try fileManager.createDirectory(at: packageRoot, withIntermediateDirectories: true)

    let hub = HubApiWrapper(downloadBase: cacheRoot)
    let modelSnapshot = try await ModelDownloadRetry.run {
      try await hub.snapshot(
        from: HubApiWrapper.Repo(id: entry.modelRepository),
        revision: entry.modelRevision,
        matching: [entry.modelFolderName + "/*"]
      ) { [weak self] current in
        guard let self else { return }
        let total = max(1, current.totalUnitCount)
        let completed = max(0, min(total, current.completedUnitCount))
        Task { await self.report(progress, entry: entry, completed: completed, total: total) }
      }
    }
    try Task.checkCancellation()

    let modelSource = modelSnapshot.appendingPathComponent(entry.modelFolderName, isDirectory: true)
    guard isDirectory(modelSource) else {
      throw WhisperKitModelInstallerError.modelFolderMissing
    }
    try copyRegularFiles(
      from: modelSource,
      to: packageRoot,
      relativeRoot: modelSource,
      progress: progress,
      entry: entry,
      stage: "整理模型文件")

    let tokenizerSnapshot = try await ModelDownloadRetry.run {
      try await hub.snapshot(
        from: HubApiWrapper.Repo(id: entry.tokenizerRepository),
        revision: entry.tokenizerRevision,
        matching: ["config.json", "tokenizer_config.json", "tokenizer.json"]
      ) { [weak self] current in
        guard let self else { return }
        let total = max(1, current.totalUnitCount)
        let completed = max(0, min(total, current.completedUnitCount))
        Task { await self.report(progress, entry: entry, completed: completed, total: total) }
      }
    }
    let tokenizerDestination =
      packageRoot
      .appendingPathComponent("models", isDirectory: true)
      .appendingPathComponent("openai", isDirectory: true)
      .appendingPathComponent(entry.tokenizerFolderName, isDirectory: true)
    try fileManager.createDirectory(at: tokenizerDestination, withIntermediateDirectories: true)
    let tokenizerFiles = ["config.json", "tokenizer_config.json", "tokenizer.json"]
    for fileName in tokenizerFiles {
      let source = tokenizerSnapshot.appendingPathComponent(fileName)
      guard fileManager.fileExists(atPath: source.path), !isSymbolicLink(source) else {
        throw WhisperKitModelInstallerError.tokenizerFilesMissing
      }
      try fileManager.copyItem(
        at: source, to: tokenizerDestination.appendingPathComponent(fileName))
    }

    guard modelFileExists(named: "AudioEncoder.mlmodelc", in: packageRoot),
      modelFileExists(named: "MelSpectrogram.mlmodelc", in: packageRoot),
      modelFileExists(named: "TextDecoder.mlmodelc", in: packageRoot)
    else {
      throw WhisperKitModelInstallerError.modelFilesMissing
    }

    let notice = """
      Woice model pack: \(entry.displayName)
      Model repository: \(entry.modelRepository)
      Model revision: \(entry.modelRevision)
      Tokenizer repository: \(entry.tokenizerRepository)
      Tokenizer revision: \(entry.tokenizerRevision)
      License: MIT (see source repository)
      Source: \(entry.sourceURL)
      """
    try Data(notice.utf8).write(
      to: packageRoot.appendingPathComponent("NOTICE.txt"), options: .atomic)

    let manifest = try makeManifest(entry: entry, packageRoot: packageRoot)
    progress?(
      ModelPackDownloadProgress(
        packID: entry.packID,
        filePath: "清单校验",
        completedBytes: 99,
        totalBytes: 100))
    let installed = try await modelStore.install(manifest: manifest, from: packageRoot)
    try? fileManager.removeItem(at: packageRoot)
    try? fileManager.removeItem(at: cacheRoot)
    progress?(
      ModelPackDownloadProgress(
        packID: entry.packID,
        filePath: "已安装",
        completedBytes: 100,
        totalBytes: 100))
    return (manifest, installed)
  }

  private func report(
    _ progress: (@Sendable (ModelPackDownloadProgress) -> Void)?,
    entry: WhisperKitModelCatalogEntry,
    completed: Int64,
    total: Int64
  ) {
    progress?(
      ModelPackDownloadProgress(
        packID: entry.packID,
        filePath: "下载 WhisperKit 模型",
        completedBytes: completed,
        totalBytes: total))
  }

  private func makeManifest(
    entry: WhisperKitModelCatalogEntry,
    packageRoot: URL
  ) throws -> ModelPackManifest {
    var files: [ModelPackFile] = []
    guard
      let enumerator = fileManager.enumerator(
        at: packageRoot,
        includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
        options: [.skipsHiddenFiles])
    else { throw WhisperKitModelInstallerError.noFiles }

    for case let url as URL in enumerator {
      if isDirectory(url) { continue }
      guard !isSymbolicLink(url) else {
        throw WhisperKitModelInstallerError.symbolicLink(relativePath(of: url, from: packageRoot))
      }
      let relative = relativePath(of: url, from: packageRoot)
      let attributes = try fileManager.attributesOfItem(atPath: url.path)
      guard let size = attributes[.size] as? NSNumber else { continue }
      let file = try ModelPackFile(
        relativePath: relative,
        byteCount: size.int64Value,
        sha256: sha256(url: url))
      files.append(file)
    }
    guard !files.isEmpty else { throw WhisperKitModelInstallerError.noFiles }
    let size = files.reduce(Int64(0)) { $0 + $1.byteCount }
    return try ModelPackManifest(
      packID: entry.packID,
      modelID: entry.modelID,
      version: entry.modelRevision,
      providerID: "com.woice.whisperkit",
      transport: .inProcess,
      capabilities: [.transcription, .timestamps],
      files: files.sorted { $0.relativePath < $1.relativePath },
      license: ModelPackLicense(
        identifier: "MIT",
        noticePath: "NOTICE.txt",
        sourceURL: entry.sourceURL),
      size: size)
  }

  private func copyRegularFiles(
    from source: URL,
    to destination: URL,
    relativeRoot: URL,
    progress: (@Sendable (ModelPackDownloadProgress) -> Void)?,
    entry: WhisperKitModelCatalogEntry,
    stage: String
  ) throws {
    guard
      let enumerator = fileManager.enumerator(
        at: source,
        includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
        options: [.skipsHiddenFiles])
    else { throw WhisperKitModelInstallerError.modelFolderMissing }
    var copied = Int64(0)
    for case let url as URL in enumerator {
      if isDirectory(url) { continue }
      guard !isSymbolicLink(url) else {
        throw WhisperKitModelInstallerError.symbolicLink(relativePath(of: url, from: relativeRoot))
      }
      let relative = relativePath(of: url, from: relativeRoot)
      let target = destination.appendingPathComponent(relative)
      try fileManager.createDirectory(
        at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
      try fileManager.copyItem(at: url, to: target)
      copied += 1
      progress?(
        ModelPackDownloadProgress(
          packID: entry.packID,
          filePath: stage,
          completedBytes: copied,
          totalBytes: 100))
    }
  }

  private func modelFileExists(named name: String, in directory: URL) -> Bool {
    fileManager.fileExists(atPath: directory.appendingPathComponent(name).path)
  }

  private func isDirectory(_ url: URL) -> Bool {
    (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
  }

  private func isSymbolicLink(_ url: URL) -> Bool {
    guard let attributes = try? fileManager.attributesOfItem(atPath: url.path) else { return false }
    return (attributes[.type] as? FileAttributeType) == .typeSymbolicLink
  }

  private func relativePath(of url: URL, from root: URL) -> String {
    let rootPath = root.standardizedFileURL.path
    let value = url.standardizedFileURL.path
    return String(value.dropFirst(rootPath.hasSuffix("/") ? rootPath.count : rootPath.count + 1))
  }

  private func sha256(url: URL) -> String {
    (try? FileSHA256.digest(url: url)) ?? ""
  }
}
