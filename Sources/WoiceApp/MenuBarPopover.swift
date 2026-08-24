import AppKit
import SwiftUI

/// The menu-bar surface is intentionally a short command palette. Material
/// browsing, imports and text-to-audio stay in the single workbench window.
struct MenuBarPopover: View {
  @Environment(AppState.self) private var appState
  @Environment(WorkspaceRouter.self) private var workspaceRouter
  @Environment(\.woiceMenuBarController) private var menuBarController
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isConfirmingQuit = false

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      if let feedback = appState.actionFeedback {
        ActionFeedbackBanner(feedback: feedback)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      if appState.isRecording {
        recordingStatus
      } else if shouldShowProcessingStatus {
        processingStatus
      }
      sourceConfiguration
      primaryAction
      Divider()
      MenuBarCommandList { command in
        perform(command)
      }
    }
    .padding(16)
    .background(.ultraThinMaterial)
    .frame(width: 336)
    .fixedSize(horizontal: false, vertical: true)
    .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: appState.actionFeedback?.id)
    .confirmationDialog(
      "正在录音",
      isPresented: $isConfirmingQuit,
      titleVisibility: .visible
    ) {
      Button("保存录音并退出") {
        Task { @MainActor in
          await appState.stopRecording()
          NSApplication.shared.terminate(nil)
        }
      }
      Button("取消", role: .cancel) {}
    } message: {
      Text("退出前先保存当前录音，避免未固化的音频丢失。")
    }
  }

  private var primaryAction: some View {
    Button {
      if appState.isRecording {
        Task { await appState.stopRecording() }
      } else {
        appState.startRecording()
      }
    } label: {
      Label(
        appState.isRecording ? "结束录音" : "开始录音",
        systemImage: appState.isRecording ? "stop.fill" : "record.circle"
      )
      .frame(maxWidth: .infinity)
    }
    .buttonStyle(.borderedProminent)
    .controlSize(.large)
    .tint(appState.isRecording ? .red : nil)
    .keyboardShortcut(.return, modifiers: [])
    .disabled(!appState.isRecording && !appState.canStartRecording)
    .accessibilityLabel(appState.isRecording ? "结束录音" : "开始录音")
    .accessibilityHint(appState.isRecording ? "保存当前录音并开始处理" : "开始一段新的本机录音")
    .help(appState.isRecording ? "结束录音并保存素材" : "开始录音")
  }

  private var sourceConfiguration: some View {
    VStack(alignment: .leading, spacing: 9) {
      HStack(alignment: .firstTextBaseline) {
        Text("录音来源")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
        Spacer()
        Text(
          RecordingSourceSelectionPresentation.summary(
            microphoneEnabled: appState.settings.captureMicrophone,
            systemAudioEnabled: appState.settings.captureSystemAudio
          )
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
      HStack(spacing: 8) {
        RecordingSourceControl(
          title: "麦克风",
          systemImage: "mic.fill",
          isEnabled: appState.settings.captureMicrophone,
          isLocked: appState.isRecording
        ) {
          appState.setMicrophoneCaptureEnabled(!appState.settings.captureMicrophone)
        }
        RecordingSourceControl(
          title: "电脑声音",
          systemImage: "speaker.wave.2.fill",
          isEnabled: appState.settings.captureSystemAudio,
          isLocked: appState.isRecording
        ) {
          appState.setSystemAudioCaptureEnabled(!appState.settings.captureSystemAudio)
        }
      }
      if !appState.settings.hasEnabledRecordingSource {
        Label("至少开启一个音源后才能录音", systemImage: "exclamationmark.circle")
          .font(.caption)
          .foregroundStyle(.orange)
          .accessibilityLabel("至少开启一个音源后才能录音")
      }
    }
    .padding(10)
    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
  }

  private var recordingStatus: some View {
    VStack(alignment: .leading, spacing: 7) {
      HStack {
        Label("正在录音", systemImage: "record.circle.fill")
          .foregroundStyle(.red)
          .font(.callout.weight(.semibold))
        Spacer()
        Text(formatDuration(appState.elapsed))
          .font(.title3.monospacedDigit().weight(.semibold))
      }
      if appState.settings.captureMicrophone {
        HStack(spacing: 6) {
          Image(systemName: appState.audioActivity.systemImage)
          Text("麦克风输入 · \(appState.audioActivity.label)")
          Spacer()
          Text("有声 \(formatDuration(appState.voiceDuration))")
            .monospacedDigit()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        ProgressView(value: Double(min(max(appState.inputLevel * 4, 0), 1)))
          .tint(appState.receivedBufferCount > 0 ? .green : .orange)
          .accessibilityLabel("麦克风输入电平")
      }
      if appState.settings.captureSystemAudio {
        Label(
          appState.isSystemAudioCapturing ? "电脑声音正在保存" : "电脑声音尚未开始",
          systemImage: appState.isSystemAudioCapturing ? "speaker.wave.2.fill" : "speaker.slash"
        )
        .font(.caption)
        .foregroundStyle(appState.isSystemAudioCapturing ? Color.secondary : Color.orange)
      }
    }
    .padding(10)
    .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
    .accessibilityElement(children: .combine)
    .accessibilityLabel("正在录音")
    .accessibilityValue(
      "时长 \(formatDuration(appState.elapsed))，麦克风 \(appState.audioActivity.label)"
    )
  }

  private var shouldShowProcessingStatus: Bool {
    appState.errorMessage != nil || appState.processingState != .ready
  }

  private var processingStatus: some View {
    HStack(alignment: .top, spacing: 8) {
      Image(
        systemName: appState.errorMessage == nil
          ? appState.processingState.systemImage : "exclamationmark.triangle.fill"
      )
      .foregroundStyle(appState.errorMessage == nil ? Color.accentColor : Color.orange)
      VStack(alignment: .leading, spacing: 3) {
        Text(appState.errorMessage == nil ? appState.processingState.label : "处理未完成")
          .font(.callout.weight(.medium))
        Text(
          appState.errorMessage
            ?? (appState.pendingExternalProcessing != nil
              ? "需要在工作台确认后才会发送；原始录音已安全保存在本机。"
              : "原始录音已安全保存在本机，可在工作台查看任务详情。")
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(3)
        if appState.pendingExternalProcessing != nil {
          Button("打开工作台") {
            workspaceRouter.show(.processing)
            menuBarController?.showWorkspace(route: .processing)
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
          .accessibilityHint("在工作台确认或稍后处理外部转写")
        }
      }
    }
    .padding(10)
    .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
    .accessibilityElement(children: .combine)
  }

  private func perform(_ command: MenuBarCommand) {
    switch command {
    case .workspace:
      workspaceRouter.show(.library)
      menuBarController?.showWorkspace(route: .library)
    case .settings:
      workspaceRouter.show(settings: .recording)
      menuBarController?.showWorkspace(route: .settings(.recording))
    case .quit:
      if appState.isRecording {
        isConfirmingQuit = true
      } else {
        NSApplication.shared.terminate(nil)
      }
    }
  }
}

enum MenuBarCommand: String, CaseIterable, Identifiable, Sendable {
  case workspace
  case settings
  case quit

  var id: Self { self }

  var title: String {
    switch self {
    case .workspace: "进入工作台"
    case .settings: "设置"
    case .quit: "退出 Woice"
    }
  }

  var systemImage: String {
    switch self {
    case .workspace: "rectangle.3.group"
    case .settings: "gearshape"
    case .quit: "power"
    }
  }
}

struct MenuBarCommandList: View {
  let action: (MenuBarCommand) -> Void

  var body: some View {
    VStack(spacing: 2) {
      ForEach(MenuBarCommand.allCases) { command in
        Button {
          action(command)
        } label: {
          Label(command.title, systemImage: command.systemImage)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.woiceBorderless)
        .accessibilityLabel(command.title)
        .help(command.title)
      }
    }
  }
}
