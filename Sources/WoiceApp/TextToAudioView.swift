import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 独立的文字转音频工作区。它不接收 RecordingRecord，避免录音完成后
/// 把朗读误当成录音转写链路的一部分。
struct TextToAudioView: View {
  @Environment(AppState.self) private var appState
  @State private var text = ""
  @State private var sourceLabel = "手动输入"
  @State private var speech = SpeechPlaybackService()
  @State private var importError: String?
  @State private var exportedURL: URL?

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      VStack(alignment: .leading, spacing: 5) {
        Text("文字转音频")
          .font(.title2.weight(.semibold))
        Text("输入文字或导入 .txt / .md 文件，点击朗读后使用本机系统语音。")
          .font(.callout)
          .foregroundStyle(.secondary)
      }

      HStack(spacing: 8) {
        Button {
          importTextFile()
        } label: {
          Label("导入文字文件", systemImage: "doc.badge.plus")
        }
        .buttonStyle(.bordered)
        Button("清空") {
          text = ""
          sourceLabel = "手动输入"
          speech.stop()
          importError = nil
          exportedURL = nil
          appState.presentActionFeedback(.success("已清空待朗读文字"))
        }
        .buttonStyle(.bordered)
        .disabled(text.isEmpty && speech.state == .idle)
        Spacer()
        Text(sourceLabel)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      TextEditor(text: $text)
        .font(.body)
        .scrollContentBackground(.hidden)
        .padding(10)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
          RoundedRectangle(cornerRadius: 10)
            .strokeBorder(.separator, lineWidth: 1)
        }
        .frame(minHeight: 280)
        .accessibilityLabel("待朗读文字")

      if let importError {
        Label(importError, systemImage: "exclamationmark.triangle.fill")
          .font(.caption)
          .foregroundStyle(.orange)
      }

      HStack(spacing: 10) {
        Label(speech.state.label, systemImage: speech.state.systemImage)
          .foregroundStyle(speech.state == .speaking ? Color.accentColor : Color.secondary)
        Spacer()
        Button {
          if speech.isActive {
            speech.togglePause()
          } else {
            startSpeech()
          }
        } label: {
          Label(
            speech.state == .paused ? "继续" : speech.state == .speaking ? "暂停" : "朗读",
            systemImage: speech.state == .speaking ? "pause.fill" : "speaker.wave.2.fill"
          )
        }
        .buttonStyle(.borderedProminent)
        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        Button("停止") {
          speech.stop()
          appState.presentActionFeedback(.success("已停止朗读"))
        }
        .buttonStyle(.bordered)
        .disabled(!speech.isActive && speech.state != .finished)
        Button("导出 WAV") {
          exportWAV()
        }
        .buttonStyle(.bordered)
        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }

      if let exportedURL {
        Label("已导出：\(exportedURL.path)", systemImage: "checkmark.circle.fill")
          .font(.caption)
          .foregroundStyle(.green)
          .textSelection(.enabled)
      }

      Text("本机系统语音只在你操作后播放或导出 WAV，不上传内容，也不会改动录音素材。")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .padding(24)
    .frame(minWidth: 680, minHeight: 460)
    .onDisappear { speech.stop() }
  }

  private func startSpeech() {
    do {
      try speech.speak(text: text, sourceLabel: sourceLabel)
      importError = nil
      appState.presentActionFeedback(.success("已开始朗读"))
    } catch {
      importError = error.localizedDescription
      appState.presentActionFeedback(.failure("朗读失败：\(error.localizedDescription)"))
    }
  }

  private func exportWAV() {
    let panel = NSSavePanel()
    panel.title = "导出文字转音频"
    panel.nameFieldStringValue = "woice-speech.wav"
    panel.allowedContentTypes = [.wav]
    guard panel.runModal() == .OK, let url = panel.url else { return }
    Task { @MainActor in
      do {
        try await speech.exportWAV(text: text, to: url)
        exportedURL = url
        importError = nil
        appState.presentActionFeedback(.success("WAV 已导出"))
      } catch {
        importError = error.localizedDescription
        appState.presentActionFeedback(.failure("导出 WAV 失败：\(error.localizedDescription)"))
      }
    }
  }

  private func importTextFile() {
    let panel = NSOpenPanel()
    panel.title = "导入文字文件"
    panel.message = "选择 UTF-8 编码的 .txt 或 .md 文件"
    panel.allowedContentTypes = [
      UTType.plainText,
      UTType(filenameExtension: "md") ?? .plainText,
    ]
    panel.allowsMultipleSelection = false
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      let imported = try String(contentsOf: url, encoding: .utf8)
      guard !imported.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw SpeechPlaybackError.emptyText
      }
      speech.stop()
      text = imported
      sourceLabel = url.lastPathComponent
      importError = nil
      appState.presentActionFeedback(.success("已导入文字文件"))
    } catch {
      importError = "无法导入文字文件：\(error.localizedDescription)"
      appState.presentActionFeedback(.failure("导入失败：\(error.localizedDescription)"))
    }
  }
}
