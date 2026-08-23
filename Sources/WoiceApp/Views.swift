import AppKit
import SwiftUI
import WoiceCore

struct WoiceAppShell: View {
  @Environment(AppState.self) private var appState

  var body: some View {
    MenuBarPopover()
      .environment(appState)
      .frame(width: 336)
  }
}

struct HistoryView: View {
  @Environment(AppState.self) private var appState
  @State private var query = ""
  @State private var selectedID: UUID?

  private var filtered: [RecordingRecord] {
    appState.recordings.filter { recordingMatchesSearchQuery($0, query: query) }
  }

  var body: some View {
    NavigationSplitView {
      List(selection: $selectedID) {
        ForEach(filtered) { record in
          VStack(alignment: .leading, spacing: 5) {
            Text(record.title).lineLimit(2)
            HStack {
              Label(
                appState.audioFileExists(for: record) ? "已保存" : "缺少音频",
                systemImage: appState.audioFileExists(for: record)
                  ? "checkmark.circle" : "exclamationmark.triangle")
              if record.systemAudioFileName != nil {
                Label(
                  appState.systemAudioFileExists(for: record) ? "双轨" : "系统声音缺失",
                  systemImage: appState.systemAudioFileExists(for: record)
                    ? "speaker.wave.2" : "speaker.slash"
                )
              }
              Spacer()
              Text(formatDuration(record.duration)).monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(
              appState.audioFileExists(for: record) ? Color.secondary : Color.red)
            Text(record.shortDate).font(.caption2).foregroundStyle(.tertiary)
          }
          .padding(.vertical, 4)
          .tag(record.id)
        }
      }
      .navigationTitle("历史记录")
      .searchable(text: $query, prompt: "搜索原文")
      .frame(minWidth: 270)
    } detail: {
      if let selectedID, let record = appState.recordings.first(where: { $0.id == selectedID }) {
        RecordingDetailView(record: record)
      } else {
        ContentUnavailableView(
          "选择一条录音", systemImage: "waveform", description: Text("原文、AI 笔记和导出操作会显示在这里。"))
      }
    }
    .frame(minWidth: 800, minHeight: 560)
  }
}

func formatDuration(_ duration: TimeInterval) -> String {
  let totalSeconds = max(0, Int(duration.rounded()))
  return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
}
