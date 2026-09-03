import SwiftUI
import WoiceCore

enum MediaImportSheetCloseAction: Equatable {
  case cancelImport
  case closeWindow
  case background
  case deferProcessing

  static func resolve(
    hasRecord: Bool,
    taskStatus: ProcessingTaskStatus?
  ) -> Self {
    guard hasRecord else { return .cancelImport }
    switch taskStatus {
    case .running, .awaitingAuthorization:
      return .background
    case .queued:
      return .deferProcessing
    default:
      return .closeWindow
    }
  }

  var title: String {
    switch self {
    case .cancelImport: "取消导入"
    case .closeWindow: "关闭窗口"
    case .background: "关闭并后台继续"
    case .deferProcessing: "关闭，稍后处理"
    }
  }

  var hint: String {
    switch self {
    case .cancelImport: "关闭导入窗口"
    case .closeWindow: "关闭导入窗口，已保存的原件不会删除"
    case .background: "关闭窗口，转写任务会继续，不会取消任务"
    case .deferProcessing: "关闭窗口，任务保留在处理列表中"
    }
  }
}

enum MediaImportSheetDismissalDestination: Equatable {
  case processing
  case recording(UUID)
  case settings(SettingsSection)

  @MainActor
  func apply(to router: WorkspaceRouter) {
    switch self {
    case .processing:
      router.show(.processing)
    case .recording(let id):
      router.show(recordID: id)
    case .settings(let section):
      router.show(settings: section)
    }
  }
}

struct MediaImportSheet: View {
  @Environment(AppState.self) private var appState
  @Environment(\.dismiss) private var dismiss

  @Binding var isPresented: Bool
  @Binding var recordID: UUID?
  @Binding var dismissalDestination: MediaImportSheetDismissalDestination?
  @State private var isShowingFileImporter = false
  @State private var isDropTarget = false
  @State private var isImportingFile = false

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
          importDropZone
        }
        Spacer(minLength: 0)
      }
      .padding(28)
      .frame(minWidth: 520, minHeight: record == nil ? 300 : 360)
      .navigationTitle("导入音视频")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(closeButtonTitle) { closeSheet() }
            .accessibilityLabel(closeButtonTitle)
            .accessibilityHint(closeButtonHint)
        }
      }
    }
    .onChange(of: record?.materialStatus) { _, status in
      guard status == .ready, let recordID else { return }
      closeSheet(after: .recording(recordID))
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
      importMedia(from: url)
    }
  }

  private var importDropZone: some View {
    VStack(spacing: 14) {
      Image(systemName: isDropTarget ? "arrow.down.doc.fill" : "square.and.arrow.down")
        .font(.system(size: 34, weight: .medium))
        .foregroundStyle(isDropTarget ? Color.accentColor : Color.secondary)
      VStack(spacing: 5) {
        Text(isDropTarget ? "放开即可导入" : "选择或拖入音视频")
          .font(.title3.weight(.semibold))
        Text("原件会保存在 Woice 本机素材目录，不会自动外发。")
          .font(.callout)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }
      if isImportingFile {
        ProgressView("正在导入…")
          .controlSize(.small)
      } else {
        Button {
          isShowingFileImporter = true
        } label: {
          Label("选择文件…", systemImage: "folder")
        }
        .buttonStyle(.borderedProminent)
        .accessibilityLabel("选择文件")
        .help("选择文件")
      }
      Text("WAV、MP3、M4A、AAC、AIFF、CAF、FLAC、MP4、MOV、M4V")
        .font(.caption)
        .foregroundStyle(.tertiary)
        .multilineTextAlignment(.center)
    }
    .padding(.horizontal, 28)
    .padding(.vertical, 24)
    .frame(maxWidth: .infinity, minHeight: 220)
    .background(
      isDropTarget ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.045),
      in: RoundedRectangle(cornerRadius: 14)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 14)
        .strokeBorder(
          isDropTarget ? Color.accentColor : Color.secondary.opacity(0.28),
          style: StrokeStyle(lineWidth: isDropTarget ? 2 : 1, dash: [6, 4]))
    }
    .contentShape(RoundedRectangle(cornerRadius: 14))
    .dropDestination(for: URL.self) { urls, _ in
      guard let url = urls.first, urls.count == 1, !isImportingFile else { return false }
      importMedia(from: url)
      return true
    } isTargeted: { isTargeted in
      isDropTarget = isTargeted
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("导入音视频")
    .accessibilityHint("可选择文件，也可拖入一个支持的音频或视频文件")
  }

  private func importMedia(from url: URL) {
    guard !isImportingFile else { return }
    isImportingFile = true
    Task { @MainActor in
      defer { isImportingFile = false }
      let accessed = url.startAccessingSecurityScopedResource()
      defer { if accessed { url.stopAccessingSecurityScopedResource() } }
      recordID = await appState.importMedia(from: url)
    }
  }

  private var activeTaskStatus: ProcessingTaskStatus? {
    guard let record else { return nil }
    return ProcessingTaskProjection.activeTranscriptionTask(in: record.processingTasks)?.status
  }

  private var closeButtonTitle: String {
    let action = MediaImportSheetCloseAction.resolve(
      hasRecord: record != nil, taskStatus: activeTaskStatus)
    return action.title
  }

  private var closeButtonHint: String {
    let action = MediaImportSheetCloseAction.resolve(
      hasRecord: record != nil, taskStatus: activeTaskStatus)
    return action.hint
  }

  private var backgroundCloseTitle: String? {
    let action = MediaImportSheetCloseAction.resolve(
      hasRecord: record != nil, taskStatus: activeTaskStatus)
    switch action {
    case .background, .deferProcessing:
      return action.title
    default:
      return nil
    }
  }

  private func closeSheet(after destination: MediaImportSheetDismissalDestination? = nil) {
    dismissalDestination = destination
    isPresented = false
    dismiss()
  }

  @ViewBuilder
  private func importedContent(_ record: RecordingRecord) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      Label(record.displayTitle, systemImage: record.sourceKind.systemImage)
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
          startTranscription(for: record)
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
        Group {
          if let backgroundCloseTitle {
            Button {
              closeSheet()
            } label: {
              Label(backgroundCloseTitle, systemImage: "xmark.circle")
            }
            .buttonStyle(.bordered)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel(backgroundCloseTitle)
            .accessibilityHint("关闭窗口，任务会继续，不会取消")
            .help("关闭浮窗，转写任务会继续")
          } else {
            Button("稍后处理") {
              closeSheet(after: .recording(record.id))
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("稍后处理")
            .help("稍后处理")
          }
        }
        Button("打开原件") {
          _ = appState.openOriginalMedia(for: record)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("打开原件")
        .help("打开原件")
      }
      if !appState.hasInstalledLocalModelPack {
        RecommendedModelInstallCard(entryPoint: .material, recordingID: record.id)
      }
    }
  }

  private func startTranscription(for record: RecordingRecord) {
    let canTranscribe = appState.canTranscribe
    if canTranscribe {
      appState.requestTranscription(for: record)
      closeSheet(after: .processing)
    } else {
      closeSheet(after: .settings(.services))
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
      return "正在后台转写；关闭此窗口不会中断任务。"
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
