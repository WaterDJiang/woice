@preconcurrency import AVFoundation
import Foundation

enum AudioActivityState: Equatable, Sendable {
  case waiting
  case active
  case quiet

  var label: String {
    switch self {
    case .waiting: "等待麦克风输入"
    case .active: "检测到声音"
    case .quiet: "麦克风已连接，当前安静"
    }
  }

  var systemImage: String {
    switch self {
    case .waiting: "mic.slash"
    case .active: "waveform"
    case .quiet: "mic"
    }
  }
}

struct AudioActivitySnapshot: Equatable, Sendable {
  let state: AudioActivityState
  let segmentCount: Int
  let currentSegmentDuration: TimeInterval
  let totalVoiceDuration: TimeInterval
  let totalFrameCount: AVAudioFramePosition
  let segments: [AudioActivitySegment]
}

struct AudioActivitySegment: Equatable, Sendable {
  let start: TimeInterval
  let end: TimeInterval

  var duration: TimeInterval { max(0, end - start) }
}

struct AudioActivityMonitor: Sendable {
  let sampleRate: Double
  let threshold: Float
  let silenceHangover: TimeInterval
  private(set) var totalFrameCount: AVAudioFramePosition = 0
  private(set) var segmentCount = 0
  private(set) var state: AudioActivityState = .waiting
  private var activeStartFrame: AVAudioFramePosition?
  private var lastVoiceEndFrame: AVAudioFramePosition?
  private var closedVoiceFrames: AVAudioFramePosition = 0
  private var closedSegments: [AudioActivitySegment] = []

  init(
    sampleRate: Double, threshold: Float = 0.0025, silenceHangover: TimeInterval = 0.6
  ) {
    self.sampleRate = max(sampleRate, 1)
    self.threshold = max(threshold, 0)
    self.silenceHangover = max(silenceHangover, 0)
  }

  mutating func consume(frameCount: AVAudioFrameCount, peakLevel: Float) -> AudioActivitySnapshot {
    guard frameCount > 0 else { return snapshot() }
    let startFrame = totalFrameCount
    totalFrameCount += AVAudioFramePosition(frameCount)
    let isVoice = peakLevel >= threshold
    if isVoice {
      if activeStartFrame == nil {
        activeStartFrame = startFrame
        segmentCount += 1
      }
      lastVoiceEndFrame = totalFrameCount
      state = .active
    } else if let activeStartFrame, let lastVoiceEndFrame {
      let silentFrames = totalFrameCount - lastVoiceEndFrame
      let hangoverFrames = AVAudioFramePosition(silenceHangover * sampleRate)
      if silentFrames >= hangoverFrames {
        closeSegment(startFrame: activeStartFrame, endFrame: lastVoiceEndFrame)
        self.activeStartFrame = nil
        self.lastVoiceEndFrame = nil
        state = .quiet
      } else {
        state = .active
      }
    } else {
      state = .quiet
    }
    return snapshot()
  }

  func snapshot() -> AudioActivitySnapshot {
    let currentVoiceFrames: AVAudioFramePosition
    if let activeStartFrame, let lastVoiceEndFrame {
      currentVoiceFrames = max(0, lastVoiceEndFrame - activeStartFrame)
    } else {
      currentVoiceFrames = 0
    }
    var segments = closedSegments
    if let activeStartFrame, let lastVoiceEndFrame {
      segments.append(
        AudioActivitySegment(
          start: Double(activeStartFrame) / sampleRate,
          end: Double(lastVoiceEndFrame) / sampleRate
        )
      )
    }
    return AudioActivitySnapshot(
      state: state,
      segmentCount: segmentCount,
      currentSegmentDuration: Double(currentVoiceFrames) / sampleRate,
      totalVoiceDuration: Double(closedVoiceFrames + currentVoiceFrames) / sampleRate,
      totalFrameCount: totalFrameCount,
      segments: segments
    )
  }

  private mutating func closeSegment(
    startFrame: AVAudioFramePosition, endFrame: AVAudioFramePosition
  ) {
    let start = Double(startFrame) / sampleRate
    let end = Double(max(startFrame, endFrame)) / sampleRate
    closedSegments.append(AudioActivitySegment(start: start, end: end))
    closedVoiceFrames += max(0, endFrame - startFrame)
  }
}
