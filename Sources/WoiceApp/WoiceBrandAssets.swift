import AppKit
import SwiftUI

enum WoiceBrandAssets {
  static let iconResourceName = "woice-app-icon-64"
  static let applicationIconResourceName = "woice-app-icon-1024"

  @MainActor
  static func iconImage(named resourceName: String = iconResourceName) -> NSImage? {
    let fileName = "\(resourceName).png"
    let candidates = [
      Bundle.main.url(forResource: resourceName, withExtension: "png"),
      Bundle.main.resourceURL?.appendingPathComponent(fileName),
      Bundle.main.bundleURL.appendingPathComponent("Woice_WoiceApp.bundle").appendingPathComponent(
        fileName
      ),
    ]
    for candidate in candidates.compactMap({ $0 }) {
      if let image = NSImage(contentsOf: candidate) { return image }
    }
    return nil
  }

}

struct WoiceBrandMark: View {
  let size: CGFloat

  var body: some View {
    brandImage
      .frame(width: size, height: size)
      .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
      .accessibilityLabel("Woice")
  }

  @ViewBuilder
  private var brandImage: some View {
    if let image = WoiceBrandAssets.iconImage() {
      Image(nsImage: image)
        .resizable()
        .interpolation(.high)
        .scaledToFit()
    } else {
      Image(systemName: "waveform.circle.fill")
        .resizable()
        .scaledToFit()
    }
  }
}

/// A compact, monochrome mark for the constrained macOS status-bar space.
/// The full-color brand asset remains reserved for the Popover and App icon.
struct WoiceStatusMark: View {
  let isRecording: Bool

  var body: some View {
    Image(systemName: isRecording ? "record.circle.fill" : "waveform.circle.fill")
      .font(.system(size: 15, weight: .medium))
      .frame(width: 18, height: 18)
      .symbolRenderingMode(.monochrome)
      .foregroundStyle(isRecording ? Color.red : Color.primary)
      .accessibilityLabel(isRecording ? "正在录音" : "Woice")
      .accessibilityHint(isRecording ? "打开录音控制器查看状态" : "点击打开录音控制器")
      .help(isRecording ? "正在录音 · 打开控制器" : "Woice · 点击打开录音控制器")
  }
}
