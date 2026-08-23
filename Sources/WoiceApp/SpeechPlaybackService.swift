import AVFoundation
import Observation

enum SpeechPlaybackState: Equatable {
  case idle
  case speaking
  case paused
  case finished

  var label: String {
    switch self {
    case .idle: "未朗读"
    case .speaking: "正在朗读"
    case .paused: "已暂停"
    case .finished: "朗读完成"
    }
  }

  var systemImage: String {
    switch self {
    case .idle: "speaker.wave.2"
    case .speaking: "speaker.wave.2.fill"
    case .paused: "pause.circle"
    case .finished: "checkmark.circle"
    }
  }
}

enum SpeechPlaybackError: LocalizedError, Sendable {
  case emptyText
  case exportFailed(String)

  var errorDescription: String? {
    switch self {
    case .emptyText: "没有可朗读的文字。"
    case .exportFailed(let message): "文字转音频失败：\(message)"
    }
  }
}

private final class SpeechExportAccumulator: @unchecked Sendable {
  private let lock = NSLock()
  private let url: URL
  private var file: AVAudioFile?
  private var continuation: CheckedContinuation<Void, Error>?
  private var didFinish = false

  init(url: URL) {
    self.url = url
  }

  func setContinuation(_ continuation: CheckedContinuation<Void, Error>) {
    lock.lock()
    self.continuation = continuation
    lock.unlock()
  }

  func consume(_ buffer: AVAudioBuffer) {
    guard let pcm = buffer as? AVAudioPCMBuffer else {
      finish(.failure(SpeechPlaybackError.exportFailed("系统语音返回了不可写入的音频格式。")))
      return
    }
    var result: Result<Void, Error>?
    lock.lock()
    guard !didFinish else {
      lock.unlock()
      return
    }
    do {
      if pcm.frameLength > 0 {
        if file == nil {
          file = try AVAudioFile(forWriting: url, settings: pcm.format.settings)
        }
        try file?.write(from: pcm)
      } else {
        guard file != nil else {
          throw SpeechPlaybackError.exportFailed("系统语音没有产生音频数据。")
        }
        file = nil
        didFinish = true
        result = .success(())
      }
    } catch {
      file = nil
      didFinish = true
      result = .failure(error)
    }
    let continuation = self.continuation
    if result != nil { self.continuation = nil }
    lock.unlock()
    if let result, let continuation { continuation.resume(with: result) }
  }

  private func finish(_ result: Result<Void, Error>) {
    lock.lock()
    guard !didFinish else {
      lock.unlock()
      return
    }
    didFinish = true
    file = nil
    let continuation = self.continuation
    self.continuation = nil
    lock.unlock()
    continuation?.resume(with: result)
  }
}

@MainActor
@Observable
final class SpeechPlaybackService {
  private let synthesizer = AVSpeechSynthesizer()
  private var stateTimer: Timer?
  private(set) var state: SpeechPlaybackState = .idle
  private(set) var sourceLabel = ""

  var isActive: Bool {
    state == .speaking || state == .paused
  }

  func speak(text: String, sourceLabel: String, language: String = "zh-CN") throws {
    let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else { throw SpeechPlaybackError.emptyText }
    stop()
    let utterance = AVSpeechUtterance(string: value)
    utterance.voice = AVSpeechSynthesisVoice(language: language)
    utterance.rate = AVSpeechUtteranceDefaultSpeechRate
    self.sourceLabel = sourceLabel
    state = .speaking
    synthesizer.speak(utterance)
    startStateTimer()
  }

  /// Explicitly renders text to a local WAV. This method is only exposed by
  /// the standalone text-to-audio workspace; recording completion never calls it.
  func exportWAV(text: String, to url: URL, language: String = "zh-CN") async throws {
    let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else { throw SpeechPlaybackError.emptyText }
    stop()
    try? FileManager.default.removeItem(at: url)
    let utterance = AVSpeechUtterance(string: value)
    utterance.voice = AVSpeechSynthesisVoice(language: language)
    utterance.rate = AVSpeechUtteranceDefaultSpeechRate
    try await withCheckedThrowingContinuation { continuation in
      let accumulator = SpeechExportAccumulator(url: url)
      accumulator.setContinuation(continuation)
      synthesizer.write(utterance) { buffer in
        accumulator.consume(buffer)
      }
    }
  }

  func togglePause() {
    switch state {
    case .speaking:
      if synthesizer.pauseSpeaking(at: .immediate) {
        state = .paused
      }
    case .paused:
      if synthesizer.continueSpeaking() {
        state = .speaking
      }
    case .idle, .finished:
      break
    }
  }

  func stop() {
    synthesizer.stopSpeaking(at: .immediate)
    stopStateTimer()
    state = .idle
    sourceLabel = ""
  }

  private func startStateTimer() {
    stopStateTimer()
    stateTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
      Task { @MainActor [weak self] in
        guard let self else { return }
        guard self.state == .speaking, !self.synthesizer.isSpeaking else { return }
        self.state = .finished
        self.stopStateTimer()
      }
    }
  }

  private func stopStateTimer() {
    stateTimer?.invalidate()
    stateTimer = nil
  }
}
