import Foundation
import Testing

@testable import WoiceApp

@Suite("首次使用准备引导")
struct FirstRunSetupTests {
  @Test("核心准备步骤按真实状态计数")
  func requiredProgressUsesMaterialMicrophoneAndModelFacts() {
    let microphone = MicrophoneInputStatus(
      permission: .granted, hasUsableInput: true, sampleRate: 48_000, channelCount: 1)

    #expect(FirstRunSetupPresentation.requiredStepCount == 3)
    #expect(
      FirstRunSetupPresentation.completedStepCount(
        hasMaterialLibrary: true,
        microphoneStatus: microphone,
        hasLocalModel: false) == 2)
  }

  @Test("开始首段录音只依赖可用保存位置和麦克风")
  func recordingReadinessDoesNotRequireDownloadedModel() {
    let readyMicrophone = MicrophoneInputStatus(
      permission: .granted, hasUsableInput: true, sampleRate: 48_000, channelCount: 1)
    let deniedMicrophone = MicrophoneInputStatus(
      permission: .denied, hasUsableInput: false, sampleRate: 0, channelCount: 0)

    #expect(
      FirstRunSetupPresentation.canStartRecording(
        hasMaterialLibrary: true, microphoneStatus: readyMicrophone))
    #expect(
      !FirstRunSetupPresentation.canStartRecording(
        hasMaterialLibrary: false, microphoneStatus: readyMicrophone))
    #expect(
      !FirstRunSetupPresentation.canStartRecording(
        hasMaterialLibrary: true, microphoneStatus: deniedMicrophone))
  }

  @Test("小白文案说明本机模型和系统音频隐私边界")
  func plainLanguageCopyExplainsDataLocationAndOptionalPermission() {
    #expect(FirstRunSetupPresentation.modelDetail.contains("保存在这台 Mac"))
    #expect(FirstRunSetupPresentation.modelDetail.contains("不会上传录音"))
    #expect(FirstRunSetupPresentation.systemAudioDetail.contains("可选"))
    #expect(FirstRunSetupPresentation.systemAudioDetail.contains("不保存屏幕画面"))
    #expect(
      FirstRunSetupPresentation.recordingHint(hasLocalModel: false).contains("暂时不会转成文字"))
  }

  @Test("首次打开清单从第一步开始")
  func setupSheetDefaultsToTop() throws {
    let projectRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let source = try String(
      contentsOf: projectRoot.appendingPathComponent("Sources/WoiceApp/FirstRunSetupView.swift"),
      encoding: .utf8)

    #expect(source.contains(".defaultScrollAnchor(.top)"))
  }

  @Test("模型清单尚未缓存时可直接检查可下载模型")
  func setupSheetCanRefreshMissingModelCatalog() throws {
    let projectRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let source = try String(
      contentsOf: projectRoot.appendingPathComponent(
        "Sources/WoiceApp/FirstRunSetupView+Steps.swift"),
      encoding: .utf8)

    #expect(source.contains("检查可下载模型"))
    #expect(source.contains("refreshModelCatalog()"))
  }
}
