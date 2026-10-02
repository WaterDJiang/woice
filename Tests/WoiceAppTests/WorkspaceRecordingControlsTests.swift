import Testing

@testable import WoiceApp

struct WorkspaceRecordingControlsTests {
  @Test("工作台录音中主操作显示结束并保存")
  func recordingStateUsesStopAction() {
    #expect(WorkspaceRecordingSessionPresentation.actionTitle(isRecording: true) == "结束并保存")
    #expect(
      WorkspaceRecordingSessionPresentation.actionSystemImage(isRecording: true) == "stop.fill")
    #expect(
      WorkspaceRecordingSessionPresentation.accessibilityHint(isRecording: true)
        == "保存当前录音并开始处理")
  }

  @Test("工作台空闲时主操作显示开始录音")
  func idleStateUsesStartAction() {
    #expect(WorkspaceRecordingSessionPresentation.actionTitle(isRecording: false) == "开始录音")
    #expect(
      WorkspaceRecordingSessionPresentation.actionSystemImage(isRecording: false)
        == "record.circle")
  }
}
