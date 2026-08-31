import Darwin
import Foundation

/// Holds an advisory lock for the installed application so build and /Applications
/// copies cannot create two menu bar entries at the same time.
final class SingleInstanceGuard {
  private let descriptor: Int32

  convenience init?() {
    let applicationSupport =
      FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask
      ).first
      ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
        "Library/Application Support")
    let directory =
      WoiceTestRuntimeConfiguration.storageRoot
      ?? WoiceAppChannel.current.workspaceRoot(in: applicationSupport)
    self.init(lockURL: directory.appendingPathComponent("instance.lock"))
  }

  init?(lockURL: URL) {
    try? FileManager.default.createDirectory(
      at: lockURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    let fileDescriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
    guard fileDescriptor >= 0 else { return nil }
    guard flock(fileDescriptor, LOCK_EX | LOCK_NB) == 0 else {
      close(fileDescriptor)
      return nil
    }
    descriptor = fileDescriptor
    let marker = Data("\(ProcessInfo.processInfo.processIdentifier)\n".utf8)
    _ = marker.withUnsafeBytes { bytes in
      Darwin.ftruncate(fileDescriptor, 0)
      return Darwin.write(fileDescriptor, bytes.baseAddress, marker.count)
    }
  }

  deinit {
    flock(descriptor, LOCK_UN)
    close(descriptor)
  }
}
