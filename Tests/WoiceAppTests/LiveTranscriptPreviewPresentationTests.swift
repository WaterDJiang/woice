import AppKit
import Testing
@testable import WoiceApp

@Test("live preview stays hidden outside an eligible microphone recording")
func livePreviewEligibility() {
  #expect(
    LiveTranscriptPreviewPresentation.make(
      isRecording: false,
      isEnabled: true,
      capturesMicrophone: true,
      state: .listening,
      transcript: "正在说话"
    ) == nil)
  #expect(
    LiveTranscriptPreviewPresentation.make(
      isRecording: true,
      isEnabled: false,
      capturesMicrophone: true,
      state: .listening,
      transcript: "正在说话"
    ) == nil)
  #expect(
    LiveTranscriptPreviewPresentation.make(
      isRecording: true,
      isEnabled: true,
      capturesMicrophone: false,
      state: .listening,
      transcript: "正在说话"
    ) == nil)
}

@Test("live preview projects preparation listening and unavailable states")
func livePreviewStateProjection() {
  let preparing = LiveTranscriptPreviewPresentation.make(
    isRecording: true,
    isEnabled: true,
    capturesMicrophone: true,
    state: .requestingPermission,
    transcript: ""
  )
  #expect(preparing?.title == "正在准备实时文字")
  #expect(preparing?.body == "正在准备本机语音识别…")

  let listening = LiveTranscriptPreviewPresentation.make(
    isRecording: true,
    isEnabled: true,
    capturesMicrophone: true,
    state: .listening,
    transcript: "  会议已经开始  "
  )
  #expect(listening?.title == "实时文字")
  #expect(listening?.body == "会议已经开始")

  let waitingForSpeech = LiveTranscriptPreviewPresentation.make(
    isRecording: true,
    isEnabled: true,
    capturesMicrophone: true,
    state: .listening,
    transcript: " \n "
  )
  #expect(waitingForSpeech?.body == "正在听…")

  let unavailable = LiveTranscriptPreviewPresentation.make(
    isRecording: true,
    isEnabled: true,
    capturesMicrophone: true,
    state: .unavailable("未允许语音识别权限；录音仍会继续保存。"),
    transcript: ""
  )
  #expect(unavailable?.title == "实时文字不可用")
  #expect(unavailable?.isWarning == true)
}

@MainActor
@Test("popover dismissal ignores its own panel and status item")
func popoverDismissalPolicy() {
  let popoverWindow = NSWindow()
  let workspaceWindow = NSWindow()

  #expect(
    !PopoverDismissalPolicy.shouldClose(
      eventWindow: popoverWindow,
      popoverWindow: popoverWindow,
      isStatusItemButton: false))
  #expect(
    !PopoverDismissalPolicy.shouldClose(
      eventWindow: workspaceWindow,
      popoverWindow: popoverWindow,
      isStatusItemButton: true))
  #expect(
    PopoverDismissalPolicy.shouldClose(
      eventWindow: workspaceWindow,
      popoverWindow: popoverWindow,
      isStatusItemButton: false))
  #expect(
    PopoverDismissalPolicy.shouldClose(
      eventWindow: nil,
      popoverWindow: popoverWindow,
      isStatusItemButton: false))
}
