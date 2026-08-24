import Foundation

/// Deterministic geometry contract for the single Woice workspace sidebar.
///
/// SwiftUI owns the actual rendering, while this value keeps the layout
/// decisions testable without a running window. Only the context region may
/// consume flexible height; the navigation header and settings footer remain
/// anchored to the top and bottom edges.
public struct WorkspaceSidebarLayout: Equatable, Sendable {
  public static let minimumWidth: Double = 280
  public static let idealWidth: Double = 320
  public static let maximumWidth: Double = 360
  public static let minimumHeight: Double = 560

  public let totalHeight: Double
  public let headerHeight: Double
  public let footerHeight: Double

  public init(
    totalHeight: Double,
    headerHeight: Double = 148,
    footerHeight: Double = 54
  ) {
    self.totalHeight = max(0, totalHeight)
    self.headerHeight = max(0, headerHeight)
    self.footerHeight = max(0, footerHeight)
  }

  /// Height available to the current workspace context. It is deliberately
  /// allowed to reach zero so a very small host window cannot make the fixed
  /// header/footer float into the middle of the sidebar.
  public var contextHeight: Double {
    max(0, totalHeight - headerHeight - footerHeight)
  }

  public var fixedRegionsFit: Bool {
    totalHeight >= headerHeight + footerHeight
  }

  /// The material row uses a stable compact contract at the minimum sidebar
  /// width. Full status text belongs in the accessibility label/detail view;
  /// the row itself keeps a short, single-line status token.
  public static func rowTextWidth(for sidebarWidth: Double) -> Double {
    max(0, sidebarWidth - 32)
  }

  public static func rowCanFitSingleLine(
    sidebarWidth: Double,
    titleWidth: Double,
    metadataWidth: Double,
    statusWidth: Double = 20
  ) -> Bool {
    guard sidebarWidth >= minimumWidth else { return false }
    let available = rowTextWidth(for: sidebarWidth)
    return titleWidth >= 1 && metadataWidth >= 1 && statusWidth >= 1
      && titleWidth + metadataWidth + statusWidth <= available
  }
}
