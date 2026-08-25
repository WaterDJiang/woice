import AppKit
import SwiftUI

private struct WoiceMenuBarControllerKey: EnvironmentKey {
  static let defaultValue: WoiceMenuBarController? = nil
}

extension EnvironmentValues {
  var woiceMenuBarController: WoiceMenuBarController? {
    get { self[WoiceMenuBarControllerKey.self] }
    set { self[WoiceMenuBarControllerKey.self] = newValue }
  }
}

@MainActor
final class WoiceMenuBarController: NSObject, Sendable {
  private let appState: AppState
  private let router: WorkspaceRouter
  private let workspaceWindowController: WoiceWorkspaceWindowController
  private let statusItem: NSStatusItem
  private let popover: NSPopover
  private var statusTimer: Timer?
  private var localMouseMonitor: Any?
  private var appResignObserver: NSObjectProtocol?

  init(
    appState: AppState, router: WorkspaceRouter,
    workspaceWindowController: WoiceWorkspaceWindowController
  ) {
    self.appState = appState
    self.router = router
    self.workspaceWindowController = workspaceWindowController
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    popover = NSPopover()
    super.init()

    popover.behavior = .transient
    popover.animates = true
    popover.delegate = self
    // The SwiftUI content reports its fitting height after layout. Keep a
    // small initial size only for the first AppKit presentation; it is
    // replaced immediately by `updatePopoverSize()`.
    popover.contentSize = NSSize(width: 336, height: 220)
    popover.contentViewController = NSHostingController(
      rootView: WoiceAppShell()
        .environment(appState)
        .environment(router)
        .environment(\.woiceMenuBarController, self))

    if let button = statusItem.button {
      button.target = self
      button.action = #selector(togglePopover)
      button.toolTip = "Woice · 点击打开录音控制器"
      button.setAccessibilityLabel("Woice")
      button.setAccessibilityHelp("点击打开录音控制器")
    }
    updateStatusItem()
    statusTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.updateStatusItem() }
    }
  }

  @objc private func togglePopover() {
    guard let button = statusItem.button else { return }
    if popover.isShown {
      popover.performClose(nil)
    } else {
      popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
      popover.contentViewController?.view.window?.becomeKey()
      installDismissalMonitors()
      DispatchQueue.main.async { [weak self] in self?.updatePopoverSize() }
    }
  }

  private func updateStatusItem() {
    guard let button = statusItem.button else { return }
    let symbolName = appState.isRecording ? "record.circle.fill" : "waveform.circle.fill"
    button.image = NSImage(
      systemSymbolName: symbolName,
      accessibilityDescription: appState.isRecording ? "正在录音" : "Woice")
    button.image?.isTemplate = !appState.isRecording
    button.contentTintColor = appState.isRecording ? .systemRed : nil

    let toolTip: String
    if appState.isRecording {
      toolTip = "正在录音 · \(formatDuration(appState.elapsed))"
    } else {
      toolTip = "Woice · 点击打开录音控制器"
    }
    button.toolTip = toolTip
    button.setAccessibilityLabel(appState.isRecording ? "正在录音" : "Woice")
    button.setAccessibilityValue(appState.isRecording ? formatDuration(appState.elapsed) : nil)
    updatePopoverSize()
  }

  private func updatePopoverSize() {
    guard popover.isShown, let view = popover.contentViewController?.view else { return }
    view.layoutSubtreeIfNeeded()
    let fitting = view.fittingSize
    let height = min(max(fitting.height, 190), 540)
    guard abs(popover.contentSize.height - height) > 1 else { return }
    popover.contentSize = NSSize(width: 336, height: height)
  }

  func showWorkspace(route: WorkspaceRoute) {
    router.route = route
    popover.performClose(nil)
    workspaceWindowController.show(route: route)
  }

  private func installDismissalMonitors() {
    removeDismissalMonitors()
    let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
    localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
      self?.closePopoverIfNeeded(for: event)
      return event
    }
    appResignObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didResignActiveNotification,
      object: NSApplication.shared,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in self?.popover.performClose(nil) }
    }
  }

  private func closePopoverIfNeeded(for event: NSEvent) {
    guard popover.isShown else { return }
    let isStatusItemButton: Bool
    if let button = statusItem.button, event.window === button.window {
      let point = button.convert(event.locationInWindow, from: nil)
      isStatusItemButton = button.bounds.contains(point)
    } else {
      isStatusItemButton = false
    }
    guard
      PopoverDismissalPolicy.shouldClose(
        eventWindow: event.window,
        popoverWindow: popover.contentViewController?.view.window,
        isStatusItemButton: isStatusItemButton)
    else { return }
    popover.performClose(nil)
  }

  private func removeDismissalMonitors() {
    if let localMouseMonitor {
      NSEvent.removeMonitor(localMouseMonitor)
      self.localMouseMonitor = nil
    }
    if let appResignObserver {
      NotificationCenter.default.removeObserver(appResignObserver)
      self.appResignObserver = nil
    }
  }
}

extension WoiceMenuBarController: NSPopoverDelegate {
  func popoverDidClose(_ notification: Notification) {
    removeDismissalMonitors()
  }
}

enum PopoverDismissalPolicy {
  static func shouldClose(
    eventWindow: NSWindow?,
    popoverWindow: NSWindow?,
    isStatusItemButton: Bool
  ) -> Bool {
    guard eventWindow !== popoverWindow else { return false }
    return !isStatusItemButton
  }
}
