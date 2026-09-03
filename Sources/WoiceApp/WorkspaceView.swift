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
  var pendingMediaImportRecordID: UUID?
  var isSidebarVisible = true

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
    MaterialPerformanceInstrumentation.event(.listSelection)
    route = .recording(recordID)
  }

  func requestMediaImport(recordID: UUID? = nil) {
    route = .library
    pendingMediaImportRecordID = recordID
    shouldPresentMediaImport = true
  }

  func toggleSidebar() {
    isSidebarVisible.toggle()
  }
}

struct WorkspaceView: View {
  @Environment(AppState.self) private var appState
  @Environment(WorkspaceRouter.self) private var router
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isShowingMediaImport = false
  @State private var importedRecordID: UUID?
  @State private var mediaImportDismissalDestination: MediaImportSheetDismissalDestination?
  @State private var loadedDetailRecord: RecordingRecord?

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
    GeometryReader { geometry in
      ZStack(alignment: .topTrailing) {
        HStack(spacing: 0) {
          if router.isSidebarVisible {
            WorkspaceSidebar(
              selection: areaSelection, selectedRecordID: selectedRecordID,
              settingsSelection: settingsSelection
            )
            .frame(width: WorkspaceSidebarLayout.idealWidth)
            Divider()
          }
          detailColumn
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Woice 工作台")
        .toolbar {
          ToolbarItem(placement: .navigation) {
            Button {
              router.toggleSidebar()
            } label: {
              Label(
                router.isSidebarVisible ? "隐藏侧边栏" : "显示侧边栏",
                systemImage: "sidebar.left")
            }
            .help(router.isSidebarVisible ? "隐藏侧边栏" : "显示侧边栏")
            .accessibilityLabel(router.isSidebarVisible ? "隐藏侧边栏" : "显示侧边栏")
          }
        }
        if !router.isSidebarVisible {
          VStack {
            HStack {
              Button {
                router.toggleSidebar()
              } label: {
                Label("显示侧边栏", systemImage: "sidebar.left")
              }
              .buttonStyle(.bordered)
              .help("显示侧边栏")
              .accessibilityLabel("显示侧边栏")
              Spacer()
            }
            Spacer()
          }
          .padding(12)
          .zIndex(5)
        }
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
            showModelInstall: !appState.hasInstalledLocalModelPack,
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
      .frame(width: geometry.size.width, height: geometry.size.height)
      .clipped()
    }
    .onChange(of: router.shouldPresentMediaImport) { _, requested in
      guard requested else { return }
      router.shouldPresentMediaImport = false
      importedRecordID = router.pendingMediaImportRecordID
      router.pendingMediaImportRecordID = nil
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
        importedRecordID = router.pendingMediaImportRecordID
        router.pendingMediaImportRecordID = nil
        mediaImportDismissalDestination = nil
        isShowingMediaImport = true
      }
    }
    .task(id: detailRecordID) {
      guard let detailRecordID else {
        loadedDetailRecord = nil
        return
      }
      if let record = appState.recordings.first(where: { $0.id == detailRecordID }) {
        loadedDetailRecord = record
        return
      }
      loadedDetailRecord = await appState.loadRecordingDetail(recordID: detailRecordID)
      if let loadedDetailRecord {
        appState.adoptRecordingDetail(loadedDetailRecord)
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

  private var detailRecordID: UUID? {
    if case .recording(let id) = router.route { return id }
    return nil
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
        hasRecordings: !appState.recordingSummaries.isEmpty || !appState.recordings.isEmpty,
        showModelInstall: !appState.hasInstalledLocalModelPack,
        canStartRecording: appState.canStartRecording,
        canImportMedia: appState.canImportMedia,
        hydrationError: appState.recordingHydrationError,
        startRecording: { appState.startRecording() },
        importMedia: {
          importedRecordID = nil
          mediaImportDismissalDestination = nil
          isShowingMediaImport = true
        },
        retryHydration: { appState.retryRecordingHydration() })
    case .recording(let id):
      if let record = appState.recordings.first(where: { $0.id == id }) {
        RecordingDetailView(record: record)
      } else if let loadedDetailRecord, loadedDetailRecord.id == id {
        RecordingDetailView(record: loadedDetailRecord)
      } else if appState.isHydratingRecordings {
        WorkspaceEmptyState(
          title: "正在打开素材", systemImage: "arrow.triangle.2.circlepath",
          message: "正在读取这条素材的详情，原始音频不会被修改。")
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

struct WorkspaceOnboardingModelPrompt {
  static let title = "转成文字前，需要先下载语音转换模型"
  static let detail = "App Store 安装包不携带模型。下载由你确认，模型只保存在这台 Mac。"
}

private struct WorkspaceOnboardingCard: View {
  let showModelInstall: Bool
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
      if showModelInstall {
        Divider()
        VStack(alignment: .leading, spacing: 8) {
          Label(WorkspaceOnboardingModelPrompt.title, systemImage: "arrow.down.circle.fill")
            .font(.subheadline.weight(.semibold))
          Text(WorkspaceOnboardingModelPrompt.detail)
            .font(.caption)
            .foregroundStyle(.secondary)
          RecommendedModelInstallCard(entryPoint: .workspace)
        }
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
  @State private var renamingRecord: RecordingRecord?
  @State private var renameDraft = ""

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
          .frame(
            maxWidth: .infinity, minHeight: 0, idealHeight: 0,
            maxHeight: .infinity, alignment: .top
          )
          .clipped()
      } else {
        ScrollView {
          contextContent
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
        }
        .frame(
          maxWidth: .infinity, minHeight: 0, idealHeight: 0,
          maxHeight: .infinity, alignment: .top
        )
        .clipped()
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
      Text("“\(record.displayTitle)”的原音频、原文和相关本机文件会一起移到 macOS 废纸篓，可从 Finder 恢复。")
    }
    .alert(
      "重命名素材",
      isPresented: Binding(
        get: { renamingRecord != nil },
        set: { if !$0 { renamingRecord = nil } }
      ),
      presenting: renamingRecord
    ) { record in
      TextField("素材名称", text: $renameDraft)
      Button("取消", role: .cancel) { renamingRecord = nil }
      Button("保存") {
        if appState.renameRecording(recordID: record.id, title: renameDraft) {
          renamingRecord = nil
        }
      }
    } message: { record in
      Text("当前名称：\(record.displayTitle)。名称仅影响素材显示和导出文件名。")
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
        .disabled(!appState.canImportMedia)
        .accessibilityLabel("导入音视频")
        .help("导入音频或视频")
        Button(role: .destructive) {
          guard let selectedRecordID else { return }
          requestDeletion(recordID: selectedRecordID)
        } label: {
          Image(systemName: "trash")
        }
        .buttonStyle(.woiceBorderless)
        .disabled(selectedRecordID == nil || !appState.canMutateRecordings)
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
      if appState.recordingSummaries.count >= 250 {
        summaryLibraryList
      } else {
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
                  .disabled(!appState.canMutateRecordings)
                }
                .contextMenu {
                  Button("重命名", systemImage: "pencil") {
                    renameDraft = record.displayTitle
                    renamingRecord = record
                  }
                  .disabled(!appState.canMutateRecordings)
                  Button("移到废纸篓", systemImage: "trash", role: .destructive) {
                    pendingDeletion = record
                  }
                  .disabled(!appState.canMutateRecordings)
                }
                .accessibilityLabel(
                  "\(record.displayTitle)，\(record.sourceKind.label)，\(record.materialStatus.label)"
                )
            }
          }
          .listStyle(.sidebar)
          .onDeleteCommand {
            guard let selectedRecordID else { return }
            requestDeletion(recordID: selectedRecordID)
          }
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
              Text(record.displayTitle).lineLimit(2)
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
            "\(record.displayTitle)，\(ProcessingTaskProjection.activeTask(in: record.processingTasks)?.status.label ?? record.materialStatus.label)"
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

  @ViewBuilder
  private var summaryLibraryList: some View {
    let filteredSummaries = appState.recordingSummaries.filter {
      materialFilter.matches($0.materialStatus) && summaryMatchesSearchQuery($0, query: query)
    }
    if filteredSummaries.isEmpty {
      Text(query.isEmpty ? "还没有素材" : "没有匹配结果")
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    } else {
      List(selection: $selectedRecordID) {
        ForEach(filteredSummaries) { summary in
          WorkspaceRecordingSummaryRow(summary: summary)
            .tag(summary.id)
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
              Button("移到废纸篓", systemImage: "trash", role: .destructive) {
                requestDeletion(recordID: summary.id)
              }
              .disabled(!appState.canMutateRecordings)
            }
            .contextMenu {
              Button("重命名", systemImage: "pencil") {
                beginRename(recordID: summary.id, fallbackTitle: summary.displayTitle)
              }
              .disabled(!appState.canMutateRecordings)
              Button("移到废纸篓", systemImage: "trash", role: .destructive) {
                requestDeletion(recordID: summary.id)
              }
              .disabled(!appState.canMutateRecordings)
            }
        }
      }
      .listStyle(.sidebar)
      .onAppear { MaterialPerformanceInstrumentation.event(.summaryPresented) }
      .onDeleteCommand {
        guard let selectedRecordID else { return }
        requestDeletion(recordID: selectedRecordID)
      }
    }
  }

  private func requestDeletion(recordID: UUID) {
    guard appState.canMutateRecordings else {
      let message =
        appState.isHydratingRecordings
        ? "正在读取素材库，请稍后再删除素材。"
        : "素材详情读取失败，请先点击“重新读取”后再删除素材。"
      appState.presentActionFeedback(.progress(message))
      return
    }
    if let record = appState.recordings.first(where: { $0.id == recordID }) {
      pendingDeletion = record
      return
    }
    Task { @MainActor in
      guard let record = await appState.loadRecordingDetail(recordID: recordID) else { return }
      appState.adoptRecordingDetail(record)
      pendingDeletion = record
    }
  }

  private func beginRename(recordID: UUID, fallbackTitle: String) {
    guard appState.canMutateRecordings else {
      let message =
        appState.isHydratingRecordings
        ? "正在读取素材库，请稍后再重命名。"
        : "素材详情读取失败，请先点击“重新读取”后再重命名。"
      appState.presentActionFeedback(.progress(message))
      return
    }
    renameDraft = fallbackTitle
    if let record = appState.recordings.first(where: { $0.id == recordID }) {
      renamingRecord = record
      return
    }
    Task { @MainActor in
      guard let record = await appState.loadRecordingDetail(recordID: recordID) else { return }
      appState.adoptRecordingDetail(record)
      renameDraft = record.displayTitle
      renamingRecord = record
    }
  }
}

private struct WorkspaceRecordingSummaryRow: View {
  let summary: RecordingSummary

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(summary.displayTitle)
        .lineLimit(2)
      HStack {
        Label(summary.materialStatus.label, systemImage: summary.materialStatus.systemImage)
        if summary.hasSystemAudio {
          Label("双轨", systemImage: "speaker.wave.2")
        }
        Spacer()
        Text(formatDuration(summary.duration)).monospacedDigit()
      }
      .font(.caption)
      .foregroundStyle(summary.materialStatus == .failed ? .red : .secondary)
      Text(summary.shortDate).font(.caption2).foregroundStyle(.tertiary)
    }
    .padding(.vertical, 4)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(
      "\(summary.displayTitle)，\(summary.sourceKind.label)，\(summary.materialStatus.label)")
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
    record.displayTitle,
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

func summaryMatchesSearchQuery(_ summary: RecordingSummary, query: String) -> Bool {
  let terms = query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    .filter { !$0.isEmpty }
  guard !terms.isEmpty else { return true }
  let searchable = [
    summary.displayTitle,
    summary.shortDate,
    summary.materialStatus.label,
    summary.materialStatus.rawValue,
    summary.sourceKind.label,
    summary.sourceKind.rawValue,
  ].map { $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) }
  return terms.allSatisfy { term in
    let normalized = term.folding(
      options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    return searchable.contains { $0.localizedCaseInsensitiveContains(normalized) }
  }
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
        Text(record.displayTitle).lineLimit(2)
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
  let canStartRecording: Bool
  let canImportMedia: Bool
  let hydrationError: String?
  let startRecording: () -> Void
  let importMedia: () -> Void
  let retryHydration: () -> Void

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
      if let hydrationError {
        VStack(alignment: .leading, spacing: 6) {
          Label("素材详情暂不可用", systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
            .font(.headline)
          Text(hydrationError)
            .font(.callout)
            .foregroundStyle(.secondary)
          Button("重新读取", systemImage: "arrow.clockwise", action: retryHydration)
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: 440, alignment: .leading)
        .padding(12)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
      }
      HStack(spacing: 10) {
        Button("开始录音", systemImage: "mic.fill", action: startRecording)
          .buttonStyle(.borderedProminent)
          .disabled(!canStartRecording)
        Button("导入音视频…", systemImage: "square.and.arrow.down", action: importMedia)
          .buttonStyle(.bordered)
          .disabled(!canImportMedia)
      }
      if showModelInstall {
        RecommendedModelInstallCard(entryPoint: .workspace)
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
                  Text(record.displayTitle).lineLimit(2)
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
                "\(record.displayTitle)，\(ProcessingTaskProjection.activeTask(in: record.processingTasks)?.status.label ?? record.materialStatus.label)"
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
                record.displayTitle,
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
              "\(record.displayTitle)，\(task?.status.label ?? record.materialStatus.label)，可继续处理"
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
