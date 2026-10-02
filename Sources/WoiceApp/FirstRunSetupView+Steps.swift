import SwiftUI

extension FirstRunSetupView {
  var materialLibraryStep: some View {
    FirstRunSetupStepCard(
      number: 1,
      title: "选择素材保存位置",
      status: hasMaterialLibrary ? "已就绪" : "待完成",
      isComplete: hasMaterialLibrary,
      detail: materialLibraryDetail
    ) {
      if appState.needsUserSelectedMaterialLibrary {
        Button("选择保存文件夹…", systemImage: "folder.badge.plus") {
          _ = appState.chooseUserSelectedMaterialLibrary()
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
      } else if let url = appState.userSelectedMaterialLibraryURL {
        Button("重新选择…", systemImage: "folder") {
          _ = appState.chooseUserSelectedMaterialLibrary()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        Text(url.lastPathComponent)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  var materialLibraryDetail: String {
    if let url = appState.userSelectedMaterialLibraryURL {
      return "将保存到“\(url.lastPathComponent)”。这是你可以直接打开、备份和管理的文件夹。"
    }
    if hasMaterialLibrary {
      return "当前版本的本机素材位置已可用。"
    }
    return "录音、电脑声音和导入原件都放在你选择的文件夹，不会藏在 App 内部。"
  }

  var microphoneStep: some View {
    FirstRunSetupStepCard(
      number: 2,
      title: "允许麦克风",
      status: microphoneStatusTitle,
      isComplete: microphoneStatus.permission == .granted && microphoneStatus.hasUsableInput,
      detail: microphoneStatusDetail
    ) {
      microphoneActions
    }
  }

  @ViewBuilder
  var microphoneActions: some View {
    switch microphoneStatus.permission {
    case .notDetermined:
      Button("允许麦克风", systemImage: "mic.badge.plus") {
        requestMicrophonePermission()
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.small)
      .disabled(isRequestingMicrophone)
    case .denied:
      Button("打开系统设置", systemImage: "gear") {
        openSystemPreference("Privacy_Microphone")
      }
      .buttonStyle(.bordered)
      .controlSize(.small)
      refreshMicrophoneButton
    case .granted where !microphoneStatus.hasUsableInput:
      Button("打开声音设置", systemImage: "speaker.wave.2") {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.sound?") else {
          return
        }
        openURL(url)
      }
      .buttonStyle(.bordered)
      .controlSize(.small)
      refreshMicrophoneButton
    case .unknown:
      refreshMicrophoneButton
    case .granted:
      EmptyView()
    }
  }

  var refreshMicrophoneButton: some View {
    Button("重新检查", systemImage: "arrow.clockwise") {
      Task { microphoneStatus = await appState.recorder.refreshMicrophoneStatus() }
    }
    .buttonStyle(.borderless)
    .controlSize(.small)
  }

  var microphoneStatusTitle: String {
    switch microphoneStatus.permission {
    case .granted where microphoneStatus.hasUsableInput: "已就绪"
    case .granted: "已允许，但没有可用输入"
    case .denied: "需要在系统设置中允许"
    case .notDetermined: "等待你允许"
    case .unknown: "尚未检查"
    }
  }

  var microphoneStatusDetail: String {
    switch microphoneStatus.permission {
    case .granted where microphoneStatus.hasUsableInput:
      "麦克风可用；只有你点击开始录音后，Woice 才会采集声音。"
    case .granted:
      "权限已允许，但 macOS 没有提供可用麦克风。请选择输入设备后重新检查。"
    case .denied:
      "之前选择了不允许。原始素材未受影响；在系统设置中开启后回到 Woice 重新检查。"
    case .notDetermined:
      "Woice 用麦克风保存你主动开始的录音。点击后才会出现 macOS 权限弹窗。"
    case .unknown:
      "点击重新检查；如果仍无法读取，可稍后在“录音与输入”中处理。"
    }
  }

  var modelStep: some View {
    FirstRunSetupStepCard(
      number: 3,
      title: "下载本机转写模型",
      status: hasLocalModel ? "已就绪" : (appState.isDownloadingModel ? "正在下载" : "建议完成"),
      isComplete: hasLocalModel,
      detail: FirstRunSetupPresentation.modelDetail
    ) {
      if hasLocalModel {
        Label("已安装可用模型", systemImage: "checkmark.circle.fill")
          .font(.caption)
          .foregroundStyle(.green)
      }

      Text("三个模型都在本机运行。推荐项排在最前，你也可以按速度、中文表现或复杂会议准确率自行选择。")
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      ForEach(Array(firstRunModelChoices.enumerated()), id: \.offset) { _, model in
        ModelInstallCard(
          entryPoint: .workspace,
          model: model,
          recommendation: firstRunModelRecommendation)
      }

      if StoreCapabilityProfile.current.isStoreEdition,
        appState.verifiedModelCatalogEntries.isEmpty,
        appState.canUpdateModelCatalog
      {
        Button {
          Task { @MainActor in
            _ = await appState.refreshModelCatalog()
          }
        } label: {
          if appState.modelCatalogState == .updating {
            ProgressView().controlSize(.small)
            Text("正在检查")
          } else {
            Label("检查可下载模型", systemImage: "arrow.clockwise")
          }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(appState.modelCatalogState == .updating)

        Text("先下载并验证一份很小的模型清单；模型文件要等你下一步确认后才会下载。")
          .font(.caption2)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  var firstRunModelRecommendation: RecommendedModelPolicy.Recommendation? {
    RecommendedModelPolicy.recommendation(
      physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory)
  }

  var firstRunModelChoices: [ModelInstallCardModel] {
    RecommendedModelPolicy.orderedCandidates(
      physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory)
  }

  var systemAudioStep: some View {
    let capability = appState.systemAudioCapability.capability.state
    return FirstRunSetupStepCard(
      number: nil,
      title: "录制电脑声音（可选）",
      status: systemAudioStatus(capability),
      isComplete: capability == .ready || capability == .readyWindow,
      detail: FirstRunSetupPresentation.systemAudioDetail
    ) {
      if capability == .needsPermission || capability == .needsReauthorization {
        Button(
          capability == .needsReauthorization ? "重新授权当前版本" : "允许电脑声音",
          systemImage: "lock.open"
        ) {
          appState.systemAudioCapability.requestPermission()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
      }
      Button("重新检查", systemImage: "arrow.clockwise") {
        appState.systemAudioCapability.refresh()
      }
      .buttonStyle(.borderless)
      .controlSize(.small)
    }
  }

  func openSystemPreference(_ pane: String) {
    guard
      let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")
    else { return }
    openURL(url)
  }

  func systemAudioStatus(_ state: SystemAudioCapabilityState) -> String {
    switch state {
    case .ready, .readyWindow: "已就绪"
    case .needsPermission: "需要你允许"
    case .needsReauthorization: "需要重新允许"
    case .notChecked: "尚未检查"
    case .noDisplay: "未找到可用显示器"
    case .unavailable: "暂不可用"
    }
  }
}
