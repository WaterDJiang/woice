import CryptoKit
import Darwin
import Foundation

enum FileSHA256 {
  static let defaultChunkSize = 1024 * 1024

  static func digest(url: URL, chunkSize: Int = defaultChunkSize) throws -> String {
    precondition(chunkSize > 0)
    let descriptor = Darwin.open(url.path, O_RDONLY | O_CLOEXEC)
    guard descriptor >= 0 else {
      throw posixError(url: url)
    }
    defer { Darwin.close(descriptor) }

    let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: chunkSize, alignment: 64)
    defer { buffer.deallocate() }
    var digest = SHA256()

    while true {
      let byteCount = Darwin.read(descriptor, buffer.baseAddress, buffer.count)
      if byteCount == 0 { break }
      if byteCount < 0 {
        if errno == EINTR { continue }
        throw posixError(url: url)
      }
      digest.update(
        bufferPointer: UnsafeRawBufferPointer(start: buffer.baseAddress, count: byteCount))
    }

    return digest.finalize().map { String(format: "%02x", $0) }.joined()
  }

  private static func posixError(url: URL) -> NSError {
    NSError(
      domain: NSPOSIXErrorDomain,
      code: Int(errno),
      userInfo: [NSURLErrorKey: url])
  }
}
