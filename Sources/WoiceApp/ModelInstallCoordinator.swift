import Foundation
import WoiceCore

/// Coordinates the single user-triggered install pipeline shared by the
/// workspace, material and settings entry points. The filesystem/SQLite
/// records remain the durable truth; this object only coalesces concurrent
/// callers in the current process so a second click cannot start another
/// download for the same pack and revision.
@MainActor
final class ModelInstallCoordinator {
  typealias Key = String

  private var activeTasks: [Key: Task<Bool, Never>] = [:]

  func enqueue(
    packID: String,
    version: String,
    operation: @escaping @MainActor () async -> Bool
  ) -> Task<Bool, Never> {
    let key = Self.key(packID: packID, version: version)
    if let active = activeTasks[key] { return active }
    let task = Task { @MainActor [weak self] in
      defer { self?.activeTasks.removeValue(forKey: key) }
      return await operation()
    }
    activeTasks[key] = task
    return task
  }

  func isActive(packID: String, version: String) -> Bool {
    activeTasks[Self.key(packID: packID, version: version)] != nil
  }

  func cancel(packID: String, version: String) {
    activeTasks[Self.key(packID: packID, version: version)]?.cancel()
  }

  static func key(packID: String, version: String) -> Key {
    "\(packID)/\(version)"
  }
}
