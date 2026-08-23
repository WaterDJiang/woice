import AVFoundation
import Observation

@MainActor
@Observable
final class AudioPlaybackService {
  private(set) var currentURL: URL?
  private(set) var duration: TimeInterval = 0
  private(set) var currentTime: TimeInterval = 0
  private(set) var isPlaying = false
  var errorMessage: String?

  private var player: AVAudioPlayer?
  private var timer: Timer?

  /// Loads the committed audio container without starting playback. Detail
  /// views use this so the duration is truthful before the first click.
  func prepare(url: URL) {
    guard currentURL != url || duration <= 0 else { return }
    _ = load(url: url)
  }

  func toggle(url: URL) {
    if currentURL != url {
      guard load(url: url) else { return }
    }
    if isPlaying {
      pause()
    } else {
      play()
    }
  }

  func play(url: URL) {
    if currentURL != url, !load(url: url) { return }
    play()
  }

  func pause() {
    player?.pause()
    isPlaying = false
    stopTimer()
    syncCurrentTime()
  }

  func stop() {
    player?.stop()
    player?.currentTime = 0
    isPlaying = false
    currentTime = 0
    stopTimer()
  }

  func seek(to time: TimeInterval) {
    guard let player else { return }
    let clamped = min(max(time, 0), duration)
    player.currentTime = clamped
    currentTime = clamped
  }

  private func load(url: URL) -> Bool {
    stop()
    errorMessage = nil
    guard FileManager.default.fileExists(atPath: url.path) else {
      errorMessage = "找不到原始录音文件。"
      return false
    }
    do {
      let loaded = try AVAudioPlayer(contentsOf: url)
      loaded.prepareToPlay()
      player = loaded
      currentURL = url
      duration = loaded.duration
      currentTime = 0
      return true
    } catch {
      player = nil
      currentURL = nil
      duration = 0
      currentTime = 0
      errorMessage = "录音无法播放：\(error.localizedDescription)"
      return false
    }
  }

  private func play() {
    guard let player else { return }
    if currentTime >= duration - 0.01 {
      player.currentTime = 0
      currentTime = 0
    }
    guard player.play() else {
      errorMessage = "录音播放失败，请检查系统输出设备。"
      isPlaying = false
      return
    }
    errorMessage = nil
    isPlaying = true
    startTimer()
  }

  private func startTimer() {
    stopTimer()
    timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
      Task { @MainActor [weak self] in
        guard let self, self.isPlaying, let player = self.player else { return }
        self.currentTime = player.currentTime
        if !player.isPlaying {
          self.currentTime = self.duration
          self.isPlaying = false
          self.stopTimer()
        }
      }
    }
  }

  private func stopTimer() {
    timer?.invalidate()
    timer = nil
  }

  private func syncCurrentTime() {
    currentTime = player?.currentTime ?? 0
  }
}
