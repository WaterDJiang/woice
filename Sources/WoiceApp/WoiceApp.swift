import AppKit
import Darwin

@main
@MainActor
final class WoiceApp: NSObject, NSApplicationDelegate {
  private let instanceGuard: SingleInstanceGuard
  private let workspaceWindowController: WoiceWorkspaceWindowController
  private let menuBarController: WoiceMenuBarController
  private let appState: AppState
  private let workspaceRouter: WorkspaceRouter

  static func main() {
    let application = NSApplication.shared
    let delegate = WoiceApp()
    let mainMenu = NSMenu()
    let appMenuItem = NSMenuItem(title: "Woice", action: nil, keyEquivalent: "")
    let appMenu = NSMenu(title: "Woice")
    appMenu.addItem(
      withTitle: "退出 Woice",
      action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q"
    )
    appMenuItem.submenu = appMenu
    mainMenu.addItem(appMenuItem)
    let workspaceMenuItem = NSMenuItem(title: "工作区", action: nil, keyEquivalent: "")
    let workspaceMenu = NSMenu(title: "工作区")
    let workspaceItems: [(String, Selector, String)] = [
      ("素材库", #selector(showLibraryWorkspace(_:)), "1"),
      ("处理任务", #selector(showProcessingWorkspace(_:)), "2"),
      ("文字转音频", #selector(showTextToAudioWorkspace(_:)), "3"),
      ("设置", #selector(showSettingsWorkspace(_:)), "4"),
    ]
    for (title, action, keyEquivalent) in workspaceItems {
      let item = workspaceMenu.addItem(
        withTitle: title, action: action, keyEquivalent: keyEquivalent)
      item.target = delegate
      item.keyEquivalentModifierMask = [.command]
    }
    workspaceMenuItem.submenu = workspaceMenu
    mainMenu.addItem(workspaceMenuItem)
    let windowMenuItem = NSMenuItem(title: "窗口", action: nil, keyEquivalent: "")
    let windowMenu = NSMenu(title: "窗口")
    windowMenu.addItem(
      withTitle: "关闭窗口",
      action: #selector(NSWindow.performClose(_:)),
      keyEquivalent: "w"
    )
    windowMenuItem.submenu = windowMenu
    mainMenu.addItem(windowMenuItem)
    application.mainMenu = mainMenu
    application.setActivationPolicy(.regular)
    application.delegate = delegate
    withExtendedLifetime(delegate) {
      application.run()
    }
  }

  override init() {
    guard let instanceGuard = SingleInstanceGuard() else {
      Darwin.exit(EXIT_SUCCESS)
    }
    self.instanceGuard = instanceGuard
    // Dock/Finder/Launchpad use the signed Bundle AppIcon. Do not replace it
    // at runtime with the raw white PNG, otherwise macOS cannot apply its
    // system rounded-rectangle mask consistently.

    let state = AppState()
    let router = WorkspaceRouter()
    appState = state
    workspaceRouter = router
    workspaceWindowController = WoiceWorkspaceWindowController(appState: state, router: router)
    menuBarController = WoiceMenuBarController(
      appState: state, router: router, workspaceWindowController: workspaceWindowController)
    do {
      try state.startPiConnector()
    } catch {
      state.errorMessage = "本地 Connector 未启动：\(error.localizedDescription)"
    }
    super.init()
  }

  func applicationWillFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    workspaceWindowController.show()
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.workspaceWindowController.show()
      guard let importSource = WoiceTestRuntimeConfiguration.importSource else { return }
      Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(1_500))
        guard let recordID = await self.appState.importMedia(from: importSource),
          let record = self.appState.recordings.first(where: { $0.id == recordID })
        else { return }
        self.workspaceRouter.show(recordID: recordID)
        self.workspaceWindowController.show()
        guard WoiceTestRuntimeConfiguration.shouldTranscribeImportedSource else { return }
        self.appState.requestTranscription(for: record)
      }
    }
  }

  func applicationDidBecomeActive(_ notification: Notification) {
    let hasVisibleWorkspace = NSApp.windows.contains {
      $0.identifier == NSUserInterfaceItemIdentifier("com.woice.workspace") && $0.isVisible
    }
    guard !hasVisibleWorkspace else {
      return
    }
    workspaceWindowController.show()
  }

  func applicationShouldHandleReopen(
    _ sender: NSApplication, hasVisibleWindows flag: Bool
  ) -> Bool {
    workspaceWindowController.show()
    return true
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }

  @objc private func showLibraryWorkspace(_ sender: Any?) {
    showWorkspace(.library)
  }

  @objc private func showProcessingWorkspace(_ sender: Any?) {
    showWorkspace(.processing)
  }

  @objc private func showTextToAudioWorkspace(_ sender: Any?) {
    showWorkspace(.textToAudio)
  }

  @objc private func showSettingsWorkspace(_ sender: Any?) {
    showWorkspace(.settings)
  }

  private func showWorkspace(_ area: WorkspaceArea) {
    workspaceRouter.show(area)
    workspaceWindowController.show()
  }
}
