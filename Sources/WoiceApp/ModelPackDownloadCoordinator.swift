import Foundation
import WoiceCore

enum ModelPackDownloadError: LocalizedError, Equatable, Sendable {
  case invalidBaseURL
  case invalidResponse
  case httpStatus(Int)
  case insufficientDiskSpace(required: Int64, available: Int64)
  case contentLengthMismatch(path: String)

  var errorDescription: String? {
    switch self {
    case .invalidBaseURL:
      "模型下载地址必须是 HTTP(S) URL。"
    case .invalidResponse:
      "模型下载返回了无法识别的响应。"
    case .httpStatus(let status):
      "模型下载返回 HTTP \(status)。"
    case .insufficientDiskSpace(let required, let available):
      "磁盘空间不足：至少需要 \(required) 字节，当前可用 \(available) 字节。"
    case .contentLengthMismatch(let path):
      "模型文件下载大小与清单不一致：\(path)"
    }
  }
}

enum ModelCatalogDownloadError: LocalizedError, Equatable, Sendable {
  case entryNotFound(packID: String, version: String?)
  case missingDownloadBaseURL(String)
  case invalidDownloadBaseURL(String)
  case disallowedDownloadHost(String)

  var errorDescription: String? {
    switch self {
    case .entryNotFound(let packID, let version):
      let suffix = version.map { "/\($0)" } ?? ""
      return "模型清单中找不到条目：\(packID)\(suffix)。"
    case .missingDownloadBaseURL(let packID):
      return "模型条目没有受信下载地址：\(packID)。"
    case .invalidDownloadBaseURL(let value):
      return "模型下载地址无效：\(value)。"
    case .disallowedDownloadHost(let host):
      return "模型下载主机未被发行包允许：\(host)。"
    }
  }
}

struct ModelPackDownloadProgress: Equatable, Sendable {
  let packID: String
  let filePath: String
  let completedBytes: Int64
  let totalBytes: Int64

  var fractionCompleted: Double {
    guard totalBytes > 0 else { return 0 }
    return min(1, max(0, Double(completedBytes) / Double(totalBytes)))
  }
}

/// Downloads a user-requested model pack into a resumable staging directory.
/// It never changes the active model directly: only ModelPackStore.install can
/// create the installed directory and current pointer after all checks pass.
actor ModelPackDownloadCoordinator {
  private let rootURL: URL
  private let modelStore: ModelPackStore
  private let fileManager: FileManager
  private let session: URLSession
  private let chunkSize = 64 * 1024

  init(
    rootURL: URL,
    modelStore: ModelPackStore? = nil,
    session: URLSession = .shared
  ) {
    self.rootURL = rootURL.standardizedFileURL
    self.modelStore = modelStore ?? ModelPackStore(rootURL: rootURL)
    self.fileManager = .default
    self.session = session
  }

  /// Downloads and atomically installs a manifest from `baseURL`.
  /// `baseURL` itself is never contacted; one request is made for each
  /// manifest-listed relative path only after the user invokes this method.
  @discardableResult
  func download(
    manifest: ModelPackManifest,
    baseURL: URL,
    policy: ModelPackInstallPolicy = .localImport,
    allowedHosts: Set<String>? = nil,
    progress: (@Sendable (ModelPackDownloadProgress) -> Void)? = nil
  ) async throws -> URL {
    try manifest.validate()
    guard let scheme = baseURL.scheme?.lowercased(), ["http", "https"].contains(scheme),
      baseURL.host != nil
    else { throw ModelPackDownloadError.invalidBaseURL }

    let staging = try stagingDirectory(for: manifest)
    try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
    let available = availableDiskSpace(at: staging)
    let existingBytes = existingByteCount(manifest: manifest, staging: staging)
    let required = max(0, manifest.size - existingBytes)
    guard available >= required else {
      throw ModelPackDownloadError.insufficientDiskSpace(required: required, available: available)
    }

    var completedPackBytes: Int64 = 0
    for file in manifest.files {
      try Task.checkCancellation()
      let destination = try safeChild(file.relativePath, of: staging)
      try fileManager.createDirectory(
        at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
      let completedBefore = currentFileByteCount(at: destination)
      if completedBefore == file.byteCount {
        if sha256(url: destination) == file.sha256.lowercased() {
          progress?(
            ModelPackDownloadProgress(
              packID: manifest.packID,
              filePath: file.relativePath,
              completedBytes: completedPackBytes + completedBefore,
              totalBytes: manifest.size))
          completedPackBytes += file.byteCount
          continue
        }
        // A same-sized but corrupted prefix must not be treated as complete;
        // remove it so the next explicit attempt can fetch the file again.
        try fileManager.removeItem(at: destination)
      }
      if completedBefore > file.byteCount {
        try fileManager.removeItem(at: destination)
      }
      let completed = try await downloadFile(
        file: file,
        baseURL: baseURL,
        destination: destination,
        manifest: manifest,
        progressOffset: completedPackBytes,
        allowedHosts: allowedHosts,
        progress: progress)
      guard completed == file.byteCount else {
        throw ModelPackDownloadError.contentLengthMismatch(path: file.relativePath)
      }
      completedPackBytes += completed
    }

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(manifest).write(
      to: try safeChild("manifest.json", of: staging), options: .atomic)
    let installed = try await modelStore.install(
      manifest: manifest, from: staging, policy: policy)
    try? fileManager.removeItem(at: staging)
    return installed
  }

  /// Leaves the staging directory in place so the next explicit invocation
  /// can resume with Range requests. This is intentionally not automatic.
  func resumableStagingDirectory(for manifest: ModelPackManifest) throws -> URL {
    try manifest.validate()
    return try stagingDirectory(for: manifest)
  }

  private func downloadFile(
    file: ModelPackFile,
    baseURL: URL,
    destination: URL,
    manifest: ModelPackManifest,
    progressOffset: Int64,
    allowedHosts: Set<String>?,
    progress: (@Sendable (ModelPackDownloadProgress) -> Void)?
  ) async throws -> Int64 {
    try await ModelDownloadRetry.run {
      try await self.downloadFileAttempt(
        file: file,
        baseURL: baseURL,
        destination: destination,
        manifest: manifest,
        progressOffset: progressOffset,
        allowedHosts: allowedHosts,
        progress: progress)
    }
  }

  private func downloadFileAttempt(
    file: ModelPackFile,
    baseURL: URL,
    destination: URL,
    manifest: ModelPackManifest,
    progressOffset: Int64,
    allowedHosts: Set<String>?,
    progress: (@Sendable (ModelPackDownloadProgress) -> Void)?
  ) async throws -> Int64 {
    let url: URL
    if let rawDownloadURL = file.downloadURL {
      let normalizedAllowedHosts = allowedHosts?.map { $0.lowercased() }
      guard
        let directURL = URL(string: rawDownloadURL),
        ModelPackValidation.isValidDownloadURL(rawDownloadURL),
        let host = directURL.host?.lowercased(),
        normalizedAllowedHosts?.contains(host)
          ?? (host == baseURL.host?.lowercased())
      else { throw ModelPackDownloadError.invalidBaseURL }
      url = directURL
    } else {
      url = baseURL.appendingPathComponent(file.relativePath)
    }
    var offset = currentFileByteCount(at: destination)
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    if offset > 0 { request.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range") }

    let (bytes, response) = try await session.bytes(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw ModelPackDownloadError.invalidResponse
    }
    guard (200...299).contains(http.statusCode) else {
      throw ModelPackDownloadError.httpStatus(http.statusCode)
    }

    // A server that ignores Range is safe: restart this file from zero rather
    // than appending a full response to a partial prefix.
    if offset > 0 && http.statusCode == 200 {
      try fileManager.removeItem(at: destination)
      offset = 0
    }
    let append = offset > 0 && http.statusCode == 206
    let handle = try FileHandle(forWritingTo: destination, createIfMissing: true)
    defer { try? handle.close() }
    if append {
      try handle.seekToEnd()
    } else {
      try handle.truncate(atOffset: 0)
    }

    var completed = offset
    var buffer = Data()
    buffer.reserveCapacity(chunkSize)
    for try await byte in bytes {
      try Task.checkCancellation()
      buffer.append(byte)
      if buffer.count >= chunkSize {
        try handle.write(contentsOf: buffer)
        completed += Int64(buffer.count)
        buffer.removeAll(keepingCapacity: true)
        progress?(
          ModelPackDownloadProgress(
            packID: manifest.packID,
            filePath: file.relativePath,
            completedBytes: progressOffset + completed,
            totalBytes: manifest.size))
      }
    }
    if !buffer.isEmpty {
      try handle.write(contentsOf: buffer)
      completed += Int64(buffer.count)
      progress?(
        ModelPackDownloadProgress(
          packID: manifest.packID,
          filePath: file.relativePath,
          completedBytes: progressOffset + completed,
          totalBytes: manifest.size))
    }
    return completed
  }

  private func stagingDirectory(for manifest: ModelPackManifest) throws -> URL {
    let downloads = rootURL.appendingPathComponent("downloads", isDirectory: true)
    try fileManager.createDirectory(at: downloads, withIntermediateDirectories: true)
    return downloads.appendingPathComponent(
      "\(manifest.packID)-\(manifest.version).partial", isDirectory: true)
  }

  private func safeChild(_ relativePath: String, of directory: URL) throws -> URL {
    guard ModelPackValidation.isSafeRelativePath(relativePath) else {
      throw ModelPackStoreError.unsafePath(relativePath)
    }
    let base = directory.standardizedFileURL
    let candidate = base.appendingPathComponent(relativePath).standardizedFileURL
    let prefix = base.path.hasSuffix("/") ? base.path : base.path + "/"
    guard candidate.path.hasPrefix(prefix) else {
      throw ModelPackStoreError.unsafePath(relativePath)
    }
    return candidate
  }

  private func currentFileByteCount(at url: URL) -> Int64 {
    guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
      let size = attributes[.size] as? NSNumber
    else { return 0 }
    return max(0, size.int64Value)
  }

  private func existingByteCount(manifest: ModelPackManifest, staging: URL) -> Int64 {
    manifest.files.reduce(Int64(0)) { total, file in
      total
        + min(
          file.byteCount,
          currentFileByteCount(at: staging.appendingPathComponent(file.relativePath)))
    }
  }

  private func availableDiskSpace(at url: URL) -> Int64 {
    let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
    return Int64(values?.volumeAvailableCapacityForImportantUsage ?? 0)
  }

  private func sha256(url: URL) -> String {
    (try? FileSHA256.digest(url: url)) ?? ""
  }
}

/// Resolves an already verified Catalog entry into the generic multi-file
/// downloader. The caller must obtain `catalog` from ModelCatalogStore; this
/// type deliberately does not accept raw network bytes or perform trust
/// verification itself.
actor ModelCatalogDownloadCoordinator {
  private let coordinator: ModelPackDownloadCoordinator

  init(
    rootURL: URL,
    modelStore: ModelPackStore? = nil,
    session: URLSession = .shared
  ) {
    self.coordinator = ModelPackDownloadCoordinator(
      rootURL: rootURL, modelStore: modelStore, session: session)
  }

  @discardableResult
  func download(
    catalog: ModelCatalog,
    packID: String,
    version: String? = nil,
    allowedHosts: Set<String>,
    progress: (@Sendable (ModelPackDownloadProgress) -> Void)? = nil
  ) async throws -> URL {
    guard
      let manifest = catalog.entries.first(where: {
        $0.packID == packID && (version == nil || $0.version == version)
      })
    else {
      throw ModelCatalogDownloadError.entryNotFound(packID: packID, version: version)
    }
    guard let rawBaseURL = manifest.downloadBaseURL, !rawBaseURL.isEmpty else {
      throw ModelCatalogDownloadError.missingDownloadBaseURL(packID)
    }
    guard let baseURL = URL(string: rawBaseURL), baseURL.scheme?.lowercased() == "https",
      baseURL.user == nil, baseURL.password == nil, baseURL.query == nil,
      baseURL.fragment == nil, let host = baseURL.host?.lowercased(), !host.isEmpty
    else {
      throw ModelCatalogDownloadError.invalidDownloadBaseURL(rawBaseURL)
    }
    let normalizedHosts = Set(allowedHosts.map { $0.lowercased() })
    guard normalizedHosts.contains(host) else {
      throw ModelCatalogDownloadError.disallowedDownloadHost(host)
    }
    return try await coordinator.download(
      manifest: manifest,
      baseURL: baseURL,
      policy: .storeCatalog,
      allowedHosts: allowedHosts,
      progress: progress)
  }
}

extension FileHandle {
  fileprivate convenience init(forWritingTo url: URL, createIfMissing: Bool) throws {
    if createIfMissing && !FileManager.default.fileExists(atPath: url.path) {
      FileManager.default.createFile(atPath: url.path, contents: nil)
    }
    try self.init(forWritingTo: url)
  }
}
