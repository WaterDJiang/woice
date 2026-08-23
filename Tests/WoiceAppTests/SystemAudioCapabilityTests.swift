import Foundation
import Testing
import WoiceCore

@testable import WoiceApp

@Test("系统音频能力状态按权限、显示器和错误稳定映射")
func systemAudioCapabilityStateMapping() {
  #expect(
    SystemAudioCapability.resolved(screenCaptureAuthorized: false, displayCount: 0).state
      == .needsPermission)
  #expect(
    SystemAudioCapability.resolved(
      screenCaptureAuthorized: false, displayCount: 0, permissionRefreshRequired: true
    ).state == .needsReauthorization)
  #expect(
    SystemAudioCapability.resolved(screenCaptureAuthorized: true, displayCount: 0).state
      == .noDisplay)
  #expect(
    SystemAudioCapability.resolved(screenCaptureAuthorized: true, displayCount: 1).state == .ready)
  #expect(
    SystemAudioCapability.resolved(screenCaptureAuthorized: true, displayCount: 0, windowCount: 1)
      .state == .readyWindow)
  #expect(
    SystemAudioCapability.resolved(
      screenCaptureAuthorized: true, displayCount: 0, errorDescription: "读取失败"
    ).state == .unavailable("读取失败"))
}

@Test("系统音频重新授权状态给出当前安装包修复提示")
func systemAudioReauthorizationStateIsActionable() {
  #expect(SystemAudioCapabilityState.needsReauthorization.title.contains("当前安装包"))
}

@Test("系统音频权限错误提供可执行的屏幕录制授权提示")
func systemAudioPermissionErrorIsActionable() {
  let message = WoiceError.systemAudioPermissionDenied.errorDescription ?? ""
  #expect(message.contains("当前 Woice 安装实例"))
  #expect(message.contains("屏幕录制"))
  #expect(message.contains("系统设置"))
  #expect(message.contains("重新检查"))
}

@Test("系统音频无采集目标错误说明桌面恢复动作")
func systemAudioUnavailableErrorIsActionable() {
  let message = WoiceError.systemAudioUnavailable.errorDescription ?? ""
  #expect(message.contains("可共享显示器或窗口"))
  #expect(message.contains("解锁桌面"))
  #expect(message.contains("远程桌面"))
}
