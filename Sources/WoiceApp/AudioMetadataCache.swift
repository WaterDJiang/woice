@preconcurrency import AVFoundation
import Foundation
import WoiceCore

/// A small immutable projection used by the detail view. It deliberately
/// contains no audio buffers: existence, file size and duration are enough to
/// render the first frame and choose a playback track.
struct AudioMetadataSnapshot: Equatable, Sendable {
  let url: URL
  let exists: Bool
  let byteCount: Int64?
  let duration: TimeInterval?
  let modifiedAt: Date?
}

/// Reads audio metadata away from the MainActor and reuses it while the file
/// signature is unchanged. A bounded cache prevents a large material library
/// from turning every detail navigation into another AVAudioFile probe.
actor AudioMetadataCache {
  private struct FileSignature: Equatable, Sendable {
    let exists: Bool
    let byteCount: Int64?
    let modifiedAt: Date?
  }

  private struct Entry: Sendable {
    let signature: FileSignature
    let snapshot: AudioMetadataSnapshot
  }

  private let capacity = 32
  private var entries: [URL: Entry] = [:]
  private var order: [URL] = []

  func read(url: URL) -> AudioMetadataSnapshot {
    let signature = signature(for: url)
    if let entry = entries[url], entry.signature == signature {
      touch(url)
      return entry.snapshot
    }

    let duration: TimeInterval?
    if signature.exists,
      let file = try? AVAudioFile(forReading: url),
      file.processingFormat.sampleRate > 0,
      file.length > 0
    {
      duration = Double(file.length) / file.processingFormat.sampleRate
    } else {
      duration = nil
    }
    let snapshot = AudioMetadataSnapshot(
      url: url,
      exists: signature.exists,
      byteCount: signature.byteCount,
      duration: duration,
      modifiedAt: signature.modifiedAt)
    entries[url] = Entry(signature: signature, snapshot: snapshot)
    touch(url)
    trim()
    return snapshot
  }

  func read(urls: [URL]) -> [URL: AudioMetadataSnapshot] {
    var result: [URL: AudioMetadataSnapshot] = [:]
    for url in urls { result[url] = read(url: url) }
    return result
  }

  func invalidate(url: URL) {
    entries.removeValue(forKey: url)
    order.removeAll { $0 == url }
  }

  func invalidateAll() {
    entries.removeAll(keepingCapacity: true)
    order.removeAll(keepingCapacity: true)
  }

  var cachedURLCount: Int { order.count }

  private func signature(for url: URL) -> FileSignature {
    guard
      let values = try? url.resourceValues(
        forKeys: [.fileSizeKey, .contentModificationDateKey]),
      let byteCount = values.fileSize
    else {
      return FileSignature(exists: false, byteCount: nil, modifiedAt: nil)
    }
    return FileSignature(
      exists: true,
      byteCount: Int64(byteCount),
      modifiedAt: values.contentModificationDate)
  }

  private func touch(_ url: URL) {
    order.removeAll { $0 == url }
    order.insert(url, at: 0)
  }

  private func trim() {
    guard order.count > capacity else { return }
    for url in order.dropFirst(capacity) { entries.removeValue(forKey: url) }
    order = Array(order.prefix(capacity))
  }
}
