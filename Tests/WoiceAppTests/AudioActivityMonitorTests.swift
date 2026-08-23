import Testing

@testable import WoiceApp

@Test("VAD 阈值、静音 hangover 和片段计数稳定")
func audioActivityMonitorTracksVoiceSegments() {
  var monitor = AudioActivityMonitor(sampleRate: 100, threshold: 0.01, silenceHangover: 0.6)
  #expect(monitor.snapshot().state == .waiting)

  let quiet = monitor.consume(frameCount: 20, peakLevel: 0.001)
  #expect(quiet.state == .quiet)
  #expect(quiet.segmentCount == 0)

  let voice = monitor.consume(frameCount: 20, peakLevel: 0.02)
  #expect(voice.state == .active)
  #expect(voice.segmentCount == 1)
  #expect(abs(voice.currentSegmentDuration - 0.2) < 0.001)

  let hangover = monitor.consume(frameCount: 40, peakLevel: 0.001)
  #expect(hangover.state == .active)
  #expect(hangover.segmentCount == 1)

  let closed = monitor.consume(frameCount: 20, peakLevel: 0.001)
  #expect(closed.state == .quiet)
  #expect(closed.totalVoiceDuration > 0.19)
  #expect(closed.segments == [AudioActivitySegment(start: 0.2, end: 0.4)])

  let second = monitor.consume(frameCount: 10, peakLevel: 0.02)
  #expect(second.state == .active)
  #expect(second.segmentCount == 2)
  #expect(second.segments.count == 2)
  #expect(abs(second.segments[1].duration - 0.1) < 0.001)
}
