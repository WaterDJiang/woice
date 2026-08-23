@preconcurrency import AVFoundation
import Foundation
@preconcurrency import Speech
import WoiceCore

enum LiveTranscriptionState: Equatable, Sendable {
  case disabled
  case requestingPermission
  case unavailable(String)
  case listening
  case finished

  var label: String {
    switch self {
    case .disabled: "未开启本机实时预览"
    case .requestingPermission: "正在准备本机实时预览"
    case .unavailable(let message): message
    case .listening: "本机实时预览"
    case .finished: "本机实时预览已结束"
    }
  }

  var systemImage: String {
    switch self {
    case .disabled: "text.badge.minus"
    case .requestingPermission: "hourglass"
    case .unavailable: "exclamationmark.triangle"
    case .listening: "text.badge.checkmark"
    case .finished: "checkmark.circle"
    }
  }

  var isUnavailable: Bool {
    if case .unavailable = self { return true }
    return false
  }
}

struct LiveTranscriptionSnapshot: Equatable, Sendable {
  let state: LiveTranscriptionState
  let text: String
}

enum LiveTranscriptionError: LocalizedError, Equatable {
  case permissionDenied
  case onDeviceRecognitionUnavailable
  case recognizerUnavailable

  var errorDescription: String? {
    switch self {
    case .permissionDenied:
      "未允许语音识别权限；录音仍会继续保存。"
    case .onDeviceRecognitionUnavailable:
      "当前 Mac 没有可用的本机语音识别模型；录音仍会继续保存。"
    case .recognizerUnavailable:
      "本机语音识别暂时不可用；录音仍会继续保存。"
    }
  }
}

/// A fail-closed, on-device-only Speech buffer consumer. The recognition
/// callback and audio tap are both outside MainActor, so mutable state is
/// protected explicitly and UI reads use `snapshot()`.
final class LiveTranscriptionService: @unchecked Sendable {
  private let lock = NSLock()
  private var recognizer: SFSpeechRecognizer?
  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var task: SFSpeechRecognitionTask?
  private var currentText = ""
  private var currentState: LiveTranscriptionState = .disabled
  private var recognitionGeneration: UInt64 = 0

  func start(language: String) async throws {
    cancel()
    let generation = currentGeneration()
    setState(.requestingPermission, text: "")
    let authorization = await requestAuthorization()
    guard isCurrent(generation) else { return }
    guard authorization == .authorized else {
      let error = LiveTranscriptionError.permissionDenied
      setState(.unavailable(error.localizedDescription), text: "")
      throw error
    }

    let localeIdentifier = TranscriptionLanguageOption.providerLanguageCode(for: language)
    guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier)) else {
      let error = LiveTranscriptionError.recognizerUnavailable
      setState(.unavailable(error.localizedDescription), text: "")
      throw error
    }
    guard recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
      let error = LiveTranscriptionError.onDeviceRecognitionUnavailable
      setState(.unavailable(error.localizedDescription), text: "")
      throw error
    }

    let request = SFSpeechAudioBufferRecognitionRequest()
    request.shouldReportPartialResults = true
    request.requiresOnDeviceRecognition = true
    guard setRecognizer(recognizer, request: request, generation: generation) else { return }

    let task = recognizer.recognitionTask(with: request) { [weak self, generation] result, error in
      guard let self else { return }
      guard self.isCurrent(generation) else { return }
      if let result {
        self.setState(.listening, text: result.bestTranscription.formattedString)
      }
      if error != nil {
        // The final ASR path remains authoritative. Keep the preview text and
        // expose an actionable state without turning a recognition error into
        // a recording failure.
        self.setState(.unavailable("本机实时预览暂时不可用；录音仍会继续保存。"), text: nil)
      }
    }
    guard setTask(task, generation: generation) else {
      task.cancel()
      return
    }
    setState(.listening, text: "")
  }

  /// Called directly from the AVAudioEngine tap. Speech copies the buffer
  /// before the tap returns, so the writer and recognizer can share one tap.
  func append(_ buffer: AVAudioPCMBuffer) {
    lock.lock()
    let request = self.request
    lock.unlock()
    request?.append(buffer)
  }

  func snapshot() -> LiveTranscriptionSnapshot {
    lock.lock()
    defer { lock.unlock() }
    return LiveTranscriptionSnapshot(state: currentState, text: currentText)
  }

  func finish() -> LiveTranscriptionSnapshot {
    lock.lock()
    recognitionGeneration &+= 1
    let request = self.request
    let task = self.task
    self.request = nil
    self.task = nil
    self.recognizer = nil
    let snapshot = LiveTranscriptionSnapshot(state: .finished, text: currentText)
    currentState = .finished
    lock.unlock()
    request?.endAudio()
    task?.finish()
    return snapshot
  }

  func cancel() {
    lock.lock()
    recognitionGeneration &+= 1
    let request = self.request
    let task = self.task
    self.request = nil
    self.task = nil
    self.recognizer = nil
    currentText = ""
    currentState = .disabled
    lock.unlock()
    request?.endAudio()
    task?.cancel()
  }

  private func setState(_ state: LiveTranscriptionState, text: String?) {
    lock.lock()
    currentState = state
    if let text { currentText = text }
    lock.unlock()
  }

  private func setRecognizer(
    _ recognizer: SFSpeechRecognizer,
    request: SFSpeechAudioBufferRecognitionRequest,
    generation: UInt64
  ) -> Bool {
    lock.lock()
    guard generation == recognitionGeneration else {
      lock.unlock()
      return false
    }
    self.recognizer = recognizer
    self.request = request
    lock.unlock()
    return true
  }

  private func setTask(_ task: SFSpeechRecognitionTask, generation: UInt64) -> Bool {
    lock.lock()
    guard generation == recognitionGeneration else {
      lock.unlock()
      return false
    }
    self.task = task
    lock.unlock()
    return true
  }

  private func currentGeneration() -> UInt64 {
    lock.lock()
    defer { lock.unlock() }
    return recognitionGeneration
  }

  private func isCurrent(_ generation: UInt64) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return generation == recognitionGeneration
  }

  private func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
    await withCheckedContinuation { continuation in
      SFSpeechRecognizer.requestAuthorization { status in
        continuation.resume(returning: status)
      }
    }
  }
}
