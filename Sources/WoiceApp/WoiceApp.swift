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
  private var terminationCleanupInProgress = false

  static func main() {
    let application = NSApplication.shared
    let delegate = WoiceApp()
    let mainMenu = NSMenu()
    let appName = WoiceAppChannel.current.displayName
    let appMenuItem = NSMenuItem(title: appName, action: nil, keyEquivalent: "")
    let appMenu = NSMenu(title: appName)
    appMenu.addItem(
      withTitle: "退出 \(appName)",
      action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q"
    )
    appMenuItem.submenu = appMenu
    mainMenu.addItem(appMenuItem)

    // Keep AppKit's standard first-responder editing path available to SwiftUI
    // TextField controls. Without an Edit menu, ⌘A/⌘C/⌘V/⌘X are not reliably
    // routed to the focused field in the packaged app.
    let editMenuItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
    let editMenu = NSMenu(title: "编辑")
    let editItems: [(String, Selector, String, NSEvent.ModifierFlags)] = [
      ("撤销", Selector(("undo:")), "z", [.command]),
      ("重做", Selector(("redo:")), "z", [.command, .shift]),
      ("剪切", #selector(NSText.cut(_:)), "x", [.command]),
      ("拷贝", #selector(NSText.copy(_:)), "c", [.command]),
      ("粘贴", #selector(NSText.paste(_:)), "v", [.command]),
      ("删除", #selector(NSText.delete(_:)), "", []),
      ("全选", #selector(NSText.selectAll(_:)), "a", [.command]),
    ]
    for (index, (title, action, keyEquivalent, modifiers)) in editItems.enumerated() {
      if index == 2 {
        editMenu.addItem(.separator())
      }
      let item = editMenu.addItem(
        withTitle: title,
        action: action,
        keyEquivalent: keyEquivalent
      )
      item.keyEquivalentModifierMask = modifiers
    }
    editMenuItem.submenu = editMenu
    mainMenu.addItem(editMenuItem)

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
    windowMenu.addItem(.separator())
    let toggleSidebarItem = windowMenu.addItem(
      withTitle: "显示/隐藏侧边栏",
      action: #selector(toggleWorkspaceSidebar(_:)),
      keyEquivalent: "s"
    )
    toggleSidebarItem.target = delegate
    toggleSidebarItem.keyEquivalentModifierMask = [.command, .control]
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
    #if !WOICE_APP_STORE
      if StoreCapabilityProfile.current.allowsExternalAgentConnector {
        do {
          try state.startPiConnector()
        } catch {
          state.errorMessage = "本地 Connector 未启动：\(error.localizedDescription)"
        }
      }
    #endif
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
        // Startup hydrates the summary list before allowing any operation that
        // can rewrite the complete recordings collection. The isolated
        // desktop Journey must wait for that fact instead of racing the
        // fail-closed import guard on a fresh temporary Workspace.
        for _ in 0..<40 {
          guard !Task.isCancelled else { return }
          if self.appState.canImportMedia { break }
          do {
            try await Task.sleep(for: .milliseconds(250))
          } catch {
            return
          }
        }
        guard self.appState.canImportMedia else { return }
        guard let recordID = await self.appState.importMedia(from: importSource),
          let record = self.appState.recordings.first(where: { $0.id == recordID })
        else { return }
        let shouldTranscribe = WoiceTestRuntimeConfiguration.shouldTranscribeImportedSource
        if shouldTranscribe {
          self.appState.requestTranscription(for: record)
        }
        if WoiceTestRuntimeConfiguration.shouldPresentImportSheet {
          self.workspaceRouter.requestMediaImport(recordID: recordID)
        } else {
          self.workspaceRouter.show(recordID: recordID)
        }
        self.workspaceWindowController.show()
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

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard !terminationCleanupInProgress else { return .terminateLater }
    terminationCleanupInProgress = true
    Task { @MainActor [weak self] in
      guard let self else { return }
      await appState.prepareForTermination()
      terminationCleanupInProgress = false
      NSApp.reply(toApplicationShouldTerminate: true)
    }
    return .terminateLater
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

  @objc private func toggleWorkspaceSidebar(_ sender: Any?) {
    workspaceRouter.toggleSidebar()
    workspaceWindowController.show()
  }

  private func showWorkspace(_ area: WorkspaceArea) {
    workspaceRouter.show(area)
    workspaceWindowController.show()
  }
}
