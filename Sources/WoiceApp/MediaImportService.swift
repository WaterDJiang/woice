@preconcurrency import AVFoundation
import CryptoKit
import Foundation
import UniformTypeIdentifiers
import WoiceCore

struct ImportedMediaResult: Sendable {
  let id: UUID
  let sourceKind: RecordingSourceKind
  let originalFileName: String
  let originalURL: URL
  let originalSHA256: String
  let originalByteCount: Int64
  let derivedAudioURL: URL
  let duration: TimeInterval
}

enum MediaImportError: LocalizedError, Equatable, Sendable {
  case unsupportedFileType
  case originalFileMissing
  case originalFileEmpty
  case noAudioTrack
  case unableToDecodeAudio
  case copyFailed(String)
  case extractionFailed(String)
  case preparationFailed(String)

  var errorDescription: String? {
    switch self {
    case .unsupportedFileType: "不支持此文件类型；请选择 WAV、MP3、M4A、AAC、AIFF、CAF、FLAC、MP4、MOV 或 M4V。"
    case .originalFileMissing: "找不到要导入的文件。"
    case .originalFileEmpty: "文件为空，未创建素材。"
    case .noAudioTrack: "视频没有可用音轨，未创建素材。"
    case .unableToDecodeAudio: "无法解码音频；原始文件未被覆盖。"
    case .copyFailed(let message): "原始文件保存失败：\(message)"
    case .extractionFailed(let message): "视频音轨提取失败：\(message)"
    case .preparationFailed(let message): "导入音频准备失败：\(message)"
    }
  }
}

private final class AssetExportSessionBox: @unchecked Sendable {
  let session: AVAssetExportSession

  init(_ session: AVAssetExportSession) {
    self.session = session
  }
}

@MainActor
enum MediaImportService {
  static let allowedContentTypes: [UTType] = [
    "wav", "mp3", "m4a", "aac", "aiff", "aif", "caf", "flac", "mp4", "mov", "m4v",
  ].compactMap { UTType(filenameExtension: $0) }

  private static let audioExtensions: Set<String> = [
    "wav", "mp3", "m4a", "aac", "aiff", "aif", "caf", "flac",
  ]
  private static let videoExtensions: Set<String> = ["mp4", "mov", "m4v"]

  static func importFile(
    sourceURL: URL,
    recordingsDirectory: URL,
    id: UUID = UUID()
  ) async throws -> ImportedMediaResult {
    guard FileManager.default.fileExists(atPath: sourceURL.path) else {
      throw MediaImportError.originalFileMissing
    }
    let values = try sourceURL.resourceValues(forKeys: [.fileSizeKey])
    guard (values.fileSize ?? 0) > 0 else { throw MediaImportError.originalFileEmpty }

    let extensionName = sourceURL.pathExtension.lowercased()
    let isVideo = videoExtensions.contains(extensionName)
    let isAudio = audioExtensions.contains(extensionName)
    guard isAudio || isVideo else { throw MediaImportError.unsupportedFileType }

    let fileManager = FileManager.default
    try fileManager.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)
    // Keep a UUID-owned storage prefix for collision resistance while
    // retaining the user's original basename for the material title and
    // Finder-facing metadata. The path remains inside Woice's controlled
    // recordings directory.
    let originalFileName = "\(id.uuidString).source.\(sourceURL.lastPathComponent)"
    let originalURL = recordingsDirectory.appendingPathComponent(originalFileName)
    let derivedAudioURL = recordingsDirectory.appendingPathComponent("\(id.uuidString).wav")
    let temporaryExtractionURL = recordingsDirectory.appendingPathComponent(
      ".\(id.uuidString).extracted.m4a")
    do {
      try fileManager.copyItem(at: sourceURL, to: originalURL)
      let originalSHA256 = try sha256(url: originalURL)
      let decodeURL: URL
      if isVideo {
        try await extractAudio(from: originalURL, to: temporaryExtractionURL)
        decodeURL = temporaryExtractionURL
      } else {
        decodeURL = originalURL
      }
      try AudioPreparationService.prepareTranscriptionAudio(
        sourceURL: decodeURL, outputURL: derivedAudioURL)
      guard let audioFile = try? AVAudioFile(forReading: derivedAudioURL), audioFile.length > 0,
        audioFile.processingFormat.sampleRate > 0
      else {
        throw MediaImportError.unableToDecodeAudio
      }
      let duration = Double(audioFile.length) / audioFile.processingFormat.sampleRate
      return ImportedMediaResult(
        id: id,
        sourceKind: isVideo ? RecordingSourceKind.importedVideo : RecordingSourceKind.importedAudio,
        originalFileName: sourceURL.lastPathComponent,
        originalURL: originalURL,
        originalSHA256: originalSHA256,
        originalByteCount: Int64(values.fileSize ?? 0),
        derivedAudioURL: derivedAudioURL,
        duration: duration)
    } catch let error as MediaImportError {
      try? fileManager.removeItem(at: originalURL)
      try? fileManager.removeItem(at: derivedAudioURL)
      try? fileManager.removeItem(at: temporaryExtractionURL)
      throw error
    } catch let error as AudioPreparationError {
      try? fileManager.removeItem(at: originalURL)
      try? fileManager.removeItem(at: derivedAudioURL)
      try? fileManager.removeItem(at: temporaryExtractionURL)
      throw MediaImportError.preparationFailed(error.localizedDescription)
    } catch {
      try? fileManager.removeItem(at: originalURL)
      try? fileManager.removeItem(at: derivedAudioURL)
      try? fileManager.removeItem(at: temporaryExtractionURL)
      throw MediaImportError.copyFailed(error.localizedDescription)
    }
  }

  private static func extractAudio(from sourceURL: URL, to outputURL: URL) async throws {
    let asset = AVURLAsset(url: sourceURL)
    let tracks: [AVAssetTrack]
    do {
      tracks = try await asset.loadTracks(withMediaType: .audio)
    } catch {
      // A container that cannot be opened is a media/extraction failure, not
      // a failure to copy the immutable original. Keep the user-facing error
      // stable and avoid exposing a filesystem path from AVFoundation.
      throw MediaImportError.extractionFailed("无法读取视频音轨；文件可能损坏或格式不受支持。")
    }
    guard !tracks.isEmpty else {
      throw MediaImportError.noAudioTrack
    }
    guard
      let exporter = AVAssetExportSession(
        asset: asset, presetName: AVAssetExportPresetAppleM4A)
    else { throw MediaImportError.extractionFailed("当前系统无法创建音轨导出器。") }
    try? FileManager.default.removeItem(at: outputURL)
    exporter.outputURL = outputURL
    exporter.outputFileType = .m4a
    exporter.shouldOptimizeForNetworkUse = false
    let box = AssetExportSessionBox(exporter)
    try await withCheckedThrowingContinuation { continuation in
      box.session.exportAsynchronously {
        switch box.session.status {
        case .completed:
          continuation.resume()
        case .cancelled:
          continuation.resume(throwing: MediaImportError.extractionFailed("用户取消了导入。"))
        default:
          continuation.resume(
            throwing: MediaImportError.extractionFailed(
              box.session.error?.localizedDescription ?? "系统未返回具体原因。"))
        }
      }
    }
  }

  private static func sha256(url: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var digest = SHA256()
    while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
      digest.update(data: chunk)
    }
    return digest.finalize().map { String(format: "%02x", $0) }.joined()
  }
}
