import SwiftUI
import WoiceCore

struct MediaImportSheet: View {
  @Environment(AppState.self) private var appState
  @Environment(WorkspaceRouter.self) private var router
  @Environment(\.dismiss) private var dismiss

  @Binding var recordID: UUID?
  @State private var isShowingFileImporter = false

  private var record: RecordingRecord? {
    guard let recordID else { return nil }
    return appState.recordings.first { $0.id == recordID }
  }

  var body: some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: 18) {
        if let record {
          importedContent(record)
        } else {
          ContentUnavailableView(
            "导入音视频",
            systemImage: "square.and.arrow.down",
            description: Text("原始文件会保存到 Woice 本机素材目录，并生成可重试的转写任务。不会自动外发。"))
          Button {
            isShowingFileImporter = true
          } label: {
            Label("选择文件…", systemImage: "folder")
          }
          .buttonStyle(.borderedProminent)
          .accessibilityLabel("选择文件")
          .help("选择文件")
          .frame(maxWidth: .infinity)
        }
        Spacer(minLength: 0)
      }
      .padding(28)
      .frame(minWidth: 560, minHeight: 360)
      .navigationTitle("导入音视频")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("取消") { dismiss() }
        }
      }
    }
    .onChange(of: record?.materialStatus) { _, status in
      guard status == .ready, let recordID else { return }
      router.show(recordID: recordID)
      dismiss()
    }
    .fileImporter(
      isPresented: $isShowingFileImporter,
      allowedContentTypes: MediaImportService.allowedContentTypes,
      allowsMultipleSelection: false
    ) { result in
      guard case .success(let urls) = result, let url = urls.first else {
        if case .failure(let error) = result {
          appState.presentActionFeedback(.failure("选择文件失败：\(error.localizedDescription)"))
        }
        return
      }
      Task { @MainActor in
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        recordID = await appState.importMedia(from: url)
      }
    }
  }

  @ViewBuilder
  private func importedContent(_ record: RecordingRecord) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      Label(record.title, systemImage: record.sourceKind.systemImage)
        .font(.title3.weight(.semibold))
      Text("\(record.sourceKind.label) · \(formatDuration(record.duration)) · 原件已保存")
        .font(.callout)
        .foregroundStyle(.secondary)
      if let sha256 = record.originalMediaSHA256 {
        Text("原件 SHA-256：\(sha256.prefix(16))…")
          .font(.caption.monospaced())
          .foregroundStyle(.tertiary)
          .textSelection(.enabled)
      }
      HStack(spacing: 10) {
        Image(systemName: statusImage(for: record))
          .foregroundStyle(statusColor(for: record))
        VStack(alignment: .leading, spacing: 3) {
          Text(statusLabel(for: record))
            .font(.headline)
          Text(statusDescription(record))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      .padding(14)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))

      HStack(spacing: 10) {
        Button {
          if appState.canTranscribe {
            appState.requestTranscription(for: record)
          } else {
            router.show(settings: .services)
            dismiss()
          }
        } label: {
          Label(transcribeButtonTitle(record), systemImage: "text.badge.checkmark")
        }
        .buttonStyle(.borderedProminent)
        .disabled(
          ProcessingTaskProjection.activeTranscriptionTask(in: record.processingTasks)?.status
            == .running
            || ProcessingTaskProjection.activeTranscriptionTask(in: record.processingTasks)?.status
              == .awaitingAuthorization
        )
        .accessibilityLabel(transcribeButtonTitle(record))
        .help(transcribeButtonTitle(record))
        Button("稍后处理") {
          router.show(recordID: record.id)
          dismiss()
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("稍后处理")
        .help("稍后处理")
        Button("打开原件") {
          _ = appState.openOriginalMedia(for: record)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("打开原件")
        .help("打开原件")
      }
    }
  }

  private func transcribeButtonTitle(_ record: RecordingRecord) -> String {
    if record.transcript?.isEmpty == false { return "打开素材" }
    if ProcessingTaskProjection.activeTranscriptionTask(in: record.processingTasks)?.status
      == .awaitingAuthorization
    {
      return "等待确认"
    }
    if ProcessingTaskProjection.activeTranscriptionTask(in: record.processingTasks)?.status
      == .running
    {
      return "正在转写"
    }
    return appState.canTranscribe ? "转文字" : "选择模型"
  }

  private func statusDescription(_ record: RecordingRecord) -> String {
    switch ProcessingTaskProjection.activeTranscriptionTask(in: record.processingTasks)?.status {
    case .awaitingAuthorization:
      return "等待你确认外发；原始文件已安全保存在本机。"
    case .running:
      return "正在转写；可以关闭此窗口，任务会继续。"
    case .queued:
      return "文件已保存并排队；点击“转文字”开始处理。"
    case .waitingForModel:
      return "文件已安全保存；请先选择语言转文字模型。"
    case .completed, .failed, .interrupted, .cancelled, nil:
      break
    }
    if let error = record.processingError, !error.isEmpty {
      return "文件已安全保存：\(error)"
    }
    if record.materialStatus == .ready { return "转写完成，正在打开新素材详情。" }
    return "确认后才开始本机或外部转写。"
  }

  private func statusLabel(for record: RecordingRecord) -> String {
    switch ProcessingTaskProjection.activeTranscriptionTask(in: record.processingTasks)?.status {
    case .queued: "待处理"
    case .waitingForModel: "等待选择模型"
    case .awaitingAuthorization: "等待确认"
    case .running: "正在转写"
    default: record.materialStatus.label
    }
  }

  private func statusImage(for record: RecordingRecord) -> String {
    switch ProcessingTaskProjection.activeTranscriptionTask(in: record.processingTasks)?.status {
    case .queued: "clock"
    case .waitingForModel: "square.stack.3d.up"
    case .awaitingAuthorization: "hand.raised.fill"
    case .running: "arrow.triangle.2.circlepath"
    default: record.materialStatus.systemImage
    }
  }

  private func statusColor(for record: RecordingRecord) -> Color {
    switch ProcessingTaskProjection.activeTranscriptionTask(in: record.processingTasks)?.status {
    case .queued: .secondary
    case .waitingForModel: .accentColor
    case .awaitingAuthorization: .orange
    case .running: .accentColor
    default: statusColor(record.materialStatus)
    }
  }

  private func statusColor(_ status: RecordingMaterialStatus) -> Color {
    switch status {
    case .ready: .green
    case .failed, .partiallyReady: .orange
    case .processing, .waitingForModel: .accentColor
    case .saved: .secondary
    }
  }
}
