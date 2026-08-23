import Foundation
import Testing

@testable import WoiceApp

@Test("单实例锁拒绝第二个 Woice 实例")
func singleInstanceGuardRejectsSecondInstance() {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "woice-instance-guard-(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let lockURL = root.appendingPathComponent("instance.lock")

  let first = SingleInstanceGuard(lockURL: lockURL)
  #expect(first != nil)
  let second = SingleInstanceGuard(lockURL: lockURL)
  #expect(second == nil)
}
