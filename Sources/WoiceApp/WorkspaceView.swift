import AppKit
import Observation
import SwiftUI
import WoiceCore

enum WorkspaceArea: String, CaseIterable, Hashable, Identifiable {
  case library
  case processing
  case textToAudio
  case settings

  var id: Self { self }

  var title: String {
    switch self {
    case .library: "素材库"
    case .processing: "处理任务"
    case .textToAudio: "文字转音频"
    case .settings: "设置"
    }
  }

  var subtitle: String {
    switch self {
    case .library: "录音、原文与复听"
    case .processing: "后台转写与失败重试"
    case .textToAudio: "文字或文件朗读"
    case .settings: "录音、模型与文件"
    }
  }

  var systemImage: String {
    switch self {
    case .library: "waveform"
    case .processing: "arrow.triangle.2.circlepath"
    case .textToAudio: "speaker.wave.2"
    case .settings: "gearshape"
    }
  }

  var keyboardShortcut: KeyEquivalent {
    switch self {
    case .library: "1"
    case .processing: "2"
    case .textToAudio: "3"
    case .settings: "4"
    }
  }

  var keyboardShortcutLabel: String {
    switch self {
    case .library: "⌘1"
    case .processing: "⌘2"
    case .textToAudio: "⌘3"
    case .settings: "⌘4"
    }
  }
}

enum WorkspaceRoute: Hashable {
  case library
  case recording(UUID)
  case processing
  case textToAudio
  case settings(SettingsSection)

  var area: WorkspaceArea {
    switch self {
    case .library, .recording: .library
    case .processing: .processing
    case .textToAudio: .textToAudio
    case .settings: .settings
    }
  }
}

private enum WorkspaceMaterialFilter: String, CaseIterable, Identifiable {
  case all
  case processing
  case partial
  case failed

  var id: Self { self }

  var label: String {
    switch self {
    case .all: "全部"
    case .processing: "处理中"
    case .partial: "部分就绪"
    case .failed: "失败"
    }
  }

  func matches(_ status: RecordingMaterialStatus) -> Bool {
    switch self {
    case .all: true
    case .processing: status == .processing || status == .waitingForModel
    case .partial: status == .partiallyReady
    case .failed: status == .failed
    }
  }
}

@MainActor
@Observable
final class WorkspaceRouter {
  var route: WorkspaceRoute = .library
  var shouldPresentMediaImport = false

  func show(_ area: WorkspaceArea) {
    switch area {
    case .library: route = .library
    case .processing: route = .processing
    case .textToAudio: route = .textToAudio
    case .settings: route = .settings(.recording)
    }
  }

  func show(settings section: SettingsSection) {
    if section == .agents && !StoreCapabilityProfile.current.allowsExternalAgentConnector {
      route = .settings(.recording)
    } else {
      route = .settings(section)
    }
  }

  func show(recordID: UUID) {
    route = .recording(recordID)
  }

  func requestMediaImport() {
    route = .library
    shouldPresentMediaImport = true
  }
}

struct WorkspaceView: View {
  @Environment(AppState.self) private var appState
  @Environment(WorkspaceRouter.self) private var router
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isShowingMediaImport = false
  @State private var importedRecordID: UUID?
  @State private var mediaImportDismissalDestination: MediaImportSheetDismissalDestination?

  private var areaSelection: Binding<WorkspaceArea> {
    Binding(
      get: { router.route.area },
      set: { router.show($0) }
    )
  }

  private var settingsSelection: Binding<SettingsSection> {
    Binding(
      get: {
        if case .settings(let section) = router.route { return section }
        return .recording
      },
      set: { router.show(settings: $0) }
    )
  }

  private var selectedRecordID: Binding<UUID?> {
    Binding(
      get: {
        if case .recording(let id) = router.route { return id }
        return nil
      },
      set: { id in
        if let id { router.show(recordID: id) } else { router.show(.library) }
      }
    )
  }

  var body: some View {
    ZStack(alignment: .topTrailing) {
      NavigationSplitView {
        WorkspaceSidebar(
          selection: areaSelection, selectedRecordID: selectedRecordID,
          settingsSelection: settingsSelection)
      } detail: {
        detailColumn
      }
      .navigationSplitViewStyle(.balanced)
      .navigationTitle("Woice 工作台")
      if let feedback = appState.actionFeedback {
        ActionFeedbackBanner(feedback: feedback)
          .padding(16)
          .transition(.move(edge: .top).combined(with: .opacity))
      }
      if let livePreviewPresentation {
        LiveTranscriptPreviewCard(presentation: livePreviewPresentation)
          .frame(maxWidth: 520)
          .frame(maxWidth: .infinity, alignment: .top)
          .padding(.top, 16)
          .padding(.horizontal, 24)
          .zIndex(4)
          .transition(.move(edge: .top).combined(with: .opacity))
      }
      if let request = appState.pendingExternalProcessing {
        WorkspaceExternalProcessingCard(request: request)
          .frame(maxWidth: 520)
          .padding(.top, appState.actionFeedback == nil ? 16 : 68)
          .padding(.trailing, 24)
          .zIndex(3)
          .transition(.move(edge: .top).combined(with: .opacity))
      }
      if appState.isShowingOnboarding {
        WorkspaceOnboardingCard(
          openRecordingSettings: {
            appState.isShowingOnboarding = false
            router.show(settings: .recording)
          },
          startRecording: {
            appState.isShowingOnboarding = false
            appState.startRecording()
          },
          dismiss: { appState.isShowingOnboarding = false }
        )
        .frame(maxWidth: 420)
        .padding(.top, 54)
        .padding(.trailing, 24)
        .zIndex(2)
        .transition(.move(edge: .top).combined(with: .opacity))
      }
    }
    .onChange(of: router.shouldPresentMediaImport) { _, requested in
      guard requested else { return }
      router.shouldPresentMediaImport = false
      importedRecordID = nil
      mediaImportDismissalDestination = nil
      isShowingMediaImport = true
    }
    .sheet(isPresented: $isShowingMediaImport, onDismiss: handleMediaImportDismissal) {
      MediaImportSheet(
        isPresented: $isShowingMediaImport,
        recordID: $importedRecordID,
        dismissalDestination: $mediaImportDismissalDestination
      )
      .environment(appState)
    }
    .task {
      if router.shouldPresentMediaImport {
        router.shouldPresentMediaImport = false
        mediaImportDismissalDestination = nil
        isShowingMediaImport = true
      }
    }
    .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: appState.actionFeedback?.id)
    .animation(
      reduceMotion ? nil : .easeOut(duration: 0.2),
      value: livePreviewPresentation
    )
    .frame(minWidth: 1_080, idealWidth: 1_180, minHeight: 700, idealHeight: 760)
  }

  private func handleMediaImportDismissal() {
    guard let destination = mediaImportDismissalDestination else { return }
    mediaImportDismissalDestination = nil
    destination.apply(to: router)
  }

  private var livePreviewPresentation: LiveTranscriptPreviewPresentation? {
    LiveTranscriptPreviewPresentation.make(
      isRecording: appState.isRecording || appState.liveTranscriptionState == .requestingPermission,
      isEnabled: appState.settings.enableLiveTranscription,
      capturesMicrophone: appState.settings.captureMicrophone,
      state: appState.liveTranscriptionState,
      transcript: appState.liveTranscript)
  }

  @ViewBuilder
  private var detailColumn: some View {
    switch router.route {
    case .library:
      WorkspaceLibraryEmptyState(
        hasRecordings: !appState.recordings.isEmpty,
        showModelInstall: !appState.hasInstalledLocalModelPack,
        startRecording: { appState.startRecording() },
        importMedia: {
          importedRecordID = nil
          mediaImportDismissalDestination = nil
          isShowingMediaImport = true
        })
    case .recording(let id):
      if let record = appState.recordings.first(where: { $0.id == id }) {
        RecordingDetailView(record: record)
      } else {
        WorkspaceEmptyState(
          title: "录音不存在", systemImage: "questionmark.folder", message: "这条录音可能已被删除。")
      }
    case .processing:
      WorkspaceProcessingOverview()
    case .textToAudio:
      TextToAudioView()
    case .settings:
      SettingsView(selection: settingsSelection)
    }
  }
}

private struct WorkspaceExternalProcessingCard: View {
  @Environment(AppState.self) private var appState
  let request: ExternalProcessingRequest

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Label(request.confirmationTitle, systemImage: "hand.raised.fill")
          .font(.headline)
        Spacer()
        Text("需确认")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.orange)
      }
      Text(request.confirmationMessage)
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      HStack(spacing: 8) {
        Button("确认并开始") {
          Task { await appState.confirmExternalProcessing() }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        Button("稍后处理") {
          appState.deferExternalProcessing()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
      }
    }
    .padding(14)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    .overlay {
      RoundedRectangle(cornerRadius: 14)
        .strokeBorder(Color.orange.opacity(0.35), lineWidth: 1)
    }
    .shadow(color: .black.opacity(0.14), radius: 12, y: 5)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("等待确认的外部处理任务：\(request.confirmationTitle)")
  }
}

private struct WorkspaceOnboardingCard: View {
  let openRecordingSettings: () -> Void
  let startRecording: () -> Void
  let dismiss: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Label("开始使用 Woice", systemImage: "hand.wave.fill")
          .font(.headline)
        Spacer()
        Button("稍后", action: dismiss)
          .buttonStyle(.woiceBorderless)
          .font(.caption)
      }
      Text("先录音，再把素材转成文字；所有原始录音都会先保存在这台 Mac 上。")
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      VStack(alignment: .leading, spacing: 8) {
        onboardingRow("mic.fill", "按下开始录音，录音期间会显示时长和输入状态")
        onboardingRow("text.badge.checkmark", "录音结束后按需转写，失败时仍保留原始素材")
        onboardingRow("slider.horizontal.3", "在设置中选择麦克风、电脑声音和转写方式")
      }
      HStack {
        Button("打开录音设置", action: openRecordingSettings)
          .buttonStyle(.bordered)
          .controlSize(.small)
        Spacer()
        Button("开始录音", action: startRecording)
          .buttonStyle(.borderedProminent)
          .controlSize(.small)
      }
    }
    .padding(16)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    .overlay {
      RoundedRectangle(cornerRadius: 14)
        .strokeBorder(Color.accentColor.opacity(0.2), lineWidth: 1)
    }
    .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Woice 首次使用引导")
  }

  private func onboardingRow(_ systemImage: String, _ text: String) -> some View {
    Label(text, systemImage: systemImage)
      .font(.caption)
      .foregroundStyle(.primary)
      .fixedSize(horizontal: false, vertical: true)
  }
}

private struct WorkspaceSidebar: View {
  @Environment(AppState.self) private var appState
  @Environment(WorkspaceRouter.self) private var router
  @Binding var selection: WorkspaceArea
  @Binding var selectedRecordID: UUID?
  @Binding var settingsSelection: SettingsSection
  @State private var query = ""
  @State private var materialFilter: WorkspaceMaterialFilter = .all
  @State private var pendingDeletion: RecordingRecord?

  var body: some View {
    VStack(spacing: 0) {
      VStack(alignment: .leading, spacing: 10) {
        Text("工作区")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
          .padding(.horizontal, 10)
          .padding(.top, 10)
        sidebarRow(.library)
        sidebarRow(.processing)
        sidebarRow(.textToAudio)
      }
      .padding(.horizontal, 8)
      .padding(.bottom, 8)
      Divider()
      if selection == .library {
        libraryContext
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      } else {
        ScrollView {
          contextContent
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      }
      Divider()
      sidebarRow(.settings)
        .padding(8)
    }
    .listStyle(.sidebar)
    .navigationTitle("Woice")
    .navigationSubtitle(WoiceAppVersion.navigationSubtitle)
    .frame(
      minWidth: WorkspaceSidebarLayout.minimumWidth,
      idealWidth: WorkspaceSidebarLayout.idealWidth,
      maxWidth: WorkspaceSidebarLayout.maximumWidth,
      maxHeight: .infinity,
      alignment: .top
    )
    .alert(
      "将素材移到废纸篓？",
      isPresented: Binding(
        get: { pendingDeletion != nil },
        set: { if !$0 { pendingDeletion = nil } }
      ),
      presenting: pendingDeletion
    ) { record in
      Button("取消", role: .cancel) { pendingDeletion = nil }
      Button("移到废纸篓", role: .destructive) {
        if appState.moveToTrash(record: record) {
          selectedRecordID = nil
          router.show(.library)
        }
        pendingDeletion = nil
      }
    } message: { record in
      Text("“\(record.title)”的原音频、原文和相关本机文件会一起移到 macOS 废纸篓，可从 Finder 恢复。")
    }
  }

  private func sidebarRow(_ area: WorkspaceArea) -> some View {
    Button {
      router.show(area)
    } label: {
      HStack(spacing: 10) {
        Image(systemName: area.systemImage)
          .frame(width: 20)
        Text(area.title)
          .font(.body.weight(selection == area ? .semibold : .regular))
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 7)
      .contentShape(RoundedRectangle(cornerRadius: 8))
      .background(
        selection == area ? Color.accentColor.opacity(0.16) : .clear,
        in: RoundedRectangle(cornerRadius: 8))
    }
    .buttonStyle(.plain)
    .keyboardShortcut(area.keyboardShortcut, modifiers: [.command])
    .foregroundStyle(selection == area ? .primary : .secondary)
    .accessibilityLabel(area.title)
    .accessibilityValue(selection == area ? "当前工作区" : "")
    .accessibilityHint("打开\(area.title)，快捷键 \(area.keyboardShortcutLabel)")
  }

  @ViewBuilder
  private var contextContent: some View {
    switch selection {
    case .library:
      libraryContext
    case .processing:
      processingContext
    case .textToAudio:
      Text("最近输入和导出记录")
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
    case .settings:
      settingsContext
    }
  }

  private var libraryContext: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        Text("素材库")
          .font(.headline)
        Spacer()
        Button {
          router.requestMediaImport()
        } label: {
          Image(systemName: "square.and.arrow.down")
        }
        .buttonStyle(.woiceBorderless)
        .accessibilityLabel("导入音视频")
        .help("导入音频或视频")
        Button(role: .destructive) {
          guard let selectedRecordID,
            let record = appState.recordings.first(where: { $0.id == selectedRecordID })
          else { return }
          pendingDeletion = record
        } label: {
          Image(systemName: "trash")
        }
        .buttonStyle(.woiceBorderless)
        .disabled(selectedRecordID == nil)
        .accessibilityLabel("删除所选素材")
        .help("将所选素材移到废纸篓")
      }
      .padding(.horizontal, 10)
      TextField("搜索素材", text: $query)
        .textFieldStyle(.roundedBorder)
        .padding(.horizontal, 10)
      Picker("状态", selection: $materialFilter) {
        ForEach(WorkspaceMaterialFilter.allCases) { filter in
          Text(filter.label).tag(filter)
        }
      }
      .pickerStyle(.menu)
      .padding(.horizontal, 10)
      let filteredRecords = appState.recordings.filter {
        materialFilter.matches($0.materialStatus) && recordingMatchesSearchQuery($0, query: query)
      }
      if filteredRecords.isEmpty {
        Text(query.isEmpty ? "还没有素材" : "没有匹配结果")
          .font(.caption)
          .foregroundStyle(.secondary)
          .padding(.horizontal, 10)
          .padding(.vertical, 8)
      } else {
        List(selection: $selectedRecordID) {
          ForEach(filteredRecords) { record in
            WorkspaceRecordingRow(record: record)
              .tag(record.id)
              .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button("移到废纸篓", systemImage: "trash", role: .destructive) {
                  pendingDeletion = record
                }
              }
              .contextMenu {
                Button("移到废纸篓", systemImage: "trash", role: .destructive) {
                  pendingDeletion = record
                }
              }
              .accessibilityLabel(
                "\(record.title)，\(record.sourceKind.label)，\(record.materialStatus.label)")
          }
        }
        .listStyle(.sidebar)
        .onDeleteCommand {
          guard let selectedRecordID,
            let record = appState.recordings.first(where: { $0.id == selectedRecordID })
          else { return }
          pendingDeletion = record
        }
      }
    }
    .padding(.horizontal, 8)
    .padding(.top, 10)
  }

  private var processingContext: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("当前任务")
        .font(.headline)
        .padding(.horizontal, 10)
      let records = appState.recordings.filter {
        !$0.processingTasks.isEmpty || $0.processingError != nil
      }
      if records.isEmpty
        && (!StoreCapabilityProfile.current.allowsExternalAgentConnector
          || appState.agentDispatchJobs.isEmpty)
      {
        Text("没有待处理任务")
          .font(.caption)
          .foregroundStyle(.secondary)
          .padding(.horizontal, 10)
      } else {
        ForEach(records) { record in
          Button {
            selectedRecordID = record.id
            router.show(recordID: record.id)
          } label: {
            VStack(alignment: .leading, spacing: 3) {
              Text(record.title).lineLimit(2)
              Label(
                ProcessingTaskProjection.activeTask(in: record.processingTasks)?.status.label
                  ?? record.materialStatus.label,
                systemImage: ProcessingTaskProjection.activeTask(in: record.processingTasks)?.status
                  .systemImage ?? record.materialStatus.systemImage
              )
              .font(.caption2)
              .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
          }
          .buttonStyle(.plain)
          .accessibilityLabel(
            "\(record.title)，\(ProcessingTaskProjection.activeTask(in: record.processingTasks)?.status.label ?? record.materialStatus.label)"
          )
          .accessibilityHint("打开录音详情查看处理任务")
        }
      }
    }
  }

  private var settingsContext: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("设置")
        .font(.headline)
        .padding(.horizontal, 10)
      ForEach(SettingsSection.availableCases) { section in
        Button {
          settingsSelection = section
        } label: {
          Label(section.title, systemImage: section.systemImage)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
              settingsSelection == section ? Color.accentColor.opacity(0.12) : .clear,
              in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(section.title)
        .accessibilityHint("打开设置：\(section.title)")
      }
    }
  }
}

private struct WorkspaceRecordingList: View {
  @Environment(AppState.self) private var appState
  @Environment(WorkspaceRouter.self) private var router
  @Binding var selection: UUID?
  @State private var query = ""

  private var filteredRecords: [RecordingRecord] {
    appState.recordings.filter { recordingMatchesSearchQuery($0, query: query) }
  }

  var body: some View {
    List(selection: $selection) {
      if filteredRecords.isEmpty {
        ContentUnavailableView(
          query.isEmpty ? "还没有录音" : "没有匹配结果",
          systemImage: query.isEmpty ? "waveform" : "magnifyingglass",
          description: Text(query.isEmpty ? "从菜单栏或工作台点击开始录音。" : "换一个关键词搜索原文。")
        )
      } else {
        ForEach(filteredRecords, id: \.id) { record in
          WorkspaceRecordingRow(record: record)
            .tag(record.id)
        }
      }
    }
    .navigationTitle("素材库")
    .searchable(text: $query, prompt: "搜索原文")
    .toolbar {
      ToolbarItem(placement: .automatic) {
        Button {
          router.show(.library)
          appState.presentActionFeedback(.success("已清除当前选择"))
        } label: {
          Label("清除选择", systemImage: "rectangle.on.rectangle")
        }
        .buttonStyle(.woiceToolbar)
        .help("清除当前录音选择")
        .disabled(selection == nil)
      }
    }
  }
}

func recordingMatchesSearchQuery(_ record: RecordingRecord, query: String) -> Bool {
  let terms =
    query
    .split(whereSeparator: { $0.isWhitespace })
    .map(String.init)
    .filter { !$0.isEmpty }
  guard !terms.isEmpty else { return true }

  var searchableValues = [
    record.title,
    TranscriptTextNormalizer.normalize(record.transcript ?? ""),
    TranscriptTextNormalizer.normalize(record.generatedMarkdown ?? ""),
    record.shortDate,
    record.materialStatus.label,
    record.materialStatus.rawValue,
    record.sourceKind.label,
    record.sourceKind.rawValue,
  ]
  if record.systemAudioFileName != nil {
    searchableValues += [AudioTrackKind.systemAudio.label, AudioTrackKind.systemAudio.rawValue]
  }
  if record.meetingMixFileName != nil {
    searchableValues += [AudioTrackKind.meetingMix.label, AudioTrackKind.meetingMix.rawValue]
  }
  let searchable = searchableValues.joined(separator: " ")
  return terms.allSatisfy { searchable.localizedCaseInsensitiveContains($0) }
}

private struct WorkspaceRecordingRow: View {
  @Environment(AppState.self) private var appState
  let record: RecordingRecord

  private var audioSaved: Bool {
    appState.audioFileExists(for: record)
  }

  private var transcriptStateImage: String? {
    if record.transcript?.isEmpty == false { return "text.badge.checkmark" }
    if record.processingError != nil { return "exclamationmark.triangle" }
    return nil
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Text(record.title).lineLimit(2)
        Spacer(minLength: 4)
        Image(systemName: transcriptStateImage ?? record.materialStatus.systemImage)
          .foregroundStyle(materialStatusColor)
          .accessibilityLabel(record.materialStatus.label)
      }
      HStack(spacing: 5) {
        Label(record.sourceKind.label, systemImage: record.sourceKind.systemImage)
          .lineLimit(1)
        Text("·")
        Text(formatDuration(record.duration)).monospacedDigit()
        Text("·")
        Text(record.shortDate).lineLimit(1)
        Spacer(minLength: 0)
      }
      .font(.caption2)
      .foregroundStyle(audioSaved ? Color.secondary : Color.red)
      Text(record.materialStatus.label)
        .font(.caption2)
        .foregroundStyle(materialStatusColor)
        .lineLimit(1)
    }
    .padding(.vertical, 5)
  }

  private var materialStatusColor: Color {
    switch record.materialStatus {
    case .ready: .green
    case .failed, .partiallyReady: .orange
    case .processing, .waitingForModel: .accentColor
    case .saved: .secondary
    }
  }
}

private struct WorkspaceLibraryEmptyState: View {
  let hasRecordings: Bool
  let showModelInstall: Bool
  let startRecording: () -> Void
  let importMedia: () -> Void

  var body: some View {
    VStack(spacing: 14) {
      Image(systemName: hasRecordings ? "waveform" : "rectangle.and.waveform")
        .font(.system(size: 34))
        .foregroundStyle(.tint)
      Text(hasRecordings ? "选择一条录音" : "还没有素材")
        .font(.title3.weight(.semibold))
      Text(
        hasRecordings
          ? "从左侧选择素材，查看原文、复听和处理结果。"
          : "开始录音或导入音视频，原件会先保存在本机。"
      )
      .foregroundStyle(.secondary)
      HStack(spacing: 10) {
        Button("开始录音", systemImage: "mic.fill", action: startRecording)
          .buttonStyle(.borderedProminent)
        Button("导入音视频…", systemImage: "square.and.arrow.down", action: importMedia)
          .buttonStyle(.bordered)
      }
      if showModelInstall {
        ModelInstallCard(entryPoint: .workspace)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(28)
  }
}

private struct WorkspaceProcessingList: View {
  @Environment(AppState.self) private var appState
  @Environment(WorkspaceRouter.self) private var router

  private var recordsWithTasks: [RecordingRecord] {
    appState.recordings.filter { !$0.processingTasks.isEmpty || $0.processingError != nil }
  }

  var body: some View {
    List {
      if recordsWithTasks.isEmpty
        && (!StoreCapabilityProfile.current.allowsExternalAgentConnector
          || appState.agentDispatchJobs.isEmpty)
      {
        ContentUnavailableView(
          "暂无处理任务", systemImage: "checkmark.circle", description: Text("录音后的转写和笔记任务会显示在这里。"))
      } else {
        if !recordsWithTasks.isEmpty {
          Section("录音处理") {
            ForEach(recordsWithTasks) { record in
              Button {
                router.show(recordID: record.id)
              } label: {
                VStack(alignment: .leading, spacing: 6) {
                  Text(record.title).lineLimit(2)
                  if let task = ProcessingTaskProjection.activeTask(in: record.processingTasks) {
                    Label(task.status.label, systemImage: task.status.systemImage)
                      .font(.caption)
                      .foregroundStyle(task.status == .failed ? .orange : .secondary)
                  } else {
                    Label("需要处理", systemImage: "clock")
                      .font(.caption)
                      .foregroundStyle(.secondary)
                  }
                  if let error = record.processingError, !error.isEmpty {
                    Text(error)
                      .font(.caption2)
                      .foregroundStyle(.orange)
                      .lineLimit(2)
                  }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 5)
              }
              .buttonStyle(.plain)
              .accessibilityLabel(
                "\(record.title)，\(ProcessingTaskProjection.activeTask(in: record.processingTasks)?.status.label ?? record.materialStatus.label)"
              )
              .accessibilityHint("打开录音详情查看处理任务")
            }
          }
        }
        #if !WOICE_APP_STORE
          if StoreCapabilityProfile.current.allowsExternalAgentConnector,
            !appState.agentDispatchJobs.isEmpty
          {
            Section("Agent 任务（CLI Beta）") {
              ForEach(appState.agentDispatchJobs.sorted { $0.updatedAt > $1.updatedAt }) { job in
                VStack(alignment: .leading, spacing: 5) {
                  HStack(spacing: 8) {
                    Image(systemName: agentStatusSystemImage(job.status))
                      .foregroundStyle(agentStatusColor(job.status))
                    Text(AgentCLIAdapterCatalog.userFacingDisplayName(for: job.connectorID))
                      .font(.callout.weight(.medium))
                    Spacer()
                    Text(job.updatedAt, style: .time)
                      .font(.caption2.monospacedDigit())
                      .foregroundStyle(.tertiary)
                  }
                  Text(agentStatusLabel(job.status))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                  if let error = job.lastError, !error.isEmpty {
                    Text(error)
                      .font(.caption2)
                      .foregroundStyle(.orange)
                      .lineLimit(2)
                  }
                  if let artifact = job.resultArtifact {
                    HStack(spacing: 8) {
                      Label("结果已保存", systemImage: "arrow.down.doc")
                        .font(.caption2)
                        .foregroundStyle(.green)
                      Spacer()
                      Button("查看结果") {
                        router.show(recordID: artifact.parentRecordingID)
                      }
                      .buttonStyle(.bordered)
                      .controlSize(.small)
                    }
                  }
                }
                .padding(.vertical, 5)
                .accessibilityElement(children: .combine)
              }
            }
          }
        #endif
      }
    }
    .navigationTitle("处理任务")
  }

  private func agentStatusLabel(_ status: AgentDispatchStatus) -> String {
    switch status {
    case .draft: "草稿"
    case .awaitingAuthorization: "等待授权"
    case .queued: "排队中"
    case .launching: "正在启动"
    case .running: "处理中"
    case .collecting: "正在收集结果"
    case .awaitingAgentApproval: "等待 Agent 审批"
    case .completed: "已完成"
    case .failed: "处理失败"
    case .cancelled: "已取消"
    case .interrupted: "已中断，未自动重放"
    }
  }

  private func agentStatusSystemImage(_ status: AgentDispatchStatus) -> String {
    switch status {
    case .completed: "checkmark.circle.fill"
    case .failed, .interrupted: "exclamationmark.triangle.fill"
    case .cancelled: "xmark.circle"
    case .draft: "doc"
    default: "arrow.triangle.2.circlepath"
    }
  }

  private func agentStatusColor(_ status: AgentDispatchStatus) -> Color {
    switch status {
    case .completed: .green
    case .failed, .interrupted: .orange
    case .cancelled: .secondary
    default: .accentColor
    }
  }
}

private struct WorkspaceSettingsList: View {
  @Binding var selection: SettingsSection

  var body: some View {
    List(SettingsSection.availableCases, selection: $selection) { section in
      Label {
        VStack(alignment: .leading, spacing: 2) {
          Text(section.title)
          Text(section.subtitle)
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
      } icon: {
        Image(systemName: section.systemImage)
      }
      .tag(section)
      .padding(.vertical, 5)
    }
    .listStyle(.sidebar)
    .navigationTitle("设置")
  }
}

private struct WorkspaceToolSummary: View {
  let area: WorkspaceArea

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Label(area.title, systemImage: area.systemImage)
        .font(.headline)
      Text(area.subtitle)
        .font(.caption)
        .foregroundStyle(.secondary)
      Divider()
      Text("在右侧完成\(area.title)操作。")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .padding(20)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .navigationTitle(area.title)
  }
}

private struct WorkspaceProcessingOverview: View {
  @Environment(AppState.self) private var appState

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Label("处理任务", systemImage: "arrow.triangle.2.circlepath")
        .font(.title2.weight(.semibold))
      Text(appState.processingState.label)
        .font(.headline)
      if appState.isBusy {
        HStack(spacing: 8) {
          ProgressView().controlSize(.small)
          Text("处理会在本机继续；录音素材已保存。")
        }
        .foregroundStyle(.secondary)
      } else {
        Text("从左侧选择一条任务，查看模型、授权和失败原因。Agent 任务只在用户明确派发后运行。")
          .foregroundStyle(.secondary)
      }
      if StoreCapabilityProfile.current.allowsExternalAgentConnector,
        !appState.agentDispatchJobs.isEmpty
      {
        Label(
          "Agent 任务：\(appState.agentDispatchJobs.count) 条已记录",
          systemImage: "arrow.triangle.branch"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
      let resumableRecords = appState.recordings.filter { record in
        ProcessingTaskProjection.resumableTask(in: record.processingTasks) != nil
      }
      if !resumableRecords.isEmpty {
        VStack(alignment: .leading, spacing: 8) {
          Text("可继续的任务")
            .font(.headline)
          ForEach(resumableRecords) { record in
            let task = ProcessingTaskProjection.resumableTask(in: record.processingTasks)
            HStack(spacing: 10) {
              Label(
                record.title,
                systemImage: task?.status.systemImage ?? record.materialStatus.systemImage
              )
              .lineLimit(2)
              Spacer()
              Button("继续处理") {
                appState.resumeProcessing(for: record)
              }
              .buttonStyle(.bordered)
              .controlSize(.small)
            }
            .padding(10)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
              "\(record.title)，\(task?.status.label ?? record.materialStatus.label)，可继续处理"
            )
          }
        }
      }
      Spacer()
    }
    .padding(28)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

private struct WorkspaceEmptyState: View {
  let title: String
  let systemImage: String
  let message: String

  var body: some View {
    ContentUnavailableView(title, systemImage: systemImage, description: Text(message))
      .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
