import AppKit
import SwiftUI

private final class WoiceWorkspaceWindow: NSWindow {
  override var title: String {
    get { super.title }
    set { super.title = "Woice 工作台" }
  }
}

@MainActor
final class WoiceWorkspaceWindowController: NSWindowController {
  private let router: WorkspaceRouter

  init(appState: AppState, router: WorkspaceRouter) {
    self.router = router
    let rootView = WorkspaceView()
      .environment(appState)
      .environment(router)
    let hostingController = NSHostingController(rootView: rootView)
    let window = WoiceWorkspaceWindow(contentViewController: hostingController)
    window.title = "Woice 工作台"
    window.identifier = NSUserInterfaceItemIdentifier("com.woice.workspace")
    window.isRestorable = false
    window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
    window.collectionBehavior = [.managed, .fullScreenAuxiliary]
    window.titleVisibility = .visible
    window.isReleasedWhenClosed = false
    window.contentMinSize = NSSize(width: 1_080, height: 700)
    window.setContentSize(NSSize(width: 1_180, height: 760))
    super.init(window: window)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("WoiceWorkspaceWindowController 不支持从 NSCoder 初始化")
  }

  func show(route: WorkspaceRoute? = nil) {
    if let route { router.route = route }
    guard let window else { return }
    if !window.isVisible || window.screen == nil { window.center() }
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
    showWindow(nil)
    window.makeKeyAndOrderFront(nil)
    window.orderFrontRegardless()
    DispatchQueue.main.async { [weak window] in
      guard let window else { return }
      NSApp.setActivationPolicy(.regular)
      NSApp.activate(ignoringOtherApps: true)
      window.makeKeyAndOrderFront(nil)
      window.orderFrontRegardless()
    }
  }
}
