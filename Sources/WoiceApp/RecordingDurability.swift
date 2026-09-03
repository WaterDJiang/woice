@preconcurrency import AVFoundation
import CryptoKit
import Darwin
import Foundation
import WoiceCore

/// A closed, hashed audio block. The file is renamed to its committed name
/// before this value is published, so a descriptor never points at a
/// still-open container.
struct RecordingChunkDescriptor: Codable, Equatable, Hashable, Sendable {
  let index: Int
  let track: AudioTrackKind
  let fileName: String
  let startOffset: TimeInterval
  let duration: TimeInterval
  let byteCount: Int64
  let sha256: String

  init(
    index: Int,
    track: AudioTrackKind,
    fileName: String,
    startOffset: TimeInterval,
    duration: TimeInterval,
    byteCount: Int64,
    sha256: String
  ) {
    self.index = index
    self.track = track
    self.fileName = fileName
    self.startOffset = max(0, startOffset)
    self.duration = max(0, duration)
    self.byteCount = max(0, byteCount)
    self.sha256 = sha256
  }
}

struct RecordingSessionManifest: Codable, Equatable, Sendable {
  static let currentSchemaVersion = 1
  let schemaVersion: Int
  let sessionID: UUID
  let createdAt: Date
  let chunkDuration: TimeInterval
  let expectedTracks: [AudioTrackKind]
  var updatedAt: Date
  var committedChunks: [RecordingChunkDescriptor]
  var lastError: String?

  init(
    sessionID: UUID,
    createdAt: Date = Date(),
    chunkDuration: TimeInterval = RecordingDurabilityPolicy.chunkDuration,
    expectedTracks: [AudioTrackKind],
    updatedAt: Date = Date(),
    committedChunks: [RecordingChunkDescriptor] = [],
    lastError: String? = nil
  ) {
    self.schemaVersion = Self.currentSchemaVersion
    self.sessionID = sessionID
    self.createdAt = createdAt
    self.chunkDuration = max(1, chunkDuration)
    self.expectedTracks = Array(Set(expectedTracks)).sorted { $0.rawValue < $1.rawValue }
    self.updatedAt = updatedAt
    self.committedChunks = committedChunks.sorted {
      ($0.track.rawValue, $0.index) < ($1.track.rawValue, $1.index)
    }
    self.lastError = lastError
  }

  var isValid: Bool {
    let chunkKeys = committedChunks.map { "\($0.track.rawValue):\($0.index)" }
    return schemaVersion == Self.currentSchemaVersion
      && !expectedTracks.isEmpty
      && expectedTracks.allSatisfy { $0 != .meetingMix }
      && Set(chunkKeys).count == chunkKeys.count
      && committedChunks.allSatisfy {
        $0.index >= 0 && $0.duration > 0 && $0.byteCount > 0 && $0.sha256.count == 64
          && expectedTracks.contains($0.track)
          && $0.fileName.hasSuffix(".committed.m4a")
          && $0.sha256.allSatisfy { $0.isHexDigit }
      }
  }

  func chunks(for track: AudioTrackKind) -> [RecordingChunkDescriptor] {
    committedChunks.filter { $0.track == track }.sorted { $0.index < $1.index }
  }

  var committedDurationByTrack: [AudioTrackKind: TimeInterval] {
    Dictionary(
      uniqueKeysWithValues: expectedTracks.map { track in
        (track, chunks(for: track).map(\.duration).reduce(0, +))
      })
  }
}

enum RecordingDurabilityPolicy {
  static let chunkDuration: TimeInterval = 10
  static let maximumUncommittedTail: TimeInterval = chunkDuration
}

enum RecordingDurabilityError: LocalizedError, Equatable {
  case invalidManifest
  case manifestMissing
  case chunkMissing(String)
  case chunkDigestMismatch(String)
  case unsupportedTrack(AudioTrackKind)
  case rebuildFailed(String)

  var errorDescription: String? {
    switch self {
    case .invalidManifest: "录音清单格式无效，已拒绝恢复。"
    case .manifestMissing: "找不到录音块清单。"
    case .chunkMissing(let fileName): "找不到已提交录音块：\(fileName)。"
    case .chunkDigestMismatch(let fileName): "录音块校验失败：\(fileName)。"
    case .unsupportedTrack(let track): "不支持恢复音轨：\(track.label)。"
    case .rebuildFailed(let message): "录音块重建失败：\(message)"
    }
  }
}

/// Owns one manifest file and its chunk directory. It is deliberately
/// lock-based: audio callbacks arrive on realtime queues while recovery and
/// cleanup run on the MainActor.
final class RecordingChunkManifestStore: @unchecked Sendable {
  let sessionID: UUID
  let manifestURL: URL
  let chunkDirectoryURL: URL
  private let fileManager: FileManager
  private let lock = NSLock()
  private var manifest: RecordingSessionManifest

  init(
    rootURL: URL,
    sessionID: UUID,
    expectedTracks: [AudioTrackKind],
    createdAt: Date = Date(),
    fileManager: FileManager = .default
  ) throws {
    guard !expectedTracks.isEmpty, !expectedTracks.contains(.meetingMix) else {
      throw RecordingDurabilityError.invalidManifest
    }
    self.sessionID = sessionID
    self.fileManager = fileManager
    manifestURL = rootURL.appendingPathComponent("\(sessionID.uuidString).manifest.json")
    chunkDirectoryURL = rootURL.appendingPathComponent(
      "\(sessionID.uuidString).chunks", isDirectory: true)
    manifest = RecordingSessionManifest(
      sessionID: sessionID, createdAt: createdAt, expectedTracks: expectedTracks)
    try fileManager.createDirectory(at: chunkDirectoryURL, withIntermediateDirectories: true)
    try persistLocked()
  }

  /// Reopens a manifest left by a crashed recording. No new manifest is
  /// created and no malformed data is accepted.
  init(recovering manifestURL: URL, fileManager: FileManager = .default) throws {
    self.fileManager = fileManager
    self.manifestURL = manifestURL
    let data: Data
    do { data = try Data(contentsOf: manifestURL) } catch {
      throw RecordingDurabilityError.manifestMissing
    }
    guard let decoded = try? JSONDecoder.woice.decode(RecordingSessionManifest.self, from: data),
      decoded.isValid
    else { throw RecordingDurabilityError.invalidManifest }
    sessionID = decoded.sessionID
    manifest = decoded
    chunkDirectoryURL = manifestURL.deletingPathExtension()
      .deletingPathExtension()
      .appendingPathExtension("chunks")
    // The canonical name is <UUID>.manifest.json; deleting both extensions
    // yields <UUID>, then appending .chunks preserves that contract.
  }

  func snapshot() -> RecordingSessionManifest {
    lock.lock()
    defer { lock.unlock() }
    return manifest
  }

  func commit(_ chunk: RecordingChunkCommit) throws {
    lock.lock()
    defer { lock.unlock() }
    guard chunk.sessionID == sessionID, chunk.track != .meetingMix else {
      throw RecordingDurabilityError.invalidManifest
    }
    let canonicalDirectory = chunkDirectoryURL.standardizedFileURL
    let chunkDirectory = chunk.url.deletingLastPathComponent().standardizedFileURL
    guard chunkDirectory == canonicalDirectory,
      chunk.url.lastPathComponent.hasSuffix(".committed.m4a"),
      let parsed = parseChunkName(chunk.url.lastPathComponent),
      parsed.track == chunk.track,
      parsed.index == chunk.index
    else {
      throw RecordingDurabilityError.invalidManifest
    }
    guard fileManager.fileExists(atPath: chunk.url.path) else {
      throw RecordingDurabilityError.chunkMissing(chunk.url.lastPathComponent)
    }
    let attributes = try fileManager.attributesOfItem(atPath: chunk.url.path)
    let byteCount = (attributes[.size] as? NSNumber)?.int64Value ?? 0
    guard byteCount > 0 else {
      throw RecordingDurabilityError.chunkMissing(chunk.url.lastPathComponent)
    }
    let digest = try FileSHA256.digest(url: chunk.url)
    if let expectedDigest = chunk.sha256, !expectedDigest.isEmpty,
      digest != expectedDigest
    {
      throw RecordingDurabilityError.chunkDigestMismatch(chunk.url.lastPathComponent)
    }
    let previousManifest = manifest
    let descriptor = RecordingChunkDescriptor(
      index: chunk.index,
      track: chunk.track,
      fileName: chunk.url.lastPathComponent,
      startOffset: chunk.startOffset,
      duration: chunk.duration,
      byteCount: byteCount,
      sha256: digest)
    manifest.committedChunks.removeAll {
      $0.track == descriptor.track && $0.index == descriptor.index
    }
    manifest.committedChunks.append(descriptor)
    manifest.committedChunks.sort {
      ($0.track.rawValue, $0.index) < ($1.track.rawValue, $1.index)
    }
    manifest.updatedAt = Date()
    manifest.lastError = nil
    do {
      try persistLocked()
    } catch {
      // Do not publish an in-memory descriptor unless the persistence call
      // succeeds. The committed file remains in place so a later recovery
      // pass can reconcile it as an orphan, even if the failure happened
      // after the filesystem replaced the Manifest but before directory sync.
      manifest = previousManifest
      throw error
    }
  }

  func recordError(_ error: Error) {
    lock.lock()
    defer { lock.unlock() }
    manifest.lastError = error.localizedDescription
    manifest.updatedAt = Date()
    try? persistLocked()
  }

  /// Closes the small crash window between a committed-file rename and the
  /// following Manifest transaction. A filename and readable container are
  /// sufficient to reconstruct the descriptor; uncommitted partial files are
  /// quarantined for inspection and never guessed into a transcript.
  func reconcileOrphanedChunks() {
    guard
      let names = try? fileManager.contentsOfDirectory(
        atPath: chunkDirectoryURL.path)
    else { return }
    let current = snapshot().committedChunks
    let known = Set(current.map { "\($0.track.rawValue):\($0.index)" })
    let quarantineURL = chunkDirectoryURL.appendingPathComponent("quarantine", isDirectory: true)
    for name in names {
      if name.hasSuffix(".partial.m4a") {
        let partialURL = chunkDirectoryURL.appendingPathComponent(name)
        try? fileManager.createDirectory(at: quarantineURL, withIntermediateDirectories: true)
        try? fileManager.moveItem(
          at: partialURL,
          to: quarantineURL.appendingPathComponent("\(Date().timeIntervalSince1970)-\(name)"))
        continue
      }
      guard name.hasSuffix(".committed.m4a"),
        let parsed = parseChunkName(name),
        expectedTrack(parsed.track),
        !known.contains("\(parsed.track.rawValue):\(parsed.index)")
      else { continue }
      let url = chunkDirectoryURL.appendingPathComponent(name)
      guard let file = try? AVAudioFile(forReading: url), file.length > 0,
        file.processingFormat.sampleRate > 0
      else { continue }
      let duration = Double(file.length) / file.processingFormat.sampleRate
      guard let digest = try? FileSHA256.digest(url: url) else { continue }
      do {
        try commit(
          RecordingChunkCommit(
            sessionID: sessionID,
            index: parsed.index,
            track: parsed.track,
            url: url,
            startOffset: Double(parsed.index) * snapshot().chunkDuration,
            duration: duration,
            sha256: digest))
      } catch {
        recordError(error)
      }
    }
  }

  /// Verifies every committed block and quarantines anything that is not
  /// trusted. Quarantine is recoverable and never silently deletes user data.
  func verifiedChunks() throws -> [RecordingChunkDescriptor] {
    lock.lock()
    let current = manifest
    lock.unlock()
    guard current.isValid else { throw RecordingDurabilityError.invalidManifest }
    let quarantineURL = chunkDirectoryURL.appendingPathComponent("quarantine", isDirectory: true)
    var verified: [RecordingChunkDescriptor] = []
    for chunk in current.committedChunks {
      let url = chunkDirectoryURL.appendingPathComponent(chunk.fileName)
      guard fileManager.fileExists(atPath: url.path) else {
        throw RecordingDurabilityError.chunkMissing(chunk.fileName)
      }
      let digest = try FileSHA256.digest(url: url)
      guard digest == chunk.sha256 else {
        try? fileManager.createDirectory(at: quarantineURL, withIntermediateDirectories: true)
        let target = quarantineURL.appendingPathComponent(
          "\(Date().timeIntervalSince1970)-\(chunk.fileName)")
        try? fileManager.moveItem(at: url, to: target)
        throw RecordingDurabilityError.chunkDigestMismatch(chunk.fileName)
      }
      verified.append(chunk)
    }
    return verified
  }

  /// Removes only the temporary chunk directory and manifest after the final
  /// Recording transaction has committed.
  func clear() {
    lock.lock()
    defer { lock.unlock() }
    try? fileManager.removeItem(at: manifestURL)
    try? fileManager.removeItem(at: chunkDirectoryURL)
  }

  private func persistLocked() throws {
    let data = try JSONEncoder.woice.encode(manifest)
    try atomicSynchronizedWrite(data, to: manifestURL, fileManager: fileManager)
  }

  private func expectedTrack(_ track: AudioTrackKind) -> Bool {
    snapshot().expectedTracks.contains(track)
  }

  private func parseChunkName(_ name: String) -> (track: AudioTrackKind, index: Int)? {
    let parts = name.split(separator: "-")
    guard parts.count == 3,
      parts[1] == "chunk",
      parts[2].hasSuffix(".committed.m4a")
    else { return nil }
    let indexText = parts[2].dropLast(".committed.m4a".count)
    guard let index = Int(indexText), index >= 0,
      let track = AudioTrackKind(rawValue: String(parts[0]))
    else { return nil }
    return (track, index)
  }
}

struct RecordingChunkCommit: Sendable {
  let sessionID: UUID
  let index: Int
  let track: AudioTrackKind
  let url: URL
  let startOffset: TimeInterval
  let duration: TimeInterval
  /// An expected digest supplied by a caller that already computed one. The
  /// rolling writer leaves this nil so the committer can hash off the audio
  /// callback; the Manifest always stores the digest it computed itself.
  let sha256: String?
}

/// Moves hashing and Manifest I/O off realtime audio callbacks. Chunks are
/// submitted in callback order and drained once before the final Recording
/// transaction, so the UI never observes a committed Recording before its
/// durable chunk metadata has caught up.
final class RecordingChunkCommitter: @unchecked Sendable {
  private let queue: DispatchQueue
  private let group = DispatchGroup()
  private let lock = NSLock()
  private let manifest: RecordingChunkManifestStore
  private var error: String?

  init(manifest: RecordingChunkManifestStore) {
    self.manifest = manifest
    queue = DispatchQueue(
      label: "com.woice.recording-manifest-\(manifest.sessionID.uuidString)", qos: .utility)
  }

  func submit(_ chunk: RecordingChunkCommit) {
    group.enter()
    queue.async { [manifest, self] in
      defer { self.group.leave() }
      do {
        try manifest.commit(chunk)
      } catch {
        self.lock.lock()
        if self.error == nil { self.error = error.localizedDescription }
        self.lock.unlock()
        manifest.recordError(error)
      }
    }
  }

  func flush() {
    group.wait()
  }

  var lastError: String? {
    lock.lock()
    defer { lock.unlock() }
    return error ?? manifest.snapshot().lastError
  }

  /// Async counterpart used by the stop path so hashing already-closed blocks
  /// never monopolizes the MainActor. The synchronous form remains available
  /// for cancellation/recovery paths and deterministic unit tests.
  func flushAsync() async {
    await withCheckedContinuation { continuation in
      group.notify(queue: queue) {
        continuation.resume()
      }
    }
  }
}

/// A rolling writer used by the microphone and ScreenCaptureKit callbacks.
/// Blocks are slightly longer than ten seconds by at most one input buffer;
/// that upper bound is the explicit uncommitted-tail SLO.
final class RollingPCMChunkWriter: @unchecked Sendable {
  let sessionID: UUID
  let track: AudioTrackKind
  let directoryURL: URL
  let chunkDuration: TimeInterval
  private let sampleRate: Double
  private let format: AVAudioFormat
  private var file: AVAudioFile?
  private var index = 0
  private var frameCount: AVAudioFramePosition = 0
  private var chunkStartFrame: AVAudioFramePosition = 0

  init(
    sessionID: UUID,
    track: AudioTrackKind,
    directoryURL: URL,
    format: AVAudioFormat,
    chunkDuration: TimeInterval = RecordingDurabilityPolicy.chunkDuration
  ) throws {
    guard track != .meetingMix, format.sampleRate > 0, format.channelCount > 0 else {
      throw RecordingDurabilityError.unsupportedTrack(track)
    }
    self.sessionID = sessionID
    self.track = track
    self.directoryURL = directoryURL
    self.format = format
    sampleRate = format.sampleRate
    self.chunkDuration = max(1, chunkDuration)
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
  }

  func append(_ buffer: AVAudioPCMBuffer) throws -> [RecordingChunkCommit] {
    guard buffer.frameLength > 0 else { return [] }
    if file == nil { try openNextFile() }
    guard let file else { return [] }
    try file.write(from: buffer)
    frameCount += AVAudioFramePosition(buffer.frameLength)
    guard Double(frameCount - chunkStartFrame) / sampleRate >= chunkDuration else { return [] }
    return try closeCurrentChunk()
  }

  func finish() throws -> [RecordingChunkCommit] {
    guard file != nil, frameCount > chunkStartFrame else { return [] }
    return try closeCurrentChunk()
  }

  private func openNextFile() throws {
    let name = String(format: "\(track.rawValue)-chunk-%04d.partial.m4a", index)
    let url = directoryURL.appendingPathComponent(name)
    try? FileManager.default.removeItem(at: url)
    let settings = RecordingAudioFormat.aacSettings(
      sampleRate: format.sampleRate, channelCount: Int(format.channelCount), bitRate: 64_000)
    file = try AVAudioFile(
      forWriting: url, settings: settings,
      commonFormat: format.commonFormat, interleaved: format.isInterleaved)
    chunkStartFrame = frameCount
  }

  private func closeCurrentChunk() throws -> [RecordingChunkCommit] {
    let partialURL = directoryURL.appendingPathComponent(
      String(format: "\(track.rawValue)-chunk-%04d.partial.m4a", index))
    let committedURL = directoryURL.appendingPathComponent(
      String(format: "\(track.rawValue)-chunk-%04d.committed.m4a", index))
    if #available(macOS 15.0, *) { file?.close() }
    file = nil
    try synchronizeFileContents(at: partialURL)
    let attributes = try FileManager.default.attributesOfItem(atPath: partialURL.path)
    let byteCount = (attributes[.size] as? NSNumber)?.int64Value ?? 0
    guard byteCount > 0 else {
      throw RecordingDurabilityError.chunkMissing(partialURL.lastPathComponent)
    }
    try? FileManager.default.removeItem(at: committedURL)
    try FileManager.default.moveItem(at: partialURL, to: committedURL)
    synchronizeDirectoryContents(at: directoryURL)
    let descriptor = RecordingChunkCommit(
      sessionID: sessionID,
      index: index,
      track: track,
      url: committedURL,
      startOffset: Double(chunkStartFrame) / sampleRate,
      duration: Double(frameCount - chunkStartFrame) / sampleRate,
      sha256: nil)
    index += 1
    chunkStartFrame = frameCount
    return [descriptor]
  }
}

private func synchronizeFileContents(at url: URL) throws {
  let handle = try FileHandle(forWritingTo: url)
  try handle.synchronize()
  try handle.close()
}

private func synchronizeDirectoryContents(at url: URL) {
  let descriptor = open(url.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
  guard descriptor >= 0 else { return }
  _ = fsync(descriptor)
  _ = close(descriptor)
}

enum RecordingChunkRebuilder {
  /// Re-encodes verified committed blocks into the requested output path. It
  /// never mutates a source block and writes through a temporary sibling.
  static func rebuild(
    chunks: [RecordingChunkDescriptor],
    directoryURL: URL,
    outputURL: URL
  ) throws -> TimeInterval {
    guard !chunks.isEmpty else { throw RecordingDurabilityError.rebuildFailed("没有可用录音块。") }
    let ordered = chunks.sorted { $0.index < $1.index }
    let sourceURLs = ordered.map { directoryURL.appendingPathComponent($0.fileName) }
    guard sourceURLs.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) else {
      throw RecordingDurabilityError.rebuildFailed("录音块文件缺失。")
    }
    let first = try AVAudioFile(forReading: sourceURLs[0])
    let format = first.processingFormat
    guard format.sampleRate > 0, format.channelCount > 0 else {
      throw RecordingDurabilityError.rebuildFailed("录音块格式无效。")
    }
    let temporaryURL = outputURL.appendingPathExtension("rebuilding")
    try? FileManager.default.removeItem(at: temporaryURL)
    let settings =
      outputURL.pathExtension.lowercased() == "m4a"
      ? RecordingAudioFormat.aacSettings(
        sampleRate: format.sampleRate, channelCount: Int(format.channelCount), bitRate: 64_000)
      : format.settings
    let output = try AVAudioFile(
      forWriting: temporaryURL,
      settings: settings,
      commonFormat: format.commonFormat,
      interleaved: format.isInterleaved)
    defer {
      if #available(macOS 15.0, *) { output.close() }
      try? FileManager.default.removeItem(at: temporaryURL)
    }
    for sourceURL in sourceURLs {
      let source = try AVAudioFile(forReading: sourceURL)
      let frameCount = AVAudioFrameCount(source.length)
      guard frameCount > 0,
        let buffer = AVAudioPCMBuffer(pcmFormat: source.processingFormat, frameCapacity: frameCount)
      else { throw RecordingDurabilityError.rebuildFailed("录音块为空。") }
      try source.read(into: buffer, frameCount: frameCount)
      try output.write(from: buffer)
    }
    if FileManager.default.fileExists(atPath: outputURL.path) {
      try FileManager.default.removeItem(at: outputURL)
    }
    try FileManager.default.moveItem(at: temporaryURL, to: outputURL)
    return ordered.map(\.duration).reduce(0, +)
  }
}

private func atomicSynchronizedWrite(
  _ data: Data,
  to url: URL,
  fileManager: FileManager
) throws {
  let temporaryURL = url.appendingPathExtension("tmp-\(UUID().uuidString)")
  defer { try? fileManager.removeItem(at: temporaryURL) }
  try data.write(to: temporaryURL, options: .atomic)
  let handle = try FileHandle(forWritingTo: temporaryURL)
  try handle.synchronize()
  try handle.close()
  if fileManager.fileExists(atPath: url.path) {
    _ = try fileManager.replaceItemAt(url, withItemAt: temporaryURL)
  } else {
    try fileManager.moveItem(at: temporaryURL, to: url)
  }
  let directoryDescriptor = open(
    url.deletingLastPathComponent().path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
  if directoryDescriptor >= 0 {
    _ = fsync(directoryDescriptor)
    _ = close(directoryDescriptor)
  }
}
