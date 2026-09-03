@preconcurrency import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
@preconcurrency import ScreenCaptureKit
import WoiceCore

struct SystemAudioCaptureResult: Sendable {
  let url: URL?
  let duration: TimeInterval
  let bufferCount: Int
  let peakLevel: Float
  let target: SystemAudioCaptureTarget?
  let errorDescription: String?

  var hasAudibleSignal: Bool {
    bufferCount > 0 && peakLevel > 0.0001
  }
}

private final class SystemAudioFileWriter: @unchecked Sendable {
  private let lock = NSLock()
  private let url: URL
  private let sessionID: UUID?
  private let durableChunkDirectory: URL?
  private let durableChunkObserver: (@Sendable (RecordingChunkCommit) -> Void)?
  private var file: AVAudioFile?
  private var rollingChunkWriter: RollingPCMChunkWriter?
  private var frameCount: AVAudioFramePosition = 0
  private var bufferCount = 0
  private var peakLevel: Float = 0
  private var sampleRate: Double = 0
  private var writeError: String?
  private var durabilityError: String?

  init(
    url: URL,
    sessionID: UUID? = nil,
    durableChunkDirectory: URL? = nil,
    durableChunkObserver: (@Sendable (RecordingChunkCommit) -> Void)? = nil
  ) {
    self.url = url
    self.sessionID = sessionID
    self.durableChunkDirectory = durableChunkDirectory
    self.durableChunkObserver = durableChunkObserver
  }

  func append(_ sampleBuffer: CMSampleBuffer) {
    lock.lock()
    guard CMSampleBufferDataIsReady(sampleBuffer), CMSampleBufferGetNumSamples(sampleBuffer) > 0
    else {
      lock.unlock()
      return
    }
    guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
      let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(
        formatDescription),
      let format = AVAudioFormat(streamDescription: streamDescription)
    else {
      writeError = "无法读取系统音频格式。"
      lock.unlock()
      return
    }
    if file == nil {
      do {
        sampleRate = format.sampleRate
        var settings =
          url.pathExtension.lowercased() == "m4a"
          ? RecordingAudioFormat.aacSettings(
            sampleRate: format.sampleRate, channelCount: Int(format.channelCount), bitRate: 128_000)
          : format.settings
        if url.pathExtension.lowercased() != "m4a" {
          settings[AVLinearPCMIsNonInterleaved] = false
        }
        file =
          if url.pathExtension.lowercased() == "m4a" {
            try AVAudioFile(
              forWriting: url, settings: settings, commonFormat: format.commonFormat,
              interleaved: format.isInterleaved)
          } else {
            try AVAudioFile(forWriting: url, settings: settings)
          }
        if let sessionID, let durableChunkDirectory {
          rollingChunkWriter = try RollingPCMChunkWriter(
            sessionID: sessionID,
            track: .systemAudio,
            directoryURL: durableChunkDirectory,
            format: format)
        }
      } catch {
        writeError = error.localizedDescription
        lock.unlock()
        return
      }
    }
    guard let file else {
      lock.unlock()
      return
    }
    var committedChunks: [RecordingChunkCommit] = []
    do {
      try withAudioBufferList(sampleBuffer) { bufferList, frameLength in
        guard
          let pcmBuffer = AVAudioPCMBuffer(
            pcmFormat: format, bufferListNoCopy: bufferList, deallocator: nil)
        else {
          throw WoiceError.invalidResponse
        }
        pcmBuffer.frameLength = frameLength
        try file.write(from: pcmBuffer)
        frameCount += AVAudioFramePosition(frameLength)
        bufferCount += 1
        peakLevel = max(
          peakLevel, peakLevel(in: bufferList, format: format, frameLength: frameLength))
        committedChunks = try rollingChunkWriter?.append(pcmBuffer) ?? []
      }
    } catch {
      writeError = error.localizedDescription
      if rollingChunkWriter != nil { durabilityError = error.localizedDescription }
    }
    lock.unlock()
    if let durableChunkObserver {
      for chunk in committedChunks { durableChunkObserver(chunk) }
    }
  }

  func recordStreamError(_ error: Error) {
    lock.lock()
    defer { lock.unlock() }
    if writeError == nil { writeError = error.localizedDescription }
  }

  func snapshot() -> SystemAudioCaptureResult {
    lock.lock()
    defer { lock.unlock() }
    return SystemAudioCaptureResult(
      url: bufferCount > 0 ? url : nil,
      duration: sampleRate > 0 ? Double(frameCount) / sampleRate : 0,
      bufferCount: bufferCount,
      peakLevel: peakLevel,
      target: nil,
      errorDescription: writeError ?? durabilityError
    )
  }

  /// Commits the CAF container before the file is handed to playback or the
  /// recording index. This mirrors the microphone WAV writer and avoids
  /// exposing a file whose data chunk is still only in the last AVAudioFile
  /// reference.
  func finish() {
    lock.lock()
    guard file != nil else {
      lock.unlock()
      return
    }
    var committedChunks: [RecordingChunkCommit] = []
    do { committedChunks = try rollingChunkWriter?.finish() ?? [] } catch {
      durabilityError = error.localizedDescription
    }
    rollingChunkWriter = nil
    guard let file else {
      lock.unlock()
      return
    }
    if #available(macOS 15.0, *) {
      file.close()
    }
    self.file = nil
    let durableChunkObserver = self.durableChunkObserver
    lock.unlock()
    if let durableChunkObserver {
      for chunk in committedChunks { durableChunkObserver(chunk) }
    }
  }

  private func withAudioBufferList(
    _ sampleBuffer: CMSampleBuffer,
    body: (UnsafeMutablePointer<AudioBufferList>, AVAudioFrameCount) throws -> Void
  ) throws {
    var bufferListSize = 0
    let sizeStatus = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
      sampleBuffer,
      bufferListSizeNeededOut: &bufferListSize,
      bufferListOut: nil,
      bufferListSize: 0,
      blockBufferAllocator: nil,
      blockBufferMemoryAllocator: nil,
      flags: 0,
      blockBufferOut: nil
    )
    _ = sizeStatus
    guard bufferListSize > 0 else {
      throw WoiceError.invalidResponse
    }
    let rawBufferList = UnsafeMutableRawPointer.allocate(
      byteCount: bufferListSize, alignment: MemoryLayout<AudioBufferList>.alignment)
    defer { rawBufferList.deallocate() }
    let bufferList = rawBufferList.bindMemory(to: AudioBufferList.self, capacity: 1)
    var blockBuffer: CMBlockBuffer?
    let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
      sampleBuffer,
      bufferListSizeNeededOut: &bufferListSize,
      bufferListOut: bufferList,
      bufferListSize: bufferListSize,
      blockBufferAllocator: nil,
      blockBufferMemoryAllocator: nil,
      flags: 0,
      blockBufferOut: &blockBuffer
    )
    guard status == noErr else { throw WoiceError.invalidResponse }
    let frameLength = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
    try body(bufferList, frameLength)
  }

  private func peakLevel(
    in bufferList: UnsafeMutablePointer<AudioBufferList>, format: AVAudioFormat,
    frameLength: AVAudioFrameCount
  ) -> Float {
    let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
    var peak: Float = 0
    for buffer in buffers {
      guard let data = buffer.mData else { continue }
      if format.commonFormat == .pcmFormatFloat32 {
        let samples = data.assumingMemoryBound(to: Float.self)
        for index in 0..<Int(frameLength) { peak = max(peak, abs(samples[index])) }
      } else if format.commonFormat == .pcmFormatInt16 {
        let samples = data.assumingMemoryBound(to: Int16.self)
        for index in 0..<Int(frameLength) {
          peak = max(peak, abs(Float(samples[index])) / Float(Int16.max))
        }
      }
    }
    return peak
  }
}

private final class SystemAudioStreamOutput: NSObject, SCStreamOutput, SCStreamDelegate,
  @unchecked Sendable
{
  let writer: SystemAudioFileWriter

  init(writer: SystemAudioFileWriter) {
    self.writer = writer
  }

  func stream(
    _ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
    of type: SCStreamOutputType
  ) {
    guard type == .audio else { return }
    writer.append(sampleBuffer)
  }

  func stream(_ stream: SCStream, didStopWithError error: Error) {
    _ = stream
    writer.recordStreamError(error)
  }
}

@MainActor
final class SystemAudioCaptureService {
  private var stream: SCStream?
  private var output: SystemAudioStreamOutput?
  private var writer: SystemAudioFileWriter?
  private(set) var isCapturing = false
  private(set) var captureTarget: SystemAudioCaptureTarget?

  func start(
    to url: URL,
    sessionID: UUID? = nil,
    durableChunkDirectory: URL? = nil,
    durableChunkObserver: (@Sendable (RecordingChunkCommit) -> Void)? = nil
  ) async throws {
    guard !isCapturing else { return }
    let content: SCShareableContent
    do {
      // Runtime shareable content remains the source of truth. Preflight is
      // consulted only after the runtime read fails, so a stale TCC value
      // cannot block an already-authorized capture path.
      content = try await shareableContentWithFallback()
    } catch {
      if !CGPreflightScreenCaptureAccess() {
        throw WoiceError.systemAudioPermissionDenied
      }
      throw error
    }
    let filter: SCContentFilter
    let target: SystemAudioCaptureTarget
    if let display = content.displays.first {
      filter = SCContentFilter(display: display, excludingWindows: [])
      target = .display
    } else if let windowTarget = Self.preferredWindow(in: content) {
      filter = SCContentFilter(desktopIndependentWindow: windowTarget.window)
      target = windowTarget.target
    } else {
      if !CGPreflightScreenCaptureAccess() {
        throw WoiceError.systemAudioPermissionDenied
      }
      throw WoiceError.systemAudioUnavailable
    }
    let configuration = SCStreamConfiguration()
    configuration.capturesAudio = true
    configuration.sampleRate = 48_000
    configuration.channelCount = 2
    configuration.excludesCurrentProcessAudio = true
    configuration.width = 2
    configuration.height = 2
    let writer = SystemAudioFileWriter(
      url: url,
      sessionID: sessionID,
      durableChunkDirectory: durableChunkDirectory,
      durableChunkObserver: durableChunkObserver)
    let output = SystemAudioStreamOutput(writer: writer)
    let stream = SCStream(filter: filter, configuration: configuration, delegate: output)
    let queue = DispatchQueue(label: "com.woice.system-audio", qos: .userInitiated)
    try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: queue)
    do {
      try await stream.startCapture()
    } catch {
      try? stream.removeStreamOutput(output, type: .audio)
      throw error
    }
    self.writer = writer
    self.output = output
    self.stream = stream
    self.captureTarget = target
    isCapturing = true
  }

  private func shareableContentWithFallback() async throws -> SCShareableContent {
    if let visibleContent = try? await SCShareableContent.excludingDesktopWindows(
      false, onScreenWindowsOnly: true
    ), !visibleContent.displays.isEmpty {
      return visibleContent
    }
    return try await SCShareableContent.excludingDesktopWindows(
      false, onScreenWindowsOnly: false
    )
  }

  func stop() async -> SystemAudioCaptureResult {
    guard let stream, let writer else {
      return SystemAudioCaptureResult(
        url: nil, duration: 0, bufferCount: 0, peakLevel: 0, target: nil, errorDescription: nil)
    }
    var errorDescription: String?
    do {
      try await stream.stopCapture()
    } catch {
      errorDescription = error.localizedDescription
    }
    if let output { try? stream.removeStreamOutput(output, type: .audio) }
    writer.finish()
    let result = writer.snapshot()
    self.stream = nil
    self.output = nil
    self.writer = nil
    let target = self.captureTarget
    self.captureTarget = nil
    isCapturing = false
    return SystemAudioCaptureResult(
      url: result.url,
      duration: result.duration,
      bufferCount: result.bufferCount,
      peakLevel: result.peakLevel,
      target: target,
      errorDescription: errorDescription ?? result.errorDescription
    )
  }

  func cancel() async {
    let result = await stop()
    if let url = result.url { try? FileManager.default.removeItem(at: url) }
  }

  private struct WindowTarget {
    let window: SCWindow
    let target: SystemAudioCaptureTarget
  }

  private static func preferredWindow(in content: SCShareableContent) -> WindowTarget? {
    let candidates = content.windows.filter { window in
      guard window.owningApplication?.bundleIdentifier != Bundle.main.bundleIdentifier else {
        return false
      }
      return window.isOnScreen || window.isActive
    }
    if let active = candidates.first(where: \.isActive) {
      return WindowTarget(window: active, target: .activeWindow)
    }
    if let visible = candidates.first(where: \.isOnScreen) {
      return WindowTarget(window: visible, target: .visibleWindow)
    }
    return nil
  }
}
