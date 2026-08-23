import AVFoundation
import CoreGraphics
import Foundation
@preconcurrency import ScreenCaptureKit
import Testing
import WoiceCore

@testable import WoiceApp

@Test("ScreenCaptureKit 系统音频流在已授权 Mac 上可启动并停止")
@MainActor
func systemAudioStreamStartsAndStops() async throws {
  guard CGPreflightScreenCaptureAccess() else { return }
  let content: SCShareableContent
  do {
    content = try await SCShareableContent.excludingDesktopWindows(
      false, onScreenWindowsOnly: true)
  } catch {
    if ProcessInfo.processInfo.environment["WOICE_REQUIRE_SYSTEM_AUDIO"] == "1" { throw error }
    return
  }
  guard !content.displays.isEmpty else {
    if ProcessInfo.processInfo.environment["WOICE_REQUIRE_SYSTEM_AUDIO"] == "1" {
      throw WoiceError.systemAudioUnavailable
    }
    return
  }
  let url = FileManager.default.temporaryDirectory.appendingPathComponent("woice-system-audio.caf")
  try? FileManager.default.removeItem(at: url)
  defer { try? FileManager.default.removeItem(at: url) }

  let capture = SystemAudioCaptureService()
  try await capture.start(to: url)
  #expect(capture.isCapturing)
  let requireSignal =
    ProcessInfo.processInfo.environment["WOICE_REQUIRE_SYSTEM_AUDIO_SIGNAL"] == "1"
  try await Task.sleep(for: requireSignal ? .seconds(15) : .milliseconds(250))
  let result = await capture.stop()
  #expect(!capture.isCapturing)
  #expect(result.errorDescription == nil)
  if ProcessInfo.processInfo.environment["WOICE_REQUIRE_SYSTEM_AUDIO"] == "1" {
    #expect(result.bufferCount > 0)
    #expect(result.url != nil)
    #expect(result.duration > 0)
    if requireSignal {
      #expect(result.peakLevel > 0)
    }
    if let resultURL = result.url {
      let file = try AVAudioFile(forReading: resultURL)
      #expect(file.length > 0)
    }
  }
  if let resultURL = result.url {
    #expect(FileManager.default.fileExists(atPath: resultURL.path))
  }
}

@Test("系统音频结果不会把静音 buffer 当成有效声音")
func systemAudioResultDistinguishesAudibleSignal() {
  let silent = SystemAudioCaptureResult(
    url: nil, duration: 0, bufferCount: 4, peakLevel: 0, target: nil, errorDescription: nil)
  let audible = SystemAudioCaptureResult(
    url: nil, duration: 0.2, bufferCount: 4, peakLevel: 0.02, target: .activeWindow,
    errorDescription: nil)
  #expect(!silent.hasAudibleSignal)
  #expect(audible.hasAudibleSignal)
}

@Test("系统音频目标优先全桌面，无码显示器时明确使用窗口级能力")
func systemAudioCapabilityPrefersDisplayAndExposesWindowFallback() {
  let desktop = SystemAudioCapability.resolved(
    screenCaptureAuthorized: true, displayCount: 1, windowCount: 4)
  #expect(desktop.state == .ready)
  #expect(desktop.displayCount == 1)

  let window = SystemAudioCapability.resolved(
    screenCaptureAuthorized: true, displayCount: 0, windowCount: 2)
  #expect(window.state == .readyWindow)
  #expect(window.windowCount == 2)

  let unavailable = SystemAudioCapability.resolved(
    screenCaptureAuthorized: true, displayCount: 0, windowCount: 0)
  #expect(unavailable.state == .noDisplay)
}
