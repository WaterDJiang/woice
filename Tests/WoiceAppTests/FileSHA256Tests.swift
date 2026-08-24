import CryptoKit
import Foundation
import Testing

@testable import WoiceApp

@Test("文件 SHA-256 使用多分块读取并保持摘要一致")
func fileSHA256MatchesCryptoKitAcrossChunks() throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "woice-file-sha256-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  let bytes = Data((0..<(3 * 1024 * 1024 + 17)).map { UInt8(truncatingIfNeeded: $0) })
  let fileURL = root.appendingPathComponent("fixture.bin")
  try bytes.write(to: fileURL)
  let expected = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()

  let actual = try FileSHA256.digest(url: fileURL, chunkSize: 64 * 1024)

  #expect(actual == expected)
}

@Test("文件 SHA-256 对不存在文件返回 POSIX 错误")
func fileSHA256FailsForMissingFile() {
  let missing = FileManager.default.temporaryDirectory.appendingPathComponent(
    "woice-missing-sha256-\(UUID().uuidString)")

  #expect(throws: (any Error).self) {
    try FileSHA256.digest(url: missing)
  }
}
