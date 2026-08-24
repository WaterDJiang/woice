@preconcurrency import AVFoundation
import Foundation
import WoiceCore

private struct AudioWriterSnapshot {
  let duration: TimeInterval
  let bufferCount: Int
  let currentPeakLevel: Float
  let peakLevel: Float
  let errorDescription: String?
  let activity: AudioActivitySnapshot
}

private struct MicrophoneInputFormat: Sendable {
  let sampleRate: Double
  let channelCount: Int
}

/// Bridges a potentially non-cancellable CoreAudio probe to a bounded async
/// caller. A stuck HAL call may continue on its detached thread, but it can no
/// longer block the MainActor or a settings render.
private final class MicrophoneProbeGate: @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: CheckedContinuation<MicrophoneInputFormat?, Never>?
  private var resolved = false

  func install(_ continuation: CheckedContinuation<MicrophoneInputFormat?, Never>) {
    lock.lock()
    if resolved {
      lock.unlock()
      continuation.resume(returning: nil)
      return
    }
    self.continuation = continuation
    lock.unlock()
  }

  func resolve(_ result: MicrophoneInputFormat?) {
    lock.lock()
    guard !resolved else {
      lock.unlock()
      return
    }
    resolved = true
    let continuation = self.continuation
    self.continuation = nil
    lock.unlock()
    continuation?.resume(returning: result)
  }
}

/// A VAD-closed WAV that can be transcribed while the main recording remains open.
/// The main recording is still the source of truth; this file is only a derived,
/// disposable processing input.
struct RecordedAudioSegment: Sendable {
  let url: URL
  let voiceSegment: VoiceSegment
  let index: Int
}

enum MicrophonePermissionState: String, Equatable, Sendable {
  case notDetermined
  case denied
  case granted
  case unknown
}

struct MicrophoneInputStatus: Equatable, Sendable {
  let permission: MicrophonePermissionState
  let hasUsableInput: Bool
  let sampleRate: Double
  let channelCount: Int
}

struct MicrophoneCheckResult: Equatable, Sendable {
  let duration: TimeInterval
  let bufferCount: Int
  let peakLevel: Float
}

enum MicrophoneCapturePolicy {
  static let firstBufferTimeout: Duration = .seconds(1)
  static let firstBufferPollInterval: Duration = .milliseconds(50)
}

enum RecordingStoragePolicy {
  /// A recording can grow continuously, so this is a startup safety floor,
  /// not a promise that an arbitrarily long meeting will fit.
  static let minimumAvailableBytes: Int64 = 256 * 1024 * 1024

  static func validationError(availableBytes: Int64?) -> WoiceError? {
    guard let availableBytes, availableBytes >= 0 else { return nil }
    guard availableBytes < minimumAvailableBytes else { return nil }
    return .insufficientStorage(
      required: minimumAvailableBytes, available: availableBytes)
  }
}

private final class AudioWriter: @unchecked Sendable {
  private let lock = NSLock()
  private var file: AVAudioFile?
  private let sampleRate: Double
  private var frameCount: AVAudioFramePosition = 0
  private var bufferCount = 0
  private var currentPeakLevel: Float = 0
  private var peakLevel: Float = 0
  private var writeError: String?
  private var activityMonitor: AudioActivityMonitor
  private let audioBufferObserver: (@Sendable (AVAudioPCMBuffer) -> Void)?
  private let segmentObserver: (@Sendable (RecordedAudioSegment) -> Void)?
  private var segmentFile: AVAudioFile?
  private let segmentDirectory: URL?
  private var segmentIndex = 0
  private var segmentStartFrame: AVAudioFramePosition?

  init(
    url: URL, format: AVAudioFormat,
    audioBufferObserver: (@Sendable (AVAudioPCMBuffer) -> Void)? = nil,
    segmentDirectory: URL? = nil,
    segmentObserver: (@Sendable (RecordedAudioSegment) -> Void)? = nil
  ) throws {
    let settings =
      url.pathExtension.lowercased() == "m4a"
      ? RecordingAudioFormat.aacSettings(
        sampleRate: format.sampleRate, channelCount: Int(format.channelCount), bitRate: 64_000)
      : format.settings
    file =
      if url.pathExtension.lowercased() == "m4a" {
        try AVAudioFile(
          forWriting: url, settings: settings, commonFormat: format.commonFormat,
          interleaved: format.isInterleaved)
      } else {
        try AVAudioFile(forWriting: url, settings: settings)
      }
    sampleRate = format.sampleRate
    activityMonitor = AudioActivityMonitor(sampleRate: format.sampleRate)
    self.audioBufferObserver = audioBufferObserver
    self.segmentDirectory = segmentDirectory
    self.segmentObserver = segmentObserver
    if let segmentDirectory {
      try FileManager.default.createDirectory(
        at: segmentDirectory, withIntermediateDirectories: true)
    }
  }

  func append(_ buffer: AVAudioPCMBuffer) {
    lock.lock()
    guard let file else {
      lock.unlock()
      return
    }
    var observer: (@Sendable (AVAudioPCMBuffer) -> Void)?
    var completedSegment: RecordedAudioSegment?
    do {
      try file.write(from: buffer)
      let previousActivity = activityMonitor.snapshot()
      frameCount += AVAudioFramePosition(buffer.frameLength)
      bufferCount += 1
      currentPeakLevel = peakLevel(in: buffer)
      peakLevel = max(peakLevel, currentPeakLevel)
      let activity = activityMonitor.consume(
        frameCount: buffer.frameLength, peakLevel: currentPeakLevel)
      if previousActivity.state != .active, activity.state == .active {
        startSegmentLocked(
          format: buffer.format, startFrame: frameCount - AVAudioFramePosition(buffer.frameLength))
      }
      if activity.state == .active || previousActivity.state == .active {
        do {
          try segmentFile?.write(from: buffer)
        } catch {
          // Segment files are an optimization. A failed segment must not make
          // the source recording fail; the stopped WAV remains the fallback.
          segmentFile = nil
          segmentStartFrame = nil
        }
      }
      if previousActivity.state == .active, activity.state != .active {
        completedSegment = finishSegmentLocked(
          voiceEnd: activity.segments.last?.end
            ?? Double(frameCount) / sampleRate)
      }
      observer = audioBufferObserver
    } catch {
      writeError = error.localizedDescription
    }
    lock.unlock()
    observer?(buffer)
    if let completedSegment { segmentObserver?(completedSegment) }
  }

  func snapshot() -> AudioWriterSnapshot {
    lock.lock()
    defer { lock.unlock() }
    return AudioWriterSnapshot(
      duration: sampleRate > 0 ? Double(frameCount) / sampleRate : 0,
      bufferCount: bufferCount,
      currentPeakLevel: currentPeakLevel,
      peakLevel: peakLevel,
      errorDescription: writeError,
      activity: activityMonitor.snapshot()
    )
  }

  /// Stops new writes and commits the container header before the file is
  /// handed to playback, export, or an external transcription provider.
  /// `AVAudioFile.close()` is available on macOS 15; setting the reference to
  /// nil also guarantees deallocation/finalization on macOS 14.
  func finish() -> RecordedAudioSegment? {
    lock.lock()
    guard let file else {
      lock.unlock()
      return nil
    }
    let activity = activityMonitor.snapshot()
    let completedSegment =
      segmentFile == nil
      ? nil
      : finishSegmentLocked(
        voiceEnd: activity.segments.last?.end ?? Double(frameCount) / sampleRate)
    if #available(macOS 15.0, *) {
      file.close()
    }
    self.file = nil
    lock.unlock()
    return completedSegment
  }

  private func startSegmentLocked(format: AVAudioFormat, startFrame: AVAudioFramePosition) {
    guard let segmentDirectory else { return }
    let url = segmentDirectory.appendingPathComponent("segment-\(segmentIndex).wav")
    do {
      segmentFile = try AVAudioFile(forWriting: url, settings: format.settings)
      segmentStartFrame = startFrame
    } catch {
      segmentFile = nil
      segmentStartFrame = nil
    }
  }

  private func finishSegmentLocked(voiceEnd: TimeInterval) -> RecordedAudioSegment? {
    guard let segmentFile, let segmentStartFrame, let segmentDirectory else {
      self.segmentFile = nil
      self.segmentStartFrame = nil
      return nil
    }
    if #available(macOS 15.0, *) {
      segmentFile.close()
    }
    self.segmentFile = nil
    self.segmentStartFrame = nil
    let url = segmentDirectory.appendingPathComponent("segment-\(segmentIndex).wav")
    let segment = RecordedAudioSegment(
      url: url,
      voiceSegment: VoiceSegment(
        start: Double(segmentStartFrame) / sampleRate,
        end: max(Double(segmentStartFrame) / sampleRate, voiceEnd)),
      index: segmentIndex)
    segmentIndex += 1
    return segment
  }

  private func peakLevel(in buffer: AVAudioPCMBuffer) -> Float {
    let frames = Int(buffer.frameLength)
    let channels = Int(buffer.format.channelCount)
    guard frames > 0, channels > 0 else { return 0 }

    if let channelData = buffer.floatChannelData {
      var peak: Float = 0
      for channel in 0..<channels {
        let samples = channelData[channel]
        for frame in 0..<frames {
          peak = max(peak, abs(samples[frame]))
        }
      }
      return peak
    }

    if let channelData = buffer.int16ChannelData {
      var peak: Float = 0
      for channel in 0..<channels {
        let samples = channelData[channel]
        for frame in 0..<frames {
          peak = max(peak, abs(Float(samples[frame])) / Float(Int16.max))
        }
      }
      return peak
    }

    return 0
  }
}

@MainActor
final class RecordingService {
  // Create the input engine only after TCC permission is granted. Keeping an
  // engine created before the first permission decision can leave the input
  // node bound to the pre-authorization route on the first recording.
  private var engine: AVAudioEngine?
  private var writer: AudioWriter?
  private(set) var currentURL: URL?
  private(set) var isRecording = false
  private(set) var lastWriteError: String?
  private var segmentObserver: (@Sendable (RecordedAudioSegment) -> Void)?
  private var cachedInputFormat: MicrophoneInputFormat?

  var microphoneStatus: MicrophoneInputStatus {
    let permission = currentMicrophonePermission
    guard permission == .granted, let cachedInputFormat else {
      return MicrophoneInputStatus(
        permission: permission,
        hasUsableInput: false,
        sampleRate: cachedInputFormat?.sampleRate ?? 0,
        channelCount: cachedInputFormat?.channelCount ?? 0)
    }
    return MicrophoneInputStatus(
      permission: permission,
      hasUsableInput: cachedInputFormat.sampleRate > 0 && cachedInputFormat.channelCount > 0,
      sampleRate: cachedInputFormat.sampleRate,
      channelCount: cachedInputFormat.channelCount
    )
  }

  /// Probes the current input away from the MainActor and returns within a
  /// bounded interval. CoreAudio's HAL call cannot always be cancelled, so a
  /// stuck probe is intentionally abandoned rather than freezing the UI.
  func refreshMicrophoneStatus() async -> MicrophoneInputStatus {
    let permission = currentMicrophonePermission
    guard permission == .granted else {
      cachedInputFormat = nil
      return microphoneStatus
    }
    guard !isRecording else { return microphoneStatus }

    let gate = MicrophoneProbeGate()
    let format = await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        gate.install(continuation)
        Task.detached(priority: .utility) {
          gate.resolve(Self.probeMicrophoneInputFormat())
        }
        Task.detached(priority: .utility) {
          try? await Task.sleep(for: .seconds(1))
          gate.resolve(nil)
        }
      }
    } onCancel: {
      gate.resolve(nil)
    }
    cachedInputFormat = format
    return microphoneStatus
  }

  var receivedBufferCount: Int { writer?.snapshot().bufferCount ?? 0 }
  var capturedDuration: TimeInterval { writer?.snapshot().duration ?? 0 }
  var inputLevel: Float { writer?.snapshot().currentPeakLevel ?? 0 }
  var sessionPeakLevel: Float { writer?.snapshot().peakLevel ?? 0 }
  var activity: AudioActivitySnapshot {
    writer?.snapshot().activity
      ?? AudioActivityMonitor(sampleRate: 1).snapshot()
  }

  func start(
    to url: URL,
    audioBufferObserver: (@Sendable (AVAudioPCMBuffer) -> Void)? = nil,
    segmentObserver: (@Sendable (RecordedAudioSegment) -> Void)? = nil
  ) async throws {
    guard !isRecording else { return }
    try validateStorageCapacity(for: url)
    try await requestRecordPermission()
    let engine = AVAudioEngine()
    self.engine = engine
    let input = engine.inputNode
    let format = input.outputFormat(forBus: 0)
    guard format.sampleRate > 0, format.channelCount > 0 else {
      throw WoiceError.microphoneUnavailable
    }
    cachedInputFormat = MicrophoneInputFormat(
      sampleRate: format.sampleRate, channelCount: Int(format.channelCount))
    let audioWriter = try AudioWriter(
      url: url,
      format: format,
      audioBufferObserver: audioBufferObserver,
      segmentDirectory: Self.segmentDirectory(for: url),
      segmentObserver: segmentObserver)
    // CoreAudio invokes this on RealtimeMessenger.mServiceQueue, never MainActor.
    // Build the closure from a nonisolated factory; forming it inside this
    // @MainActor method would make Swift insert a runtime executor check in the
    // realtime callback and crash the app as soon as the first buffer arrives.
    let tap = Self.makeAudioTap(writer: audioWriter)
    input.installTap(onBus: 0, bufferSize: 4_096, format: format, block: tap)
    do {
      engine.prepare()
      try engine.start()
    } catch {
      input.removeTap(onBus: 0)
      self.engine = nil
      throw error
    }
    writer = audioWriter
    currentURL = url
    isRecording = true
    lastWriteError = nil
    self.segmentObserver = segmentObserver
    do {
      try await waitForFirstAudioBuffer(from: audioWriter)
    } catch {
      let failedURL = stop().url
      if let failedURL {
        try? FileManager.default.removeItem(at: failedURL)
        try? FileManager.default.removeItem(at: Self.segmentDirectory(for: failedURL))
      }
      throw error
    }
  }

  private func waitForFirstAudioBuffer(from audioWriter: AudioWriter) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: MicrophoneCapturePolicy.firstBufferTimeout)
    while clock.now < deadline {
      let snapshot = audioWriter.snapshot()
      if snapshot.bufferCount > 0, snapshot.duration > 0 { return }
      if let errorDescription = snapshot.errorDescription {
        throw WoiceError.storageFailure(errorDescription)
      }
      try await Task.sleep(for: MicrophoneCapturePolicy.firstBufferPollInterval)
    }
    let snapshot = audioWriter.snapshot()
    if snapshot.bufferCount > 0, snapshot.duration > 0 { return }
    if let errorDescription = snapshot.errorDescription {
      throw WoiceError.storageFailure(errorDescription)
    }
    throw WoiceError.noAudio
  }

  private func validateStorageCapacity(for url: URL) throws {
    let volumeURL = url.deletingLastPathComponent()
    let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey]
    let values = try? volumeURL.resourceValues(forKeys: keys)
    if let error = RecordingStoragePolicy.validationError(
      availableBytes: values?.volumeAvailableCapacityForImportantUsage)
    {
      throw error
    }
  }

  private nonisolated static func makeAudioTap(writer: AudioWriter)
    -> @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void
  {
    { buffer, _ in
      writer.append(buffer)
    }
  }

  private func requestRecordPermission() async throws {
    switch AVAudioApplication.shared.recordPermission {
    case .granted:
      return
    case .denied:
      throw WoiceError.microphonePermissionDenied
    case .undetermined:
      let granted = await withCheckedContinuation { continuation in
        AVAudioApplication.requestRecordPermission { granted in
          continuation.resume(returning: granted)
        }
      }
      guard granted else { throw WoiceError.microphonePermissionDenied }
    @unknown default:
      throw WoiceError.microphonePermissionDenied
    }
  }

  func stop() -> (
    url: URL?, duration: TimeInterval, bufferCount: Int, peakLevel: Float,
    activity: AudioActivitySnapshot, capturedSegments: [RecordedAudioSegment]
  ) {
    guard isRecording else {
      return (
        nil, 0, 0, 0,
        AudioActivityMonitor(sampleRate: 1).snapshot(), []
      )
    }
    engine?.stop()
    engine?.inputNode.removeTap(onBus: 0)
    isRecording = false
    let snapshot = writer?.snapshot()
    let finalSegment = writer?.finish()
    lastWriteError = snapshot?.errorDescription
    let result = (
      currentURL,
      snapshot?.duration ?? 0,
      snapshot?.bufferCount ?? 0,
      snapshot?.peakLevel ?? 0,
      snapshot?.activity ?? AudioActivityMonitor(sampleRate: 1).snapshot(),
      finalSegment.map { [$0] } ?? []
    )
    writer = nil
    currentURL = nil
    engine = nil
    return result
  }

  /// Captures a short local-only sample for settings diagnostics. The sample
  /// is never indexed, uploaded, or retained after the check.
  func runMicrophoneCheck() async throws -> MicrophoneCheckResult {
    guard !isRecording else { throw WoiceError.microphoneCheckWhileRecording }
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      "woice-microphone-check-\(UUID().uuidString).wav")
    defer { try? FileManager.default.removeItem(at: url) }
    do {
      try await start(to: url)
      try await Task.sleep(for: .milliseconds(700))
      let result = stop()
      guard result.bufferCount > 0, result.duration > 0 else {
        throw WoiceError.noAudio
      }
      guard let resultURL = result.url,
        let file = try? AVAudioFile(forReading: resultURL), file.length > 0
      else {
        throw WoiceError.audioFileMissing
      }
      return MicrophoneCheckResult(
        duration: result.duration, bufferCount: result.bufferCount, peakLevel: result.peakLevel)
    } catch {
      if isRecording { cancel() }
      throw error
    }
  }

  func cancel() {
    let result = stop()
    if let url = result.url {
      try? FileManager.default.removeItem(at: url)
      try? FileManager.default.removeItem(at: Self.segmentDirectory(for: url))
    }
  }

  nonisolated private static func segmentDirectory(for url: URL) -> URL {
    url.deletingPathExtension().appendingPathExtension("segments")
  }

  private var currentMicrophonePermission: MicrophonePermissionState {
    switch AVAudioApplication.shared.recordPermission {
    case .undetermined: .notDetermined
    case .denied: .denied
    case .granted: .granted
    @unknown default: .unknown
    }
  }

  private nonisolated static func probeMicrophoneInputFormat() -> MicrophoneInputFormat? {
    let statusEngine = AVAudioEngine()
    let format = statusEngine.inputNode.inputFormat(forBus: 0)
    guard format.sampleRate > 0, format.channelCount > 0 else { return nil }
    return MicrophoneInputFormat(
      sampleRate: format.sampleRate, channelCount: Int(format.channelCount))
  }
}
