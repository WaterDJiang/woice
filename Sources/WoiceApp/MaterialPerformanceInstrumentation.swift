import Foundation
import os

enum MaterialPerformanceEvent: String, Sendable {
  case listSelection = "list-selection"
  case summaryPresented = "summary-presented"
  case detailRead = "detail-read"
  case transcriptViewport = "transcript-viewport"
  case audioMetadata = "audio-metadata"
}

/// Low-cost signposts for the material-list and detail critical path. The
/// payload contains IDs and phase names only; transcript/audio contents never
/// enter the system log.
enum MaterialPerformanceInstrumentation {
  static let log = OSLog(subsystem: "com.woice.app", category: "material-performance")

  @discardableResult
  static func begin(_ event: MaterialPerformanceEvent) -> OSSignpostID {
    let signpostID = OSSignpostID(log: log)
    os_signpost(
      .begin, log: log, name: "material", signpostID: signpostID, "%{public}s", event.rawValue)
    return signpostID
  }

  static func end(_ event: MaterialPerformanceEvent, signpostID: OSSignpostID) {
    os_signpost(
      .end, log: log, name: "material", signpostID: signpostID, "%{public}s", event.rawValue)
  }

  static func event(_ event: MaterialPerformanceEvent) {
    os_signpost(.event, log: log, name: "material", "%{public}s", event.rawValue)
  }
}

enum MaterialPerformanceBudget {
  static func percentile(_ values: [TimeInterval], percentile: Double) -> TimeInterval? {
    guard !values.isEmpty, percentile.isFinite, (0...1).contains(percentile) else { return nil }
    let sorted = values.sorted()
    let position = percentile * Double(sorted.count - 1)
    let lower = Int(position.rounded(.down))
    let upper = Int(position.rounded(.up))
    guard lower < sorted.count, upper < sorted.count else { return nil }
    if lower == upper { return sorted[lower] }
    let fraction = position - Double(lower)
    return sorted[lower] + (sorted[upper] - sorted[lower]) * fraction
  }
}
