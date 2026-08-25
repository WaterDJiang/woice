import Foundation
import WoiceCore

enum ModelPackStoreError: LocalizedError, Equatable, Sendable {
  case invalidSourceDirectory
  case missingFile(String)
  case unsafePath(String)
  case symbolicLink(String)
  case unexpectedFile(String)
  case nonRegularFile(String)
  case executableContent(String)
  case scriptContent(String)
  case machOContent(String)
  case byteCountMismatch(String)
  case checksumMismatch(String)
  case invalidManifest(String)
  case alreadyInstalled(String)
  case cannotDeleteCurrent(String)

  var errorDescription: String? {
    switch self {
    case .invalidSourceDirectory: "模型包来源目录无效。"
    case .missingFile(let path): "模型包缺少文件：\(path)"
    case .unsafePath(let path): "模型包路径不安全：\(path)"
    case .symbolicLink(let path): "模型包禁止包含符号链接：\(path)"
    case .unexpectedFile(let path): "模型包包含清单之外的文件：\(path)"
    case .nonRegularFile(let path): "模型包只能包含普通文件：\(path)"
    case .executableContent(let path): "App Store 模型包禁止包含可执行权限文件：\(path)"
    case .scriptContent(let path): "App Store 模型包禁止包含脚本或可执行类型文件：\(path)"
    case .machOContent(let path): "App Store 模型包禁止包含 Mach-O 内容：\(path)"
    case .byteCountMismatch(let path): "模型包文件大小校验失败：\(path)"
    case .checksumMismatch(let path): "模型包文件 SHA-256 校验失败：\(path)"
    case .invalidManifest(let message): "模型包清单无效：\(message)"
    case .alreadyInstalled(let packID): "模型包已经安装：\(packID)"
    case .cannotDeleteCurrent(let packID): "不能删除当前使用的模型版本：\(packID)；请先切换到其他版本。"
    }
  }
}

/// Controls how strictly a model directory is admitted. User imports retain
/// the legacy allowance for additional license metadata, while signed Catalog
/// packages are data-only and are checked again after atomic installation.
enum ModelPackInstallPolicy: Equatable, Sendable {
  case localImport
  case storeCatalog
}

enum ModelPackLocation: String, Codable, Equatable, Sendable {
  case bundled
  case downloaded
}

struct ModelPackInventoryEntry: Equatable, Sendable {
  let manifest: ModelPackManifest
  let location: ModelPackLocation
  let isCurrent: Bool
  let state: ModelInstallationState
}

/// Durable model inventory and atomic installer. It never executes anything
/// from a model pack; a pack contains only data and a validated manifest.
actor ModelPackStore {
  private struct CurrentPointer: Codable, Equatable {
    let packID: String
    let version: String
  }

  let rootURL: URL
  let bundledRootURL: URL?
  private let fileManager: FileManager

  init(
    rootURL: URL,
    bundledRootURL: URL? = nil,
    fileManager: FileManager = .default
  ) {
    self.rootURL = rootURL.standardizedFileURL
    self.bundledRootURL = bundledRootURL?.standardizedFileURL
    self.fileManager = fileManager
  }

  func inventory(bundledManifests: [ModelPackManifest] = []) throws -> [ModelPackInventoryEntry] {
    var entries: [ModelPackInventoryEntry] = []
    let resolvedBundledManifests =
      bundledManifests.isEmpty ? try discoverBundledManifests() : bundledManifests
    for manifest in resolvedBundledManifests {
      let directory = bundledDirectoryURL(for: manifest)
      guard fileManager.fileExists(atPath: directory.path) else { continue }
      try validatePackContents(
        manifest: manifest, directory: directory,
        policy: manifest.storeCompatible ? .storeCatalog : .localImport)
      entries.append(
        ModelPackInventoryEntry(
          manifest: manifest, location: .bundled, isCurrent: false, state: .installed))
    }

    let modelsDirectory = rootURL.appendingPathComponent("Models", isDirectory: true)
    guard
      let packDirectories = try? fileManager.contentsOfDirectory(
        at: modelsDirectory, includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles])
    else { return entries }

    for packDirectory in packDirectories {
      guard isDirectory(packDirectory), isSafeChild(packDirectory, of: modelsDirectory) else {
        continue
      }
      let current = try? readCurrentPointer(packDirectory: packDirectory)
      guard
        let versions = try? fileManager.contentsOfDirectory(
          at: packDirectory, includingPropertiesForKeys: [.isDirectoryKey],
          options: [.skipsHiddenFiles])
      else { continue }
      for versionDirectory in versions where versionDirectory.lastPathComponent != "current.json" {
        guard isDirectory(versionDirectory), isSafeChild(versionDirectory, of: packDirectory),
          let manifest = try? readManifest(at: versionDirectory)
        else { continue }
        try validatePackContents(
          manifest: manifest, directory: versionDirectory,
          policy: manifest.storeCompatible ? .storeCatalog : .localImport)
        entries.append(
          ModelPackInventoryEntry(
            manifest: manifest,
            location: .downloaded,
            isCurrent: current?.version == manifest.version && current?.packID == manifest.packID,
            state: .installed))
      }
    }
    return entries.sorted {
      ($0.manifest.packID, $0.manifest.version) < ($1.manifest.packID, $1.manifest.version)
    }
  }

  /// Installs a validated pack from a user-selected directory. The installed
  /// version becomes current only after every file hash and byte count pass.
  @discardableResult
  func install(
    manifest: ModelPackManifest,
    from sourceDirectory: URL,
    policy: ModelPackInstallPolicy = .localImport
  ) throws -> URL {
    guard isDirectory(sourceDirectory) else { throw ModelPackStoreError.invalidSourceDirectory }
    let destination = downloadedDirectory(for: manifest)
    let packDirectory = destination.deletingLastPathComponent()
    let downloadsDirectory = rootURL.appendingPathComponent("downloads", isDirectory: true)
    try fileManager.createDirectory(at: packDirectory, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: downloadsDirectory, withIntermediateDirectories: true)

    if fileManager.fileExists(atPath: destination.path) {
      throw ModelPackStoreError.alreadyInstalled(manifest.packID + "/" + manifest.version)
    }

    let partial = downloadsDirectory.appendingPathComponent(
      UUID().uuidString + ".partial", isDirectory: true)
    do {
      try fileManager.createDirectory(at: partial, withIntermediateDirectories: true)
      for file in manifest.files {
        let source = try safeChild(file.relativePath, of: sourceDirectory)
        guard fileManager.fileExists(atPath: source.path) else {
          throw ModelPackStoreError.missingFile(file.relativePath)
        }
        guard !isSymbolicLink(source) else {
          throw ModelPackStoreError.symbolicLink(file.relativePath)
        }
        let target = try safeChild(file.relativePath, of: partial)
        try fileManager.createDirectory(
          at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.copyItem(at: source, to: target)
      }
      try writeManifest(manifest, to: partial)
      let effectivePolicy: ModelPackInstallPolicy =
        manifest.storeCompatible ? .storeCatalog : policy
      try validatePackContents(
        manifest: manifest, directory: partial, policy: effectivePolicy)
      try fileManager.moveItem(at: partial, to: destination)
      try writeCurrentPointer(
        CurrentPointer(packID: manifest.packID, version: manifest.version), to: packDirectory)
      return destination
    } catch {
      try? fileManager.removeItem(at: partial)
      throw error
    }
  }

  func currentManifest(packID: String) throws -> ModelPackManifest? {
    try ModelPackValidation.validateIdentifier(packID)
    let packDirectory = rootURL.appendingPathComponent("Models", isDirectory: true)
      .appendingPathComponent(packID, isDirectory: true)
    guard let pointer = try? readCurrentPointer(packDirectory: packDirectory) else { return nil }
    let directory = packDirectory.appendingPathComponent(pointer.version, isDirectory: true)
    guard let manifest = try? readManifest(at: directory) else { return nil }
    try validatePackContents(
      manifest: manifest, directory: directory,
      policy: manifest.storeCompatible ? .storeCatalog : .localImport)
    return manifest
  }

  /// Returns the verified downloaded directory for an inventory entry. The
  /// caller must still construct the provider at its boundary; this method
  /// never exposes an unverified path.
  func installedDirectory(for manifest: ModelPackManifest) throws -> URL {
    try manifest.validate()
    let directory = downloadedDirectory(for: manifest)
    guard isDirectory(directory) else {
      throw ModelPackStoreError.missingFile(manifest.packID + "/" + manifest.version)
    }
    try validatePackContents(
      manifest: manifest, directory: directory,
      policy: manifest.storeCompatible ? .storeCatalog : .localImport)
    return directory
  }

  /// Deletes only a downloaded, non-current pack. Bundled packs and the
  /// atomic current pointer are never removed by this operation.
  func deleteDownloaded(manifest: ModelPackManifest) throws {
    try manifest.validate()
    let packDirectory = rootURL.appendingPathComponent("Models", isDirectory: true)
      .appendingPathComponent(manifest.packID, isDirectory: true)
    let destination = downloadedDirectory(for: manifest)
    guard isDirectory(destination) else {
      throw ModelPackStoreError.missingFile(manifest.packID + "/" + manifest.version)
    }
    if let current = try? readCurrentPointer(packDirectory: packDirectory),
      current.packID == manifest.packID && current.version == manifest.version
    {
      throw ModelPackStoreError.cannotDeleteCurrent(manifest.packID + "/" + manifest.version)
    }
    try validatePackContents(
      manifest: manifest, directory: destination,
      policy: manifest.storeCompatible ? .storeCatalog : .localImport)
    try fileManager.removeItem(at: destination)
  }

  func bundledDirectory(for manifest: ModelPackManifest) throws -> URL {
    try manifest.validate()
    let directory = bundledDirectoryURL(for: manifest)
    guard isDirectory(directory) else {
      throw ModelPackStoreError.missingFile(manifest.packID + "/" + manifest.version)
    }
    try validatePackContents(
      manifest: manifest, directory: directory,
      policy: manifest.storeCompatible ? .storeCatalog : .localImport)
    return directory
  }

  /// Reads a user-selected model directory without installing it. The
  /// manifest is decoded and validated before the caller can start a copy.
  func loadManifest(from sourceDirectory: URL) throws -> ModelPackManifest {
    guard isDirectory(sourceDirectory) else {
      throw ModelPackStoreError.invalidSourceDirectory
    }
    return try readManifest(at: sourceDirectory)
  }

  private func readManifest(at directory: URL) throws -> ModelPackManifest {
    let manifestURL = try safeChild("manifest.json", of: directory)
    do {
      return try JSONDecoder().decode(ModelPackManifest.self, from: Data(contentsOf: manifestURL))
    } catch {
      throw ModelPackStoreError.invalidManifest(error.localizedDescription)
    }
  }

  private func discoverBundledManifests() throws -> [ModelPackManifest] {
    guard let bundledRootURL, isDirectory(bundledRootURL) else { return [] }
    guard
      let enumerator = fileManager.enumerator(
        at: bundledRootURL,
        includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
        options: [.skipsHiddenFiles])
    else { return [] }
    return enumerator.compactMap { item in
      guard let url = item as? URL, url.lastPathComponent == "manifest.json" else { return nil }
      return try? readManifest(at: url.deletingLastPathComponent())
    }
  }

  private func writeManifest(_ manifest: ModelPackManifest, to directory: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let url = try safeChild("manifest.json", of: directory)
    try encoder.encode(manifest).write(to: url, options: .atomic)
  }

  private func readCurrentPointer(packDirectory: URL) throws -> CurrentPointer {
    let url = try safeChild("current.json", of: packDirectory)
    return try JSONDecoder().decode(CurrentPointer.self, from: Data(contentsOf: url))
  }

  private func writeCurrentPointer(_ pointer: CurrentPointer, to packDirectory: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let url = try safeChild("current.json", of: packDirectory)
    try encoder.encode(pointer).write(to: url, options: .atomic)
  }

  private func validatePackContents(
    manifest: ModelPackManifest,
    directory: URL,
    policy: ModelPackInstallPolicy
  ) throws {
    try manifest.validate()
    try validateDiscoveredContents(manifest: manifest, directory: directory, policy: policy)
    for file in manifest.files {
      let url = try safeChild(file.relativePath, of: directory)
      guard fileManager.fileExists(atPath: url.path) else {
        throw ModelPackStoreError.missingFile(file.relativePath)
      }
      guard !isSymbolicLink(url) else {
        throw ModelPackStoreError.symbolicLink(file.relativePath)
      }
      guard isRegularFile(url) else {
        throw ModelPackStoreError.nonRegularFile(file.relativePath)
      }
      if policy == .storeCatalog {
        try validateStoreFile(url, relativePath: file.relativePath)
      }
      guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
        let size = attributes[.size] as? NSNumber,
        size.int64Value == file.byteCount
      else { throw ModelPackStoreError.byteCountMismatch(file.relativePath) }
      guard sha256(url: url) == file.sha256.lowercased() else {
        throw ModelPackStoreError.checksumMismatch(file.relativePath)
      }
    }
  }

  private func validateDiscoveredContents(
    manifest: ModelPackManifest,
    directory: URL,
    policy: ModelPackInstallPolicy
  ) throws {
    guard
      let enumerator = fileManager.enumerator(
        at: directory,
        includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
        options: [])
    else { return }
    let declaredFiles = Set(manifest.files.map(\.relativePath))
    var allowed = declaredFiles
    allowed.insert("manifest.json")
    // Existing packs may keep the notice outside `files`; permit that one
    // explicitly while still rejecting every other unaccounted-for payload.
    allowed.insert(manifest.license.noticePath)
    for case let url as URL in enumerator {
      let relative = relativePath(of: url, from: directory)
      guard !relative.isEmpty else { continue }
      if isSymbolicLink(url) {
        throw ModelPackStoreError.symbolicLink(relative)
      }
      if isDirectory(url) { continue }
      guard isRegularFile(url) else {
        throw ModelPackStoreError.nonRegularFile(relative)
      }
      guard allowed.contains(relative) else {
        if policy == .storeCatalog {
          throw ModelPackStoreError.unexpectedFile(relative)
        }
        continue
      }
      if policy == .storeCatalog, relative != "manifest.json" {
        try validateStoreFile(url, relativePath: relative)
      }
    }
  }

  private func validateStoreFile(_ url: URL, relativePath: String) throws {
    guard
      let attributes = try? fileManager.attributesOfItem(atPath: url.path),
      let permissions = attributes[.posixPermissions] as? NSNumber
    else { throw ModelPackStoreError.nonRegularFile(relativePath) }
    if permissions.intValue & 0o111 != 0 {
      throw ModelPackStoreError.executableContent(relativePath)
    }
    let lowercased = relativePath.lowercased()
    let scriptExtensions = [
      ".app", ".bundle", ".framework", ".dylib", ".so", ".command", ".exe", ".js", ".mjs",
      ".py", ".rb", ".sh", ".swift", ".bat", ".cmd",
    ]
    if scriptExtensions.contains(where: { lowercased.hasSuffix($0) }) {
      throw ModelPackStoreError.scriptContent(relativePath)
    }
    guard let handle = try? FileHandle(forReadingFrom: url) else {
      throw ModelPackStoreError.nonRegularFile(relativePath)
    }
    defer { try? handle.close() }
    let header = (try? handle.read(upToCount: 8)) ?? Data()
    guard header.count >= 4 else { return }
    let magic = header.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    let machOMagics: Set<UInt32> = [
      0xfeed_face, 0xcefa_edfe, 0xfeed_facf, 0xcffa_edfe,
      0xcafe_babe, 0xbeba_feca, 0xcafe_babf, 0xbfba_feca,
    ]
    if machOMagics.contains(magic) {
      throw ModelPackStoreError.machOContent(relativePath)
    }
    if header.first == 0x23, header.dropFirst().first == 0x21 {
      throw ModelPackStoreError.scriptContent(relativePath)
    }
  }

  private func relativePath(of url: URL, from directory: URL) -> String {
    let base =
      directory.standardizedFileURL.path.hasSuffix("/")
      ? directory.standardizedFileURL.path
      : directory.standardizedFileURL.path + "/"
    guard url.standardizedFileURL.path.hasPrefix(base) else { return "" }
    return String(url.standardizedFileURL.path.dropFirst(base.count))
  }

  private func safeChild(_ relativePath: String, of directory: URL) throws -> URL {
    guard ModelPackValidation.isSafeRelativePath(relativePath) else {
      throw ModelPackStoreError.unsafePath(relativePath)
    }
    let base = directory.standardizedFileURL
    let candidate = base.appendingPathComponent(relativePath).standardizedFileURL
    guard isSafeChild(candidate, of: base) else {
      throw ModelPackStoreError.unsafePath(relativePath)
    }
    return candidate
  }

  private func isSafeChild(_ candidate: URL, of base: URL) -> Bool {
    let basePath =
      base.standardizedFileURL.path.hasSuffix("/")
      ? base.standardizedFileURL.path
      : base.standardizedFileURL.path + "/"
    return candidate.standardizedFileURL.path.hasPrefix(basePath)
  }

  private func isDirectory(_ url: URL) -> Bool {
    (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
  }

  private func isRegularFile(_ url: URL) -> Bool {
    (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
  }

  private func isSymbolicLink(_ url: URL) -> Bool {
    guard let attributes = try? fileManager.attributesOfItem(atPath: url.path) else { return false }
    return (attributes[.type] as? FileAttributeType) == .typeSymbolicLink
  }

  private func bundledDirectoryURL(for manifest: ModelPackManifest) -> URL {
    (bundledRootURL ?? rootURL.appendingPathComponent("BundledModels", isDirectory: true))
      .appendingPathComponent(manifest.packID, isDirectory: true)
      .appendingPathComponent(manifest.version, isDirectory: true)
  }

  private func downloadedDirectory(for manifest: ModelPackManifest) -> URL {
    rootURL.appendingPathComponent("Models", isDirectory: true)
      .appendingPathComponent(manifest.packID, isDirectory: true)
      .appendingPathComponent(manifest.version, isDirectory: true)
  }

  private func sha256(url: URL) -> String {
    (try? FileSHA256.digest(url: url)) ?? ""
  }
}
