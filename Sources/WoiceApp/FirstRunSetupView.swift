import SwiftUI

struct FirstRunSetupView: View {
  @Environment(AppState.self) var appState
  @Environment(\.openURL) var openURL

  let dismiss: () -> Void
  let startRecording: () -> Void

  @State var microphoneStatus = MicrophoneInputStatus(
    permission: .unknown, hasUsableInput: false, sampleRate: 0, channelCount: 0)
  @State var isRequestingMicrophone = false

  var hasMaterialLibrary: Bool { !appState.needsUserSelectedMaterialLibrary }
  var hasLocalModel: Bool { appState.hasInstalledLocalModelPack }
  var completedStepCount: Int {
    FirstRunSetupPresentation.completedStepCount(
      hasMaterialLibrary: hasMaterialLibrary,
      microphoneStatus: microphoneStatus,
      hasLocalModel: hasLocalModel)
  }
  var canStartRecording: Bool {
    FirstRunSetupPresentation.canStartRecording(
      hasMaterialLibrary: hasMaterialLibrary, microphoneStatus: microphoneStatus)
  }

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      ScrollView {
        VStack(spacing: 12) {
          materialLibraryStep
          microphoneStep
          modelStep
          systemAudioStep
        }
        .padding(20)
      }
      .defaultScrollAnchor(.top)
      Divider()
      footer
    }
    .frame(width: 620, height: 680)
    .background(.background)
    .task {
      microphoneStatus = await appState.recorder.refreshMicrophoneStatus()
      appState.systemAudioCapability.refresh()
    }
  }

  private var header: some View {
    HStack(alignment: .top, spacing: 14) {
      Image(systemName: "waveform.circle.fill")
        .font(.system(size: 34))
        .foregroundStyle(.tint)
      VStack(alignment: .leading, spacing: 6) {
        Text(FirstRunSetupPresentation.title)
          .font(.title2.weight(.semibold))
        Text("先选好保存位置，再允许麦克风。每一步都会说明用途，不会自动录音或上传内容。")
          .font(.callout)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        ProgressView(value: Double(completedStepCount), total: 3) {
          Text("核心准备已完成 \(completedStepCount)/3")
            .font(.caption.weight(.medium))
        }
        .accessibilityValue("已完成 \(completedStepCount) 项，共 3 项")
      }
      Spacer()
    }
    .padding(20)
  }

  private var footer: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(FirstRunSetupPresentation.recordingHint(hasLocalModel: hasLocalModel))
        .font(.caption)
        .foregroundStyle(hasLocalModel ? Color.secondary : Color.orange)
      HStack {
        Button("稍后设置", action: dismiss)
          .buttonStyle(.bordered)
        Spacer()
        Button("开始第一段录音", systemImage: "mic.fill", action: startRecording)
          .buttonStyle(.borderedProminent)
          .disabled(!canStartRecording)
          .help(canStartRecording ? "开始录音" : "请先选择保存位置并允许麦克风")
      }
    }
    .padding(20)
  }

  func requestMicrophonePermission() {
    guard !isRequestingMicrophone else { return }
    isRequestingMicrophone = true
    Task { @MainActor in
      microphoneStatus = await appState.requestMicrophoneAccessForSetup()
      isRequestingMicrophone = false
    }
  }
}
