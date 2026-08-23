import CryptoKit
import Foundation
import WoiceCore

struct ContextPackageBuildItem: Sendable {
  let reference: ContextArtifactReference
  let text: String?
  let sourceURL: URL?

  init(reference: ContextArtifactReference, text: String? = nil, sourceURL: URL? = nil) {
    self.reference = reference
    self.text = text
    self.sourceURL = sourceURL
  }
}

struct ContextPackageBundle: Sendable {
  let package: ContextPackage
  let directoryURL: URL
  let contextURL: URL
  let transcriptURL: URL
  let audioURLs: [URL]
}

enum ContextPackageBuilderError: LocalizedError, Equatable, Sendable {
  case noItems
  case duplicateArtifact
  case sourceMissing
  case sourceNotRegular
  case sourceTooLarge
  case transcriptTooLarge
  case unableToCreateDirectory
  case unableToWritePackage

  var errorDescription: String? {
    switch self {
    case .noItems: "没有可交给外部 Agent 的素材。"
    case .duplicateArtifact: "派发素材包含重复 Artifact。"
    case .sourceMissing: "选定的音频素材文件不存在。"
    case .sourceNotRegular: "选定的音频素材不是普通文件，已拒绝打包。"
    case .sourceTooLarge: "选定的音频文件超过 512 MiB 安全上限。"
    case .transcriptTooLarge: "派发原文超过 16 MiB 安全上限。"
    case .unableToCreateDirectory: "无法创建外部 Agent 的临时上下文目录。"
    case .unableToWritePackage: "无法写入外部 Agent 的上下文文件。"
    }
  }
}

/// Builds an immutable, bounded handoff directory. It only copies explicitly
/// selected files and never mutates the source Recording or Transcript.
final class ContextPackageBuilder: @unchecked Sendable {
  private let fileManager: FileManager
  private let maxAudioBytes: Int64 = 512 * 1024 * 1024
  private let maxTranscriptBytes = 16 * 1024 * 1024

  init(fileManager: FileManager = .default) {
    self.fileManager = fileManager
  }

  func build(
    items: [ContextPackageBuildItem],
    instruction: String,
    packageID: UUID = UUID(),
    createdAt: Date = Date(),
    rootURL: URL? = nil
  ) throws -> ContextPackageBundle {
    guard !items.isEmpty else { throw ContextPackageBuilderError.noItems }
    guard Set(items.map(\.reference.artifactID)).count == items.count else {
      throw ContextPackageBuilderError.duplicateArtifact
    }

    let directoryRoot = rootURL ?? fileManager.temporaryDirectory
    let directory = directoryRoot.appendingPathComponent(
      "woice-context-\(packageID.uuidString)", isDirectory: true)
    do {
      try fileManager.createDirectory(at: directory, withIntermediateDirectories: false)
      try fileManager.setAttributes(
        [.posixPermissions: NSNumber(value: Int16(0o700))], ofItemAtPath: directory.path)
    } catch {
      throw ContextPackageBuilderError.unableToCreateDirectory
    }

    do {
      let transcriptURL = directory.appendingPathComponent("transcript.md")
      let transcript = renderTranscript(items)
      let transcriptData = Data(transcript.utf8)
      guard transcriptData.count <= maxTranscriptBytes else {
        throw ContextPackageBuilderError.transcriptTooLarge
      }
      try transcriptData.write(to: transcriptURL, options: .atomic)
      try makeReadOnly(transcriptURL)

      var files = [
        ContextPackageFile(
          role: .transcriptMarkdown,
          relativePath: "transcript.md",
          artifactID: items[0].reference.artifactID,
          sha256: sha256(data: transcriptData))
      ]
      var audioURLs: [URL] = []
      let audioDirectory = directory.appendingPathComponent("audio", isDirectory: true)
      if items.contains(where: { $0.sourceURL != nil }) {
        try fileManager.createDirectory(at: audioDirectory, withIntermediateDirectories: false)
        try fileManager.setAttributes(
          [.posixPermissions: NSNumber(value: Int16(0o700))], ofItemAtPath: audioDirectory.path)
      }
      for (index, item) in items.enumerated() {
        guard let sourceURL = item.sourceURL else { continue }
        let attributes = try? fileManager.attributesOfItem(atPath: sourceURL.path)
        guard fileManager.fileExists(atPath: sourceURL.path) else {
          throw ContextPackageBuilderError.sourceMissing
        }
        guard (attributes?[.type] as? FileAttributeType) == .typeRegular else {
          throw ContextPackageBuilderError.sourceNotRegular
        }
        guard let size = attributes?[.size] as? NSNumber, size.int64Value <= maxAudioBytes else {
          throw ContextPackageBuilderError.sourceTooLarge
        }
        let extensionName = safeExtension(sourceURL.pathExtension)
        let relativePath = String(
          format: "audio/%03d-%@.%@", index, item.reference.kind.rawValue, extensionName)
        let destination = directory.appendingPathComponent(relativePath)
        try fileManager.copyItem(at: sourceURL, to: destination)
        try makeReadOnly(destination)
        files.append(
          ContextPackageFile(
            role: .audio,
            relativePath: relativePath,
            artifactID: item.reference.artifactID,
            sha256: sha256(url: destination)))
        audioURLs.append(destination)
      }

      let contentHash = packageHash(
        artifactRefs: items.map(\.reference), files: files, instruction: instruction)
      let package = ContextPackage(
        id: packageID,
        createdAt: createdAt,
        artifactRefs: items.map(\.reference),
        files: files,
        instruction: instruction,
        contentHash: contentHash)
      _ = try package.validated()
      let contextURL = directory.appendingPathComponent("context.json")
      try JSONEncoder.woice.encode(package).write(to: contextURL, options: .atomic)
      try makeReadOnly(contextURL)
      return ContextPackageBundle(
        package: package,
        directoryURL: directory,
        contextURL: contextURL,
        transcriptURL: transcriptURL,
        audioURLs: audioURLs)
    } catch let error as ContextPackageBuilderError {
      try? fileManager.removeItem(at: directory)
      throw error
    } catch {
      try? fileManager.removeItem(at: directory)
      throw ContextPackageBuilderError.unableToWritePackage
    }
  }

  private func renderTranscript(_ items: [ContextPackageBuildItem]) -> String {
    items.enumerated().map { index, item in
      let reference = item.reference
      let range = reference.timeRange.map { "\($0.start)-\($0.end)s" } ?? "full"
      let source = reference.sourceTrack?.label ?? "未指定音轨"
      let text = TranscriptTextNormalizer.normalize(item.text ?? "")
      return
        "## 素材 \(index + 1)\nartifact_id: \(reference.artifactID)\nrecording_id: \(reference.recordingID.uuidString)\n类型: \(reference.kind.rawValue)\n音轨: \(source)\n时间范围: \(range)\n\n\(text)\n"
    }.joined(separator: "\n")
  }

  private func packageHash(
    artifactRefs: [ContextArtifactReference], files: [ContextPackageFile], instruction: String
  ) -> String {
    struct HashInput: Codable {
      let artifactRefs: [ContextArtifactReference]
      let files: [ContextPackageFile]
      let instruction: String
    }
    let input = HashInput(artifactRefs: artifactRefs, files: files, instruction: instruction)
    let data = (try? JSONEncoder.woice.encode(input)) ?? Data()
    return sha256(data: data)
  }

  private func makeReadOnly(_ url: URL) throws {
    try fileManager.setAttributes(
      [.posixPermissions: NSNumber(value: Int16(0o400))], ofItemAtPath: url.path)
  }

  private func safeExtension(_ value: String) -> String {
    let normalized = value.lowercased()
    guard normalized.range(of: #"^[a-z0-9]{1,10}$"#, options: .regularExpression) != nil else {
      return "bin"
    }
    return normalized
  }

  private func sha256(data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private func sha256(url: URL) -> String {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
    defer { try? handle.close() }
    var digest = SHA256()
    while true {
      guard let chunk = try? handle.read(upToCount: 1024 * 1024), !chunk.isEmpty else { break }
      digest.update(data: chunk)
    }
    return digest.finalize().map { String(format: "%02x", $0) }.joined()
  }
}
