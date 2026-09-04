import AppKit
import SwiftUI
import WoiceCore

struct SettingsView: View {
  @Environment(AppState.self) private var appState
  private let embedded: Bool
  @Binding private var embeddedSection: SettingsSection?
  @State private var selectedSection: SettingsSection = .recording
  @State private var saved = false
  @State private var draftSettings = AppSettings.default
  @State private var baselineSettings = AppSettings.default
  @State private var isLoaded = false

  init() {
    embedded = false
    _embeddedSection = .constant(nil)
  }

  init(selection: Binding<SettingsSection>) {
    embedded = true
    _embeddedSection = Binding(
      get: { selection.wrappedValue },
      set: { newValue in
        if let newValue { selection.wrappedValue = newValue }
      })
  }

  private var hasUnsavedChanges: Bool {
    isLoaded && baselineSettings != draftSettings
  }

  private var activeSectionHasUnsavedChanges: Bool {
    guard isLoaded, let scope = activeSection.saveScope else { return false }
    return scope.applying(draftSettings, to: baselineSettings) != baselineSettings
  }

  private var otherSectionsHaveUnsavedChanges: Bool {
    guard isLoaded, let scope = activeSection.saveScope else { return hasUnsavedChanges }
    let activeDraft = scope.applying(draftSettings, to: baselineSettings)
    return activeDraft != draftSettings
  }

  var body: some View {
    mainContent
      .frame(minWidth: 760, idealWidth: 860, minHeight: 560, idealHeight: 640)
      .navigationTitle(embedded ? "设置" : "设置")
      .task {
        guard !isLoaded else { return }
        draftSettings = appState.settings
        baselineSettings = appState.settings
        isLoaded = true
      }
      .onDisappear {
        // A macOS Settings scene may reuse its SwiftUI state when the window is
        // reopened. Closing without saving must behave like dismissing a draft,
        // not like an implicit settings commit.
        draftSettings = baselineSettings
        saved = false
      }
  }

  @ViewBuilder
  private var mainContent: some View {
    if embedded {
      VStack(spacing: 0) {
        settingsEditor
        Divider()
        settingsFooter
      }
    } else {
      VStack(spacing: 0) {
        NavigationSplitView {
          settingsSectionList
            .navigationTitle("设置")
            .navigationSubtitle("Woice")
            .frame(minWidth: 228, idealWidth: 244)
        } detail: {
          settingsEditor
        }
        .navigationSplitViewStyle(.balanced)

        Divider()
        settingsFooter
      }
    }
  }

  private var activeSection: SettingsSection {
    let requested = embeddedSection ?? selectedSection
    guard requested != .agents || StoreCapabilityProfile.current.allowsExternalAgentConnector else {
      return .recording
    }
    return requested
  }

  private var availableSections: [SettingsSection] { SettingsSection.availableCases }

  private var settingsSectionList: some View {
    List(availableSections, selection: $selectedSection) { section in
      HStack(spacing: 12) {
        Image(systemName: section.systemImage)
          .font(.body.weight(.medium))
          .foregroundStyle(sectionStatusColor(section))
          .frame(width: 22)
        VStack(alignment: .leading, spacing: 3) {
          Text(section.title)
            .font(.body.weight(.medium))
          Text(sectionSummary(section))
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        Spacer(minLength: 4)
        Circle()
          .fill(sectionStatusColor(section))
          .frame(width: 6, height: 6)
          .accessibilityHidden(true)
      }
      .padding(.vertical, 7)
      .tag(section)
      .accessibilityElement(children: .combine)
      .accessibilityValue(sectionSummary(section))
    }
    .listStyle(.sidebar)
  }

  private var settingsEditor: some View {
    VStack(spacing: 0) {
      SettingsDetailHeader(section: activeSection)
      Divider()
      Group {
        switch activeSection {
        case .recording:
          #if WOICE_APP_STORE
            RecordingSettingsPane(
              settings: $draftSettings,
              recorder: appState.recorder,
              systemAudioCapability: appState.systemAudioCapability,
              globalShortcutInstalled: appState.globalShortcutInstalled,
              globalShortcutCurrent: appState.globalShortcutCurrent,
              globalShortcutError: appState.globalShortcutError
            )
          #else
            RecordingSettingsPane(
              settings: $draftSettings,
              recorder: appState.recorder,
              systemAudioCapability: appState.systemAudioCapability,
              textInsertion: appState.textInsertion,
              globalShortcutInstalled: appState.globalShortcutInstalled,
              globalShortcutCurrent: appState.globalShortcutCurrent,
              globalShortcutError: appState.globalShortcutError
            )
          #endif
        case .services:
          ProvidersSettingsPane(settings: $draftSettings, appState: appState)
            .onAppear {
              loadServicesSecretsIntoDraft()
            }
        case .files:
          StorageSettingsPane(settings: $draftSettings, store: appState.store)
        case .agents:
          #if WOICE_APP_STORE
            ContentUnavailableView(
              "Store 版本不提供外部 Agent",
              systemImage: "shippingbox",
              description: Text("录音、转写、复听、搜索和导出仍可正常使用。"))
          #else
            AgentSettingsPane(settings: $draftSettings, jobs: appState.agentDispatchJobs)
          #endif
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
  }

  private var settingsFooter: some View {
    HStack(alignment: .center, spacing: 12) {
      if let error = appState.errorMessage {
        Label(error, systemImage: "exclamationmark.triangle.fill")
          .font(.caption)
          .foregroundStyle(.red)
          .lineLimit(2)
      } else if activeSectionHasUnsavedChanges {
        Label("本页有未保存更改；保存后才会应用。", systemImage: "pencil")
          .font(.caption)
          .foregroundStyle(.orange)
      } else if otherSectionsHaveUnsavedChanges {
        Label("其他分区有未保存更改；切换回对应分区后分别保存。", systemImage: "pencil.and.outline")
          .font(.caption)
          .foregroundStyle(.orange)
      } else {
        Label(activeSection.footerPrivacyMessage, systemImage: activeSection.footerPrivacyIcon)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
      if activeSectionHasUnsavedChanges {
        Button("还原本页") {
          restoreUnsavedChanges()
        }
        .buttonStyle(.woiceBorderless)
        .foregroundStyle(.secondary)
      }
      if saved && !hasUnsavedChanges {
        Label("已保存", systemImage: "checkmark.circle.fill")
          .font(.callout)
          .foregroundStyle(.green)
      }
      Button("保存本页") {
        saveCurrentSection()
      }
      .buttonStyle(.borderedProminent)
      .keyboardShortcut("s", modifiers: [.command])
      .disabled(!isLoaded || !activeSectionHasUnsavedChanges)
    }
    .padding(.horizontal, 24)
    .padding(.vertical, 12)
    .frame(minHeight: 48)
    .background(.bar)
  }

  private func restoreUnsavedChanges() {
    guard let scope = activeSection.saveScope else { return }
    draftSettings = scope.applying(baselineSettings, to: draftSettings)
    saved = false
    appState.errorMessage = nil
    appState.presentActionFeedback(.success("已还原未保存更改"))
  }

  private func saveCurrentSection() {
    guard let scope = activeSection.saveScope else {
      appState.presentActionFeedback(.success("Agent 连接页没有需要保存的设置"))
      return
    }
    guard appState.saveSettings(candidate: draftSettings, scope: scope) else {
      saved = false
      return
    }
    // Keep drafts in other sections untouched, but move only the committed
    // section's baseline forward. The next section save will merge against the
    // settings already committed by AppState.
    baselineSettings = scope.applying(appState.settings, to: baselineSettings)
    saved = true
    Task { @MainActor in
      try? await Task.sleep(for: .seconds(2))
      saved = false
    }
  }

  private func loadServicesSecretsIntoDraft() {
    guard appState.loadKeychainSecretsIfNeeded() else { return }
    let scope = AppSettingsScope.services
    baselineSettings = scope.applying(appState.settings, to: baselineSettings)
    draftSettings = scope.applying(appState.settings, to: draftSettings)
  }

  private func sectionSummary(_ section: SettingsSection) -> String {
    switch section {
    case .recording:
      let status = appState.recorder.microphoneStatus
      if status.permission == .denied {
        return "需要麦克风权限"
      }
      return status.hasUsableInput ? "麦克风已就绪" : section.subtitle
    case .services:
      let asrConfigured = !draftSettings.asrEndpoint.trimmingCharacters(
        in: .whitespacesAndNewlines
      ).isEmpty
      let llmConfigured = !draftSettings.llmEndpoint.trimmingCharacters(
        in: .whitespacesAndNewlines
      ).isEmpty
      switch (asrConfigured, llmConfigured) {
      case (true, true): return "本机/外部转写 · 笔记已配置"
      case (true, false): return "本机模型或外部转写可选"
      case (false, true): return "本机转写 · 笔记 API 已配置"
      case (false, false): return "本机模型可用"
      }
    case .files:
      return "本机保存 · \(appState.recordings.count) 条录音"
    case .agents:
      let activeCount = appState.agentDispatchJobs.filter {
        switch $0.status {
        case .draft, .completed, .failed, .cancelled, .interrupted: false
        default: true
        }
      }.count
      let permissions = draftSettings.agentPermissions
      let enabled = [
        permissions.canReadMaterials ? "只读" : nil,
        permissions.canCreateTasks ? "创建任务" : nil,
        permissions.canControlActiveRecording ? "录音控制" : nil,
      ].compactMap { $0 }
      let grantSummary = enabled.isEmpty ? "无权限" : enabled.joined(separator: "、")
      return activeCount == 0 ? "\(grantSummary) · 未配置连接" : "\(activeCount) 个 Agent 任务处理中"
    }
  }

  private func sectionStatusColor(_ section: SettingsSection) -> Color {
    switch section {
    case .recording:
      switch appState.recorder.microphoneStatus.permission {
      case .denied: return .red
      case .granted where appState.recorder.microphoneStatus.hasUsableInput: return .green
      default: return .orange
      }
    case .services:
      return appState.localASRModel.providerID.isEmpty ? .orange : .green
    case .files:
      return .accentColor
    case .agents:
      return appState.agentDispatchJobs.isEmpty ? .secondary : .accentColor
    }
  }
}

enum SettingsSection: String, CaseIterable, Identifiable {
  case recording
  case services
  case files
  case agents

  static var availableCases: [SettingsSection] {
    allCases.filter {
      $0 != .agents || StoreCapabilityProfile.current.allowsExternalAgentConnector
    }
  }

  var id: Self { self }

  var saveScope: AppSettingsScope? {
    switch self {
    case .recording: .recording
    case .services: .services
    case .files: .files
    case .agents: .agents
    }
  }

  var title: String {
    switch self {
    case .recording: "录音与输入"
    case .services: "模型与转写"
    case .files: "文件与隐私"
    case .agents: "Agent 与连接"
    }
  }

  var subtitle: String {
    switch self {
    case .recording: "麦克风、会议模式、快捷键"
    case .services: "本机模型、外部服务"
    case .files: "保存、导出、权限"
    case .agents: "只读素材、受控派发"
    }
  }

  var detailDescription: String {
    switch self {
    case .recording:
      "控制录音输入、会议模式和录音后的本机处理行为。"
    case .services:
      "选择本机模型，管理可选的外部转写与 Markdown 服务。"
    case .files:
      "查看本机保存位置，设置导出目录和素材访问权限。"
    case .agents:
      "查看已验证的外部 Agent 能力和本地任务记录；不会自动安装、登录或执行 CLI。"
    }
  }

  var footerPrivacyMessage: String {
    switch self {
    case .recording:
      "本页只保存录音与输入设置；服务凭据不会因保存本页而改变。"
    case .services:
      "服务凭据只在你修改时更新；每次外发前都会请求确认。"
    case .files:
      "本页只保存文件与导出设置；服务凭据不会因保存本页而改变。"
    case .agents:
      "本页不保存 API Key；外部 Agent 只能通过受控协议读取已授权素材。"
    }
  }

  var footerPrivacyIcon: String {
    switch self {
    case .recording: "mic"
    case .services: "lock.shield"
    case .files: "folder"
    case .agents: "person.2.badge.gearshape"
    }
  }

  var systemImage: String {
    switch self {
    case .recording: "mic.fill"
    case .services: "waveform.and.mic"
    case .files: "folder.badge.gearshape"
    case .agents: "arrow.triangle.branch"
    }
  }
}

private struct SettingsDetailHeader: View {
  let section: SettingsSection

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: section.systemImage)
        .font(.title2.weight(.medium))
        .foregroundStyle(.tint)
        .frame(width: 28, height: 28)
      VStack(alignment: .leading, spacing: 3) {
        Text(section.title)
          .font(.title2.weight(.semibold))
        Text(section.detailDescription)
          .font(.callout)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 24)
    .padding(.top, 18)
    .padding(.bottom, 14)
    .accessibilityElement(children: .combine)
  }
}

private struct SettingsBanner: View {
  let title: String
  let message: String
  let systemImage: String
  var tint: Color = .accentColor

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: systemImage)
        .font(.title3)
        .foregroundStyle(tint)
        .frame(width: 24)
      VStack(alignment: .leading, spacing: 3) {
        Text(title).font(.callout.weight(.semibold))
        Text(message)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
    }
    .padding(12)
    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
  }
}

#if !WOICE_APP_STORE
  private struct AgentSettingsPane: View {
    @Binding var settings: AppSettings
    let jobs: [AgentDispatchJob]
    @State private var cliDiagnostics: [AgentCLIDiagnostic] = []
    @State private var isLoadingCLIDiagnostics = false

    private var recentJobs: [AgentDispatchJob] {
      jobs.sorted { $0.updatedAt > $1.updatedAt }.prefix(10).map { $0 }
    }

    var body: some View {
      Form {
        Section {
          Toggle("允许读取素材", isOn: $settings.agentPermissions.canReadMaterials)
          Toggle("允许创建后续任务", isOn: $settings.agentPermissions.canCreateTasks)
          Toggle(
            "允许控制正在录音",
            isOn: $settings.agentPermissions.canControlActiveRecording
          )
          Label(
            "录音控制默认关闭；任何创建任务仍会回到 Woice 由你确认，不会自动执行返回内容。",
            systemImage: "hand.raised"
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        } header: {
          Label("权限分级", systemImage: "lock.shield")
        } footer: {
          Text("三项权限独立保存。关闭读取会拒绝素材查询；关闭创建任务会拒绝转换请求；Woice 当前不提供绕过用户动作的录音控制。")
        }

        Section {
          SettingsBanner(
            title: "录音素材仍是 Woice 的核心",
            message: "Agent 只在素材完成后读取或接收你明确选择的内容。当前版本不会自动安装、登录或派发 CLI 任务，也不会执行 Agent 返回的命令。",
            systemImage: "waveform.and.person.filled"
          )
        }

        Section {
          capabilityRow(
            "素材只读查询", detail: "MCP / 本地 RPC 搜索、详情和分页读取",
            systemImage: "doc.text.magnifyingglass")
          capabilityRow("创建任务", detail: "用户确认后派发选中的素材并保存结果 Artifact", systemImage: "paperplane")
          capabilityRow(
            "控制正在录音", detail: "当前版本关闭；Connector 不能代替用户开始或停止录音",
            systemImage: "mic.slash", isAvailable: false)
          capabilityRow("Context Package", detail: "带哈希的文本、时间范围和显式音频快照", systemImage: "shippingbox")
          capabilityRow(
            "受控 CLI Runner（Beta）", detail: "固定可执行文件、环境白名单、超时和输出上限",
            systemImage: "lock.shield")
        } header: {
          Label("已验证基础", systemImage: "checkmark.seal")
        }

        Section {
          if recentJobs.isEmpty {
            Label("尚无 Agent 任务", systemImage: "tray")
              .foregroundStyle(.secondary)
          } else {
            ForEach(recentJobs) { job in
              AgentJobStatusRow(job: job)
            }
          }
        } header: {
          Label("任务记录", systemImage: "clock.arrow.circlepath")
        } footer: {
          Text("任务状态来自本地 SQLite；应用重启不会自动重放运行中的外部任务。")
        }

        Section {
          if isLoadingCLIDiagnostics {
            ProgressView("正在检查本机 CLI Beta")
          } else {
            ForEach(cliDiagnostics) { diagnostic in
              HStack(spacing: 10) {
                Image(systemName: diagnostic.status.systemImage)
                  .foregroundStyle(statusColor(for: diagnostic.status))
                  .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                  Text(diagnostic.displayName)
                    .font(.callout.weight(.medium))
                  Text(diagnostic.status.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
              }
              .accessibilityElement(children: .combine)
              .accessibilityLabel("\(diagnostic.displayName)，\(diagnostic.status.label)")
            }
          }
          Button("重新检查") {
            Task { await refreshCLIDiagnostics() }
          }
          .buttonStyle(.borderless)
          Text("Woice 只检查可执行文件和版本探针，不读取或复制 CLI 凭据；登录状态不会被显示为“已连接”。")
            .font(.caption)
            .foregroundStyle(.secondary)
        } header: {
          Label("CLI 连接（Beta）", systemImage: "point.3.connected.trianglepath.dotted")
        }
      }
      .formStyle(.grouped)
      .task {
        await refreshCLIDiagnostics()
      }
    }

    private func refreshCLIDiagnostics() async {
      isLoadingCLIDiagnostics = true
      let diagnostics = await Task.detached(priority: .utility) {
        AgentCLIAdapterCatalog().diagnostics()
      }.value
      cliDiagnostics = diagnostics
      isLoadingCLIDiagnostics = false
    }

    private func statusColor(for status: AgentCLIConnectionStatus) -> Color {
      switch status {
      case .notInstalled: .secondary
      case .versionDetected: .accentColor
      case .versionProbeFailed, .unsupportedVersion: .orange
      }
    }

    private func capabilityRow(
      _ title: String, detail: String, systemImage: String, isAvailable: Bool = true
    ) -> some View {
      HStack(spacing: 10) {
        Image(systemName: systemImage)
          .foregroundStyle(.tint)
          .frame(width: 22)
        VStack(alignment: .leading, spacing: 2) {
          Text(title).font(.callout.weight(.medium))
          Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        Spacer()
        Image(systemName: isAvailable ? "checkmark.circle.fill" : "minus.circle")
          .foregroundStyle(isAvailable ? .green : .secondary)
          .accessibilityLabel(isAvailable ? "已验证" : "当前关闭")
      }
    }
  }

  private struct AgentJobStatusRow: View {
    let job: AgentDispatchJob

    var body: some View {
      HStack(spacing: 10) {
        Image(systemName: statusSystemImage)
          .foregroundStyle(statusColor)
          .frame(width: 22)
        VStack(alignment: .leading, spacing: 2) {
          Text(AgentCLIAdapterCatalog.userFacingDisplayName(for: job.connectorID))
            .font(.callout.weight(.medium))
          Text(statusLabel)
            .font(.caption)
            .foregroundStyle(.secondary)
          if let error = job.lastError, !error.isEmpty {
            Text(error)
              .font(.caption2)
              .foregroundStyle(.orange)
              .lineLimit(2)
          }
        }
        Spacer()
        Text(job.updatedAt, style: .time)
          .font(.caption2.monospacedDigit())
          .foregroundStyle(.tertiary)
      }
      .accessibilityElement(children: .combine)
    }

    private var statusLabel: String {
      switch job.status {
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

    private var statusSystemImage: String {
      switch job.status {
      case .completed: "checkmark.circle.fill"
      case .failed, .interrupted: "exclamationmark.triangle.fill"
      case .cancelled: "xmark.circle"
      case .draft: "doc"
      default: "arrow.triangle.2.circlepath"
      }
    }

    private var statusColor: Color {
      switch job.status {
      case .completed: .green
      case .failed, .interrupted: .orange
      case .cancelled: .secondary
      default: .accentColor
      }
    }
  }
#endif

private struct RecordingSettingsPane: View {
  @Binding var settings: AppSettings
  let recorder: RecordingService
  let systemAudioCapability: SystemAudioCapabilityService
  #if !WOICE_APP_STORE
    let textInsertion: TextInsertionService
  #endif
  let globalShortcutInstalled: Bool
  let globalShortcutCurrent: RecordingShortcut
  let globalShortcutError: String?

  var body: some View {
    Form {
      Section {
        SettingsBanner(
          title: "录音先保存在本机",
          message: "按下开始录音后才会访问麦克风。停止后先把原始录音保存到这台 Mac，再根据你的设置和确认转写。",
          systemImage: "lock.shield"
        )
      }

      Section {
        MicrophoneStatusRow(recorder: recorder)
      } header: {
        Label("麦克风输入", systemImage: "mic")
      } footer: {
        Text("开始录音时会使用这里显示的系统输入设备；若权限已允许但没有输入格式，请先在系统设置切换默认麦克风。")
      }

      Section {
        Picker("识别语言", selection: languageBinding) {
          ForEach(TranscriptionLanguageOption.pickerOptions(currentCode: settings.language)) {
            option in
            HStack(spacing: 8) {
              Text(option.displayName)
              if !option.detail.isEmpty {
                Text(option.detail)
                  .foregroundStyle(.secondary)
              }
            }
            .tag(option)
          }
        }
        .pickerStyle(.menu)
        Toggle("转写完成后自动复制原文", isOn: $settings.autoCopyTranscript)
        #if !WOICE_APP_STORE
          Toggle("转写完成后自动粘贴到当前应用", isOn: $settings.autoPasteTranscript)
        #endif
        Toggle("录音时显示实时文字", isOn: $settings.enableLiveTranscription)
        Text("开始麦克风录音后，文字会显示在工作台和顶部录音面板。只使用本机能力，不会覆盖最终原文。")
          .font(.caption)
          .foregroundStyle(.secondary)
      } header: {
        Label("录音与转写", systemImage: "mic")
      } footer: {
        Text("这些选项只影响后续录音；原始音频和最终原文仍会安全保留。")
      }

      Section {
        DisclosureGroup("高级录音选项") {
          Toggle("保留逐句时间", isOn: $settings.includeTranscriptTimestamps)
          Text("逐句时间需要当前转写服务支持。")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      } header: {
        Label("高级", systemImage: "slider.horizontal.3")
      }

      Section {
        Label("录音状态会同时显示图标和文字；处理超过几秒时会显示当前阶段。", systemImage: "info.circle")
          .foregroundStyle(.secondary)
      }

      Section {
        ShortcutRecorderEditor(
          shortcut: $settings.recordingShortcut,
          activeShortcut: globalShortcutCurrent,
          runtimeError: globalShortcutError
        )
        GlobalShortcutStatusRow(
          shortcut: settings.recordingShortcut,
          isInstalled: globalShortcutInstalled,
          error: globalShortcutError
        )
      } header: {
        Label("键盘快捷键", systemImage: "keyboard")
      } footer: {
        Text("快捷键只触发用户动作，不会绕过权限或外发确认；保存本页后才会生效。")
      }

      Section {
        Label("录音来源在工作台顶部切换", systemImage: "switch.2")
          .foregroundStyle(.secondary)
        Picker("会议转写方式", selection: $settings.meetingTranscriptionMode) {
          ForEach(MeetingTranscriptionMode.allCases, id: \.self) { mode in
            Text(mode.label).tag(mode)
          }
        }
        .pickerStyle(.menu)
        Text(settings.meetingTranscriptionMode.description)
          .font(.caption)
          .foregroundStyle(.secondary)
        SystemAudioCapabilityRow(service: systemAudioCapability)
      } header: {
        Label("系统声音录制", systemImage: "speaker.wave.2")
      } footer: {
        Text("麦克风和电脑声音由工作台顶部两个按钮独立控制；这里只设置双轨转写方式并检查系统能力。")
      }

      #if !WOICE_APP_STORE
        Section {
          TextInsertionPermissionRow(service: textInsertion)
        } header: {
          Label("粘贴权限", systemImage: "rectangle.on.rectangle")
        } footer: {
          Text("默认不会申请辅助功能权限。只有你使用粘贴动作或开启自动粘贴后，Woice 才会引导你授权。")
        }
      #endif
    }
    .formStyle(.grouped)
    .padding(.top, 12)
  }

  private var languageBinding: Binding<TranscriptionLanguageOption> {
    Binding(
      get: { TranscriptionLanguageOption.forCode(settings.language) },
      set: { settings.language = $0.code }
    )
  }
}

private struct GlobalShortcutStatusRow: View {
  let shortcut: RecordingShortcut
  let isInstalled: Bool
  let error: String?

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: statusIcon)
        .foregroundStyle(statusColor)
        .frame(width: 20)
      VStack(alignment: .leading, spacing: 4) {
        Text(statusTitle)
          .font(.callout.weight(.medium))
        Text(detail)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer()
    }
  }

  private var statusTitle: String {
    if shortcut == .disabled { return "全局快捷键已关闭" }
    return isInstalled ? "全局快捷键已启用" : "全局快捷键不可用"
  }

  private var detail: String {
    if shortcut == .disabled { return "仅使用菜单栏按钮录音。" }
    return isInstalled ? shortcut.displayName : (error ?? "菜单栏按钮仍可用于录音。")
  }

  private var statusIcon: String {
    if shortcut == .disabled { return "keyboard.badge.slash" }
    return isInstalled ? "checkmark.circle.fill" : "keyboard.badge.exclamationmark"
  }

  private var statusColor: Color {
    if shortcut == .disabled { return .secondary }
    return isInstalled ? .green : .orange
  }
}

private struct MicrophoneStatusRow: View {
  @Environment(AppState.self) private var appState
  @Environment(\.openURL) private var openURL
  let recorder: RecordingService
  @State private var status = MicrophoneInputStatus(
    permission: .unknown, hasUsableInput: false, sampleRate: 0, channelCount: 0)
  @State private var isCheckingInput = false
  @State private var inputCheckMessage: String?
  @State private var inputCheckSucceeded = false

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .top, spacing: 10) {
        Image(systemName: status.hasUsableInput ? "checkmark.circle.fill" : "mic.slash")
          .foregroundStyle(statusColor)
          .frame(width: 20)
        VStack(alignment: .leading, spacing: 4) {
          Text(title).font(.callout.weight(.medium))
          Text(detail)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: 8)
        HStack(spacing: 8) {
          ActionFeedbackButton {
            guard !isCheckingInput else { return .progress("正在检查麦克风") }
            isCheckingInput = true
            Task { @MainActor in
              status = await recorder.refreshMicrophoneStatus()
              isCheckingInput = false
              appState.presentActionFeedback(
                status.hasUsableInput
                  ? .success("麦克风状态已刷新")
                  : .failure("未发现可用的麦克风输入"))
            }
            return .progress("正在检查麦克风")
          } label: {
            Label("刷新", systemImage: "arrow.clockwise")
          }
          .buttonStyle(.woiceBorderless)
          .disabled(isCheckingInput)

          Button {
            runInputCheck()
          } label: {
            if isCheckingInput {
              ProgressView().controlSize(.small)
              Text("测试中")
            } else {
              Label("测试输入", systemImage: "waveform.badge.mic")
            }
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
          .disabled(isCheckingInput || recorder.isRecording || !status.hasUsableInput)
        }
        .font(.caption)
      }
      if let inputCheckMessage {
        HStack(spacing: 6) {
          Image(
            systemName: inputCheckSucceeded
              ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
          Text(inputCheckMessage)
        }
        .font(.caption)
        .foregroundStyle(inputCheckSucceeded ? Color.green : Color.orange)
        .accessibilityElement(children: .combine)
      }
      if status.permission == .denied {
        HStack(spacing: 8) {
          Spacer().frame(width: 20)
          Button("打开系统设置") {
            guard
              let url = URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
              )
            else {
              return
            }
            openURL(url)
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
          Text("允许 Woice 使用麦克风后，再点击刷新。")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      if status.permission == .granted && !status.hasUsableInput {
        HStack(spacing: 8) {
          Spacer().frame(width: 20)
          Button("打开声音设置") {
            guard
              let url = URL(string: "x-apple.systempreferences:com.apple.preference.sound?")
            else { return }
            openURL(url)
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
          .accessibilityHint("选择输入设备后返回 Woice 并点击刷新")
          Text("选择一个输入设备后，再点击刷新。")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }
    .task { status = await recorder.refreshMicrophoneStatus() }
  }

  private func runInputCheck() {
    guard !isCheckingInput else { return }
    isCheckingInput = true
    inputCheckMessage = nil
    Task { @MainActor in
      defer { isCheckingInput = false }
      do {
        let result = try await recorder.runMicrophoneCheck()
        inputCheckSucceeded = result.peakLevel > 0.0001
        inputCheckMessage =
          inputCheckSucceeded
          ? "已捕获 \(String(format: "%.1f", result.duration)) 秒输入，\(result.bufferCount) 个音频缓冲。"
          : "已收到音频帧，但电平很低；请检查系统输入设备和麦克风静音状态。"
        status = recorder.microphoneStatus
        appState.presentActionFeedback(
          inputCheckSucceeded ? .success("测试输入完成") : .failure("测试输入电平偏低")
        )
      } catch {
        inputCheckSucceeded = false
        inputCheckMessage = error.localizedDescription
        appState.presentActionFeedback(.failure("测试输入失败：\(error.localizedDescription)"))
      }
    }
  }

  private var title: String {
    switch status.permission {
    case .granted where status.hasUsableInput:
      "麦克风已就绪"
    case .granted:
      "权限已允许，但没有可用输入"
    case .denied:
      "麦克风权限未允许"
    case .notDetermined:
      "尚未请求麦克风权限"
    case .unknown:
      "无法读取麦克风状态"
    }
  }

  private var detail: String {
    switch status.permission {
    case .granted where status.hasUsableInput:
      return
        "系统输入：\(Int(status.sampleRate).formatted()) Hz · \(status.channelCount) 声道；录音会保存为本机 WAV。"
    case .granted:
      return "权限已允许，但当前没有可用输入。请在系统设置 > 声音 > 输入中选择麦克风，然后点击刷新。"
    case .denied:
      return "请在系统设置中允许 Woice 使用麦克风，再点击刷新。"
    case .notDetermined:
      return "点击开始录音时，Woice 会在系统权限允许后再次检查输入设备。"
    case .unknown:
      return "无法读取麦克风状态，请稍后点击刷新。"
    }
  }

  private var statusColor: Color {
    switch status.permission {
    case .granted where status.hasUsableInput: .green
    case .denied, .unknown: .red
    default: .orange
    }
  }
}

#if !WOICE_APP_STORE
  private struct TextInsertionPermissionRow: View {
    let service: TextInsertionService

    var body: some View {
      HStack(alignment: .top, spacing: 10) {
        Image(
          systemName: service.isAccessibilityTrusted
            ? "checkmark.circle.fill" : "lock.circle"
        )
        .foregroundStyle(service.isAccessibilityTrusted ? Color.green : Color.orange)
        .frame(width: 20)
        VStack(alignment: .leading, spacing: 4) {
          Text(service.isAccessibilityTrusted ? "已允许粘贴到当前应用" : "尚未允许辅助功能粘贴")
            .font(.callout.weight(.medium))
          Text(
            service.isAccessibilityTrusted
              ? "详情页的“粘贴到当前应用”和自动粘贴已具备系统权限。"
              : "不授权也可以复制原文；粘贴动作会保留在 Woice 并提示下一步。"
          )
          .font(.caption)
          .foregroundStyle(.secondary)
          HStack(spacing: 8) {
            ActionFeedbackButton {
              service.requestPermission()
              return .progress("正在打开粘贴权限设置")
            } label: {
              Text("请求权限")
            }
            .buttonStyle(.bordered)
            ActionFeedbackButton {
              service.refreshPermission()
              return .success("粘贴权限状态已刷新")
            } label: {
              Label("重新检查", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.woiceBorderless)
          }
          .font(.caption)
        }
        Spacer()
      }
      .task { service.refreshPermission() }
    }
  }
#endif

private struct SystemAudioCapabilityRow: View {
  let service: SystemAudioCapabilityService
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: service.capability.state.systemImage)
        .foregroundStyle(tint)
        .frame(width: 20)
      VStack(alignment: .leading, spacing: 4) {
        Text(service.capability.state.title)
          .font(.callout.weight(.medium))
        Text(detail)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        HStack(spacing: 8) {
          if service.capability.state == .needsPermission
            || service.capability.state == .needsReauthorization
          {
            ActionFeedbackButton {
              service.requestPermission()
              return .progress("正在打开屏幕录制权限设置")
            } label: {
              Label(
                service.capability.state == .needsReauthorization
                  ? "重新授权当前安装包" : "请求屏幕录制权限",
                systemImage: "lock.open"
              )
            }
            .buttonStyle(.bordered)
          }
          ActionFeedbackButton {
            service.refresh()
            return .success("系统音频能力已刷新")
          } label: {
            Label("重新检查", systemImage: "arrow.clockwise")
          }
          .buttonStyle(.woiceBorderless)
          .disabled(service.isChecking)
        }
        .font(.caption)
      }
      Spacer()
      if service.isChecking {
        ProgressView()
          .controlSize(.small)
      }
    }
    .task { service.refresh() }
    .onChange(of: scenePhase) { _, newPhase in
      guard newPhase == .active else { return }
      service.refresh()
    }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification))
    {
      _ in
      service.refresh()
    }
  }

  private var detail: String {
    switch service.capability.state {
    case .notChecked:
      "点击重新检查当前 Mac 是否具备会议模式的系统音频前置条件。"
    case .needsPermission:
      "请在系统设置的隐私与安全性 > 屏幕录制中允许 Woice；授权后返回 Woice，页面会自动重检。若列表中有旧版 Woice，请先移除旧项再重新授权。"
    case .needsReauthorization:
      "系统设置里的授权可能属于旧版 Woice；请关闭旧项、重新打开当前 Woice，再回到此处检查。若系统要求触控 ID 或密码，请由你本人完成确认。"
    case .noDisplay:
      "系统没有返回可共享显示器或窗口。请解锁当前桌面、退出远程桌面后点击重新检查。"
    case .ready:
      "已发现 \(service.capability.displayCount) 个显示器；开启会议录音后可采集视频、会议等系统输出并单独保存。受保护媒体或远程桌面场景可能没有声音。"
    case .readyWindow:
      "未发现可共享显示器，但发现 \(service.capability.windowCount) 个可捕获窗口；会议录音将只保存活动窗口声音。要捕获全系统输出，请解锁当前桌面后重新检查。"
    case .unavailable:
      "系统暂时无法读取系统音频能力。请解锁桌面后点击重新检查；麦克风录音仍可单独使用。"
    }
  }

  private var tint: Color {
    switch service.capability.state.tint {
    case .green: .green
    case .orange: .orange
    case .secondary: .secondary
    }
  }
}

private struct ProvidersSettingsPane: View {
  @Binding var settings: AppSettings
  let appState: AppState
  @State private var isRequestingAuthorization = false
  @State private var isImportingModel = false
  @State private var selectingModelKey: String?
  @State private var showAdvanced = false

  private var installedLocalModels: [ModelPackInventoryEntry] {
    appState.modelPackInventory.filter {
      ModelRuntimeRegistry.admission(for: $0.manifest).isAdmitted
    }
  }

  private var selectedInstalledModel: ModelPackInventoryEntry? {
    guard appState.settings.asrProviderSelection == .onDevice else { return nil }
    if let packID = appState.settings.selectedLocalModelPackID,
      let version = appState.settings.selectedLocalModelVersion
    {
      return installedLocalModels.first {
        $0.manifest.packID == packID && $0.manifest.version == version
      }
    }
    return installedLocalModels.first {
      $0.manifest.providerID == appState.localASRModel.providerID
        && $0.manifest.modelID == appState.localASRModel.modelID
        && $0.manifest.version == appState.localASRModel.version
    }
  }

  private var downloadableRecommendationPackIDs: Set<String>? {
    guard StoreCapabilityProfile.current.isStoreEdition else { return nil }
    return Set(
      appState.verifiedModelCatalogEntries.compactMap {
        $0.downloadBaseURL == nil ? nil : $0.packID
      })
  }

  private var modelRecommendation: RecommendedModelPolicy.Recommendation? {
    RecommendedModelPolicy.recommendation(
      physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory,
      availablePackIDs: downloadableRecommendationPackIDs)
  }

  private var recommendationModels: [ModelInstallCardModel] {
    guard let modelRecommendation else { return RecommendedModelPolicy.candidates }
    return [modelRecommendation.model]
      + RecommendedModelPolicy.candidates.filter { $0 != modelRecommendation.model }
  }

  private func modelKey(_ item: ModelPackInventoryEntry) -> String {
    "\(item.manifest.packID)/\(item.manifest.version)"
  }

  private func modelName(_ item: ModelPackInventoryEntry) -> String {
    item.manifest.displayName ?? item.manifest.modelID
  }

  private func selectModel(_ item: ModelPackInventoryEntry) {
    let key = modelKey(item)
    selectingModelKey = key
    Task { @MainActor in
      let didSelect = await appState.selectInstalledModel(
        packID: item.manifest.packID, version: item.manifest.version)
      if didSelect {
        // Keep the settings draft aligned with the immediately committed
        // runtime choice so saving another services field cannot roll it back.
        settings.selectedLocalModelPackID = item.manifest.packID
        settings.selectedLocalModelVersion = item.manifest.version
        settings.asrProviderSelection = .onDevice
      }
      selectingModelKey = nil
    }
  }

  @ViewBuilder
  private var localModelPicker: some View {
    if installedLocalModels.isEmpty {
      VStack(alignment: .trailing, spacing: 3) {
        Text(appState.localASRModel.displayName)
        Text("尚未安装可切换的本机模型")
          .font(.caption)
          .foregroundStyle(.secondary)
        Button("显示模型下载") {
          showAdvanced = true
        }
        .buttonStyle(.woiceBorderless)
        .controlSize(.small)
      }
    } else {
      Menu {
        ForEach(Array(installedLocalModels.enumerated()), id: \.offset) { _, item in
          Button {
            selectModel(item)
          } label: {
            let location = item.location == .bundled ? "随包" : "已下载"
            let title = "\(modelName(item)) · \(item.manifest.version) · \(location)"
            if selectedInstalledModel?.manifest.packID == item.manifest.packID,
              selectedInstalledModel?.manifest.version == item.manifest.version
            {
              Label(title, systemImage: "checkmark")
            } else {
              Text(title)
            }
          }
          .disabled(selectingModelKey != nil)
        }
      } label: {
        HStack(spacing: 6) {
          Text(selectedInstalledModel.map(modelName) ?? appState.localASRModel.displayName)
            .lineLimit(1)
          Image(systemName: "chevron.up.chevron.down")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        }
      }
      .menuStyle(.borderedButton)
      .disabled(selectingModelKey != nil)
      if let selectingModelKey {
        ProgressView()
          .controlSize(.small)
          .accessibilityLabel("正在切换本机模型")
          .id(selectingModelKey)
      }
    }
  }

  var body: some View {
    Form {
      Section {
        SettingsBanner(
          title: "先用这台 Mac 完成转写",
          message: "Woice 默认保留本机录音，并使用当前可用的本机模型转成文字。外部服务只在你选择并确认后发送。",
          systemImage: "lock.shield"
        )
      }

      Section {
        Picker("转写方式", selection: $settings.asrProviderSelection) {
          Text("本机模型（推荐）").tag(ASRProviderSelection.onDevice)
          Text("自定义服务").tag(ASRProviderSelection.external)
        }
        LabeledContent("本机模型") {
          VStack(alignment: .trailing, spacing: 3) {
            localModelPicker
            if let selectedInstalledModel {
              Text(
                "版本 \(selectedInstalledModel.manifest.version) · \(selectedInstalledModel.location == .bundled ? "随包" : "已下载")"
              )
              .font(.caption)
              .foregroundStyle(.secondary)
            } else {
              Text(
                "版本 \(appState.localASRModel.version) · \(appState.localASRModel.dataLocation.label)"
              )
              .font(.caption)
              .foregroundStyle(.secondary)
            }
            if !installedLocalModels.isEmpty {
              Text("已验证 \(installedLocalModels.count) 个本机模型")
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
          }
        }
        LabeledContent("语音识别权限") {
          HStack(spacing: 8) {
            Label(
              appState.localASRAuthorizationState.title,
              systemImage: appState.localASRAuthorizationState.systemImage
            )
            .foregroundStyle(localAuthorizationTint)
            if appState.localASRAuthorizationState == .notDetermined {
              Button(isRequestingAuthorization ? "请求中…" : "允许") {
                isRequestingAuthorization = true
                Task {
                  await appState.requestLocalASRAuthorization()
                  isRequestingAuthorization = false
                  appState.presentActionFeedback(.success("语音识别权限状态已更新"))
                }
              }
              .buttonStyle(.woiceBorderless)
              .disabled(isRequestingAuthorization)
            }
          }
        }
        Label(
          appState.localASRModel.providerID == "com.apple.speech.on-device"
            ? "版本随 macOS 更新；录音停止后才开始最终转写。"
            : "版本来自已校验模型清单；录音停止后才开始最终转写。",
          systemImage: "info.circle"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      } header: {
        Label("本机语言转文字", systemImage: "desktopcomputer.and.arrow.down")
      } footer: {
        Text("本机模型不可用时只保留原始录音，不会自动把录音发送到云端。")
      }

      Section {
        LabeledContent("当前转写目标") {
          VStack(alignment: .trailing, spacing: 2) {
            if appState.settings.asrProviderSelection == .external {
              Text(appState.settings.asrModel)
                .font(.callout.weight(.medium))
              Text(externalEndpointSummary(appState.settings.asrEndpoint))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            } else {
              Text(appState.localASRModel.displayName)
                .font(.callout.weight(.medium))
              Text(appState.localASRModel.version)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            }
          }
        }
        Button {
          showAdvanced = true
        } label: {
          Label("管理已安装模型版本", systemImage: "arrow.triangle.2.circlepath")
        }
        .buttonStyle(.woiceBorderless)
      } header: {
        Label("实际转写路线", systemImage: "checkmark.seal")
      } footer: {
        Text("这里只显示已保存并会被下一次转写实际使用的目标；切换不会修改已有录音或原文版本。")
      }

      Section {
        Button {
          withAnimation { showAdvanced.toggle() }
        } label: {
          Label(
            showAdvanced ? "收起高级设置" : "显示高级设置",
            systemImage: showAdvanced ? "chevron.up" : "chevron.down")
        }
        .buttonStyle(.woiceBorderless)
        Text("高级设置包含模型下载、服务连接、诊断和兼容参数。")
          .font(.caption)
          .foregroundStyle(.secondary)
      } header: {
        Label("高级", systemImage: "slider.horizontal.3")
      }

      if showAdvanced {
        Section {
          ForEach(appState.asrProviderInventory, id: \.providerID) { provider in
            HStack(spacing: 10) {
              Image(systemName: providerHealthImage(provider.health))
                .foregroundStyle(providerHealthColor(provider.health))
                .frame(width: 20)
              VStack(alignment: .leading, spacing: 2) {
                Text(provider.displayName)
                  .font(.callout.weight(.medium))
                Text("\(provider.dataLocation.label) · \(provider.transport.label)")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
              Spacer()
              Text(provider.health.label)
                .font(.caption)
                .foregroundStyle(providerHealthColor(provider.health))
            }
            .accessibilityElement(children: .combine)
            .accessibilityValue(provider.health.label)
          }
        } header: {
          Label("转写能力状态", systemImage: "checkmark.shield")
        } footer: {
          Text("状态来自当前配置、已校验模型和本机权限；不会因查看设置而加载模型或发送网络请求。")
        }

        Section {
          VStack(alignment: .leading, spacing: 10) {
            Text("按设备资源和转写质量选择；下载完成后会自动设为当前本机模型。")
              .font(.caption)
              .foregroundStyle(.secondary)
            ForEach(Array(recommendationModels.enumerated()), id: \.offset) { _, model in
              ModelInstallCard(
                entryPoint: .settings,
                model: model,
                recommendation: modelRecommendation)
            }
          }
        } header: {
          Label("获取本机模型", systemImage: "arrow.down.circle")
        } footer: {
          #if WOICE_APP_STORE
            Text(
              "下载由你显式触发，完成后会校验每个文件并原子安装；Store 版本只允许已验证模型清单中的条目，下载失败不会替换当前模型。"
            )
          #else
            Text(
              "下载由你显式触发，完成后会校验每个文件并原子安装；下载失败不会替换当前模型。Tiny、Qwen3-ASR 和 Large-v3 都可独立安装与切换。"
            )
          #endif
        }

        Section {
          LabeledContent("当前使用版本") {
            VStack(alignment: .trailing, spacing: 2) {
              Text(appState.localASRModel.modelID)
                .font(.callout.weight(.medium))
              Text(appState.localASRModel.version)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            }
          }
          Label(
            "切换版本只影响后续本机转写，不会修改已有录音、原始转录或任务快照。",
            systemImage: "arrow.triangle.2.circlepath"
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        } header: {
          Label("当前模型版本", systemImage: "checkmark.seal")
        }

        Section {
          HStack(alignment: .top, spacing: 10) {
            Label(
              appState.modelCatalogState.title,
              systemImage: appState.modelCatalogState.systemImage
            )
            .foregroundStyle(modelCatalogColor(appState.modelCatalogState))
            Spacer()
            Button {
              Task { @MainActor in
                _ = await appState.refreshModelCatalog()
              }
            } label: {
              if case .updating = appState.modelCatalogState {
                ProgressView().controlSize(.small)
                Text("检查中")
              } else {
                Label("检查更新", systemImage: "arrow.clockwise")
              }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!appState.canUpdateModelCatalog || appState.modelCatalogState == .updating)
          }
          if case .failed(let message) = appState.modelCatalogState {
            Text(message)
              .font(.caption)
              .foregroundStyle(.red)
              .textSelection(.enabled)
          }
        } header: {
          Label("模型清单", systemImage: "list.bullet.rectangle")
        } footer: {
          Text("只在你点击“检查更新”后访问发行版配置的 HTTPS 地址；清单先验签和检查版本，再允许后续模型下载使用。没有配置远程清单时不会联网。")
        }

        if !catalogOnlyEntries.isEmpty {
          Section {
            ForEach(catalogOnlyEntries, id: \.packID) { entry in
              let isInstalled = appState.modelPackInventory.contains {
                $0.manifest.packID == entry.packID && $0.manifest.version == entry.version
              }
              let isDownloading = appState.isDownloadingModel(
                packID: entry.packID, version: entry.version)
              HStack(alignment: .top, spacing: 10) {
                Image(systemName: isInstalled ? "checkmark.seal" : "arrow.down.circle")
                  .foregroundStyle(isInstalled ? .green : Color.accentColor)
                  .frame(width: 20)
                VStack(alignment: .leading, spacing: 3) {
                  Text(entry.modelID)
                    .font(.callout.weight(.medium))
                  Text(
                    "版本 \(entry.version) · \(ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file))"
                  )
                  .font(.caption)
                  .foregroundStyle(.secondary)
                  .textSelection(.enabled)
                }
                Spacer()
                Button {
                  if isDownloading {
                    appState.cancelWhisperKitModelDownload()
                  } else {
                    Task { @MainActor in
                      _ = await appState.downloadVerifiedCatalogModel(
                        packID: entry.packID, version: entry.version)
                    }
                  }
                } label: {
                  if isDownloading {
                    ProgressView().controlSize(.small)
                    Text("取消")
                  } else if isInstalled {
                    Label("已安装", systemImage: "checkmark")
                  } else if appState.isDownloadingModel {
                    Text("等待当前下载")
                  } else {
                    Label("下载", systemImage: "arrow.down.circle")
                  }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(
                  (appState.isDownloadingModel && !isDownloading) || isInstalled)
              }
              if isDownloading, let progress = appState.modelDownloadProgress {
                ProgressView(value: progress.fractionCompleted)
                HStack {
                  Text(progress.filePath)
                  Spacer()
                  Text("\(Int(progress.fractionCompleted * 100))%")
                    .monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
              }
            }
          } header: {
            Label("发行版模型清单", systemImage: "list.bullet.rectangle.portrait")
          } footer: {
            Text("这些模型来自已验证的 Catalog；下载根地址和每个文件都经过发行版策略与 SHA-256 校验。")
          }
        }

        Section {
          if appState.modelPackInventory.isEmpty {
            Label("还没有安装用户模型包。", systemImage: "square.stack.3d.up.slash")
              .foregroundStyle(.secondary)
          } else {
            ForEach(appState.modelPackInventory.indices, id: \.self) { index in
              let item = appState.modelPackInventory[index]
              let isSelected =
                appState.isUsingLocalASR
                && appState.localASRModel.modelID == item.manifest.modelID
                && appState.localASRModel.version == item.manifest.version
              HStack(alignment: .top, spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                  .foregroundStyle(isSelected ? .green : .secondary)
                  .frame(width: 20)
                VStack(alignment: .leading, spacing: 3) {
                  Text(item.manifest.modelID)
                    .font(.callout.weight(.medium))
                  let locationLabel = item.location == .bundled ? "随包" : "已下载"
                  Text(
                    "版本 \(item.manifest.version) · \(locationLabel) · \(item.manifest.license.identifier)"
                  )
                  .font(.caption)
                  .foregroundStyle(.secondary)
                  if item.isCurrent && !isSelected {
                    Text("安装指针版本；当前设置已固定到另一版本")
                      .font(.caption2)
                      .foregroundStyle(.secondary)
                  }
                }
                Spacer()
                if isSelected {
                  Label("当前使用", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                } else {
                  HStack(spacing: 8) {
                    Button(selectingModelKey == modelKey(item) ? "切换中…" : "切换") {
                      selectModel(item)
                    }
                    .buttonStyle(.woiceBorderless)
                    .disabled(selectingModelKey != nil)
                    if item.location == .downloaded {
                      if item.isCurrent {
                        Label("安装指针", systemImage: "lock.fill")
                          .font(.caption2)
                          .foregroundStyle(.secondary)
                      } else {
                        Button {
                          Task { @MainActor in
                            _ = await appState.deleteInstalledModel(
                              packID: item.manifest.packID, version: item.manifest.version)
                          }
                        } label: {
                          Label("删除", systemImage: "trash")
                        }
                        .buttonStyle(.woiceBorderless)
                        .foregroundStyle(.red)
                        .help("删除这个已下载模型版本")
                        .disabled(selectingModelKey != nil || appState.isDownloadingModel)
                      }
                    }
                  }
                }
              }
            }
          }
          Button(isImportingModel ? "安装中…" : "导入模型包目录…") {
            importModelPack()
          }
          .disabled(isImportingModel)
          if let error = appState.errorMessage, error.hasPrefix("模型安装失败：") {
            Label(error, systemImage: "exclamationmark.triangle.fill")
              .font(.caption)
              .foregroundStyle(.red)
              .fixedSize(horizontal: false, vertical: true)
          }
        } header: {
          Label("模型版本控制", systemImage: "arrow.triangle.2.circlepath")
        } footer: {
          Text("可以在已验证版本之间切换或回滚。导入模型前会逐文件校验大小、SHA-256 和路径；切换成功后用于下一次本机转写。")
        }

        Section {
          HStack(alignment: .top, spacing: 10) {
            Label("本机服务预设", systemImage: "server.rack")
              .font(.callout.weight(.medium))
            Spacer()
            Menu {
              ForEach(ASRServicePreset.builtIns) { preset in
                Button {
                  applyASRServicePreset(preset)
                } label: {
                  VStack(alignment: .leading, spacing: 2) {
                    Text(preset.displayName)
                    Text(preset.description)
                      .font(.caption)
                  }
                }
              }
            } label: {
              Label("套用预设", systemImage: "slider.horizontal.3")
            }
            .menuStyle(.borderedButton)
          }
          Text("预设只填入设置草稿，不会启动服务、扫描端口或发送网络请求。地址和模型仍需按本机服务实际情况确认。")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
          providerFields(
            name: "语言转文字",
            endpoint: $settings.asrEndpoint,
            model: $settings.asrModel,
            apiKey: $settings.asrAPIKey,
            endpointPlaceholder: "https://api.openai.com/v1/audio/transcriptions",
            modelPlaceholder: "whisper-1",
            emptyDescription: "未配置外部服务：按上方选择使用本机模型")
          ASRHealthCheckRow(settings: $settings)
        } header: {
          Label("外部语言转文字（可选）", systemImage: "network")
        } footer: {
          Text(
            "选择外部服务后，录音停止会显示目标主机和数据类型，只有确认后才发送。可填写完整接口，也可填写服务根地址，Woice 会补全 /audio/transcriptions。")
        }

        Section {
          providerFields(
            name: "Markdown 笔记",
            endpoint: $settings.llmEndpoint,
            model: $settings.llmModel,
            apiKey: $settings.llmAPIKey,
            endpointPlaceholder: "https://api.openai.com/v1/chat/completions",
            modelPlaceholder: "gpt-4o-mini",
            emptyDescription: "未配置：原文仍只保存在本机")
        } header: {
          Label("Markdown 笔记（可选）", systemImage: "sparkles")
        } footer: {
          Text("LLM 只接收已经完成的原文；失败不会覆盖原始转录。服务根地址会自动补全 /chat/completions。")
        }
      }
    }
    .formStyle(.grouped)
    .padding(.top, 12)
  }

  private func externalEndpointSummary(_ endpoint: String) -> String {
    let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "尚未配置 Endpoint" }
    return URL(string: trimmed)?.host ?? trimmed
  }

  private var localAuthorizationTint: Color {
    switch appState.localASRAuthorizationState {
    case .authorized, .notRequired: .green
    case .notDetermined: .orange
    case .denied, .restricted: .red
    }
  }

  private func providerHealthColor(_ health: ASRProviderHealth) -> Color {
    switch health {
    case .ready: .green
    case .authorizationRequired, .waitingForModel, .downloading, .verifying: .orange
    case .unavailable, .incompatible, .untrusted, .disabled: .red
    case .unconfigured, .modelMissing: .secondary
    }
  }

  private func providerHealthImage(_ health: ASRProviderHealth) -> String {
    switch health {
    case .ready: "checkmark.circle.fill"
    case .authorizationRequired: "lock.trianglebadge.exclamationmark"
    case .waitingForModel, .downloading, .verifying: "clock"
    case .unavailable, .incompatible, .untrusted, .disabled: "exclamationmark.triangle.fill"
    case .unconfigured, .modelMissing: "questionmark.circle"
    }
  }

  private func modelCatalogColor(_ state: ModelCatalogRuntimeState) -> Color {
    switch state {
    case .ready: .green
    case .loadingLocal, .updating: .orange
    case .unavailable: .secondary
    case .failed: .red
    }
  }

  private func importModelPack() {
    let panel = NSOpenPanel()
    panel.title = "选择模型包目录"
    panel.message = "选择包含 manifest.json 和模型文件的目录"
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    guard panel.runModal() == .OK, let url = panel.url else { return }
    isImportingModel = true
    Task { @MainActor in
      _ = await appState.importModelPack(from: url)
      isImportingModel = false
    }
  }

  private func applyASRServicePreset(_ preset: ASRServicePreset) {
    settings = preset.applying(to: settings)
    appState.presentActionFeedback(.success("已填入 \(preset.displayName) 预设，请保存并测试连接"))
  }

  private var catalogOnlyEntries: [ModelPackManifest] {
    let builtInIDs = Set([
      WhisperKitModelCatalogEntry.recommendedTiny.packID,
      WhisperKitModelCatalogEntry.candidateLargeV3.packID,
    ])
    return appState.verifiedModelCatalogEntries.filter {
      $0.downloadBaseURL != nil && !builtInIDs.contains($0.packID)
    }
  }

  private func providerFields(
    name: String,
    endpoint: Binding<String>,
    model: Binding<String>,
    apiKey: Binding<String>,
    endpointPlaceholder: String,
    modelPlaceholder: String,
    emptyDescription: String
  ) -> some View {
    Group {
      HStack(spacing: 8) {
        Image(systemName: endpoint.wrappedValue.isEmpty ? "circle.dashed" : "checkmark.circle.fill")
          .foregroundStyle(endpoint.wrappedValue.isEmpty ? Color.secondary : Color.green)
        Text(
          endpoint.wrappedValue.isEmpty
            ? emptyDescription
            : "已配置：停止录音后可按确认发送"
        )
        .font(.callout)
        .foregroundStyle(.secondary)
        Spacer()
      }
      LabeledContent("接口地址") {
        TextField(endpointPlaceholder, text: endpoint)
          .textFieldStyle(.roundedBorder)
          .frame(maxWidth: .infinity)
          .textContentType(.URL)
      }
      LabeledContent("模型") {
        TextField(modelPlaceholder, text: model)
          .textFieldStyle(.roundedBorder)
          .frame(maxWidth: .infinity)
      }
      APIKeyField(value: apiKey)
      if let error = endpointError(endpoint.wrappedValue, name: name) {
        Label(error, systemImage: "exclamationmark.triangle.fill")
          .font(.caption)
          .foregroundStyle(.red)
      }
      if !endpoint.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
        model.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      {
        Label("已配置接口时，模型不能为空。", systemImage: "exclamationmark.triangle.fill")
          .font(.caption)
          .foregroundStyle(.red)
      }
    }
  }

  private struct ASRHealthCheckRow: View {
    @Environment(AppState.self) private var appState
    @Binding var settings: AppSettings
    @State private var isTesting = false
    @State private var message: String?
    @State private var succeeded = false

    var body: some View {
      VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 8) {
          Button {
            testConfiguration()
          } label: {
            if isTesting {
              ProgressView().controlSize(.small)
              Text("测试中")
            } else {
              Label("测试转写 API", systemImage: "waveform.badge.checkmark")
            }
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
          .disabled(isTesting || !canTest)
          Button {
            discoverModels()
          } label: {
            if appState.isDiscoveringASRModels {
              ProgressView().controlSize(.small)
              Text("发现中")
            } else {
              Label("发现本机模型", systemImage: "magnifyingglass")
            }
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
          .disabled(appState.isDiscoveringASRModels || !canDiscover)
          Spacer()
        }
        Text("健康检查只发送本机生成的短测试音频；模型发现只读取本机/局域网服务的模型列表，不发送录音。")
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        if let message {
          Label(
            message,
            systemImage: succeeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
          )
          .font(.caption)
          .foregroundStyle(succeeded ? Color.green : Color.orange)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityElement(children: .combine)
        }
        if !appState.discoveredASRModels.isEmpty {
          VStack(alignment: .leading, spacing: 4) {
            Text("可用模型（点击填入草稿）")
              .font(.caption.weight(.medium))
            ForEach(appState.discoveredASRModels, id: \.id) { model in
              Button {
                settings.asrModel = model.id
                appState.presentActionFeedback(.success("已将 \(model.id) 填入模型字段"))
              } label: {
                Label(model.id, systemImage: "text.badge.checkmark")
                  .frame(maxWidth: .infinity, alignment: .leading)
              }
              .buttonStyle(.woiceBorderless)
            }
          }
          .padding(.top, 2)
        }
      }
      .padding(.top, 2)
    }

    private var canTest: Bool {
      let endpoint = settings.asrEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
      let model = settings.asrModel.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !endpoint.isEmpty, !model.isEmpty, let url = URL(string: endpoint), url.host != nil
      else {
        return false
      }
      return ["http", "https"].contains(url.scheme?.lowercased())
    }

    private var canDiscover: Bool {
      ASRServiceDiscoveryPolicy.allows(settings.asrEndpoint)
    }

    private func testConfiguration() {
      let snapshot = settings
      isTesting = true
      message = nil
      succeeded = false
      Task { @MainActor in
        do {
          let result = try await appState.checkASRConfiguration(
            endpoint: snapshot.asrEndpoint,
            model: snapshot.asrModel,
            apiKey: snapshot.asrAPIKey,
            language: snapshot.language,
            includeTimestamps: snapshot.includeTranscriptTimestamps
          )
          let host = URL(string: snapshot.asrEndpoint)?.host ?? snapshot.asrEndpoint
          message = "已连接 \(host)（HTTP \(result.statusCode)）；测试音频未保存。"
          succeeded = true
          appState.presentActionFeedback(.success("转写 API 检查通过"))
        } catch {
          message = error.localizedDescription
          succeeded = false
          appState.presentActionFeedback(.failure("转写 API 检查失败：\(error.localizedDescription)"))
        }
        isTesting = false
      }
    }

    private func discoverModels() {
      let snapshot = settings
      Task { @MainActor in
        await appState.discoverASRModels(
          endpoint: snapshot.asrEndpoint, apiKey: snapshot.asrAPIKey)
      }
    }
  }

  private func endpointError(_ value: String, name: String) -> String? {
    let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else { return nil }
    guard let url = URL(string: value),
      let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
      url.host != nil
    else { return "\(name)接口地址必须是完整的 HTTP(S) URL。" }
    return nil
  }
}

private struct APIKeyField: View {
  @Binding var value: String
  @State private var isRevealed = false

  var body: some View {
    LabeledContent("API Key") {
      HStack(spacing: 8) {
        Group {
          if isRevealed {
            TextField("保存在 Keychain", text: $value)
          } else {
            SecureField("保存在 Keychain", text: $value)
          }
        }
        .textFieldStyle(.roundedBorder)
        .textContentType(.password)
        .frame(maxWidth: .infinity)

        Button {
          isRevealed.toggle()
        } label: {
          Image(systemName: isRevealed ? "eye.slash" : "eye")
        }
        .buttonStyle(.woiceBorderless)
        .controlSize(.small)
        .accessibilityLabel(isRevealed ? "隐藏 API Key" : "显示 API Key")
        .help(isRevealed ? "隐藏 API Key" : "显示 API Key")
      }
    }
  }
}

private struct StorageSettingsPane: View {
  @Binding var settings: AppSettings
  let store: WorkspaceStore

  var body: some View {
    Form {
      Section {
        SettingsBanner(
          title: "文件由你掌控",
          message: "原始音频和原始转录保留在本机；导出 Markdown 是派生副本，不会覆盖原始内容。",
          systemImage: "internaldrive"
        )
      }

      Section {
        #if WOICE_APP_STORE
          LabeledContent("Markdown 导出") {
            Text("导出时选择保存位置")
              .foregroundStyle(.secondary)
          }
        #else
          LabeledContent("Markdown 导出目录") {
            TextField("留空使用默认目录", text: $settings.exportDirectory)
              .textFieldStyle(.roundedBorder)
              .frame(minWidth: 360)
          }
        #endif
      } header: {
        Label("导出", systemImage: "square.and.arrow.down")
      } footer: {
        #if WOICE_APP_STORE
          Text("每次导出都使用 macOS 标准“另存为”面板；导出不会覆盖原始素材。")
        #else
          Text("导出不会删除或覆盖原始 WAV 和原始转录。")
        #endif
      }

      Section {
        storagePath("原始录音", url: store.recordingsURL)
        storagePath("工作区", url: store.rootURL)
      } header: {
        Label("本机存储", systemImage: "internaldrive")
      } footer: {
        Text("录音文件在停止录音后立即写入本机；历史记录只引用这些文件，不把音频放进云端。")
      }

      Section {
        LabeledContent("版本") {
          Text(WoiceAppVersion.display)
            .font(.callout.monospacedDigit())
            .textSelection(.enabled)
        }
        Label(
          "反馈问题时请同时提供版本号和 Build，便于定位本机模型与设置差异。",
          systemImage: "info.circle"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      } header: {
        Label("Woice 版本", systemImage: "app.badge")
      }
    }
    .formStyle(.grouped)
    .padding(.top, 12)
  }

  private func storagePath(_ title: String, url: URL) -> some View {
    LabeledContent(title) {
      Text(url.path)
        .font(.caption)
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
        .multilineTextAlignment(.trailing)
    }
  }

}
