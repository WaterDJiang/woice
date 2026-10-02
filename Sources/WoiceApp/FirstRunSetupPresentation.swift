struct FirstRunSetupPresentation {
  static let requiredStepCount = 3
  static let title = "3 分钟完成首次设置"
  static let modelDetail = "模型保存在这台 Mac，在本机把语音转成文字，不会上传录音。"
  static let systemAudioDetail = "可选：用于录制会议或视频的电脑声音；Woice 不保存屏幕画面。"

  static func completedStepCount(
    hasMaterialLibrary: Bool,
    microphoneStatus: MicrophoneInputStatus,
    hasLocalModel: Bool
  ) -> Int {
    [
      hasMaterialLibrary,
      microphoneStatus.permission == .granted && microphoneStatus.hasUsableInput,
      hasLocalModel,
    ].filter { $0 }.count
  }

  static func canStartRecording(
    hasMaterialLibrary: Bool,
    microphoneStatus: MicrophoneInputStatus
  ) -> Bool {
    hasMaterialLibrary && microphoneStatus.permission == .granted
      && microphoneStatus.hasUsableInput
  }

  static func recordingHint(hasLocalModel: Bool) -> String {
    hasLocalModel
      ? "录音会先保存，结束后可在这台 Mac 转成文字。"
      : "现在也可以录音，但暂时不会转成文字；以后下载模型即可补转。"
  }
}

struct WorkspaceOnboardingModelPrompt {
  static let title = "转成文字前，需要先下载语音转换模型"
  static let detail =
    "App Store 安装包不携带模型。下载由你确认，模型只保存在这台 Mac，不会上传录音。"
}
