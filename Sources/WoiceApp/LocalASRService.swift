import Foundation
@preconcurrency import Speech
import WoiceCore

protocol LocalASRTranscribing: Sendable {
  var model: ASRModelDescriptor { get }
  func transcribe(audioURL: URL, language: String) async throws -> TranscriptionResult
}

/// Deterministic workflow-only provider for the isolated desktop acceptance
/// Journey. It is reachable only when the process explicitly opts into test
/// mode; it is never selected by a normal Woice launch or user setting.
final class AcceptanceFixtureTranscriptionService: LocalASRTranscribing, @unchecked Sendable {
  let model = ASRModelDescriptor(
    providerID: "com.woice.acceptance.fixture",
    modelID: "desktop-import-fixture",
    displayName: "Woice 桌面导入验收模型",
    version: "fixture-v1",
    dataLocation: .onDevice)

  func transcribe(audioURL: URL, language: String) async throws -> TranscriptionResult {
    guard FileManager.default.fileExists(atPath: audioURL.path) else {
      throw LocalASRError.audioMissing
    }
    return TranscriptionResult(
      text: "桌面导入验收素材",
      segments: [TranscriptSegment(start: 0, end: 0.5, text: "桌面导入验收素材")])
  }
}

enum LocalASRAuthorizationState: Equatable, Sendable {
  case notRequired
  case notDetermined
  case authorized
  case denied
  case restricted

  var title: String {
    switch self {
    case .notRequired: "由当前本机 Provider 管理"
    case .notDetermined: "等待授权"
    case .authorized: "已允许"
    case .denied: "已拒绝"
    case .restricted: "受系统限制"
    }
  }

  var systemImage: String {
    switch self {
    case .notRequired: "checkmark.circle"
    case .notDetermined: "questionmark.circle"
    case .authorized: "checkmark.shield.fill"
    case .denied, .restricted: "exclamationmark.shield.fill"
    }
  }
}

protocol LocalASRAuthorizationProviding: Sendable {
  var authorizationState: LocalASRAuthorizationState { get }
  func requestAuthorization() async -> LocalASRAuthorizationState
}

enum LocalASRError: LocalizedError, Equatable, Sendable {
  case audioMissing
  case permissionDenied
  case modelUnavailable
  case recognizerUnavailable
  case emptyResult
  case recognitionFailed(String)

  var errorDescription: String? {
    switch self {
    case .audioMissing:
      "本机转写找不到已保存的录音文件。"
    case .permissionDenied:
      "没有语音识别权限；原始录音仍已保存在本机。请在系统设置中允许 Woice 使用语音识别。"
    case .modelUnavailable:
      "这台 Mac 没有可用的本机语音模型；原始录音仍已保存在本机。"
    case .recognizerUnavailable:
      "本机语音识别暂时不可用；原始录音仍已保存在本机。"
    case .emptyResult:
      "本机模型没有识别出文字；原始录音仍已保存在本机。"
    case .recognitionFailed(let message):
      "本机转写失败：\(message)；原始录音仍已保存在本机。"
    }
  }
}

private final class RecognitionResultGate: @unchecked Sendable {
  private let lock = NSLock()
  private var didResume = false
  private var continuation: CheckedContinuation<TranscriptionResult, Error>?

  init(_ continuation: CheckedContinuation<TranscriptionResult, Error>) {
    self.continuation = continuation
  }

  func resume(_ result: Result<TranscriptionResult, Error>) {
    lock.lock()
    guard !didResume, let continuation else {
      lock.unlock()
      return
    }
    didResume = true
    self.continuation = nil
    lock.unlock()
    continuation.resume(with: result)
  }
}

/// Final, file-based ASR using the macOS on-device Speech model. This is a
/// local Provider, not the low-latency preview service, so the saved transcript
/// always comes from the durable WAV after recording has stopped.
final class OnDeviceSpeechTranscriptionService: LocalASRTranscribing,
  LocalASRAuthorizationProviding, @unchecked Sendable
{
  let model: ASRModelDescriptor = LocalASRModelCatalog.onDeviceSpeech

  var authorizationState: LocalASRAuthorizationState {
    Self.authorizationState(for: SFSpeechRecognizer.authorizationStatus())
  }

  func requestAuthorization() async -> LocalASRAuthorizationState {
    let status = await requestSpeechAuthorization()
    return Self.authorizationState(for: status)
  }

  func transcribe(audioURL: URL, language: String) async throws -> TranscriptionResult {
    guard FileManager.default.fileExists(atPath: audioURL.path) else {
      throw LocalASRError.audioMissing
    }
    // Permission is requested only from the explicit Settings action. A
    // transcription retry must never trigger a TCC prompt or couple the
    // recording lifecycle to Speech authorization.
    guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
      throw LocalASRError.permissionDenied
    }

    let localeIdentifier = TranscriptionLanguageOption.providerLanguageCode(for: language)
    guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier)) else {
      throw LocalASRError.recognizerUnavailable
    }
    guard recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
      throw LocalASRError.modelUnavailable
    }

    let request = SFSpeechURLRecognitionRequest(url: audioURL)
    request.shouldReportPartialResults = false
    request.requiresOnDeviceRecognition = true

    return try await withCheckedThrowingContinuation { continuation in
      let gate = RecognitionResultGate(continuation)
      _ = recognizer.recognitionTask(with: request) { result, error in
        if let result, result.isFinal {
          let text = result.bestTranscription.formattedString
            .trimmingCharacters(in: .whitespacesAndNewlines)
          guard !text.isEmpty else {
            gate.resume(.failure(LocalASRError.emptyResult))
            return
          }
          gate.resume(.success(TranscriptionResult(text: text)))
          return
        }
        if let error {
          gate.resume(.failure(LocalASRError.recognitionFailed(error.localizedDescription)))
        }
      }
    }
  }

  private func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
    await withCheckedContinuation { continuation in
      SFSpeechRecognizer.requestAuthorization { status in
        continuation.resume(returning: status)
      }
    }
  }

  private static func authorizationState(
    for status: SFSpeechRecognizerAuthorizationStatus
  ) -> LocalASRAuthorizationState {
    switch status {
    case .notDetermined: .notDetermined
    case .authorized: .authorized
    case .denied: .denied
    case .restricted: .restricted
    @unknown default: .restricted
    }
  }
}
