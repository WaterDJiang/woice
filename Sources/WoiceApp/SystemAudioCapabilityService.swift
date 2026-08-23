import CoreGraphics
import Foundation
import Observation
import ScreenCaptureKit

enum SystemAudioCapabilityState: Equatable, Sendable {
  case notChecked
  case needsPermission
  case needsReauthorization
  case noDisplay
  case ready
  case readyWindow
  case unavailable(String)

  var title: String {
    switch self {
    case .notChecked: "尚未检查"
    case .needsPermission: "需要屏幕录制权限"
    case .needsReauthorization: "需要重新授权当前安装包"
    case .noDisplay: "没有可用显示器"
    case .ready: "系统音频能力可用"
    case .readyWindow: "仅窗口级系统音频可用"
    case .unavailable: "暂不可用"
    }
  }

  var systemImage: String {
    switch self {
    case .notChecked: "questionmark.circle"
    case .needsPermission, .needsReauthorization: "lock.fill"
    case .noDisplay: "display"
    case .ready, .readyWindow: "checkmark.circle.fill"
    case .unavailable: "exclamationmark.triangle.fill"
    }
  }

  var tint: SystemAudioCapabilityTint {
    switch self {
    case .ready, .readyWindow: .green
    case .needsPermission, .needsReauthorization, .noDisplay, .unavailable: .orange
    case .notChecked: .secondary
    }
  }
}

enum SystemAudioCapabilityTint: Sendable {
  case green
  case orange
  case secondary
}

struct SystemAudioCapability: Equatable, Sendable {
  var state: SystemAudioCapabilityState = .notChecked
  var displayCount = 0
  var windowCount = 0
  var checkedAt: Date?

  static func resolved(
    screenCaptureAuthorized: Bool,
    displayCount: Int,
    windowCount: Int = 0,
    errorDescription: String? = nil,
    permissionRefreshRequired: Bool = false
  ) -> Self {
    let state: SystemAudioCapabilityState
    if let errorDescription {
      state = .unavailable(errorDescription)
    } else if !screenCaptureAuthorized {
      state = permissionRefreshRequired ? .needsReauthorization : .needsPermission
    } else if displayCount == 0 {
      state = windowCount > 0 ? .readyWindow : .noDisplay
    } else {
      state = .ready
    }
    return Self(
      state: state, displayCount: displayCount, windowCount: windowCount, checkedAt: Date())
  }
}

@MainActor
@Observable
final class SystemAudioCapabilityService {
  private(set) var capability = SystemAudioCapability()
  private(set) var isChecking = false

  func refresh() {
    guard !isChecking else { return }
    isChecking = true
    Task { @MainActor [weak self] in
      guard let self else { return }
      await self.refreshNow()
    }
  }

  func requestPermission() {
    guard !isChecking else { return }
    _ = CGRequestScreenCaptureAccess()
    // The system settings change happens outside this process. Refreshing
    // synchronously here only reads the old TCC decision and makes a newly
    // granted permission look like it failed. The view also refreshes when the
    // app becomes active again.
    capability = .resolved(screenCaptureAuthorized: false, displayCount: 0)
    Task { @MainActor [weak self] in
      // TCC changes are committed by System Settings after the request returns.
      // Poll a small bounded window so returning to Woice does not leave the
      // previous "needs permission" projection visible until a later redraw.
      for delay in [0.35, 0.75, 1.5, 2.5] {
        try? await Task.sleep(for: .seconds(delay))
        guard !Task.isCancelled, let self else { return }
        await self.refreshNow()
        switch self.capability.state {
        case .ready, .readyWindow, .noDisplay, .unavailable:
          return
        case .notChecked, .needsPermission, .needsReauthorization:
          continue
        }
      }
      guard !Task.isCancelled, let self else { return }
      // The user returned from System Settings, but this running bundle still
      // cannot pass TCC/ScreenCaptureKit. Keep the distinction visible: the
      // switch may belong to an older ad hoc install and needs a fresh grant.
      self.capability = .resolved(
        screenCaptureAuthorized: false, displayCount: 0, permissionRefreshRequired: true)
    }
  }

  private func refreshNow() async {
    defer { isChecking = false }
    let preflightAuthorized = CGPreflightScreenCaptureAccess()
    do {
      let content = try await shareableContentWithFallback()
      // Reading shareable content is the runtime fact required by the capture
      // path. It is intentionally allowed to override a stale preflight false
      // after the user changed TCC in System Settings.
      capability = .resolved(
        screenCaptureAuthorized: true,
        displayCount: content.displays.count,
        windowCount: content.windows.filter(Self.isCaptureCandidate).count)
    } catch {
      if preflightAuthorized {
        capability = .resolved(
          screenCaptureAuthorized: true,
          displayCount: 0,
          windowCount: 0,
          errorDescription: "无法读取可共享内容：\(error.localizedDescription)"
        )
      } else {
        capability = .resolved(screenCaptureAuthorized: false, displayCount: 0)
      }
    }
  }

  private func shareableContentWithFallback() async throws -> SCShareableContent {
    if let visibleContent = try? await SCShareableContent.excludingDesktopWindows(
      false, onScreenWindowsOnly: true
    ), !visibleContent.displays.isEmpty {
      return visibleContent
    }
    return try await SCShareableContent.excludingDesktopWindows(
      false, onScreenWindowsOnly: false
    )
  }

  private static func isCaptureCandidate(_ window: SCWindow) -> Bool {
    guard window.owningApplication?.bundleIdentifier != Bundle.main.bundleIdentifier else {
      return false
    }
    return window.isOnScreen || window.isActive
  }
}
