@preconcurrency import AVFoundation
import AppKit
import CryptoKit
import Foundation
import Observation
import WoiceCore

enum ExternalProcessingKind: Equatable {
  case transcription
  case segmentTranscription
  case languageModel

  var title: String {
    switch self {
    case .transcription: "发送录音并转写"
    case .segmentTranscription: "发送声音片段并转写"
    case .languageModel: "发送原文并生成笔记"
    }
  }

  var dataDescription: String {
    switch self {
    case .transcription: "原始录音（WAV）"
    case .segmentTranscription: "检测到声音的分段 WAV"
    case .languageModel: "原始转录文本"
    }
  }

  var taskKind: ProcessingTaskKind {
    switch self {
    case .transcription: .transcription
    case .segmentTranscription: .segmentTranscription
    case .languageModel: .languageModel
    }
  }
}

struct ExternalProcessingRequest: Identifiable {
  let id = UUID()
  let recordID: UUID
  let kind: ExternalProcessingKind
  let host: String
  let endpoint: String
  let apiKey: String
  let model: String
  let language: String
  let includeTranscriptTimestamps: Bool
  let sourceTrack: AudioTrackKind?

  var dataDescription: String {
    if let sourceTrack {
      switch sourceTrack {
      case .meetingMix: return "会议合成音频（WAV）"
      case .microphone: return "麦克风原始录音（WAV）"
      case .systemAudio: return "电脑声音音轨（标准化 WAV）"
      }
    }
    return kind.dataDescription
  }

  var confirmationTitle: String {
    switch sourceTrack {
    case .meetingMix: "转写会议完整回放"
    case .microphone: "转写我的声音"
    case .systemAudio: "转写电脑声音"
    case nil:
      switch kind {
      case .transcription: "转写录音"
      case .segmentTranscription: "转写有声片段"
      case .languageModel: "生成文字笔记"
      }
    }
  }

  var confirmationMessage: String {
    "输入：\(userFacingDataDescription)\n目标：\(host) · 1 个文件 · 1 个请求\n录音已安全保存在本机；仅在你确认后才会发送。"
  }

  private var userFacingDataDescription: String {
    switch sourceTrack {
    case .meetingMix: "会议完整回放"
    case .microphone: "我的声音（麦克风）"
    case .systemAudio: "电脑声音"
    case nil:
      switch kind {
      case .transcription: "录音素材"
      case .segmentTranscription: "检测到的有声片段"
      case .languageModel: "原文"
      }
    }
  }
}

enum RecordingExportKind: CaseIterable, Identifiable {
  case microphoneAudio
  case systemAudio
  case meetingMixAudio
  case transcriptText
  case transcriptJSON
  case markdown

  var id: Self { self }

  var title: String {
    switch self {
    case .microphoneAudio: "麦克风原始音频"
    case .systemAudio: "电脑声音原始音频"
    case .meetingMixAudio: "会议合成音频"
    case .transcriptText: "原文 TXT"
    case .transcriptJSON: "时间戳 JSON"
    case .markdown: "Markdown"
    }
  }

  var systemImage: String {
    switch self {
    case .microphoneAudio: "waveform"
    case .systemAudio: "speaker.wave.2"
    case .meetingMixAudio: "waveform.and.mic"
    case .transcriptText: "doc.text"
    case .transcriptJSON: "curlybraces"
    case .markdown: "doc.richtext"
    }
  }
}

private struct ExportedTranscriptSegment: Codable {
  let start: TimeInterval
  let end: TimeInterval
  let text: String
  let sourceTrack: String?
}

private struct ExportedRecording: Codable {
  let id: UUID
  let createdAt: Date
  let duration: TimeInterval
  let transcript: String
  let segments: [ExportedTranscriptSegment]
  let audioFiles: [String: String]
  let materialStatus: RecordingMaterialStatus
  let activeTranscriptArtifactID: UUID?
  let transcriptArtifacts: [TranscriptArtifact]
  let sourceKind: RecordingSourceKind
  let originalMediaFileName: String?
  let originalMediaSHA256: String?
}

enum BackgroundTranscriptionState: Equatable, Sendable {
  case disabled
  case waiting
  case transcribing(segment: Int)
  case completed(count: Int)
  case failed(segment: Int, message: String)

  var label: String {
    switch self {
    case .disabled: "录音结束后转写"
    case .waiting: "等待声音片段"
    case .transcribing(let segment): "后台转写第 \(segment + 1) 段"
    case .completed(let count): "已后台转写 \(count) 段"
    case .failed(let segment, _): "第 \(segment + 1) 段后台转写失败"
    }
  }

  var systemImage: String {
    switch self {
    case .disabled: "clock"
    case .waiting: "hourglass"
    case .transcribing: "arrow.triangle.2.circlepath"
    case .completed: "checkmark.circle"
    case .failed: "exclamationmark.triangle"
    }
  }

  var isFailure: Bool {
    if case .failed = self { return true }
    return false
  }
}

@MainActor
@Observable
final class AppState {
  var settings: AppSettings
  var recordings: [RecordingRecord]
  var processingState: ProcessingState = .ready
  var errorMessage: String?
  var actionFeedback: ActionFeedback?
  var isShowingOnboarding = false
  var pendingExternalProcessing: ExternalProcessingRequest?
  var elapsed: TimeInterval = 0
  var inputLevel: Float = 0
  var receivedBufferCount = 0
  var audioActivity: AudioActivityState = .waiting
  var audioSegmentCount = 0
  var voiceDuration: TimeInterval = 0
  var liveTranscript = ""
  var liveTranscriptionState: LiveTranscriptionState = .disabled
  var backgroundTranscriptionState: BackgroundTranscriptionState = .disabled
  var backgroundTranscript = ""
  var modelPackInventory: [ModelPackInventoryEntry] = []
  var asrProviderInventory: [ASRProviderDescriptor] = ASRProviderDescriptor.builtIns
  var discoveredASRModels: [ASRDiscoveredModel] = []
  var isDiscoveringASRModels = false
  var asrDiscoveryMessage: String?
  var modelDownloadTasks: [ModelDownloadTask] = []
  var modelDownloadProgress: ModelPackDownloadProgress?
  var isDownloadingModel = false
  var modelCatalogState: ModelCatalogRuntimeState = .unavailable
  var verifiedModelCatalogEntries: [ModelPackManifest] = []
  var agentDispatchJobs: [AgentDispatchJob]
  private(set) var agentAuditEvents: [AgentAuditEvent]
  private(set) var piConnectorServer: PiConnectorServer?

  let store: WorkspaceStore
  let recorder: RecordingService
  let systemAudioCapability = SystemAudioCapabilityService()
  let textInsertion = TextInsertionService()
  let systemAudioRecorder: SystemAudioCaptureService
  let liveTranscription = LiveTranscriptionService()
  private(set) var localTranscription: LocalASRTranscribing
  let modelPackStore: ModelPackStore
  let asrProviderRegistry = ASRProviderRegistry()
  private let keychain: any KeychainStoring
  private var loadedKeychainAccounts: Set<String> = []
  private let transcriptionClient: TranscriptionClient
  private let llmClient: LLMClient
  private let whisperKitModelInstaller: WhisperKitModelInstaller
  private let modelCatalogDownloader: ModelCatalogDownloadCoordinator
  private let modelCatalogConfiguration: ModelCatalogRuntimeConfiguration?
  private let modelCatalogFetcher = ModelCatalogFetcher()
  private let modelCatalogStore: ModelCatalogStore?
  private let leaseOwner = "woice-app-\(UUID().uuidString)"
  private let globalShortcutService = GlobalShortcutService()
  private var recordingTimerTask: Task<Void, Never>?
  private var queuedExternalProcessing: [ExternalProcessingRequest] = []
  /// Loopback services become eligible for automatic post-recording work only
  /// after the user explicitly runs the health check in Settings.
  private var verifiedLocalASRTrust: LocalASRTrustSnapshot?
  private var activeModelDownloadTaskID: UUID?
  @ObservationIgnored private var modelDownloadTask: Task<Void, Never>?
  private var systemAudioStartError: String?
  private(set) var globalShortcutError: String?
  private var activeRecordingID: UUID?
  private var recordingSessionStartedAt: Date?
  private var systemAudioStartedAt: Date?
  private var backgroundSegmentResults: [UUID: [Int: [TranscriptSegment]]] = [:]
  private var backgroundSegmentFailures: [UUID: Set<Int>] = [:]
  private var backgroundTranscriptionChain: Task<Void, Never>?
  private var activeLocalTranscriptionIDs: Set<String> = []
  private var agentDispatchCancellations: [UUID: ControlledCLICancellation] = [:]
  @ObservationIgnored private var recordingLifecycleObservers: [NSObjectProtocol] = []
  private var isStoppingForRecordingInterruption = false
  @ObservationIgnored private var actionFeedbackTask: Task<Void, Never>?
  private let recycleMaterialDirectory: (URL) throws -> Void

  init(
    store: WorkspaceStore = WorkspaceStore(), recorder: RecordingService = RecordingService(),
    systemAudioRecorder: SystemAudioCaptureService = SystemAudioCaptureService(),
    transcriptionClient: TranscriptionClient = TranscriptionClient(),
    llmClient: LLMClient = LLMClient(),
    keychain: any KeychainStoring = KeychainStore(),
    localTranscription: LocalASRTranscribing? = nil,
    modelCatalogConfiguration: ModelCatalogRuntimeConfiguration? =
      ModelCatalogRuntimeConfiguration
      .fromBundle(),
    recycleMaterialDirectory: ((URL) throws -> Void)? = nil
  ) {
    self.store = store
    self.recorder = recorder
    self.systemAudioRecorder = systemAudioRecorder
    self.transcriptionClient = transcriptionClient
    self.llmClient = llmClient
    self.keychain = keychain
    self.recycleMaterialDirectory =
      recycleMaterialDirectory
      ?? { directory in
        var resultingURL: NSURL?
        try FileManager.default.trashItem(at: directory, resultingItemURL: &resultingURL)
      }
    let bundledModelsRoot = Bundle.main.resourceURL?.appendingPathComponent(
      "Models", isDirectory: true)
    self.modelPackStore = ModelPackStore(
      rootURL: store.rootURL, bundledRootURL: bundledModelsRoot)
    self.whisperKitModelInstaller = WhisperKitModelInstaller(
      rootURL: store.rootURL, modelStore: self.modelPackStore)
    self.modelCatalogDownloader = ModelCatalogDownloadCoordinator(
      rootURL: store.rootURL, modelStore: self.modelPackStore)
    self.modelCatalogConfiguration = modelCatalogConfiguration
    if let modelCatalogConfiguration {
      self.modelCatalogStore = try? ModelCatalogStore(
        storageURL: store.rootURL.appendingPathComponent("model-catalog-history.json"),
        catalogID: modelCatalogConfiguration.catalogID,
        trustedKeys: modelCatalogConfiguration.trustedKeys)
    } else {
      self.modelCatalogStore = nil
    }
    let loaded = store.loadSettings()
    self.localTranscription =
      localTranscription
      ?? Self.acceptanceFixtureProviderIfOptedIn()
      ?? WhisperKitTranscriptionService.defaultProvider(
        rootURL: store.rootURL,
        bundledRootURL: bundledModelsRoot,
        preferredPackID: loaded.selectedLocalModelPackID,
        preferredVersion: loaded.selectedLocalModelVersion)
    settings = loaded
    // Persist deterministic settings migrations (including the reliable
    // dual-track transcription strategy marker) once after decoding.
    try? store.saveSettings(loaded)
    recordings = store.loadRecordings()
    _ = try? store.recoverAgentDispatchJobs()
    agentDispatchJobs = store.loadAgentDispatchJobs()
    agentAuditEvents = store.loadAgentAuditEvents()
    verifiedLocalASRTrust = store.loadLocalASRTrust()
    if normalizeLegacyTranscriptSourceLabels() {
      _ = persistRecordings()
    }
    if let trust = verifiedLocalASRTrust, !isValidLocalASRTrust(trust, for: loaded) {
      verifiedLocalASRTrust = nil
      store.clearLocalASRTrust()
    }
    if normalizeLegacyMeetingTasks() {
      _ = persistRecordings()
    }
    recoverInterruptedRecordingSession()
    _ = try? store.recoverModelDownloadTasks()
    modelDownloadTasks = store.loadModelDownloadTasks()
    if let storageError = store.storageErrorDescription {
      errorMessage = "本地数据库需要检查：\(storageError)"
    }
    recoverInterruptedTasks()
    restoreQueuedProcessingAuthorization()
    isShowingOnboarding = loaded.asrEndpoint.isEmpty && recordings.isEmpty
    installRecordingLifecycleObservers()
    installGlobalShortcut()
    Task { @MainActor [weak self] in
      await self?.refreshModelPackInventory()
      await self?.refreshASRProviderInventory()
      await self?.loadLocalModelCatalog()
    }
  }

  private static func acceptanceFixtureProviderIfOptedIn() -> LocalASRTranscribing? {
    guard WoiceTestRuntimeConfiguration.usesFixtureTranscription else { return nil }
    return AcceptanceFixtureTranscriptionService()
  }

  var isRecording: Bool { recorder.isRecording }
  var isSystemAudioCapturing: Bool { systemAudioRecorder.isCapturing }
  var isBusy: Bool {
    switch processingState {
    case .authorizing, .transcribing, .generating, .awaitingAuthorization:
      true
    default:
      false
    }
  }

  @discardableResult
  func saveAgentDispatchJob(_ job: AgentDispatchJob) -> Bool {
    let previousJob = agentDispatchJobs.first(where: { $0.id == job.id })
    do {
      _ = try job.validated()
      if let index = agentDispatchJobs.firstIndex(where: { $0.id == job.id }) {
        agentDispatchJobs[index] = job
      } else {
        agentDispatchJobs.insert(job, at: 0)
      }
      try store.saveAgentDispatchJob(job)
      return true
    } catch {
      if let previousJob {
        agentDispatchJobs.removeAll { $0.id == job.id }
        agentDispatchJobs.append(previousJob)
        agentDispatchJobs.sort { $0.updatedAt > $1.updatedAt }
      } else {
        agentDispatchJobs.removeAll { $0.id == job.id }
      }
      errorMessage = error.localizedDescription
      return false
    }
  }

  @discardableResult
  func recordAgentAudit(_ event: AgentAuditEvent) -> Bool {
    do {
      _ = try event.validated()
      try store.saveAgentAuditEvent(event)
      agentAuditEvents.insert(event, at: 0)
      if agentAuditEvents.count > 1_000 {
        agentAuditEvents.removeLast(agentAuditEvents.count - 1_000)
      }
      return true
    } catch {
      errorMessage = "Agent 审计记录失败：\(error.localizedDescription)"
      return false
    }
  }

  /// Starts one explicit outbound handoff after the UI has shown the target,
  /// data types and permission summary. The actual CLI runs off the main actor;
  /// only durable state projections return to AppState.
  @discardableResult
  func dispatchToAgent(
    record: RecordingRecord,
    manifest: AgentCLIAdapterManifest,
    instruction: String,
    permissionLevel: AgentPermissionLevel = .createTasks
  ) async -> UUID? {
    let readableTranscript = TranscriptTextNormalizer.normalize(record.transcript ?? "")
    guard !readableTranscript.isEmpty else {
      presentActionFeedback(.failure("这条录音还没有可交给 Agent 的原文"))
      return nil
    }
    let trimmedInstruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedInstruction.isEmpty else {
      presentActionFeedback(.failure("请先填写要交给 Agent 的任务说明"))
      return nil
    }
    do {
      _ = try manifest.validated()
      guard permissionLevel == .createTasks,
        manifest.capabilities.contains(.receiveText),
        manifest.capabilities.contains(.returnText)
      else {
        presentActionFeedback(.failure("当前连接器只允许经过确认的创建任务，不允许控制录音或无结果派发"))
        return nil
      }
      let package = try ContextPackageBuilder().build(
        items: [
          ContextPackageBuildItem(
            reference: ContextArtifactReference(
              artifactID: "recording:\(record.id.uuidString):transcript",
              recordingID: record.id,
              kind: .transcript,
              timeRange: nil),
            text: readableTranscript)
        ],
        instruction: trimmedInstruction)
      let jobID = UUID()
      let job = AgentDispatchJob(
        id: jobID,
        idempotencyKey:
          "agent:\(manifest.id):\(record.id.uuidString):\(package.package.contentHash)",
        connectorID: manifest.id,
        connectorVersion: manifest.version,
        contextPackageID: package.package.id,
        instructionHash: sha256(Data(trimmedInstruction.utf8)),
        permissionSnapshotHash: sha256(
          Data(
            "outbound|\(permissionLevel.rawValue)|\(manifest.id)|\(record.id.uuidString)|text"
              .utf8)),
        traceID: UUID().uuidString,
        status: .queued)
      guard saveAgentDispatchJob(job) else {
        try? FileManager.default.removeItem(at: package.directoryURL)
        return nil
      }
      _ = recordAgentAudit(
        AgentAuditEvent(
          action: .dispatchRequested,
          caller: "local-user",
          connectorID: manifest.id,
          connectorVersion: manifest.version,
          jobID: jobID,
          traceID: job.traceID,
          parentJobID: job.parentJobID,
          hop: job.hop,
          artifactIDs: package.package.artifactRefs.map(\.artifactID),
          dataTypes: package.package.artifactRefs.map(\.kind)))
      let cancellation = ControlledCLICancellation()
      agentDispatchCancellations[jobID] = cancellation
      updateAgentDispatchJob(jobID: jobID, status: .launching)
      let service = AgentDispatchService()
      let rootURL = store.rootURL
      Task { @MainActor [weak self] in
        do {
          self?.updateAgentDispatchJob(jobID: jobID, status: .running)
          if let job = self?.agentDispatchJobs.first(where: { $0.id == jobID }) {
            _ = self?.recordAgentAudit(
              AgentAuditEvent(
                action: .dispatchStarted,
                caller: "local-user",
                connectorID: job.connectorID,
                connectorVersion: job.connectorVersion,
                jobID: job.id,
                traceID: job.traceID,
                parentJobID: job.parentJobID,
                hop: job.hop))
          }
          let execution = try await Task.detached(priority: .userInitiated) {
            try service.execute(
              manifest: manifest,
              package: package,
              parentRecordingID: record.id,
              rootURL: rootURL,
              cancellation: cancellation)
          }.value
          try? FileManager.default.removeItem(at: package.directoryURL)
          self?.updateAgentDispatchJob(
            jobID: jobID, status: .completed, resultArtifact: execution.artifact)
          if let job = self?.agentDispatchJobs.first(where: { $0.id == jobID }) {
            _ = self?.recordAgentAudit(
              AgentAuditEvent(
                action: .dispatchCompleted,
                caller: "local-user",
                connectorID: job.connectorID,
                connectorVersion: job.connectorVersion,
                jobID: job.id,
                traceID: job.traceID,
                parentJobID: job.parentJobID,
                hop: job.hop,
                artifactIDs: execution.artifact.parentArtifactIDs,
                resultArtifactID: execution.artifact.id,
                outcomeCode: "completed"))
          }
          self?.agentDispatchCancellations.removeValue(forKey: jobID)
          self?.presentActionFeedback(.success("Agent 任务已完成，结果已保存为新素材"))
        } catch {
          try? FileManager.default.removeItem(at: package.directoryURL)
          let cancelled = (error as? ControlledCLIRunnerError) == .cancelled
          self?.updateAgentDispatchJob(
            jobID: jobID,
            status: cancelled ? .cancelled : .failed,
            errorCode: cancelled ? .cancelled : self?.agentDispatchErrorCode(error),
            error: error.localizedDescription)
          if let job = self?.agentDispatchJobs.first(where: { $0.id == jobID }) {
            _ = self?.recordAgentAudit(
              AgentAuditEvent(
                action: cancelled ? .dispatchCancelled : .dispatchFailed,
                caller: "local-user",
                connectorID: job.connectorID,
                connectorVersion: job.connectorVersion,
                jobID: job.id,
                traceID: job.traceID,
                parentJobID: job.parentJobID,
                hop: job.hop,
                outcomeCode: self?.agentDispatchErrorCode(error).rawValue))
          }
          self?.agentDispatchCancellations.removeValue(forKey: jobID)
          self?.presentActionFeedback(
            .failure(cancelled ? "Agent 任务已取消" : "Agent 任务失败：\(error.localizedDescription)"))
        }
      }
      presentActionFeedback(.progress("已派发给 \(manifest.displayName)，正在等待结果"))
      return jobID
    } catch {
      errorMessage = error.localizedDescription
      presentActionFeedback(.failure("创建 Agent 任务失败：\(error.localizedDescription)"))
      return nil
    }
  }

  @discardableResult
  func cancelAgentDispatch(jobID: UUID) -> Bool {
    guard let cancellation = agentDispatchCancellations[jobID] else {
      presentActionFeedback(.failure("这条 Agent 任务当前不可取消"))
      return false
    }
    cancellation.cancel()
    presentActionFeedback(.progress("正在取消 Agent 任务"))
    return true
  }

  func agentResultURL(for artifact: AgentResultArtifact) -> URL {
    store.agentResultURL(for: artifact)
  }

  private func updateAgentDispatchJob(
    jobID: UUID,
    status: AgentDispatchStatus,
    resultArtifact: AgentResultArtifact? = nil,
    errorCode: AgentDispatchErrorCode? = nil,
    error: String? = nil
  ) {
    guard var job = agentDispatchJobs.first(where: { $0.id == jobID }) else { return }
    job.status = status
    job.updatedAt = Date()
    if let resultArtifact { job.resultArtifact = resultArtifact }
    job.lastErrorCode = errorCode
    job.lastError = error
    _ = saveAgentDispatchJob(job)
  }

  private func agentDispatchErrorCode(_ error: Error) -> AgentDispatchErrorCode {
    switch error {
    case ControlledCLIRunnerError.executableMissing: .notInstalled
    case ControlledCLIRunnerError.rejectedTrust,
      ControlledCLIRunnerError.signatureVerificationFailed:
      .permissionDenied
    case ControlledCLIRunnerError.timedOut: .timedOut
    case ControlledCLIRunnerError.cancelled: .cancelled
    case ControlledCLIRunnerError.outputLimitExceeded: .outputLimitExceeded
    case ControlledCLIRunnerError.nonZeroExit: .crashed
    case AgentDispatchServiceError.unsupportedOutput: .invalidOutput
    case AgentDispatchServiceError.emptyOutput: .invalidOutput
    default: .invalidContract
    }
  }

  private func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  var globalShortcutInstalled: Bool { globalShortcutService.isInstalled }
  var globalShortcutCurrent: RecordingShortcut { globalShortcutService.currentShortcut }

  var localASRModel: ASRModelDescriptor { localTranscription.model }
  var isUsingLocalASR: Bool { shouldUseLocalASR }

  private func refreshASRProviderInventory() async {
    let localModelAvailable = localASRModel.providerID == "com.woice.whisperkit"
    do {
      let resolved = try await asrProviderRegistry.resolve(
        configuration: settings.asrConfiguration, localModelAvailable: localModelAvailable)
      try await asrProviderRegistry.updateHealth(
        providerID: resolved.providerID, health: resolved.health)
    } catch {
      // Inventory remains a safe, static description when a configured route
      // is unavailable; the processing path reports the actionable error.
    }
    asrProviderInventory = await asrProviderRegistry.snapshot()
    if !localModelAvailable,
      let speechIndex = asrProviderInventory.firstIndex(
        where: { $0.providerID == "com.apple.speech.on-device" })
    {
      var speech = asrProviderInventory[speechIndex]
      speech.health =
        localASRAuthorizationState == .authorized ? .ready : .authorizationRequired
      asrProviderInventory[speechIndex] = speech
    }
  }

  deinit {
    modelDownloadTask?.cancel()
    for observer in recordingLifecycleObservers {
      NotificationCenter.default.removeObserver(observer)
    }
  }

  var localASRAuthorizationState: LocalASRAuthorizationState {
    (localTranscription as? LocalASRAuthorizationProviding)?.authorizationState ?? .notRequired
  }

  /// Reads API keys only after a user-visible services action or immediately
  /// before an external request. Ordinary startup and recording/file settings
  /// remain independent of Keychain access.
  @discardableResult
  func loadKeychainSecretsIfNeeded() -> Bool {
    let asrLoaded = loadKeychainSecret(account: "asr-api-key")
    let llmLoaded = loadKeychainSecret(account: "llm-api-key")
    return asrLoaded || llmLoaded
  }

  private func loadKeychainSecret(account: String) -> Bool {
    guard loadedKeychainAccounts.insert(account).inserted else { return false }
    switch account {
    case "asr-api-key" where settings.asrAPIKey.isEmpty:
      settings.asrAPIKey = keychain.read(account: account)
    case "llm-api-key" where settings.llmAPIKey.isEmpty:
      settings.llmAPIKey = keychain.read(account: account)
    default:
      break
    }
    return true
  }

  func requestLocalASRAuthorization() async {
    _ = await (localTranscription as? LocalASRAuthorizationProviding)?.requestAuthorization()
    await refreshASRProviderInventory()
  }

  func refreshModelPackInventory() async {
    do {
      modelPackInventory = try await modelPackStore.inventory()
    } catch {
      errorMessage = "模型库存读取失败：\(error.localizedDescription)"
    }
  }

  var canUpdateModelCatalog: Bool {
    modelCatalogConfiguration != nil && modelCatalogStore != nil
  }

  private func loadLocalModelCatalog() async {
    guard let modelCatalogStore else { return }
    modelCatalogState = .loadingLocal
    do {
      if let catalog = try await modelCatalogStore.load() {
        modelCatalogState = .ready(version: catalog.catalogVersion)
        verifiedModelCatalogEntries = catalog.entries
      } else {
        modelCatalogState = .unavailable
        verifiedModelCatalogEntries = []
      }
    } catch {
      modelCatalogState = .failed(error.localizedDescription)
    }
  }

  /// Updates the signed Catalog only after an explicit user action. The
  /// fetched bytes are verified and committed before any model download can
  /// consume them; failures preserve the last accepted snapshot.
  @discardableResult
  func refreshModelCatalog() async -> Bool {
    guard let configuration = modelCatalogConfiguration, let modelCatalogStore else {
      modelCatalogState = .unavailable
      presentActionFeedback(.failure("当前发行包未配置模型清单更新"))
      return false
    }
    modelCatalogState = .updating
    do {
      let data = try await modelCatalogFetcher.fetch(
        from: configuration.url, policy: configuration.policy)
      let catalog = try await modelCatalogStore.accept(data: data)
      modelCatalogState = .ready(version: catalog.catalogVersion)
      verifiedModelCatalogEntries = catalog.entries
      errorMessage = nil
      presentActionFeedback(.success("模型清单已验证更新到 v\(catalog.catalogVersion)"))
      return true
    } catch {
      modelCatalogState = .failed(error.localizedDescription)
      errorMessage = "模型清单更新失败：\(error.localizedDescription)；当前模型和录音未改变。"
      presentActionFeedback(.failure("模型清单更新失败"))
      return false
    }
  }

  func refreshModelDownloadTasks() {
    modelDownloadTasks = store.loadModelDownloadTasks()
  }

  var isRecommendedWhisperKitModelInstalled: Bool {
    isModelPackInstalled(entry: .recommendedTiny)
  }

  func isModelPackInstalled(entry: WhisperKitModelCatalogEntry) -> Bool {
    modelPackInventory.contains {
      $0.manifest.packID == entry.packID && $0.manifest.version == entry.modelRevision
    }
  }

  func isDownloadingModel(entry: WhisperKitModelCatalogEntry) -> Bool {
    guard isDownloadingModel, let activeModelDownloadTaskID else { return false }
    guard let task = modelDownloadTasks.first(where: { $0.id == activeModelDownloadTaskID }) else {
      return false
    }
    return task.packID == entry.packID && task.version == entry.modelRevision
  }

  /// Explicitly downloads the pinned official model. The download itself is
  /// kept outside the recording path; only an atomically verified pack can
  /// replace the current local ASR provider.
  func downloadRecommendedWhisperKitModel() async -> Bool {
    await downloadWhisperKitModel(entry: .recommendedTiny)
  }

  /// Starts a user-visible download task that can be cancelled from Settings.
  /// The existing async method remains available for acceptance tests and
  /// callers that already own their Task handle.
  func startWhisperKitModelDownload(entry: WhisperKitModelCatalogEntry) {
    guard modelDownloadTask == nil, !isDownloadingModel else { return }
    modelDownloadTask = Task { @MainActor [weak self] in
      guard let self else { return }
      _ = await self.downloadWhisperKitModel(entry: entry)
      self.modelDownloadTask = nil
    }
  }

  func cancelWhisperKitModelDownload() {
    guard isDownloadingModel else { return }
    modelDownloadTask?.cancel()
  }

  /// Downloads a catalogued model after an explicit user action. The entry is
  /// never inferred from a model ID typed into a field.
  func downloadWhisperKitModel(entry: WhisperKitModelCatalogEntry) async -> Bool {
    if let catalog = await verifiedCatalog(containing: entry) {
      return await downloadVerifiedCatalogModel(
        catalog: catalog, packID: entry.packID, version: entry.modelRevision)
    }
    guard !isDownloadingModel else { return false }
    isDownloadingModel = true
    modelDownloadProgress = nil
    errorMessage = nil
    let catalog = entry
    let taskID: UUID
    do {
      if let existing = modelDownloadTasks.first(where: {
        $0.packID == catalog.packID && $0.version == catalog.modelRevision
      }) {
        taskID = existing.id
      } else {
        taskID = UUID()
      }
      let task =
        try ModelDownloadTask(
          id: taskID,
          packID: catalog.packID,
          version: catalog.modelRevision,
          state: .downloading,
          completedBytes: modelDownloadTasks.first(where: { $0.id == taskID })?.completedBytes ?? 0,
          totalBytes: catalog.estimatedBytes,
          stagingPath: store.rootURL.appendingPathComponent(
            "downloads/\(catalog.packID)-\(catalog.modelRevision).hub-cache"
          ).path,
          lastError: nil,
          createdAt: modelDownloadTasks.first(where: { $0.id == taskID })?.createdAt ?? Date(),
          updatedAt: Date())
      try store.saveModelDownloadTask(task)
      modelDownloadTasks = store.loadModelDownloadTasks()
      activeModelDownloadTaskID = taskID
    } catch {
      isDownloadingModel = false
      errorMessage = "模型下载任务无法保存：\(error.localizedDescription)；当前本机模型和录音未改变。"
      presentActionFeedback(.failure("模型下载任务保存失败"))
      return false
    }
    defer {
      isDownloadingModel = false
      activeModelDownloadTaskID = nil
      if modelDownloadProgress?.fractionCompleted == 1 { modelDownloadProgress = nil }
    }
    do {
      let result = try await whisperKitModelInstaller.install(
        entry: catalog,
        progress: { [weak self] progress in
          Task { @MainActor [weak self] in
            self?.updateModelDownloadProgress(progress, taskID: taskID, entry: catalog)
          }
        })
      let provider = try WhisperKitTranscriptionService(
        manifest: result.manifest, modelFolder: result.installedURL)
      var updatedSettings = settings
      updatedSettings.selectedLocalModelPackID = result.manifest.packID
      updatedSettings.selectedLocalModelVersion = result.manifest.version
      updatedSettings.asrProviderSelection = .onDevice
      try store.saveSettings(updatedSettings)
      localTranscription = provider
      settings = updatedSettings
      withdrawExternalASRRequestsForLocalRoute()
      try updateModelDownloadTask(
        id: taskID, state: .installed, completedBytes: catalog.estimatedBytes, lastError: nil)
      await refreshModelPackInventory()
      await refreshASRProviderInventory()
      errorMessage = nil
      presentActionFeedback(.success("模型已下载并安装"))
      return true
    } catch is CancellationError {
      _ = try? updateModelDownloadTask(
        id: taskID, state: .paused, completedBytes: currentDownloadBytes(taskID: taskID),
        lastError: "用户取消下载；点击继续即可恢复。")
      errorMessage = "模型下载已取消；当前本机模型和录音未改变。"
      presentActionFeedback(.failure("模型下载已取消"))
      return false
    } catch {
      _ = try? updateModelDownloadTask(
        id: taskID, state: .failed, completedBytes: currentDownloadBytes(taskID: taskID),
        lastError: error.localizedDescription)
      errorMessage = "模型下载失败：\(error.localizedDescription)；当前本机模型和录音未改变。"
      presentActionFeedback(.failure("模型下载失败：\(error.localizedDescription)"))
      return false
    }
  }

  /// Consumes only the last locally verified Catalog snapshot. If a matching
  /// entry exists, the generic downloader is mandatory; the legacy pinned
  /// WhisperKit Hub installer is used only when no Catalog entry is present.
  private func verifiedCatalog(containing entry: WhisperKitModelCatalogEntry) async
    -> ModelCatalog?
  {
    guard let modelCatalogStore else { return nil }
    guard let catalog = await modelCatalogStore.snapshot(),
      catalog.entries.contains(where: {
        $0.packID == entry.packID && $0.version == entry.modelRevision
      })
    else { return nil }
    return catalog
  }

  /// Downloads one signed Catalog entry through the generic multi-file
  /// coordinator, then activates it only after ModelPackStore commits the
  /// verified directory and current pointer.
  private func downloadVerifiedCatalogModel(
    catalog: ModelCatalog, packID: String, version: String? = nil
  ) async -> Bool {
    guard let configuration = modelCatalogConfiguration else {
      errorMessage = "当前发行包未配置模型下载策略；当前模型和录音未改变。"
      presentActionFeedback(.failure("模型下载策略不可用"))
      return false
    }
    guard
      let manifest = catalog.entries.first(where: {
        $0.packID == packID && (version == nil || $0.version == version)
      })
    else {
      errorMessage = "模型清单中找不到所选模型；当前模型和录音未改变。"
      presentActionFeedback(.failure("找不到模型清单条目"))
      return false
    }
    guard manifest.providerID == "com.woice.whisperkit" else {
      errorMessage = "当前版本暂不支持该模型 Provider：\(manifest.providerID)。"
      presentActionFeedback(.failure("模型 Provider 暂不支持"))
      return false
    }
    guard !isDownloadingModel else { return false }
    isDownloadingModel = true
    modelDownloadProgress = nil
    errorMessage = nil
    let taskID: UUID
    do {
      if let existing = modelDownloadTasks.first(where: {
        $0.packID == manifest.packID && $0.version == manifest.version
      }) {
        taskID = existing.id
      } else {
        taskID = UUID()
      }
      let task = try ModelDownloadTask(
        id: taskID,
        packID: manifest.packID,
        version: manifest.version,
        state: .downloading,
        completedBytes: modelDownloadTasks.first(where: { $0.id == taskID })?.completedBytes ?? 0,
        totalBytes: manifest.size,
        stagingPath: store.rootURL.appendingPathComponent(
          "downloads/\(manifest.packID)-\(manifest.version).partial"
        ).path,
        lastError: nil,
        createdAt: modelDownloadTasks.first(where: { $0.id == taskID })?.createdAt ?? Date(),
        updatedAt: Date())
      try store.saveModelDownloadTask(task)
      modelDownloadTasks = store.loadModelDownloadTasks()
      activeModelDownloadTaskID = taskID
    } catch {
      isDownloadingModel = false
      errorMessage = "模型下载任务无法保存：\(error.localizedDescription)；当前模型和录音未改变。"
      presentActionFeedback(.failure("模型下载任务保存失败"))
      return false
    }
    defer {
      isDownloadingModel = false
      activeModelDownloadTaskID = nil
      if modelDownloadProgress?.fractionCompleted == 1 { modelDownloadProgress = nil }
    }
    do {
      let result = try await modelCatalogDownloader.download(
        catalog: catalog,
        packID: manifest.packID,
        version: manifest.version,
        allowedHosts: configuration.modelDownloadAllowedHosts,
        progress: { [weak self] progress in
          Task { @MainActor [weak self] in
            self?.updateModelDownloadProgress(
              progress, taskID: taskID, totalBytes: manifest.size)
          }
        })
      let provider = try WhisperKitTranscriptionService(
        manifest: manifest, modelFolder: result)
      var updatedSettings = settings
      updatedSettings.selectedLocalModelPackID = manifest.packID
      updatedSettings.selectedLocalModelVersion = manifest.version
      updatedSettings.asrProviderSelection = .onDevice
      try store.saveSettings(updatedSettings)
      localTranscription = provider
      settings = updatedSettings
      withdrawExternalASRRequestsForLocalRoute()
      try updateModelDownloadTask(
        id: taskID, state: .installed, completedBytes: manifest.size, lastError: nil)
      await refreshModelPackInventory()
      await refreshASRProviderInventory()
      presentActionFeedback(.success("模型已下载并安装"))
      return true
    } catch is CancellationError {
      _ = try? updateModelDownloadTask(
        id: taskID, state: .paused, completedBytes: currentDownloadBytes(taskID: taskID),
        lastError: "用户取消下载；点击继续即可恢复。")
      errorMessage = "模型下载已取消；当前本机模型和录音未改变。"
      presentActionFeedback(.failure("模型下载已取消"))
      return false
    } catch {
      _ = try? updateModelDownloadTask(
        id: taskID, state: .failed, completedBytes: currentDownloadBytes(taskID: taskID),
        lastError: error.localizedDescription)
      errorMessage = "模型下载失败：\(error.localizedDescription)；当前本机模型和录音未改变。"
      presentActionFeedback(.failure("模型下载失败：\(error.localizedDescription)"))
      return false
    }
  }

  /// UI convenience that resolves only the locally verified Catalog snapshot;
  /// it never fetches or trusts a new Catalog implicitly.
  func downloadVerifiedCatalogModel(packID: String, version: String) async -> Bool {
    guard let catalog = await modelCatalogStore?.snapshot() else {
      errorMessage = "没有可用的已验证模型清单；当前模型和录音未改变。"
      presentActionFeedback(.failure("模型清单不可用"))
      return false
    }
    return await downloadVerifiedCatalogModel(
      catalog: catalog, packID: packID, version: version)
  }

  func isDownloadingModel(packID: String, version: String) -> Bool {
    guard isDownloadingModel, let activeModelDownloadTaskID else { return false }
    return modelDownloadTasks.contains {
      $0.id == activeModelDownloadTaskID && $0.packID == packID && $0.version == version
    }
  }

  private func updateModelDownloadProgress(
    _ progress: ModelPackDownloadProgress,
    taskID: UUID,
    entry: WhisperKitModelCatalogEntry
  ) {
    updateModelDownloadProgress(progress, taskID: taskID, totalBytes: entry.estimatedBytes)
  }

  private func updateModelDownloadProgress(
    _ progress: ModelPackDownloadProgress,
    taskID: UUID,
    totalBytes: Int64
  ) {
    guard activeModelDownloadTaskID == taskID else { return }
    modelDownloadProgress = progress
    let total = modelDownloadTasks.first(where: { $0.id == taskID })?.totalBytes ?? totalBytes
    let completed = Int64(Double(total) * progress.fractionCompleted)
    let state: ModelInstallationState = progress.filePath == "清单校验" ? .verifying : .downloading
    _ = try? updateModelDownloadTask(
      id: taskID, state: state, completedBytes: completed, lastError: nil)
  }

  private func currentDownloadBytes(taskID: UUID) -> Int64 {
    modelDownloadTasks.first(where: { $0.id == taskID })?.completedBytes ?? 0
  }

  @discardableResult
  private func updateModelDownloadTask(
    id: UUID,
    state: ModelInstallationState,
    completedBytes: Int64,
    lastError: String?
  ) throws -> ModelDownloadTask {
    guard let old = modelDownloadTasks.first(where: { $0.id == id }) else {
      throw WoiceError.storageFailure("找不到模型下载任务。")
    }
    let task = try ModelDownloadTask(
      id: old.id,
      packID: old.packID,
      version: old.version,
      state: state,
      completedBytes: min(old.totalBytes, max(0, completedBytes)),
      totalBytes: old.totalBytes,
      stagingPath: old.stagingPath,
      lastError: lastError,
      createdAt: old.createdAt,
      updatedAt: Date())
    try store.saveModelDownloadTask(task)
    modelDownloadTasks = store.loadModelDownloadTasks()
    return task
  }

  /// Installs a user-selected, already downloaded model directory. This is
  /// deliberately explicit; no URL is fetched and no existing model is
  /// replaced until ModelPackStore has verified every file.
  func importModelPack(from sourceDirectory: URL) async -> Bool {
    do {
      let manifest = try await modelPackStore.loadManifest(from: sourceDirectory)
      let installedURL = try await modelPackStore.install(
        manifest: manifest, from: sourceDirectory)
      if manifest.providerID == "com.woice.whisperkit" {
        let provider = try WhisperKitTranscriptionService(
          manifest: manifest, modelFolder: installedURL)
        var updatedSettings = settings
        updatedSettings.selectedLocalModelPackID = manifest.packID
        updatedSettings.selectedLocalModelVersion = manifest.version
        updatedSettings.asrProviderSelection = .onDevice
        try store.saveSettings(updatedSettings)
        localTranscription = provider
        settings = updatedSettings
        withdrawExternalASRRequestsForLocalRoute()
      }
      await refreshModelPackInventory()
      await refreshASRProviderInventory()
      errorMessage = nil
      presentActionFeedback(.success("模型包已导入"))
      return true
    } catch {
      errorMessage = "模型安装失败：\(error.localizedDescription)；原有录音和模型未改变。"
      presentActionFeedback(.failure("模型包导入失败：\(error.localizedDescription)"))
      return false
    }
  }

  /// Pins the next local transcription to an already verified installed pack.
  /// The selection is separate from the pack's atomic current pointer so a
  /// user can keep a known-good older version while a newer pack is present.
  func selectInstalledModel(packID: String, version: String) async -> Bool {
    do {
      guard
        let item = try await modelPackStore.inventory().first(where: {
          $0.manifest.packID == packID && $0.manifest.version == version
        }),
        item.manifest.providerID == "com.woice.whisperkit"
      else {
        throw ModelPackStoreError.invalidManifest("找不到已安装的本机模型版本。")
      }
      let modelFolder =
        try await
        (item.location == .bundled
        ? modelPackStore.bundledDirectory(for: item.manifest)
        : modelPackStore.installedDirectory(for: item.manifest))
      let provider = try WhisperKitTranscriptionService(
        manifest: item.manifest, modelFolder: modelFolder)
      var updatedSettings = settings
      updatedSettings.selectedLocalModelPackID = packID
      updatedSettings.selectedLocalModelVersion = version
      updatedSettings.asrProviderSelection = .onDevice
      try store.saveSettings(updatedSettings)
      localTranscription = provider
      settings = updatedSettings
      withdrawExternalASRRequestsForLocalRoute()
      await refreshModelPackInventory()
      await refreshASRProviderInventory()
      errorMessage = nil
      presentActionFeedback(.success("已切换本机模型版本"))
      return true
    } catch {
      errorMessage = "本机模型切换失败：\(error.localizedDescription)；当前模型和录音未改变。"
      presentActionFeedback(.failure("模型切换失败：\(error.localizedDescription)"))
      return false
    }
  }

  @discardableResult
  func deleteInstalledModel(packID: String, version: String) async -> Bool {
    do {
      let item = try await modelPackStore.inventory().first(where: {
        $0.manifest.packID == packID && $0.manifest.version == version
      })
      guard let item, item.location == .downloaded else {
        throw ModelPackStoreError.invalidManifest("只能删除已下载的模型版本。")
      }
      guard !item.isCurrent else {
        throw ModelPackStoreError.cannotDeleteCurrent(packID + "/" + version)
      }
      guard
        localASRModel.modelID != item.manifest.modelID
          || localASRModel.version != item.manifest.version
      else {
        throw ModelPackStoreError.cannotDeleteCurrent(packID + "/" + version)
      }
      try await modelPackStore.deleteDownloaded(manifest: item.manifest)
      await refreshModelPackInventory()
      presentActionFeedback(.success("已删除模型版本"))
      return true
    } catch {
      errorMessage = "模型删除失败：\(error.localizedDescription)；录音和已有转写未改变。"
      presentActionFeedback(.failure("模型删除失败：\(error.localizedDescription)"))
      return false
    }
  }

  /// A recording can always be preserved. The route is actionable when the
  /// local model is selected or an external endpoint is available; failures
  /// are reported after the durable WAV exists.
  var canTranscribe: Bool { shouldUseLocalASR || hasExternalASR }

  private var canRunBackgroundLocalASR: Bool {
    guard shouldUseLocalASR else { return false }
    guard let authorizationProvider = localTranscription as? LocalASRAuthorizationProviding
    else { return true }
    return authorizationProvider.authorizationState == .authorized
  }

  private func enqueueBackgroundSegment(_ segment: RecordedAudioSegment, recordID: UUID) {
    guard activeRecordingID == recordID, canRunBackgroundLocalASR else { return }
    let previous = backgroundTranscriptionChain
    backgroundTranscriptionChain = Task { @MainActor [weak self] in
      _ = await previous?.value
      guard let self, self.activeRecordingID == recordID else { return }
      await self.transcribeBackgroundSegment(segment, recordID: recordID)
    }
  }

  private func transcribeBackgroundSegment(
    _ segment: RecordedAudioSegment, recordID: UUID
  ) async {
    guard FileManager.default.fileExists(atPath: segment.url.path) else {
      backgroundSegmentFailures[recordID, default: []].insert(segment.index)
      persistBackgroundTranscriptionJournal(recordID: recordID)
      backgroundTranscriptionState = .failed(
        segment: segment.index, message: "片段文件尚未固化。")
      return
    }
    backgroundTranscriptionState = .transcribing(segment: segment.index)
    do {
      let result = try await localTranscription.transcribe(
        audioURL: segment.url, language: settings.language)
      let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty else { throw LocalASRError.emptyResult }
      let derivedSegments: [TranscriptSegment]
      if result.segments.isEmpty {
        derivedSegments = [
          TranscriptSegment(
            start: segment.voiceSegment.start,
            end: segment.voiceSegment.end,
            text: text)
        ]
      } else {
        derivedSegments = result.segments.map { item in
          TranscriptSegment(
            start: segment.voiceSegment.start + max(0, item.start),
            end: segment.voiceSegment.start + max(item.start, item.end),
            text: item.text)
        }
      }
      backgroundSegmentResults[recordID, default: [:]][segment.index] = derivedSegments
      backgroundTranscript = backgroundSegmentResults[recordID, default: [:]]
        .values
        .flatMap { $0 }
        .sorted { $0.start < $1.start }
        .map(\.text)
        .joined(separator: "\n")
      persistBackgroundTranscriptionJournal(recordID: recordID)
      backgroundTranscriptionState = .completed(
        count: backgroundSegmentResults[recordID]?.count ?? 0)
    } catch {
      backgroundSegmentFailures[recordID, default: []].insert(segment.index)
      persistBackgroundTranscriptionJournal(recordID: recordID)
      backgroundTranscriptionState = .failed(
        segment: segment.index, message: error.localizedDescription)
    }
  }

  private func persistBackgroundTranscriptionJournal(recordID: UUID) {
    let journal = BackgroundTranscriptionJournal(
      recordID: recordID,
      results: backgroundSegmentResults[recordID] ?? [:],
      failedSegmentIndexes: Array(backgroundSegmentFailures[recordID] ?? []).sorted(),
      providerID: localASRModel.providerID,
      modelID: localASRModel.modelID,
      modelVersion: localASRModel.version,
      dataLocation: .onDevice,
      configurationHash: processingConfigurationHash(
        kind: .transcription,
        providerID: localASRModel.providerID,
        modelID: localASRModel.modelID,
        modelVersion: localASRModel.version,
        dataLocation: .onDevice,
        capability: .transcription,
        endpoint: nil,
        language: settings.language,
        includeTimestamps: settings.includeTranscriptTimestamps,
        sourceTrack: .microphone,
        meetingMode: settings.captureSystemAudio ? settings.meetingTranscriptionMode : nil))
    try? store.saveBackgroundTranscriptionJournal(journal)
  }

  private func backgroundTranscriptSnapshot(
    recordID: UUID
  ) -> (text: String, segments: [TranscriptSegment])? {
    let resultByIndex = backgroundSegmentResults[recordID] ?? [:]
    let segments = resultByIndex.values
      .flatMap { $0 }
      .sorted { $0.start < $1.start }
    guard !segments.isEmpty else { return nil }
    let text = segments.map(\.text).joined(separator: "\n")
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    return (text, segments)
  }

  private func backgroundTranscriptIfComplete(
    recordID: UUID, voiceSegments: [VoiceSegment]
  ) -> (text: String, segments: [TranscriptSegment])? {
    guard !voiceSegments.isEmpty,
      backgroundSegmentFailures[recordID, default: []].isEmpty,
      let resultByIndex = backgroundSegmentResults[recordID],
      resultByIndex.count == voiceSegments.count
    else { return nil }
    let segments = resultByIndex.values
      .flatMap { $0 }
      .sorted { $0.start < $1.start }
    guard !segments.isEmpty else { return nil }
    let text = segments.map(\.text).joined(separator: "\n")
    guard !text.isEmpty else { return nil }
    return (text, segments)
  }

  private func clearBackgroundState(for recordID: UUID, removeJournal: Bool = true) {
    backgroundSegmentResults.removeValue(forKey: recordID)
    backgroundSegmentFailures.removeValue(forKey: recordID)
    backgroundTranscriptionChain = nil
    activeRecordingID = nil
    let segmentDirectory = store.recordingsURL
      .appendingPathComponent("\(recordID.uuidString).segments", isDirectory: true)
    try? FileManager.default.removeItem(at: segmentDirectory)
    if removeJournal {
      store.clearBackgroundTranscriptionJournal(for: recordID)
    }
  }

  private var hasExternalASR: Bool {
    !settings.asrEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private var canAutoProcessLocalExternalASR: Bool {
    settings.asrProviderSelection == .external
      && hasExternalASR
      && dataLocation(for: settings.asrEndpoint) == .onDevice
      && localASRTrustMatchesCurrentSettings
  }

  private func normalizedEndpointKey(_ endpoint: String) -> String {
    let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let url = URL(string: trimmed),
      var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    else {
      return trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
    }
    components.user = nil
    components.password = nil
    components.query = nil
    components.fragment = nil
    components.scheme = components.scheme?.lowercased()
    components.host = components.host?.lowercased()
    return (components.string ?? trimmed)
      .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
      .lowercased()
  }

  private var localASRTrustMatchesCurrentSettings: Bool {
    guard settings.asrProviderSelection == .external,
      dataLocation(for: settings.asrEndpoint) == .onDevice,
      let trust = verifiedLocalASRTrust
    else { return false }
    return trust.matches(
      endpointIdentity: normalizedEndpointKey(settings.asrEndpoint),
      modelID: settings.asrModel,
      language: settings.language,
      includeTimestamps: settings.includeTranscriptTimestamps,
      configurationHash: localASRTrustConfigurationHash(
        endpoint: settings.asrEndpoint,
        model: settings.asrModel,
        language: settings.language,
        includeTimestamps: settings.includeTranscriptTimestamps))
  }

  private var shouldUseLocalASR: Bool {
    switch settings.asrProviderSelection {
    case .onDevice, .automatic: true
    case .external: false
    }
  }

  var pendingExternalProcessingCount: Int {
    (pendingExternalProcessing == nil ? 0 : 1) + queuedExternalProcessing.count
  }

  private func installGlobalShortcut() {
    globalShortcutError = nil
    do {
      try globalShortcutService.replace(with: settings.recordingShortcut, action: shortcutAction)
    } catch {
      globalShortcutError = error.localizedDescription
    }
  }

  private var shortcutAction: @Sendable () -> Void {
    { [weak self] in
      Task { @MainActor [weak self] in
        self?.toggleRecordingFromShortcut()
      }
    }
  }

  func toggleRecordingFromShortcut() {
    if recorder.isRecording {
      Task { await stopRecording() }
    } else {
      startRecording()
    }
  }

  private func installRecordingLifecycleObservers() {
    let center = NotificationCenter.default
    let configurationObserver = center.addObserver(
      forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.stopRecordingAfterInterruption("音频输入设备或权限发生变化")
      }
    }
    let sleepObserver = center.addObserver(
      forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.stopRecordingAfterInterruption("Mac 即将休眠")
      }
    }
    recordingLifecycleObservers = [configurationObserver, sleepObserver]
  }

  private func stopRecordingAfterInterruption(_ reason: String) {
    guard recorder.isRecording, !isStoppingForRecordingInterruption else { return }
    isStoppingForRecordingInterruption = true
    errorMessage = "\(reason)，正在保存已捕获的录音…"
    presentActionFeedback(.progress("录音被\(reason)，正在保存素材"))
    Task { @MainActor [weak self] in
      guard let self else { return }
      await stopRecording()
      if !recordings.isEmpty {
        errorMessage = "录音因\(reason)已停止；已捕获的音频已保存，可在详情页继续转写。"
        presentActionFeedback(.success("录音已停止并保存素材"))
      }
      isStoppingForRecordingInterruption = false
    }
  }

  func startPiConnector() throws {
    guard piConnectorServer == nil else { return }
    let socketURL = store.rootURL.appendingPathComponent("woice.sock")
    let server = PiConnectorServer(router: PiConnectorRouter(appState: self), socketURL: socketURL)
    try server.start()
    piConnectorServer = server
  }

  func startRecording() {
    guard !recorder.isRecording, !isBusy else { return }
    isShowingOnboarding = false
    errorMessage = nil
    systemAudioStartError = nil
    liveTranscript = ""
    backgroundTranscript = ""
    liveTranscriptionState = settings.enableLiveTranscription ? .requestingPermission : .disabled
    backgroundTranscriptionState = canRunBackgroundLocalASR ? .waiting : .disabled
    processingState = .authorizing
    let id = UUID()
    activeRecordingID = id
    let fileName = "\(id.uuidString).wav"
    let url = store.recordingsURL.appendingPathComponent(fileName)
    let systemAudioURL =
      settings.captureSystemAudio
      ? store.recordingsURL.appendingPathComponent("\(id.uuidString).caf") : nil
    let liveEnabled = settings.enableLiveTranscription
    let liveLanguage = settings.language
    let liveService = liveTranscription
    let backgroundEnabled = canRunBackgroundLocalASR
    recordingSessionStartedAt = Date()
    systemAudioStartedAt = nil
    do {
      try store.saveRecordingSession(
        RecordingSessionJournal(
          id: id,
          createdAt: recordingSessionStartedAt ?? Date(),
          audioFileName: fileName,
          systemAudioFileName: systemAudioURL?.lastPathComponent,
          captureSystemAudio: settings.captureSystemAudio,
          meetingTranscriptionMode: settings.meetingTranscriptionMode))
    } catch {
      activeRecordingID = nil
      recordingSessionStartedAt = nil
      processingState = .failed("录音会话无法持久化：\(error.localizedDescription)")
      errorMessage = "录音尚未开始：无法保存会话恢复信息。"
      return
    }
    let audioBufferObserver: (@Sendable (AVAudioPCMBuffer) -> Void)? =
      liveEnabled
      ? { @Sendable buffer in liveService.append(buffer) } : nil
    let segmentObserver: (@Sendable (RecordedAudioSegment) -> Void)? =
      backgroundEnabled
      ? { @Sendable segment in
        Task { @MainActor [weak self] in
          self?.enqueueBackgroundSegment(segment, recordID: id)
        }
      } : nil
    Task { @MainActor [weak self] in
      guard let self else { return }
      do {
        if liveEnabled {
          do {
            try await liveService.start(language: liveLanguage)
          } catch {
            self.liveTranscriptionState = liveService.snapshot().state
          }
        }
        try await recorder.start(
          to: url,
          audioBufferObserver: audioBufferObserver,
          segmentObserver: segmentObserver)
        var systemAudioError: String?
        if let systemAudioURL {
          do {
            try await systemAudioRecorder.start(to: systemAudioURL)
            systemAudioStartedAt = Date()
          } catch {
            systemAudioError = "系统音频未开始：\(error.localizedDescription)；麦克风仍会继续录音。"
          }
        }
        systemAudioStartError = systemAudioError
        elapsed = 0
        inputLevel = 0
        receivedBufferCount = 0
        audioActivity = .waiting
        audioSegmentCount = 0
        voiceDuration = 0
        processingState = .recording
        errorMessage = systemAudioError
        startRecordingTimer()
      } catch {
        if systemAudioRecorder.isCapturing { await systemAudioRecorder.cancel() }
        liveTranscription.cancel()
        liveTranscriptionState = .disabled
        recorder.cancel()
        store.clearRecordingSession()
        activeRecordingID = nil
        recordingSessionStartedAt = nil
        systemAudioStartedAt = nil
        backgroundTranscriptionState = .disabled
        stopRecordingTimer()
        processingState = .failed(error.localizedDescription)
        errorMessage = error.localizedDescription
      }
    }
  }

  func stopRecording() async {
    guard recorder.isRecording else { return }
    stopRecordingTimer()
    let systemAudioResult = await systemAudioRecorder.stop()
    let result = recorder.stop()
    let recordID =
      activeRecordingID
      ?? UUID(uuidString: result.url?.deletingPathExtension().lastPathComponent ?? "")
      ?? UUID()
    for segment in result.capturedSegments {
      enqueueBackgroundSegment(segment, recordID: recordID)
    }
    let liveResult = liveTranscription.finish()
    liveTranscript = liveResult.text
    liveTranscriptionState = liveResult.state
    var systemAudioError =
      systemAudioStartError
      ?? systemAudioResult.errorDescription
      ?? systemAudioDiagnostic(for: systemAudioResult)
    systemAudioStartError = nil
    let sessionStartedAt = recordingSessionStartedAt
    let systemStartedAt = systemAudioStartedAt
    recordingSessionStartedAt = nil
    systemAudioStartedAt = nil
    let hasUsableSystemAudio =
      settings.captureSystemAudio
      && systemAudioResult.hasAudibleSignal
      && systemAudioResult.url != nil
      && systemAudioResult.duration > 0.05
    elapsed = max(result.duration, hasUsableSystemAudio ? systemAudioResult.duration : 0)
    guard let url = result.url else {
      store.clearRecordingSession()
      clearBackgroundState(for: recordID)
      backgroundTranscriptionState = .disabled
      return
    }
    let microphoneFileIsUsable = isUsableAudioFile(at: url)
    if let writeError = recorder.lastWriteError {
      if !Self.shouldPreserveRecording(
        microphoneFileIsUsable: microphoneFileIsUsable,
        systemAudioIsUsable: hasUsableSystemAudio)
      {
        try? FileManager.default.removeItem(at: url)
        store.clearRecordingSession()
        processingState = .failed("录音文件写入失败：\(writeError)")
        errorMessage = "录音文件写入失败：\(writeError)"
        clearBackgroundState(for: recordID)
        return
      }
      if microphoneFileIsUsable {
        errorMessage = "录音写入中途出现问题，已保留可读取的部分音频：\(writeError)"
      }
    }
    if result.duration <= 0.05 || result.bufferCount == 0 {
      if !hasUsableSystemAudio {
        try? FileManager.default.removeItem(at: url)
        store.clearRecordingSession()
        processingState = .failed(WoiceError.noAudio.localizedDescription)
        errorMessage = WoiceError.noAudio.localizedDescription
        clearBackgroundState(for: recordID)
        return
      }
    }
    guard
      Self.shouldPreserveRecording(
        microphoneFileIsUsable: microphoneFileIsUsable,
        systemAudioIsUsable: hasUsableSystemAudio)
    else {
      try? FileManager.default.removeItem(at: url)
      store.clearRecordingSession()
      processingState = .failed(WoiceError.audioFileMissing.localizedDescription)
      errorMessage = WoiceError.audioFileMissing.localizedDescription
      clearBackgroundState(for: recordID)
      return
    }
    let noMicrophoneInput = result.peakLevel <= 0.0001
    let noMicrophoneInputMessage = "没有检测到麦克风输入，请检查系统输入设备和麦克风权限。"
    let voiceSegments = result.activity.segments.map { VoiceSegment(start: $0.start, end: $0.end) }
    await backgroundTranscriptionChain?.value
    let backgroundSnapshot: (text: String, segments: [TranscriptSegment])? =
      settings.captureSystemAudio && settings.meetingTranscriptionMode == .sourceSeparated
      ? nil
      : backgroundTranscriptSnapshot(recordID: recordID)
    let systemAudioStartOffset = sessionStartedAt.flatMap { sessionStart in
      systemStartedAt.map { max(0, $0.timeIntervalSince(sessionStart)) }
    }
    var meetingMixFileName: String?
    var meetingMixGenerationFailed = false
    if settings.captureSystemAudio, hasUsableSystemAudio,
      let systemAudioURL = systemAudioResult.url
    {
      let mixURL = store.recordingsURL.appendingPathComponent(
        "\(recordID.uuidString).meeting-mix.wav")
      do {
        _ = try AudioPreparationService.prepareMeetingMix(
          microphoneURL: microphoneFileIsUsable ? url : nil,
          systemAudioURL: systemAudioURL,
          outputURL: mixURL,
          microphoneStartOffset: 0,
          systemAudioStartOffset: systemAudioStartOffset ?? 0)
        meetingMixFileName = mixURL.lastPathComponent
      } catch {
        meetingMixGenerationFailed = true
        errorMessage = "会议合成音频生成失败：\(error.localizedDescription)；原始双音轨仍已保留。"
        let mixError = "会议回放生成失败：\(error.localizedDescription)"
        systemAudioError = [systemAudioError, mixError]
          .compactMap { $0 }
          .joined(separator: "；")
      }
    }
    let hasUsableInput = !noMicrophoneInput || hasUsableSystemAudio
    let systemAudioMissingMessage =
      settings.captureSystemAudio && !hasUsableSystemAudio
        && !noMicrophoneInput
      ? "未录到电脑声音，本次仅转写我的声音。"
      : nil
    let microphoneWriteError = recorder.lastWriteError.map {
      "麦克风原始音轨写入出现问题：\($0)；电脑声音音轨仍已保留。"
    }
    let transcriptionTrack: AudioTrackKind? =
      meetingMixFileName != nil
      ? .meetingMix
      : (noMicrophoneInput && hasUsableSystemAudio ? .systemAudio : .microphone)
    var sourceSeparatedTracks: [AudioTrackKind] = []
    if !noMicrophoneInput { sourceSeparatedTracks.append(.microphone) }
    if hasUsableSystemAudio { sourceSeparatedTracks.append(.systemAudio) }
    let taskTracks: [AudioTrackKind?] =
      settings.captureSystemAudio && settings.meetingTranscriptionMode == .sourceSeparated
      ? sourceSeparatedTracks.map(Optional.some)
      : [transcriptionTrack]
    let processingTasks: [ProcessingTask]
    if meetingMixGenerationFailed && settings.meetingTranscriptionMode == .standardMix {
      processingTasks = []
    } else if !hasUsableInput {
      processingTasks = []
    } else if shouldUseLocalASR || hasExternalASR {
      processingTasks = taskTracks.map { track in
        ProcessingTask(
          kind: .transcription,
          idempotencyKey: taskKey(recordID: recordID, kind: .transcription, sourceTrack: track),
          providerID: shouldUseLocalASR ? localASRModel.providerID : "openai-compatible.asr",
          modelID: shouldUseLocalASR ? localASRModel.modelID : settings.asrModel,
          modelVersion: shouldUseLocalASR ? localASRModel.version : nil,
          dataLocation: shouldUseLocalASR
            ? .onDevice : dataLocation(for: settings.asrEndpoint),
          capability: .transcription,
          configurationHash: processingConfigurationHash(
            kind: .transcription,
            providerID: shouldUseLocalASR ? localASRModel.providerID : "openai-compatible.asr",
            modelID: shouldUseLocalASR ? localASRModel.modelID : settings.asrModel,
            modelVersion: shouldUseLocalASR ? localASRModel.version : nil,
            dataLocation: shouldUseLocalASR
              ? .onDevice : dataLocation(for: settings.asrEndpoint),
            capability: .transcription,
            endpoint: shouldUseLocalASR ? nil : settings.asrEndpoint,
            language: settings.language,
            includeTimestamps: settings.includeTranscriptTimestamps,
            sourceTrack: track,
            meetingMode: settings.captureSystemAudio
              ? settings.meetingTranscriptionMode : nil),
          sourceTrack: track,
          meetingTranscriptionMode: settings.captureSystemAudio
            ? settings.meetingTranscriptionMode : nil
        )
      }
    } else {
      processingTasks = taskTracks.map { track in
        ProcessingTask(
          kind: .transcription,
          idempotencyKey: taskKey(recordID: recordID, kind: .transcription, sourceTrack: track),
          status: .waitingForModel,
          lastError: "还没有选择语言转文字模型；录音已安全保存在本机。",
          capability: .transcription,
          blockReason: .noModelSelected,
          sourceTrack: track,
          meetingTranscriptionMode: settings.captureSystemAudio
            ? settings.meetingTranscriptionMode : nil
        )
      }
    }
    let record = RecordingRecord(
      id: recordID,
      createdAt: Date(),
      audioFileName: url.lastPathComponent,
      duration: max(result.duration, hasUsableSystemAudio ? systemAudioResult.duration : 0),
      transcript: backgroundSnapshot?.text,
      generatedMarkdown: nil,
      processingError: hasUsableInput
        ? (microphoneWriteError ?? systemAudioMissingMessage)
        : noMicrophoneInputMessage,
      systemAudioFileName: systemAudioResult.url?.lastPathComponent,
      systemAudioError: systemAudioError
        ?? (settings.captureSystemAudio && systemAudioResult.bufferCount == 0
          ? "未检测到系统音频；请确认录音期间有正在播放的系统声音。" : nil),
      systemAudioBufferCount: settings.captureSystemAudio ? systemAudioResult.bufferCount : nil,
      systemAudioPeakLevel: settings.captureSystemAudio ? systemAudioResult.peakLevel : nil,
      systemAudioDuration: settings.captureSystemAudio ? systemAudioResult.duration : nil,
      systemAudioStartOffset: settings.captureSystemAudio ? systemAudioStartOffset : nil,
      meetingMixFileName: meetingMixFileName,
      meetingTranscriptionMode: settings.captureSystemAudio
        ? settings.meetingTranscriptionMode : nil,
      systemAudioCaptureTarget: settings.captureSystemAudio ? systemAudioResult.target : nil,
      transcriptSegments: backgroundSnapshot?.segments,
      processingTasks: hasUsableInput ? processingTasks : [],
      voiceSegments: voiceSegments.isEmpty ? nil : voiceSegments
    )
    recordings.insert(record, at: 0)
    let persisted = persistRecordings()
    if persisted { store.clearRecordingSession() }
    if !hasUsableInput {
      processingState = .failed(noMicrophoneInputMessage)
      errorMessage = noMicrophoneInputMessage
      clearBackgroundState(for: record.id, removeJournal: persisted)
      return
    }
    if let systemAudioMissingMessage {
      errorMessage = systemAudioMissingMessage
      presentActionFeedback(.progress(systemAudioMissingMessage))
    }
    if meetingMixGenerationFailed && settings.meetingTranscriptionMode == .standardMix {
      let message = "会议完整回放生成失败；两条原始音轨仍可分别播放，请重试合成或切换为来源分离。"
      updateRecord(id: record.id) { $0.processingError = message }
      processingState = .failed(message)
      errorMessage = message
      clearBackgroundState(for: record.id, removeJournal: persisted)
      return
    }
    if shouldUseLocalASR {
      if settings.captureSystemAudio,
        settings.meetingTranscriptionMode == .sourceSeparated
      {
        for track in sourceSeparatedTracks {
          await processLocalTranscription(for: record.id, sourceTrack: track)
        }
        clearBackgroundState(for: record.id, removeJournal: persisted)
      } else if meetingMixFileName == nil,
        let backgroundResult = backgroundTranscriptIfComplete(
          recordID: record.id, voiceSegments: voiceSegments)
      {
        appendTranscriptArtifact(
          recordID: record.id,
          text: backgroundResult.text,
          segments: backgroundResult.segments,
          sourceTrack: .microphone)
        updateProcessingTask(recordID: record.id, kind: .transcription) {
          $0.status = .completed
          $0.updatedAt = Date()
          $0.lastError = nil
        }
        if settings.autoCopyTranscript { copyTranscript(backgroundResult.text) }
        processingState = .saved
        errorMessage = nil
        clearBackgroundState(for: record.id, removeJournal: persisted)
      } else {
        await processLocalTranscription(for: record.id)
        clearBackgroundState(for: record.id, removeJournal: persisted)
      }
    } else if canAutoProcessLocalExternalASR {
      presentActionFeedback(
        .progress("正在使用本机服务转写\(transcriptionSourceDescription(transcriptionTrack))"))
      if settings.captureSystemAudio,
        settings.meetingTranscriptionMode == .sourceSeparated
      {
        for track in sourceSeparatedTracks {
          await transcribe(
            recordID: record.id, endpoint: settings.asrEndpoint, apiKey: settings.asrAPIKey,
            model: settings.asrModel, language: settings.language,
            includeSegments: settings.includeTranscriptTimestamps, sourceTrack: track)
        }
      } else {
        await transcribe(
          recordID: record.id, endpoint: settings.asrEndpoint, apiKey: settings.asrAPIKey,
          model: settings.asrModel, language: settings.language,
          includeSegments: settings.includeTranscriptTimestamps, sourceTrack: transcriptionTrack)
      }
      clearBackgroundState(for: record.id, removeJournal: persisted)
    } else if hasExternalASR {
      if settings.captureSystemAudio,
        settings.meetingTranscriptionMode == .sourceSeparated
      {
        for track in sourceSeparatedTracks {
          requestExternalProcessing(
            for: record.id, kind: .transcription, endpoint: settings.asrEndpoint,
            sourceTrack: track)
        }
      } else {
        requestExternalProcessing(
          for: record.id, kind: .transcription, endpoint: settings.asrEndpoint)
      }
      clearBackgroundState(for: record.id, removeJournal: persisted)
    } else {
      updateProcessingTask(recordID: record.id, kind: .transcription) {
        $0.status = .waitingForModel
        $0.blockReason = .noModelSelected
        $0.updatedAt = Date()
        $0.lastError = "还没有选择语言转文字模型；录音已安全保存在本机。"
      }
      processingState = .saved
      clearBackgroundState(for: record.id, removeJournal: persisted)
    }
  }

  func confirmExternalProcessing() async {
    guard let request = pendingExternalProcessing else { return }
    if request.kind == .segmentTranscription,
      let record = recordings.first(where: { $0.id == request.recordID }),
      hasActiveMainTranscription(for: record)
    {
      deferExternalProcessing()
      errorMessage = "主转写任务正在等待或运行，声音片段任务已暂存。"
      return
    }
    pendingExternalProcessing = nil
    defer { presentNextExternalProcessing() }
    let taskKind = request.kind.taskKind
    let idempotencyKey =
      recordings.first(where: { $0.id == request.recordID })?.processingTasks
      .first(where: {
        $0.kind == taskKind
          && (request.sourceTrack == nil || $0.sourceTrack == request.sourceTrack
            || (request.sourceTrack == .microphone && $0.sourceTrack == nil))
      })?.idempotencyKey
      ?? taskKey(
        recordID: request.recordID, kind: taskKind, sourceTrack: request.sourceTrack)
    do {
      guard try store.acquireJobLease(idempotencyKey: idempotencyKey, owner: leaseOwner) else {
        let message = "这项处理任务正在其他 Woice 会话中运行，请稍后重试。"
        markProcessingTaskFailed(
          recordID: request.recordID, kind: taskKind, sourceTrack: request.sourceTrack,
          message: message)
        processingState = .failed(message)
        errorMessage = message
        return
      }
    } catch {
      let message = error.localizedDescription
      markProcessingTaskFailed(
        recordID: request.recordID, kind: taskKind, sourceTrack: request.sourceTrack,
        message: message)
      processingState = .failed(message)
      errorMessage = message
      return
    }
    let leaseHeartbeat = Task { @MainActor [weak self] in
      while !Task.isCancelled {
        do {
          try await Task.sleep(for: .seconds(20))
        } catch {
          return
        }
        guard let self, !Task.isCancelled else { return }
        guard
          (try? self.store.renewJobLease(
            idempotencyKey: idempotencyKey, owner: self.leaseOwner, duration: 60
          )) == true
        else {
          return
        }
      }
    }
    defer { _ = try? store.releaseJobLease(idempotencyKey: idempotencyKey, owner: leaseOwner) }
    defer { leaseHeartbeat.cancel() }
    let requestMeetingMode = recordings.first(where: { $0.id == request.recordID })?
      .meetingTranscriptionMode
    updateProcessingTask(
      recordID: request.recordID, kind: request.kind.taskKind, sourceTrack: request.sourceTrack
    ) {
      $0.status = .running
      $0.attempt += 1
      $0.updatedAt = Date()
      $0.lastError = nil
      $0.blockReason = nil
      switch request.kind {
      case .transcription, .segmentTranscription:
        $0.providerID = "openai-compatible.asr"
        $0.modelID = request.model
        $0.modelVersion = nil
        $0.dataLocation = dataLocation(for: request.endpoint)
        $0.capability = .transcription
        $0.sourceTrack = request.sourceTrack
        $0.configurationHash = processingConfigurationHash(
          kind: request.kind.taskKind,
          providerID: "openai-compatible.asr",
          modelID: request.model,
          modelVersion: nil,
          dataLocation: dataLocation(for: request.endpoint),
          capability: .transcription,
          endpoint: request.endpoint,
          language: request.language,
          includeTimestamps: request.includeTranscriptTimestamps,
          sourceTrack: request.sourceTrack,
          meetingMode: requestMeetingMode)
      case .languageModel:
        $0.providerID = "openai-compatible.llm"
        $0.modelID = request.model
        $0.modelVersion = nil
        $0.dataLocation = dataLocation(for: request.endpoint)
        $0.capability = nil
        $0.configurationHash = processingConfigurationHash(
          kind: request.kind.taskKind,
          providerID: "openai-compatible.llm",
          modelID: request.model,
          modelVersion: nil,
          dataLocation: dataLocation(for: request.endpoint),
          capability: nil,
          endpoint: request.endpoint,
          language: "",
          includeTimestamps: false,
          sourceTrack: nil,
          meetingMode: nil)
      }
    }
    switch request.kind {
    case .transcription:
      await transcribe(
        recordID: request.recordID, endpoint: request.endpoint, apiKey: request.apiKey,
        model: request.model, language: request.language,
        includeSegments: request.includeTranscriptTimestamps,
        sourceTrack: request.sourceTrack)
    case .segmentTranscription:
      await transcribeSegments(
        recordID: request.recordID, endpoint: request.endpoint, apiKey: request.apiKey,
        model: request.model, language: request.language)
    case .languageModel:
      await generateMarkdown(
        recordID: request.recordID, endpoint: request.endpoint, apiKey: request.apiKey,
        model: request.model)
    }
  }

  func dismissExternalProcessing() {
    deferExternalProcessing()
  }

  /// Keeps an external task durable and resumable. This is deliberately not
  /// a cancellation: the workbench can present the same request again after
  /// the user leaves the menu bar or restarts Woice.
  func deferExternalProcessing() {
    if let request = pendingExternalProcessing {
      updateProcessingTask(
        recordID: request.recordID, kind: request.kind.taskKind, sourceTrack: request.sourceTrack
      ) {
        $0.status = .queued
        $0.blockReason = .authorizationRequired
        $0.lastError = "已稍后处理；可在工作台继续转写。"
        $0.updatedAt = Date()
      }
      queuedExternalProcessing.append(request)
    }
    pendingExternalProcessing = nil
    processingState = .saved
    presentActionFeedback(.success("已稍后处理；可在工作台继续转写"))
  }

  /// Resumes one durable/deferred task from the workbench. Only this explicit
  /// user action promotes a queued external task back to confirmation.
  func resumeProcessing(for record: RecordingRecord) {
    guard pendingExternalProcessing == nil else { return }
    if let index = queuedExternalProcessing.firstIndex(where: { $0.recordID == record.id }) {
      let request = queuedExternalProcessing.remove(at: index)
      pendingExternalProcessing = request
      updateProcessingTask(
        recordID: request.recordID, kind: request.kind.taskKind, sourceTrack: request.sourceTrack
      ) {
        $0.status = .awaitingAuthorization
        $0.blockReason = .authorizationRequired
        $0.lastError = nil
        $0.updatedAt = Date()
      }
      processingState = .awaitingAuthorization
      return
    }
    guard let task = ProcessingTaskProjection.resumableTask(in: record.processingTasks) else {
      retryProcessing(for: record)
      return
    }
    switch task.kind {
    case .transcription:
      if shouldUseLocalASR || canAutoProcessLocalExternalASR {
        requestTranscription(for: record)
      } else if hasExternalASR {
        requestExternalProcessing(
          for: record.id, kind: .transcription, endpoint: settings.asrEndpoint,
          sourceTrack: task.sourceTrack, rehydrateQueuedTask: true)
      }
    case .segmentTranscription:
      requestSegmentTranscription(for: record)
    case .languageModel:
      requestMarkdown(for: record)
    }
  }

  func requestTranscription(for record: RecordingRecord) {
    let record = prepareReliableMeetingTranscription(for: record)
    if shouldUseLocalASR {
      presentActionFeedback(.progress("正在开始本机转写"))
      Task { @MainActor [weak self] in
        guard let self else { return }
        let tracks = self.transcriptionTracks(for: record)
        if tracks.count > 1 {
          for track in tracks {
            await self.processLocalTranscription(for: record.id, sourceTrack: track)
          }
        } else {
          await self.processLocalTranscription(for: record.id, sourceTrack: tracks.first)
        }
      }
    } else if canAutoProcessLocalExternalASR {
      let tracks = transcriptionTracks(for: record)
      presentActionFeedback(
        .progress(
          "正在使用本机服务转写\(tracks.count > 1 ? "两条原始音轨" : transcriptionSourceDescription(tracks.first))"
        ))
      Task { @MainActor [weak self] in
        guard let self else { return }
        for track in tracks {
          await self.transcribe(
            recordID: record.id, endpoint: self.settings.asrEndpoint,
            apiKey: self.settings.asrAPIKey, model: self.settings.asrModel,
            language: self.settings.language,
            includeSegments: self.settings.includeTranscriptTimestamps, sourceTrack: track)
        }
      }
    } else if hasExternalASR {
      presentActionFeedback(.progress("等待确认后发送转写"))
      let tracks = transcriptionTracks(for: record)
      if tracks.count > 1 {
        for track in tracks {
          requestExternalProcessing(
            for: record.id, kind: .transcription, endpoint: settings.asrEndpoint,
            sourceTrack: track)
        }
      } else {
        requestExternalProcessing(
          for: record.id, kind: .transcription, endpoint: settings.asrEndpoint,
          sourceTrack: tracks.first)
      }
    } else {
      updateProcessingTask(recordID: record.id, kind: .transcription) {
        $0.status = .waitingForModel
        $0.blockReason = .noModelSelected
        $0.updatedAt = Date()
        $0.lastError = "还没有选择语言转文字模型；原始录音仍安全保存在本机。"
      }
      errorMessage = "还没有选择语言转文字模型；原始录音仍安全保存在本机。"
      presentActionFeedback(.failure("还没有选择语言转文字模型"))
    }
  }

  /// Imports one immutable audio/video original and creates the same durable
  /// transcription task used by recordings. The caller decides when to start
  /// transcription; importing never sends data externally by itself.
  @discardableResult
  func importMedia(from sourceURL: URL) async -> UUID? {
    do {
      let imported = try await MediaImportService.importFile(
        sourceURL: sourceURL, recordingsDirectory: store.recordingsURL)
      let task: ProcessingTask
      if shouldUseLocalASR || hasExternalASR {
        task = ProcessingTask(
          kind: .transcription,
          idempotencyKey: taskKey(recordID: imported.id, kind: .transcription),
          providerID: shouldUseLocalASR ? localASRModel.providerID : "openai-compatible.asr",
          modelID: shouldUseLocalASR ? localASRModel.modelID : settings.asrModel,
          modelVersion: shouldUseLocalASR ? localASRModel.version : nil,
          dataLocation: shouldUseLocalASR ? .onDevice : dataLocation(for: settings.asrEndpoint),
          capability: .transcription,
          configurationHash: processingConfigurationHash(
            kind: .transcription,
            providerID: shouldUseLocalASR ? localASRModel.providerID : "openai-compatible.asr",
            modelID: shouldUseLocalASR ? localASRModel.modelID : settings.asrModel,
            modelVersion: shouldUseLocalASR ? localASRModel.version : nil,
            dataLocation: shouldUseLocalASR ? .onDevice : dataLocation(for: settings.asrEndpoint),
            capability: .transcription,
            endpoint: shouldUseLocalASR ? nil : settings.asrEndpoint,
            language: settings.language,
            includeTimestamps: settings.includeTranscriptTimestamps,
            sourceTrack: nil,
            meetingMode: nil))
      } else {
        task = ProcessingTask(
          kind: .transcription,
          idempotencyKey: taskKey(recordID: imported.id, kind: .transcription),
          status: .waitingForModel,
          lastError: "还没有选择语言转文字模型；导入文件已安全保存在本机。",
          capability: .transcription,
          blockReason: .noModelSelected)
      }
      let record = RecordingRecord(
        id: imported.id,
        createdAt: Date(),
        audioFileName: imported.derivedAudioURL.lastPathComponent,
        duration: imported.duration,
        transcript: nil,
        generatedMarkdown: nil,
        processingError: nil,
        processingTasks: [task],
        sourceKind: imported.sourceKind,
        originalMediaFileName: imported.originalURL.lastPathComponent,
        originalMediaSHA256: imported.originalSHA256,
        originalMediaByteCount: imported.originalByteCount)
      recordings.insert(record, at: 0)
      guard persistRecordings() else {
        try? FileManager.default.removeItem(at: imported.derivedAudioURL)
        try? FileManager.default.removeItem(at: imported.originalURL)
        recordings.removeAll { $0.id == imported.id }
        return nil
      }
      processingState = .saved
      presentActionFeedback(.success("已导入\(imported.sourceKind.label)，可在当前窗口转文字"))
      return imported.id
    } catch {
      errorMessage = error.localizedDescription
      presentActionFeedback(.failure("导入失败：\(error.localizedDescription)"))
      return nil
    }
  }

  /// Sends a short, locally generated tone to the draft ASR configuration.
  /// This intentionally does not touch AppState settings, history, or the
  /// external-processing confirmation queue.
  func checkASRConfiguration(
    endpoint: String,
    model: String,
    apiKey: String,
    language: String,
    includeTimestamps: Bool? = nil
  ) async throws -> ASRHealthCheckResult {
    if let error = endpointValidation(for: endpoint, name: "语言转文字") {
      throw WoiceError.invalidEndpoint(error)
    }
    if let error = modelValidation(endpoint: endpoint, model: model, name: "语言转文字") {
      throw WoiceError.storageFailure(error)
    }
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      ".woice-asr-health-\(UUID().uuidString).wav")
    defer { try? FileManager.default.removeItem(at: url) }
    try writeASRHealthCheckAudio(to: url)
    let result = try await transcriptionClient.checkConfiguration(
      audioURL: url, endpoint: endpoint, apiKey: apiKey, model: model, language: language)
    if dataLocation(for: endpoint) == .onDevice {
      let timestamps = includeTimestamps ?? settings.includeTranscriptTimestamps
      let trust = LocalASRTrustSnapshot(
        endpointIdentity: normalizedEndpointKey(endpoint),
        modelID: model,
        language: language,
        includeTimestamps: timestamps,
        configurationHash: localASRTrustConfigurationHash(
          endpoint: endpoint,
          model: model,
          language: language,
          includeTimestamps: timestamps))
      verifiedLocalASRTrust = trust
      do {
        try store.saveLocalASRTrust(trust)
      } catch {
        verifiedLocalASRTrust = nil
        throw WoiceError.storageFailure("本机服务授权事实无法保存：\(error.localizedDescription)")
      }
    }
    return result
  }

  /// Discovery is always explicit and only reads model metadata from a
  /// loopback/private endpoint. It never changes the saved route or creates a
  /// recording/job; the settings view decides whether to copy a model ID into
  /// its draft.
  func discoverASRModels(endpoint: String, apiKey: String) async {
    isDiscoveringASRModels = true
    asrDiscoveryMessage = nil
    defer { isDiscoveringASRModels = false }
    do {
      discoveredASRModels = try await transcriptionClient.discoverModels(
        endpoint: endpoint, apiKey: apiKey, timeout: 5)
      asrDiscoveryMessage = "已发现 \(discoveredASRModels.count) 个模型"
      presentActionFeedback(.success("已发现本机转写模型"))
    } catch {
      discoveredASRModels = []
      asrDiscoveryMessage = error.localizedDescription
      presentActionFeedback(.failure("模型发现失败：\(error.localizedDescription)"))
    }
  }

  func requestSegmentTranscription(for record: RecordingRecord) {
    guard !hasActiveMainTranscription(for: record) else {
      errorMessage = "主转写任务正在等待或运行，完成后再按声音片段转写。"
      presentActionFeedback(.failure("已避免重复创建声音片段任务"))
      return
    }
    guard !settings.asrEndpoint.isEmpty else {
      errorMessage = "请先在设置中配置语言转文字 API。"
      return
    }
    guard record.voiceSegments?.isEmpty == false else {
      errorMessage = "这条录音没有可用的声音片段，请先完成一段有声音的录音。"
      return
    }
    requestExternalProcessing(
      for: record.id, kind: .segmentTranscription, endpoint: settings.asrEndpoint,
      rehydrateQueuedTask: true)
    presentActionFeedback(.progress("等待确认后转写声音片段"))
  }

  func requestMarkdown(for record: RecordingRecord) {
    guard !settings.llmEndpoint.isEmpty else {
      errorMessage = "请先在设置中配置 Markdown 笔记 API。"
      return
    }
    guard let transcript = record.transcript, !transcript.isEmpty else {
      errorMessage = "请先完成语言转文字，再生成 Markdown 笔记。"
      return
    }
    requestExternalProcessing(
      for: record.id, kind: .languageModel, endpoint: settings.llmEndpoint,
      rehydrateQueuedTask: true)
    presentActionFeedback(.progress("等待确认后生成 Markdown 笔记"))
  }

  func retryProcessing(for record: RecordingRecord) {
    if let task = record.processingTasks.reversed().first(where: { $0.status.isRetryable }) {
      switch task.kind {
      case .transcription:
        requestTranscription(for: record)
      case .segmentTranscription:
        requestSegmentTranscription(for: record)
      case .languageModel:
        requestMarkdown(for: record)
      }
      return
    }
    if record.transcript?.isEmpty == false, !settings.llmEndpoint.isEmpty {
      requestMarkdown(for: record)
    } else {
      requestTranscription(for: record)
    }
  }

  private func transcribe(
    recordID: UUID,
    endpoint: String,
    apiKey: String,
    model: String,
    language: String,
    includeSegments: Bool,
    sourceTrack: AudioTrackKind? = nil
  ) async {
    guard let record = recordings.first(where: { $0.id == recordID }) else { return }
    let effectiveTrack = sourceTrack ?? transcriptionSourceTrack(for: record)
    processingState = .transcribing
    var temporaryInputURL: URL?
    do {
      let prepared = try preparedTranscriptionInput(
        for: record, sourceTrack: effectiveTrack)
      temporaryInputURL = prepared.isTemporary ? prepared.url : nil
      defer {
        if let temporaryInputURL { try? FileManager.default.removeItem(at: temporaryInputURL) }
      }
      let result = try await transcribeExternalInput(
        audioURL: prepared.url,
        endpoint: endpoint,
        apiKey: apiKey,
        model: model,
        language: language,
        includeSegments: includeSegments,
        sourceTrack: effectiveTrack)
      applyTranscriptionResult(
        recordID: record.id,
        result: result,
        sourceTrack: effectiveTrack)
      updateProcessingTask(
        recordID: record.id, kind: .transcription, sourceTrack: sourceTrack
      ) {
        $0.status = .completed
        $0.updatedAt = Date()
        $0.lastError = nil
      }
      presentActionFeedback(.success("转写已完成"))
      if settings.autoCopyTranscript { copyTranscript(result.text) }
      if settings.autoPasteTranscript {
        do {
          try textInsertion.paste(text: result.text)
        } catch {
          errorMessage = error.localizedDescription
        }
      }
      if !settings.llmEndpoint.isEmpty, !result.text.isEmpty,
        transcriptionJobsComplete(for: record.id)
      {
        requestExternalProcessing(
          for: record.id, kind: .languageModel, endpoint: settings.llmEndpoint)
      } else {
        processingState = .saved
      }
    } catch {
      let message = error.localizedDescription
      updateRecord(id: record.id) { $0.processingError = message }
      markProcessingTaskFailed(
        recordID: record.id, kind: .transcription, sourceTrack: sourceTrack, message: message)
      processingState = .failed(error.localizedDescription)
      errorMessage = error.localizedDescription
    }
  }

  private func transcribeExternalInput(
    audioURL: URL,
    endpoint: String,
    apiKey: String,
    model: String,
    language: String,
    includeSegments: Bool,
    sourceTrack: AudioTrackKind
  ) async throws -> TranscriptionResult {
    let chunks = try AudioChunkingService.plan(sourceURL: audioURL)
    guard !chunks.isEmpty else {
      return try await transcriptionClient.transcribeDetailed(
        audioURL: audioURL,
        endpoint: endpoint,
        apiKey: apiKey,
        model: model,
        language: language,
        includeSegments: includeSegments)
    }

    let workingDirectory = store.rootURL
      .appendingPathComponent("working", isDirectory: true)
      .appendingPathComponent("transcription-\(UUID().uuidString)", isDirectory: true)
    let chunkURLs = try AudioChunkingService.materialize(
      sourceURL: audioURL, chunks: chunks, workingDirectory: workingDirectory)
    defer { try? FileManager.default.removeItem(at: workingDirectory) }

    var texts: [String] = []
    var segments: [TranscriptSegment] = []
    for (position, item) in zip(chunks, chunkURLs).enumerated() {
      presentActionFeedback(.progress("正在转写第 \(position + 1)/\(chunks.count) 段"))
      let result = try await transcriptionClient.transcribeDetailed(
        audioURL: item.1,
        endpoint: endpoint,
        apiKey: apiKey,
        model: model,
        language: language,
        includeSegments: true)
      let text = TranscriptTextNormalizer.normalize(result.text)
      if !text.isEmpty { texts.append(text) }
      if result.segments.isEmpty {
        if !text.isEmpty {
          segments.append(
            TranscriptSegment(
              start: item.0.start, end: item.0.end, text: text, sourceTrack: sourceTrack))
        }
      } else {
        segments.append(
          contentsOf: result.segments.map {
            TranscriptSegment(
              start: item.0.start + max(0, $0.start),
              end: item.0.start + max($0.start, $0.end),
              text: $0.text,
              sourceTrack: sourceTrack)
          })
      }
    }
    let text = TranscriptTextNormalizer.normalize(texts.joined(separator: "\n"))
    guard !text.isEmpty else { throw WoiceError.invalidResponse }
    return TranscriptionResult(
      text: text,
      segments: includeSegments ? segments : [])
  }

  private func processLocalTranscription(
    for recordID: UUID, sourceTrack: AudioTrackKind? = nil
  ) async {
    guard let record = recordings.first(where: { $0.id == recordID }) else { return }
    let effectiveTrack = sourceTrack ?? transcriptionSourceTrack(for: record)
    let activityKey = recordID.uuidString + ":" + effectiveTrack.rawValue
    guard activeLocalTranscriptionIDs.insert(activityKey).inserted else { return }
    defer { activeLocalTranscriptionIDs.remove(activityKey) }
    if let authorizationProvider = localTranscription as? LocalASRAuthorizationProviding,
      authorizationProvider.authorizationState != .authorized
    {
      let message =
        "本机语言转文字需要语音识别权限；原始录音仍安全保存在本机。请在设置页点击“允许”后重试。"
      updateProcessingTask(recordID: recordID, kind: .transcription, sourceTrack: sourceTrack) {
        $0.status = .failed
        $0.updatedAt = Date()
        $0.lastError = message
        $0.blockReason = .authorizationRequired
        $0.providerID = localASRModel.providerID
        $0.modelID = localASRModel.modelID
        $0.modelVersion = localASRModel.version
        $0.dataLocation = .onDevice
        $0.capability = .transcription
        $0.sourceTrack = effectiveTrack
        $0.configurationHash = processingConfigurationHash(
          kind: .transcription,
          providerID: localASRModel.providerID,
          modelID: localASRModel.modelID,
          modelVersion: localASRModel.version,
          dataLocation: .onDevice,
          capability: .transcription,
          endpoint: nil,
          language: settings.language,
          includeTimestamps: settings.includeTranscriptTimestamps,
          sourceTrack: effectiveTrack,
          meetingMode: record.meetingTranscriptionMode)
      }
      updateRecord(id: recordID) { $0.processingError = message }
      processingState = .failed(message)
      errorMessage = message
      return
    }
    let existingTask =
      recordings
      .first(where: { $0.id == recordID })?.processingTasks
      .first(where: {
        $0.kind == .transcription
          && (sourceTrack == nil || $0.sourceTrack == sourceTrack
            || (sourceTrack == .microphone && $0.sourceTrack == nil))
      })
    let key =
      existingTask?.idempotencyKey
      ?? taskKey(recordID: recordID, kind: .transcription, sourceTrack: effectiveTrack)
    if existingTask?.status != .running {
      updateProcessingTask(recordID: recordID, kind: .transcription, sourceTrack: sourceTrack) {
        $0.providerID = localASRModel.providerID
        $0.modelID = localASRModel.modelID
        $0.modelVersion = localASRModel.version
        $0.dataLocation = .onDevice
        $0.capability = .transcription
        $0.sourceTrack = effectiveTrack
        $0.blockReason = nil
        $0.configurationHash = processingConfigurationHash(
          kind: .transcription,
          providerID: localASRModel.providerID,
          modelID: localASRModel.modelID,
          modelVersion: localASRModel.version,
          dataLocation: .onDevice,
          capability: .transcription,
          endpoint: nil,
          language: settings.language,
          includeTimestamps: settings.includeTranscriptTimestamps,
          sourceTrack: effectiveTrack,
          meetingMode: record.meetingTranscriptionMode)
      }
    }
    do {
      guard try await acquireLocalTranscriptionLease(idempotencyKey: key) else {
        let message = "这条录音正在其他 Woice 会话中转写；原始录音和已有原文未改变，请稍后重试。"
        processingState = .saved
        errorMessage = message
        return
      }
    } catch is CancellationError {
      return
    } catch {
      let message = error.localizedDescription
      markProcessingTaskFailed(
        recordID: recordID, kind: .transcription, sourceTrack: sourceTrack, message: message)
      processingState = .failed(message)
      errorMessage = message
      return
    }
    defer { _ = try? store.releaseJobLease(idempotencyKey: key, owner: leaseOwner) }
    let leaseHeartbeat = Task { @MainActor [weak self] in
      while !Task.isCancelled {
        do {
          try await Task.sleep(for: .seconds(20))
        } catch {
          return
        }
        guard let self, !Task.isCancelled else { return }
        guard
          (try? self.store.renewJobLease(
            idempotencyKey: key, owner: self.leaseOwner, duration: 60
          )) == true
        else {
          return
        }
      }
    }
    defer { leaseHeartbeat.cancel() }
    updateProcessingTask(recordID: recordID, kind: .transcription, sourceTrack: sourceTrack) {
      $0.status = .running
      $0.attempt += 1
      $0.updatedAt = Date()
      $0.providerID = localASRModel.providerID
      $0.modelID = localASRModel.modelID
      $0.modelVersion = localASRModel.version
      $0.dataLocation = .onDevice
      $0.capability = .transcription
      $0.sourceTrack = effectiveTrack
      $0.blockReason = nil
      $0.lastError = nil
      $0.configurationHash = processingConfigurationHash(
        kind: .transcription,
        providerID: localASRModel.providerID,
        modelID: localASRModel.modelID,
        modelVersion: localASRModel.version,
        dataLocation: .onDevice,
        capability: .transcription,
        endpoint: nil,
        language: settings.language,
        includeTimestamps: settings.includeTranscriptTimestamps,
        sourceTrack: effectiveTrack,
        meetingMode: record.meetingTranscriptionMode)
    }
    processingState = .transcribing
    do {
      let prepared = try preparedTranscriptionInput(
        for: record, sourceTrack: effectiveTrack)
      defer {
        if prepared.isTemporary { try? FileManager.default.removeItem(at: prepared.url) }
      }
      let result = try await localTranscription.transcribe(
        audioURL: prepared.url,
        language: settings.language)
      applyTranscriptionResult(recordID: recordID, result: result, sourceTrack: effectiveTrack)
      updateProcessingTask(recordID: recordID, kind: .transcription, sourceTrack: sourceTrack) {
        $0.status = .completed
        $0.updatedAt = Date()
        $0.lastError = nil
      }
      presentActionFeedback(.success("本机转写已完成"))
      if settings.autoCopyTranscript { copyTranscript(result.text) }
      if settings.autoPasteTranscript {
        do {
          try textInsertion.paste(text: result.text)
        } catch {
          errorMessage = error.localizedDescription
        }
      }
      processingState = .saved
      errorMessage = nil
    } catch {
      let message = error.localizedDescription
      updateRecord(id: recordID) { $0.processingError = message }
      markProcessingTaskFailed(
        recordID: recordID, kind: .transcription, sourceTrack: sourceTrack, message: message)
      processingState = .failed(message)
      errorMessage = message
    }
  }

  private func acquireLocalTranscriptionLease(idempotencyKey: String) async throws -> Bool {
    for delayMilliseconds in [0, 150, 300, 600] {
      if delayMilliseconds > 0 {
        try await Task.sleep(for: .milliseconds(delayMilliseconds))
      }
      if try store.acquireJobLease(idempotencyKey: idempotencyKey, owner: leaseOwner) {
        return true
      }
    }
    return false
  }

  private func applyTranscriptionResult(
    recordID: UUID, result: TranscriptionResult, sourceTrack: AudioTrackKind
  ) {
    guard let record = recordings.first(where: { $0.id == recordID }) else { return }
    let trackOffset = sourceTrack == .systemAudio ? (record.systemAudioStartOffset ?? 0) : 0
    let incomingSegments: [TranscriptSegment]
    if result.segments.isEmpty {
      incomingSegments =
        result.text.isEmpty
        ? []
        : [
          TranscriptSegment(
            start: trackOffset, end: trackOffset, text: result.text,
            sourceTrack: sourceTrack)
        ]
    } else {
      incomingSegments = result.segments.map {
        TranscriptSegment(
          start: trackOffset + $0.start,
          end: trackOffset + $0.end,
          text: $0.text,
          sourceTrack: sourceTrack)
      }
    }
    if record.meetingTranscriptionMode == .sourceSeparated {
      let previous = record.transcriptSegments ?? []
      let retained = previous.filter { $0.sourceTrack != sourceTrack }
      let merged = (retained + incomingSegments).sorted {
        if $0.start != $1.start { return $0.start < $1.start }
        return sourceOrder($0.sourceTrack) < sourceOrder($1.sourceTrack)
      }
      appendTranscriptArtifact(
        recordID: recordID,
        text: merged.map(\.text).joined(separator: "\n"),
        segments: merged,
        sourceTrack: sourceTrack)
    } else {
      appendTranscriptArtifact(
        recordID: recordID,
        text: result.text,
        segments: incomingSegments,
        sourceTrack: sourceTrack)
    }
  }

  /// Appends a new immutable transcript version and updates only the current
  /// UI projection. Legacy records are lazily wrapped before their first
  /// re-transcription so an older transcript is never silently lost.
  private func appendTranscriptArtifact(
    recordID: UUID,
    text: String,
    segments: [TranscriptSegment],
    sourceTrack: AudioTrackKind
  ) {
    guard let record = recordings.first(where: { $0.id == recordID }) else { return }
    let normalizedText = TranscriptTextNormalizer.normalize(text)
    guard !normalizedText.isEmpty else { return }
    var artifacts = record.transcriptArtifacts
    if artifacts.isEmpty, let existing = record.transcript {
      let legacyText = TranscriptTextNormalizer.normalize(existing)
      if !legacyText.isEmpty {
        artifacts.append(
          TranscriptArtifact(
            parentRecordingID: recordID,
            createdAt: record.createdAt,
            text: legacyText,
            segments: record.transcriptSegments ?? [],
            sourceTrack: sourceTrack,
            meetingTranscriptionMode: record.meetingTranscriptionMode))
      }
    }
    let task = record.processingTasks
      .filter { $0.kind == .transcription || $0.kind == .segmentTranscription }
      .filter { task in
        task.sourceTrack == sourceTrack || task.sourceTrack == nil
      }
      .max { $0.updatedAt < $1.updatedAt }
    let artifact = TranscriptArtifact(
      parentRecordingID: recordID,
      supersedesID: artifacts.last?.id,
      text: normalizedText,
      segments: segments,
      providerID: task?.providerID,
      modelID: task?.modelID,
      modelVersion: task?.modelVersion,
      dataLocation: task?.dataLocation,
      configurationHash: task?.configurationHash,
      sourceTrack: sourceTrack,
      meetingTranscriptionMode: record.meetingTranscriptionMode)
    artifacts.append(artifact)
    updateRecord(id: recordID) {
      $0.transcriptArtifacts = artifacts
      $0.activeTranscriptArtifactID = artifact.id
      $0.transcript = normalizedText
      $0.transcriptSegments = segments.isEmpty ? nil : segments
      $0.processingError = nil
    }
  }

  private func transcriptionJobsComplete(for recordID: UUID) -> Bool {
    guard let record = recordings.first(where: { $0.id == recordID }) else { return false }
    guard record.meetingTranscriptionMode == .sourceSeparated else { return true }
    let requiredTracks = transcriptionTracks(for: record)
    return requiredTracks.allSatisfy { track in
      record.processingTasks.contains {
        $0.kind == .transcription && $0.sourceTrack == track && $0.status == .completed
      }
    }
  }

  private func sourceOrder(_ track: AudioTrackKind?) -> Int {
    switch track {
    case .microphone: 0
    case .systemAudio: 1
    case .meetingMix, nil: 2
    }
  }

  private func transcribeSegments(
    recordID: UUID, endpoint: String, apiKey: String, model: String, language: String
  ) async {
    guard let record = recordings.first(where: { $0.id == recordID }),
      let voiceSegments = record.voiceSegments, !voiceSegments.isEmpty
    else { return }
    processingState = .transcribing
    var transcriptSegments: [TranscriptSegment] = []
    do {
      for (index, voiceSegment) in voiceSegments.enumerated() {
        let fileName = "." + record.id.uuidString + "-segment-" + String(index) + ".wav"
        let temporaryURL = store.recordingsURL.appendingPathComponent(fileName)
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        try AudioSegmentExtractor.extract(
          sourceURL: store.audioURL(for: record), segment: voiceSegment,
          destinationURL: temporaryURL)
        let text = try await transcriptionClient.transcribe(
          audioURL: temporaryURL,
          endpoint: endpoint,
          apiKey: apiKey,
          model: model,
          language: language
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { continue }
        transcriptSegments.append(
          TranscriptSegment(start: voiceSegment.start, end: voiceSegment.end, text: text))
        let partialText = transcriptSegments.map(\.text).joined(separator: "\n")
        updateRecord(id: record.id) {
          $0.transcript = partialText
          $0.transcriptSegments = transcriptSegments
          $0.processingError = nil
        }
      }
      guard !transcriptSegments.isEmpty else { throw WoiceError.invalidResponse }
      let transcript = transcriptSegments.map(\.text).joined(separator: "\n")
      appendTranscriptArtifact(
        recordID: record.id,
        text: transcript,
        segments: transcriptSegments,
        sourceTrack: .microphone)
      updateProcessingTask(recordID: record.id, kind: .segmentTranscription) {
        $0.status = .completed
        $0.updatedAt = Date()
        $0.lastError = nil
      }
      presentActionFeedback(.success("声音片段转写已完成"))
      if settings.autoCopyTranscript { copyTranscript(transcript) }
      processingState = .saved
    } catch {
      let message = error.localizedDescription
      updateRecord(id: record.id) { $0.processingError = message }
      markProcessingTaskFailed(recordID: record.id, kind: .segmentTranscription, message: message)
      processingState = .failed(message)
      errorMessage = message
    }
  }

  private func generateMarkdown(
    recordID: UUID, endpoint: String, apiKey: String, model: String
  ) async {
    guard let record = recordings.first(where: { $0.id == recordID }),
      let transcript = record.transcript, !transcript.isEmpty
    else { return }
    let readableTranscript = TranscriptTextNormalizer.normalize(transcript)
    guard !readableTranscript.isEmpty else { return }
    processingState = .generating
    do {
      let markdown = try await llmClient.generateMarkdown(
        transcript: readableTranscript,
        endpoint: endpoint,
        apiKey: apiKey,
        model: model
      )
      updateRecord(id: record.id) {
        $0.generatedMarkdown = markdown
        $0.processingError = nil
      }
      updateProcessingTask(recordID: record.id, kind: .languageModel) {
        $0.status = .completed
        $0.updatedAt = Date()
        $0.lastError = nil
      }
      presentActionFeedback(.success("Markdown 笔记已生成"))
      processingState = .saved
    } catch {
      let message = error.localizedDescription
      updateRecord(id: record.id) { $0.processingError = message }
      markProcessingTaskFailed(recordID: record.id, kind: .languageModel, message: message)
      processingState = .failed(error.localizedDescription)
      errorMessage = error.localizedDescription
    }
  }

  private func requestExternalProcessing(
    for recordID: UUID,
    kind: ExternalProcessingKind,
    endpoint: String,
    sourceTrack: AudioTrackKind? = nil,
    rehydrateQueuedTask: Bool = false
  ) {
    guard let record = recordings.first(where: { $0.id == recordID }) else { return }
    if kind == .segmentTranscription, hasActiveMainTranscription(for: record) {
      errorMessage = "主转写任务正在等待或运行，暂不创建声音片段任务。"
      presentActionFeedback(.failure("已避免重复创建声音片段任务"))
      return
    }
    let existingTask = record.processingTasks.first(where: {
      $0.kind == kind.taskKind
        && (sourceTrack == nil || $0.sourceTrack == sourceTrack
          || (sourceTrack == .microphone && $0.sourceTrack == nil))
    })
    if let existingTask,
      existingTask.status == .awaitingAuthorization || existingTask.status == .running
        || (existingTask.status == .queued && existingTask.blockReason == .authorizationRequired
          && !rehydrateQueuedTask)
    {
      return
    }
    _ = loadKeychainSecret(
      account: kind == .languageModel ? "llm-api-key" : "asr-api-key")
    let configuredModel = kind == .languageModel ? settings.llmModel : settings.asrModel
    let configuredLanguage = kind == .languageModel ? "" : settings.language
    let configuredIncludeTimestamps =
      kind == .transcription
      ? settings.includeTranscriptTimestamps : false
    let configuredProviderID =
      kind == .languageModel ? "openai-compatible.llm" : "openai-compatible.asr"
    let configuredCapability: ASRProviderCapability? =
      kind == .languageModel ? nil : .transcription
    let configuredMeetingMode = record.meetingTranscriptionMode
    updateProcessingTask(recordID: recordID, kind: kind.taskKind, sourceTrack: sourceTrack) {
      $0.status = .awaitingAuthorization
      $0.updatedAt = Date()
      $0.lastError = nil
      $0.blockReason = nil
      $0.providerID = configuredProviderID
      $0.modelID = configuredModel
      $0.modelVersion = nil
      $0.dataLocation = dataLocation(for: endpoint)
      $0.capability = configuredCapability
      $0.sourceTrack = sourceTrack
      $0.configurationHash = processingConfigurationHash(
        kind: kind.taskKind,
        providerID: configuredProviderID,
        modelID: configuredModel,
        modelVersion: nil,
        dataLocation: dataLocation(for: endpoint),
        capability: configuredCapability,
        endpoint: endpoint,
        language: configuredLanguage,
        includeTimestamps: configuredIncludeTimestamps,
        sourceTrack: sourceTrack,
        meetingMode: configuredMeetingMode)
    }
    let host = URL(string: endpoint)?.host ?? endpoint
    let apiKey: String
    let model: String
    let language: String
    switch kind {
    case .transcription:
      apiKey = settings.asrAPIKey
      model = settings.asrModel
      language = settings.language
    case .segmentTranscription:
      apiKey = settings.asrAPIKey
      model = settings.asrModel
      language = settings.language
    case .languageModel:
      apiKey = settings.llmAPIKey
      model = settings.llmModel
      language = ""
    }
    let request = ExternalProcessingRequest(
      recordID: recordID, kind: kind, host: host, endpoint: endpoint, apiKey: apiKey,
      model: model, language: language,
      includeTranscriptTimestamps: configuredIncludeTimestamps,
      sourceTrack: kind == .transcription
        ? (sourceTrack
          ?? recordings.first(where: { $0.id == recordID }).map {
            self.transcriptionSourceTrack(for: $0)
          })
        : nil)
    if pendingExternalProcessing == nil {
      pendingExternalProcessing = request
      processingState = .awaitingAuthorization
    } else {
      queuedExternalProcessing.append(request)
    }
  }

  @discardableResult
  func saveSettings(candidate: AppSettings? = nil, scope: AppSettingsScope? = nil) -> Bool {
    let requested = candidate ?? settings
    let candidate = scope?.applying(requested, to: settings) ?? requested
    if let error = endpointValidation(for: candidate.asrEndpoint, name: "语言转文字") {
      errorMessage = error
      return false
    }
    if let error = modelValidation(
      endpoint: candidate.asrEndpoint, model: candidate.asrModel, name: "语言转文字")
    {
      errorMessage = error
      return false
    }
    if let error = endpointValidation(for: candidate.llmEndpoint, name: "Markdown 笔记") {
      errorMessage = error
      return false
    }
    if let error = modelValidation(
      endpoint: candidate.llmEndpoint, model: candidate.llmModel, name: "Markdown 笔记")
    {
      errorMessage = error
      return false
    }
    let shortcutChanged =
      (scope == nil || scope == .recording)
      && candidate.recordingShortcut != settings.recordingShortcut
    if shortcutChanged {
      let probe = GlobalShortcutService.probe(candidate.recordingShortcut)
      guard probe.isAvailable else {
        globalShortcutError = shortcutProbeMessage(probe, shortcut: candidate.recordingShortcut)
        errorMessage = globalShortcutError
        return false
      }
    }
    let previousSettings = settings
    let previousShortcut = globalShortcutService.currentShortcut
    let apiKeyChanges: [(account: String, previous: String, candidate: String)] = [
      ("asr-api-key", settings.asrAPIKey, candidate.asrAPIKey),
      ("llm-api-key", settings.llmAPIKey, candidate.llmAPIKey),
    ].filter { $0.previous != $0.candidate }
    var writtenAPIKeys: [(account: String, previous: String)] = []
    var shortcutApplied = false
    do {
      for change in apiKeyChanges {
        try keychain.write(change.candidate, account: change.account)
        writtenAPIKeys.append((change.account, change.previous))
      }
      if shortcutChanged {
        try globalShortcutService.replace(with: candidate.recordingShortcut, action: shortcutAction)
        shortcutApplied = true
      }
      var persisted = candidate
      persisted.asrAPIKey = ""
      persisted.llmAPIKey = ""
      try store.saveSettings(persisted)
      settings = candidate
      if previousSettings.asrConfiguration.usesExternalService,
        !candidate.asrConfiguration.usesExternalService
      {
        withdrawExternalASRRequestsForLocalRoute()
      }
      if let trust = verifiedLocalASRTrust, isValidLocalASRTrust(trust, for: candidate) {
        // Keep an explicit health-check fact only when the saved route still
        // describes the exact endpoint/model/configuration that was checked.
        try? store.saveLocalASRTrust(trust)
      } else {
        verifiedLocalASRTrust = nil
        store.clearLocalASRTrust()
      }
      if scope == nil || scope == .services {
        loadedKeychainAccounts.insert("asr-api-key")
        loadedKeychainAccounts.insert("llm-api-key")
      }
      if scope == nil || scope == .recording {
        installGlobalShortcut()
      }
      if scope == nil || scope == .services {
        Task { @MainActor [weak self] in
          await self?.refreshASRProviderInventory()
        }
      }
      globalShortcutError = nil
      errorMessage = nil
      presentActionFeedback(.success("设置已保存"))
      return true
    } catch {
      // Keychain and the settings file are separate stores. Restore only the
      // API Key entries written by this save; ordinary settings never touch
      // Keychain and a failed draft save cannot partially take effect.
      for change in writtenAPIKeys.reversed() {
        restoreKeychainValue(account: change.account, value: change.previous)
      }
      if shortcutApplied {
        do {
          try globalShortcutService.replace(with: previousShortcut, action: shortcutAction)
        } catch {
          globalShortcutError = "快捷键回滚失败：\(error.localizedDescription)"
        }
      }
      settings = previousSettings
      errorMessage = error.localizedDescription
      return false
    }
  }

  private func shortcutProbeMessage(
    _ result: GlobalShortcutProbeResult, shortcut: RecordingShortcut
  ) -> String {
    switch result {
    case .available: "\(shortcut.displayName) 当前可注册。"
    case .disabled: "快捷键已关闭。"
    case .invalid(let reason): "快捷键不可用：\(reason)。"
    case .systemReserved: "\(shortcut.displayName) 是系统保留组合，请换一个快捷键。"
    case .occupied: "\(shortcut.displayName) 已被其他应用占用，请换一个组合。"
    }
  }

  private func restoreKeychainValue(account: String, value: String) {
    if value.isEmpty {
      keychain.remove(account: account)
    } else {
      try? keychain.write(value, account: account)
    }
  }

  func copyTranscript(_ text: String) {
    let readable = TranscriptTextNormalizer.normalize(text)
    guard !readable.isEmpty else {
      presentActionFeedback(.failure("没有可复制的原文"))
      return
    }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(readable, forType: .string)
    presentActionFeedback(.success("已复制原文"))
  }

  @discardableResult
  func selectTranscriptArtifact(recordID: UUID, artifactID: UUID) -> Bool {
    guard let record = recordings.first(where: { $0.id == recordID }),
      let artifact = record.transcriptArtifacts.first(where: { $0.id == artifactID })
    else {
      presentActionFeedback(.failure("找不到这版原文"))
      return false
    }
    updateRecord(id: recordID) {
      $0.activeTranscriptArtifactID = artifact.id
      $0.transcript = artifact.text
      $0.transcriptSegments = artifact.segments.isEmpty ? nil : artifact.segments
      $0.processingError = nil
    }
    errorMessage = nil
    presentActionFeedback(.success("已切换原文版本"))
    return true
  }

  @discardableResult
  func pasteTranscript(for record: RecordingRecord) -> Bool {
    guard let transcript = record.transcript, !transcript.isEmpty else {
      errorMessage = "这条录音还没有可粘贴的原文。"
      presentActionFeedback(.failure("没有可粘贴的原文"))
      return false
    }
    do {
      try textInsertion.paste(text: TranscriptTextNormalizer.normalize(transcript))
      errorMessage = nil
      presentActionFeedback(.success("已粘贴到当前应用"))
      return true
    } catch {
      errorMessage = error.localizedDescription
      presentActionFeedback(.failure("粘贴失败：\(error.localizedDescription)"))
      return false
    }
  }

  func presentActionFeedback(_ feedback: ActionFeedback) {
    actionFeedbackTask?.cancel()
    actionFeedback = feedback
    actionFeedbackTask = Task { @MainActor [weak self] in
      do {
        try await Task.sleep(for: .seconds(2.8))
      } catch {
        return
      }
      guard let self, self.actionFeedback?.id == feedback.id else { return }
      self.actionFeedback = nil
    }
  }

  func requestAccessibilityPermission() {
    textInsertion.requestPermission()
    presentActionFeedback(.progress("正在打开粘贴权限设置"))
  }

  func audioFileExists(for record: RecordingRecord) -> Bool {
    FileManager.default.fileExists(atPath: store.audioURL(for: record).path)
  }

  func audioURL(for record: RecordingRecord) -> URL {
    store.audioURL(for: record)
  }

  func originalMediaURL(for record: RecordingRecord) -> URL? {
    store.originalMediaURL(for: record)
  }

  @discardableResult
  func openOriginalMedia(for record: RecordingRecord) -> Bool {
    guard let url = store.originalMediaURL(for: record),
      FileManager.default.fileExists(atPath: url.path)
    else {
      presentActionFeedback(.failure("找不到导入的原始文件"))
      return false
    }
    guard NSWorkspace.shared.open(url) else {
      presentActionFeedback(.failure("macOS 无法打开原始文件"))
      return false
    }
    presentActionFeedback(.success("已打开导入的原始文件"))
    return true
  }

  func systemAudioURL(for record: RecordingRecord) -> URL? {
    store.systemAudioURL(for: record)
  }

  func meetingMixURL(for record: RecordingRecord) -> URL {
    store.meetingMixURL(for: record)
  }

  func meetingMixFileExists(for record: RecordingRecord) -> Bool {
    FileManager.default.fileExists(atPath: store.meetingMixURL(for: record).path)
  }

  func systemAudioFileExists(for record: RecordingRecord) -> Bool {
    guard let url = store.systemAudioURL(for: record) else { return false }
    return FileManager.default.fileExists(atPath: url.path)
  }

  func audioFileSize(for record: RecordingRecord) -> Int64? {
    guard
      let attributes = try? FileManager.default.attributesOfItem(
        atPath: store.audioURL(for: record).path),
      let size = attributes[.size] as? NSNumber
    else { return nil }
    return size.int64Value
  }

  @discardableResult
  func revealAudioFile(for record: RecordingRecord) -> Bool {
    let url = store.audioURL(for: record)
    guard FileManager.default.fileExists(atPath: url.path) else {
      errorMessage = "找不到原始录音文件。"
      presentActionFeedback(.failure("找不到原始录音文件"))
      return false
    }
    NSWorkspace.shared.activateFileViewerSelecting([url])
    presentActionFeedback(.success("已在 Finder 中显示录音"))
    return true
  }

  @discardableResult
  func revealAgentResult(_ artifact: AgentResultArtifact) -> Bool {
    let url = store.agentResultURL(for: artifact)
    guard FileManager.default.fileExists(atPath: url.path) else {
      presentActionFeedback(.failure("Agent 结果文件不存在"))
      return false
    }
    NSWorkspace.shared.activateFileViewerSelecting([url])
    presentActionFeedback(.success("已在 Finder 中显示 Agent 结果"))
    return true
  }

  func copyAgentResultPreview(_ artifact: AgentResultArtifact) {
    guard !artifact.preview.isEmpty else {
      presentActionFeedback(.failure("Agent 没有可复制的结果预览"))
      return
    }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(artifact.preview, forType: .string)
    presentActionFeedback(.success("已复制 Agent 结果预览"))
  }

  @discardableResult
  func exportMaterial(for record: RecordingRecord, kind: RecordingExportKind) -> URL? {
    do {
      let url: URL
      switch kind {
      case .microphoneAudio:
        url = try copyAudioExport(
          source: store.audioURL(for: record), record: record, suffix: "microphone.wav")
      case .systemAudio:
        guard let source = store.systemAudioURL(for: record) else {
          throw WoiceError.audioFileMissing
        }
        url = try copyAudioExport(source: source, record: record, suffix: "system-audio.caf")
      case .meetingMixAudio:
        url = try copyAudioExport(
          source: store.meetingMixURL(for: record), record: record, suffix: "meeting-mix.wav")
      case .transcriptText:
        let transcript = try exportableTranscript(for: record)
        url = try writeExport(
          Data(transcript.utf8), record: record, suffix: "transcript.txt")
      case .transcriptJSON:
        let transcript = try exportableTranscript(for: record)
        let payload = ExportedRecording(
          id: record.id,
          createdAt: record.createdAt,
          duration: record.duration,
          transcript: transcript,
          segments: (record.transcriptSegments ?? []).map {
            ExportedTranscriptSegment(
              start: $0.start,
              end: $0.end,
              text: TranscriptTextNormalizer.normalize($0.text),
              sourceTrack: $0.sourceTrack?.rawValue)
          },
          audioFiles: audioFileManifest(for: record),
          materialStatus: record.materialStatus,
          activeTranscriptArtifactID: record.activeTranscriptArtifactID,
          transcriptArtifacts: record.transcriptArtifacts,
          sourceKind: record.sourceKind,
          originalMediaFileName: record.originalMediaFileName,
          originalMediaSHA256: record.originalMediaSHA256)
        let data = try JSONEncoder.woice.encode(payload)
        url = try writeExport(data, record: record, suffix: "transcript.json")
      case .markdown:
        guard let markdownURL = exportMarkdown(for: record) else { return nil }
        return markdownURL
      }
      presentActionFeedback(.success("已导出\(kind.title)"))
      return url
    } catch {
      let message = error.localizedDescription
      errorMessage = message
      presentActionFeedback(.failure("导出\(kind.title)失败：\(message)"))
      return nil
    }
  }

  @discardableResult
  func openMaterialFile(for record: RecordingRecord, track: AudioTrackKind) -> Bool {
    guard let url = materialURL(for: record, track: track),
      FileManager.default.fileExists(atPath: url.path)
    else {
      errorMessage = "这条录音的\(track.label)文件不存在。"
      presentActionFeedback(.failure("无法打开\(track.label)"))
      return false
    }
    guard NSWorkspace.shared.open(url) else {
      errorMessage = "macOS 没有打开这个音频文件。"
      presentActionFeedback(.failure("打开\(track.label)失败"))
      return false
    }
    presentActionFeedback(.success("已用默认应用打开\(track.label)"))
    return true
  }

  @discardableResult
  func revealMaterialFiles(for record: RecordingRecord) -> Bool {
    let audioURLs = [AudioTrackKind.microphone, .systemAudio, .meetingMix]
      .compactMap { materialURL(for: record, track: $0) }
      .filter { FileManager.default.fileExists(atPath: $0.path) }
    let urls =
      audioURLs
      + [store.originalMediaURL(for: record)].compactMap { $0 }
      .filter { FileManager.default.fileExists(atPath: $0.path) }
    guard !urls.isEmpty else {
      errorMessage = "没有找到这条录音的已保存音频文件。"
      presentActionFeedback(.failure("没有可显示的音频文件"))
      return false
    }
    NSWorkspace.shared.activateFileViewerSelecting(urls)
    presentActionFeedback(.success("已在 Finder 中显示录音文件"))
    return true
  }

  private func materialURL(for record: RecordingRecord, track: AudioTrackKind) -> URL? {
    switch track {
    case .microphone:
      return store.audioURL(for: record)
    case .systemAudio:
      return store.systemAudioURL(for: record)
    case .meetingMix:
      guard record.meetingMixFileName != nil else { return nil }
      return store.meetingMixURL(for: record)
    }
  }

  func exportMarkdown(for record: RecordingRecord) -> URL? {
    guard let transcript = record.transcript, !transcript.isEmpty else {
      errorMessage = "这条录音还没有转写原文。"
      presentActionFeedback(.failure("还没有可导出的原文"))
      return nil
    }
    let directory =
      settings.exportDirectory.isEmpty ? nil : URL(fileURLWithPath: settings.exportDirectory)
    let url = store.markdownURL(for: record, directory: directory)
    let markdown = MarkdownRenderer.render(
      title: record.title, transcript: transcript, generatedMarkdown: record.generatedMarkdown)
    do {
      try markdown.data(using: .utf8)?.write(to: url, options: .atomic)
      presentActionFeedback(.success("Markdown 已导出"))
      return url
    } catch {
      errorMessage = error.localizedDescription
      presentActionFeedback(.failure("导出失败：\(error.localizedDescription)"))
      return nil
    }
  }

  private func exportableTranscript(for record: RecordingRecord) throws -> String {
    guard let transcript = record.transcript, !transcript.isEmpty else {
      throw WoiceError.transcriptMissing
    }
    let normalized = TranscriptTextNormalizer.normalize(transcript)
    guard !normalized.isEmpty else { throw WoiceError.transcriptMissing }
    return normalized
  }

  private func audioFileManifest(for record: RecordingRecord) -> [String: String] {
    var manifest = ["microphone": record.audioFileName]
    if let systemAudioFileName = record.systemAudioFileName {
      manifest["systemAudio"] = systemAudioFileName
    }
    if let meetingMixFileName = record.meetingMixFileName {
      manifest["meetingMix"] = meetingMixFileName
    }
    return manifest
  }

  private func copyAudioExport(source: URL, record: RecordingRecord, suffix: String) throws -> URL {
    guard FileManager.default.fileExists(atPath: source.path) else {
      throw WoiceError.audioFileMissing
    }
    let target = exportURL(for: record, suffix: suffix)
    if FileManager.default.fileExists(atPath: target.path) {
      try FileManager.default.removeItem(at: target)
    }
    try FileManager.default.copyItem(at: source, to: target)
    return target
  }

  private func writeExport(_ data: Data, record: RecordingRecord, suffix: String) throws -> URL {
    let target = exportURL(for: record, suffix: suffix)
    try data.write(to: target, options: .atomic)
    return target
  }

  private func exportURL(for record: RecordingRecord, suffix: String) -> URL {
    let directory = settings.exportDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
    let customDirectory = directory.isEmpty ? nil : URL(fileURLWithPath: directory)
    return store.exportURL(for: record, suffix: suffix, directory: customDirectory)
  }

  @discardableResult
  func moveToTrash(record: RecordingRecord) -> Bool {
    guard recordings.contains(where: { $0.id == record.id }) else {
      presentActionFeedback(.failure("这条素材已经不在列表中"))
      return false
    }
    guard activeRecordingID != record.id else {
      presentActionFeedback(.failure("正在录音，结束并保存后才能删除"))
      return false
    }

    let fileManager = FileManager.default
    let stagingRoot = store.rootURL.appendingPathComponent(
      ".deletion-staging", isDirectory: true)
    let stagingDirectory = stagingRoot.appendingPathComponent(
      "Woice-\(record.id.uuidString)", isDirectory: true)
    let previousRecordings = recordings
    var movedFiles: [(source: URL, staged: URL)] = []

    do {
      try fileManager.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
      if fileManager.fileExists(atPath: stagingDirectory.path) {
        throw WoiceError.storageFailure("这条素材已有未完成的删除事务。")
      }
      try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: false)
      let manifestURL = stagingDirectory.appendingPathComponent("record.json")
      try JSONEncoder.woice.encode(record).write(to: manifestURL, options: .atomic)

      for source in materialURLsForDeletion(record: record) {
        let staged = stagingDirectory.appendingPathComponent(source.lastPathComponent)
        try fileManager.moveItem(at: source, to: staged)
        movedFiles.append((source: source, staged: staged))
      }

      recordings.removeAll { $0.id == record.id }
      guard persistRecordings() else {
        recordings = previousRecordings
        restoreStagedMaterial(movedFiles, stagingDirectory: stagingDirectory)
        _ = persistRecordings()
        presentActionFeedback(.failure("删除失败，素材和索引已恢复"))
        return false
      }

      do {
        try recycleMaterialDirectory(stagingDirectory)
      } catch {
        recordings = previousRecordings
        restoreStagedMaterial(movedFiles, stagingDirectory: stagingDirectory)
        _ = persistRecordings()
        throw error
      }

      try? fileManager.removeItem(at: stagingRoot)
      errorMessage = nil
      presentActionFeedback(.success("素材已移到废纸篓"))
      return true
    } catch {
      recordings = previousRecordings
      restoreStagedMaterial(movedFiles, stagingDirectory: stagingDirectory)
      _ = persistRecordings()
      errorMessage = error.localizedDescription
      presentActionFeedback(.failure("无法移到废纸篓：\(error.localizedDescription)"))
      return false
    }
  }

  private func materialURLsForDeletion(record: RecordingRecord) -> [URL] {
    var candidates = [store.audioURL(for: record), store.meetingMixURL(for: record)]
    if let originalMediaURL = store.originalMediaURL(for: record) {
      candidates.append(originalMediaURL)
    }
    if let systemAudioURL = store.systemAudioURL(for: record) {
      candidates.append(systemAudioURL)
    }
    candidates.append(store.backgroundTranscriptionURL(for: record.id))
    if let related = try? FileManager.default.contentsOfDirectory(
      at: store.recordingsURL,
      includingPropertiesForKeys: [.isRegularFileKey],
      options: []
    ) {
      candidates.append(
        contentsOf: related.filter { $0.lastPathComponent.contains(record.id.uuidString) })
    }

    var seen: Set<String> = []
    return candidates.filter { url in
      guard FileManager.default.fileExists(atPath: url.path) else { return false }
      return seen.insert(url.standardizedFileURL.path).inserted
    }
  }

  private func restoreStagedMaterial(
    _ movedFiles: [(source: URL, staged: URL)], stagingDirectory: URL
  ) {
    let fileManager = FileManager.default
    for move in movedFiles.reversed() where fileManager.fileExists(atPath: move.staged.path) {
      try? fileManager.moveItem(at: move.staged, to: move.source)
    }
    try? fileManager.removeItem(at: stagingDirectory)
  }

  private func startRecordingTimer() {
    stopRecordingTimer()
    recordingTimerTask = Task { @MainActor [weak self] in
      while !Task.isCancelled {
        guard let self, self.recorder.isRecording else { return }
        self.elapsed = self.recorder.capturedDuration
        self.inputLevel = self.recorder.inputLevel
        self.receivedBufferCount = self.recorder.receivedBufferCount
        self.audioActivity = self.recorder.activity.state
        self.audioSegmentCount = self.recorder.activity.segmentCount
        self.voiceDuration = self.recorder.activity.totalVoiceDuration
        let liveSnapshot = self.liveTranscription.snapshot()
        self.liveTranscript = liveSnapshot.text
        self.liveTranscriptionState = liveSnapshot.state
        try? await Task.sleep(for: .milliseconds(100))
      }
    }
  }

  private func stopRecordingTimer() {
    recordingTimerTask?.cancel()
    recordingTimerTask = nil
    inputLevel = 0
    receivedBufferCount = 0
    audioActivity = .waiting
    audioSegmentCount = 0
    voiceDuration = 0
  }

  private func systemAudioDiagnostic(for result: SystemAudioCaptureResult) -> String? {
    guard settings.captureSystemAudio else { return nil }
    guard result.hasAudibleSignal else {
      return
        "未检测到可听见的系统声音；请确认视频或会议正在播放且输出设备未静音。麦克风原始录音仍已保留。"
    }
    return nil
  }

  private func updateRecord(id: UUID, mutate: (inout RecordingRecord) -> Void) {
    guard let index = recordings.firstIndex(where: { $0.id == id }) else { return }
    mutate(&recordings[index])
    persistRecordings()
  }

  private func taskKey(recordID: UUID, kind: ProcessingTaskKind) -> String {
    taskKey(recordID: recordID, kind: kind, sourceTrack: nil)
  }

  private func hasActiveMainTranscription(for record: RecordingRecord) -> Bool {
    record.processingTasks.contains {
      $0.kind == .transcription
        && ($0.status == .waitingForModel
          || $0.status == .awaitingAuthorization || $0.status == .running
          || ($0.status == .queued && $0.blockReason == .authorizationRequired))
    }
  }

  /// Repairs the pre-MSS task shape where a standard meeting-mix task could
  /// have a `meetingMix` idempotency key but no source track. It also removes
  /// cancelled/awaiting duplicates left by an interrupted confirmation queue.
  @discardableResult
  private func normalizeLegacyMeetingTasks() -> Bool {
    var didChange = false
    for recordIndex in recordings.indices {
      let record = recordings[recordIndex]
      guard record.meetingTranscriptionMode == .standardMix,
        record.meetingMixFileName != nil
      else { continue }
      var normalized: [ProcessingTask] = []
      var indexesByKey: [String: Int] = [:]
      for task in recordings[recordIndex].processingTasks {
        guard task.kind == .transcription else {
          normalized.append(task)
          continue
        }
        let needsMeetingMix =
          task.sourceTrack == nil
          && (task.idempotencyKey.contains("meetingMix")
            || task.meetingTranscriptionMode == .standardMix)
        let repaired =
          needsMeetingMix
          ? ProcessingTask(
            kind: task.kind,
            idempotencyKey: taskKey(
              recordID: record.id, kind: .transcription, sourceTrack: .meetingMix),
            status: task.status,
            attempt: task.attempt,
            createdAt: task.createdAt,
            updatedAt: task.updatedAt,
            lastError: task.lastError,
            providerID: task.providerID,
            modelID: task.modelID,
            modelVersion: task.modelVersion,
            dataLocation: task.dataLocation,
            capability: task.capability,
            configurationHash: task.configurationHash,
            blockReason: task.blockReason,
            sourceTrack: .meetingMix,
            meetingTranscriptionMode: .standardMix)
          : task
        if repaired != task { didChange = true }
        if let previousIndex = indexesByKey[repaired.idempotencyKey] {
          let previous = normalized[previousIndex]
          // A completed/running task wins over a cancelled confirmation; for
          // equal priority keep the most recently updated record.
          let previousPriority = taskStatusPriority(previous.status)
          let currentPriority = taskStatusPriority(repaired.status)
          if currentPriority > previousPriority
            || (currentPriority == previousPriority && repaired.updatedAt > previous.updatedAt)
          {
            normalized[previousIndex] = repaired
          }
          didChange = true
        } else {
          indexesByKey[repaired.idempotencyKey] = normalized.count
          normalized.append(repaired)
        }
      }
      if normalized != recordings[recordIndex].processingTasks {
        recordings[recordIndex].processingTasks = normalized
        didChange = true
      }
    }
    for recordIndex in recordings.indices {
      let hasMain = hasActiveMainTranscription(for: recordings[recordIndex])
      guard hasMain else { continue }
      for taskIndex in recordings[recordIndex].processingTasks.indices {
        guard recordings[recordIndex].processingTasks[taskIndex].kind == .segmentTranscription,
          recordings[recordIndex].processingTasks[taskIndex].status == .awaitingAuthorization
            || recordings[recordIndex].processingTasks[taskIndex].status == .running
        else { continue }
        recordings[recordIndex].processingTasks[taskIndex].status = .queued
        recordings[recordIndex].processingTasks[taskIndex].blockReason = .authorizationRequired
        recordings[recordIndex].processingTasks[taskIndex].lastError =
          "主转写任务正在等待或运行；完成后可继续声音片段转写。"
        recordings[recordIndex].processingTasks[taskIndex].updatedAt = Date()
        didChange = true
      }
    }
    return didChange
  }

  /// Build 2026082402 briefly stored source labels in the plain transcript.
  /// Preserve that immutable version, then publish a new presentation-clean
  /// artifact rebuilt from the already structured segments.
  private func normalizeLegacyTranscriptSourceLabels() -> Bool {
    var didChange = false
    for index in recordings.indices {
      let record = recordings[index]
      guard record.meetingTranscriptionMode == .sourceSeparated,
        let transcript = record.transcript,
        transcript.contains("[我的麦克风]") || transcript.contains("[电脑声音]"),
        let segments = record.transcriptSegments,
        !segments.isEmpty
      else { continue }
      let cleanText = TranscriptTextNormalizer.normalize(
        segments.map(\.text).joined(separator: "\n"))
      guard !cleanText.isEmpty, cleanText != transcript else { continue }
      let previousArtifact =
        record.activeTranscriptArtifactID.flatMap { activeID in
          record.transcriptArtifacts.first(where: { $0.id == activeID })
        }
        ?? record.transcriptArtifacts.last
      var artifacts = record.transcriptArtifacts
      let cleanArtifact = TranscriptArtifact(
        parentRecordingID: record.id,
        supersedesID: previousArtifact?.id,
        text: cleanText,
        segments: segments,
        providerID: previousArtifact?.providerID,
        modelID: previousArtifact?.modelID,
        modelVersion: previousArtifact?.modelVersion,
        dataLocation: previousArtifact?.dataLocation,
        configurationHash: previousArtifact?.configurationHash,
        sourceTrack: nil,
        meetingTranscriptionMode: .sourceSeparated)
      artifacts.append(cleanArtifact)
      recordings[index].transcriptArtifacts = artifacts
      recordings[index].activeTranscriptArtifactID = cleanArtifact.id
      recordings[index].transcript = cleanText
      didChange = true
    }
    return didChange
  }

  private func taskStatusPriority(_ status: ProcessingTaskStatus) -> Int {
    switch status {
    case .completed: 5
    case .running: 4
    case .awaitingAuthorization, .queued: 3
    case .failed, .interrupted: 2
    case .cancelled: 1
    case .waitingForModel: 0
    }
  }

  private func taskKey(
    recordID: UUID, kind: ProcessingTaskKind, sourceTrack: AudioTrackKind?
  ) -> String {
    let base = recordID.uuidString.lowercased() + ":" + kind.rawValue
    guard let sourceTrack else { return base }
    return base + ":" + sourceTrack.rawValue
  }

  private func transcriptionSourceURL(
    for record: RecordingRecord, sourceTrack: AudioTrackKind? = nil
  ) -> URL {
    if sourceTrack == .meetingMix {
      return store.meetingMixURL(for: record)
    }
    if sourceTrack == nil, record.meetingTranscriptionMode == .standardMix,
      record.meetingMixFileName != nil,
      FileManager.default.fileExists(atPath: store.meetingMixURL(for: record).path)
    {
      return store.meetingMixURL(for: record)
    }
    if sourceTrack == .systemAudio,
      let systemAudioURL = store.systemAudioURL(for: record),
      FileManager.default.fileExists(atPath: systemAudioURL.path)
    {
      return systemAudioURL
    }
    if sourceTrack == nil,
      record.meetingTranscriptionMode == .standardMix,
      record.systemAudioFileName != nil,
      record.processingError?.contains("没有检测到麦克风") == true,
      let systemAudioURL = store.systemAudioURL(for: record),
      FileManager.default.fileExists(atPath: systemAudioURL.path)
    {
      return systemAudioURL
    }
    return store.audioURL(for: record)
  }

  private func preparedTranscriptionInput(
    for record: RecordingRecord, sourceTrack: AudioTrackKind
  ) throws -> (url: URL, isTemporary: Bool) {
    let sourceURL = transcriptionSourceURL(for: record, sourceTrack: sourceTrack)
    if sourceTrack == .meetingMix,
      !FileManager.default.fileExists(atPath: sourceURL.path)
    {
      throw WoiceError.audioFileMissing
    }
    guard sourceTrack == .systemAudio else {
      return (sourceURL, false)
    }
    let workingDirectory = store.rootURL.appendingPathComponent("working", isDirectory: true)
    try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
    let outputURL = workingDirectory.appendingPathComponent(
      "\(record.id.uuidString).system-asr.wav")
    _ = try AudioPreparationService.prepareMeetingMix(
      microphoneURL: nil,
      systemAudioURL: sourceURL,
      outputURL: outputURL)
    return (outputURL, true)
  }

  private func transcriptionSourceTrack(for record: RecordingRecord) -> AudioTrackKind {
    if record.meetingMixFileName != nil, record.meetingTranscriptionMode == .standardMix {
      return .meetingMix
    }
    if record.processingError?.contains("没有检测到麦克风") == true,
      record.systemAudioFileName != nil
    {
      return .systemAudio
    }
    return .microphone
  }

  private func transcriptionSourceDescription(_ track: AudioTrackKind?) -> String {
    switch track {
    case .meetingMix: "会议完整回放"
    case .microphone: "我的声音"
    case .systemAudio: "电脑声音"
    case nil: "录音素材"
    }
  }

  private func transcriptionTracks(for record: RecordingRecord) -> [AudioTrackKind] {
    if record.meetingTranscriptionMode == .sourceSeparated {
      var rawTracks: [AudioTrackKind] = []
      if FileManager.default.fileExists(atPath: store.audioURL(for: record).path) {
        rawTracks.append(.microphone)
      }
      if let systemURL = store.systemAudioURL(for: record),
        FileManager.default.fileExists(atPath: systemURL.path)
      {
        rawTracks.append(.systemAudio)
      }
      if !rawTracks.isEmpty { return rawTracks }
    }
    let tracks = record.processingTasks
      .filter { $0.kind == .transcription }
      .compactMap(\.sourceTrack)
    if !tracks.isEmpty { return tracks }
    return [transcriptionSourceTrack(for: record)]
  }

  /// Real meeting samples showed that pre-mixing overlapping speech can make
  /// Whisper consistently omit one side. Historical dual-track recordings are
  /// therefore upgraded only when the user explicitly asks to transcribe
  /// again; immutable audio and previous Transcript Artifacts stay untouched.
  private func prepareReliableMeetingTranscription(
    for record: RecordingRecord
  ) -> RecordingRecord {
    guard FileManager.default.fileExists(atPath: store.audioURL(for: record).path),
      let systemURL = store.systemAudioURL(for: record),
      FileManager.default.fileExists(atPath: systemURL.path)
    else { return record }
    guard record.meetingTranscriptionMode != .sourceSeparated else { return record }
    updateRecord(id: record.id) {
      $0.meetingTranscriptionMode = .sourceSeparated
      $0.processingError = nil
    }
    return recordings.first(where: { $0.id == record.id }) ?? record
  }

  private func updateProcessingTask(
    recordID: UUID, kind: ProcessingTaskKind, mutate: (inout ProcessingTask) -> Void
  ) {
    updateProcessingTask(recordID: recordID, kind: kind, sourceTrack: nil, mutate: mutate)
  }

  private func updateProcessingTask(
    recordID: UUID,
    kind: ProcessingTaskKind,
    sourceTrack: AudioTrackKind?,
    mutate: (inout ProcessingTask) -> Void
  ) {
    guard let index = recordings.firstIndex(where: { $0.id == recordID }) else { return }
    if let taskIndex = recordings[index].processingTasks.firstIndex(where: {
      $0.kind == kind
        && (sourceTrack == nil || $0.sourceTrack == sourceTrack
          || (sourceTrack == .microphone && $0.sourceTrack == nil))
    }) {
      mutate(&recordings[index].processingTasks[taskIndex])
    } else {
      var task = ProcessingTask(
        kind: kind,
        idempotencyKey: taskKey(recordID: recordID, kind: kind, sourceTrack: sourceTrack),
        sourceTrack: sourceTrack)
      mutate(&task)
      recordings[index].processingTasks.append(task)
    }
    persistRecordings()
  }

  private func markProcessingTaskFailed(
    recordID: UUID, kind: ProcessingTaskKind, message: String
  ) {
    markProcessingTaskFailed(recordID: recordID, kind: kind, sourceTrack: nil, message: message)
  }

  private func markProcessingTaskFailed(
    recordID: UUID,
    kind: ProcessingTaskKind,
    sourceTrack: AudioTrackKind?,
    message: String
  ) {
    updateProcessingTask(recordID: recordID, kind: kind, sourceTrack: sourceTrack) {
      $0.status = .failed
      $0.updatedAt = Date()
      $0.lastError = message
    }
  }

  private func recoverInterruptedTasks() {
    var didChange = false
    for index in recordings.indices {
      for taskIndex in recordings[index].processingTasks.indices {
        let status = recordings[index].processingTasks[taskIndex].status
        guard status == .running || status == .awaitingAuthorization else { continue }
        recordings[index].processingTasks[taskIndex].status = .interrupted
        recordings[index].processingTasks[taskIndex].updatedAt = Date()
        recordings[index].processingTasks[taskIndex].lastError =
          "应用上次关闭时任务未完成，请手动重试。"
        didChange = true
      }
    }
    if didChange { persistRecordings() }
  }

  /// Rehydrates a durable queued job into the same explicit confirmation used
  /// after a fresh recording. This never sends data during app startup.
  private func restoreQueuedProcessingAuthorization() {
    guard pendingExternalProcessing == nil else { return }
    for record in recordings {
      let queuedTranscriptionTasks = record.processingTasks.filter {
        $0.status == .queued && $0.kind == .transcription
      }
      if !queuedTranscriptionTasks.isEmpty,
        settings.asrProviderSelection == .external,
        !settings.asrEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      {
        if canAutoProcessLocalExternalASR {
          for task in queuedTranscriptionTasks {
            Task { @MainActor [weak self] in
              guard let self else { return }
              await self.transcribe(
                recordID: record.id, endpoint: self.settings.asrEndpoint,
                apiKey: self.settings.asrAPIKey, model: self.settings.asrModel,
                language: self.settings.language,
                includeSegments: self.settings.includeTranscriptTimestamps,
                sourceTrack: task.sourceTrack)
            }
          }
        } else {
          for task in queuedTranscriptionTasks {
            requestExternalProcessing(
              for: record.id, kind: .transcription, endpoint: settings.asrEndpoint,
              sourceTrack: task.sourceTrack, rehydrateQueuedTask: true)
          }
        }
      }
      if !hasActiveMainTranscription(for: record),
        record.processingTasks.contains(
          where: { $0.status == .queued && $0.kind == .segmentTranscription }
        ), settings.asrProviderSelection == .external,
        !settings.asrEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      {
        requestExternalProcessing(
          for: record.id, kind: .segmentTranscription, endpoint: settings.asrEndpoint,
          rehydrateQueuedTask: true)
      }
      if record.processingTasks.contains(
        where: { $0.status == .queued && $0.kind == .languageModel }
      ), !settings.llmEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
        record.transcript?.isEmpty == false
      {
        requestExternalProcessing(
          for: record.id, kind: .languageModel, endpoint: settings.llmEndpoint,
          rehydrateQueuedTask: true)
      }
    }
  }

  private func withdrawExternalASRRequestsForLocalRoute() {
    let isASRRequest: (ExternalProcessingRequest) -> Bool = {
      $0.kind == .transcription || $0.kind == .segmentTranscription
    }
    if let request = pendingExternalProcessing, isASRRequest(request) {
      pendingExternalProcessing = nil
    }
    queuedExternalProcessing.removeAll(where: isASRRequest)

    var didChange = false
    for recordIndex in recordings.indices {
      for taskIndex in recordings[recordIndex].processingTasks.indices {
        let task = recordings[recordIndex].processingTasks[taskIndex]
        guard task.kind == .transcription || task.kind == .segmentTranscription else { continue }
        guard
          task.status == .awaitingAuthorization
            || (task.status == .queued && task.blockReason == .authorizationRequired)
        else { continue }
        recordings[recordIndex].processingTasks[taskIndex].status = .interrupted
        recordings[recordIndex].processingTasks[taskIndex].blockReason = nil
        recordings[recordIndex].processingTasks[taskIndex].lastError =
          "转写目标已切换为本机模型；原始录音安全保留，请重试。"
        recordings[recordIndex].processingTasks[taskIndex].updatedAt = Date()
        didChange = true
      }
    }
    if didChange { _ = persistRecordings() }
    if pendingExternalProcessing == nil { presentNextExternalProcessing() }
    if pendingExternalProcessing == nil, processingState == .awaitingAuthorization {
      processingState = .saved
    }
  }

  private func presentNextExternalProcessing() {
    guard pendingExternalProcessing == nil, !queuedExternalProcessing.isEmpty else { return }
    pendingExternalProcessing = queuedExternalProcessing.removeFirst()
    if let request = pendingExternalProcessing {
      updateProcessingTask(
        recordID: request.recordID, kind: request.kind.taskKind, sourceTrack: request.sourceTrack
      ) {
        $0.status = .awaitingAuthorization
        $0.blockReason = .authorizationRequired
        $0.lastError = nil
        $0.updatedAt = Date()
      }
    }
    processingState = .awaitingAuthorization
  }

  private func isUsableAudioFile(at url: URL) -> Bool {
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
      let size = attributes[.size] as? NSNumber
    else { return false }
    // Size alone is insufficient: a partially finalized WAV can contain PCM
    // bytes while advertising a zero-length data chunk. Parse the committed
    // header before exposing the file to playback or an ASR provider.
    guard size.int64Value > 44,
      let audioFile = try? AVAudioFile(forReading: url),
      audioFile.length > 0,
      audioFile.fileFormat.sampleRate > 0
    else { return false }
    return true
  }

  nonisolated static func shouldPreserveRecording(
    microphoneFileIsUsable: Bool, systemAudioIsUsable: Bool
  ) -> Bool {
    microphoneFileIsUsable || systemAudioIsUsable
  }

  private func endpointValidation(for endpoint: String, name: String) -> String? {
    let value = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else { return nil }
    guard let url = URL(string: value),
      let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
      url.host != nil
    else { return "\(name)接口地址必须是完整的 HTTP(S) URL。" }
    return nil
  }

  private func dataLocation(for endpoint: String) -> ASRDataLocation {
    guard let url = URL(string: endpoint), let host = url.host?.lowercased() else {
      return .cloud
    }
    if host == "localhost" || host == "127.0.0.1" || host == "::1" {
      return .onDevice
    }
    if host.hasPrefix("10.") || host.hasPrefix("192.168.") || host.hasPrefix("172.16.") {
      return .localNetwork
    }
    return .cloud
  }

  private func localASRTrustConfigurationHash(
    endpoint: String, model: String, language: String, includeTimestamps: Bool
  ) -> String {
    let payload = [
      "schema=local-asr-trust-v1",
      "endpoint=\(normalizedEndpointKey(endpoint))",
      "model=\(model.trimmingCharacters(in: .whitespacesAndNewlines))",
      "language=\(language)",
      "timestamps=\(includeTimestamps)",
    ].joined(separator: "\n")
    let digest = SHA256.hash(data: Data(payload.utf8))
    return "sha256-v1:" + digest.map { String(format: "%02x", $0) }.joined()
  }

  private func isValidLocalASRTrust(
    _ trust: LocalASRTrustSnapshot, for candidate: AppSettings
  ) -> Bool {
    guard candidate.asrProviderSelection == .external,
      dataLocation(for: candidate.asrEndpoint) == .onDevice
    else { return false }
    return trust.matches(
      endpointIdentity: normalizedEndpointKey(candidate.asrEndpoint),
      modelID: candidate.asrModel,
      language: candidate.language,
      includeTimestamps: candidate.includeTranscriptTimestamps,
      configurationHash: localASRTrustConfigurationHash(
        endpoint: candidate.asrEndpoint,
        model: candidate.asrModel,
        language: candidate.language,
        includeTimestamps: candidate.includeTranscriptTimestamps))
  }

  /// Returns a stable, non-secret digest for the configuration actually used
  /// by a processing task. Endpoint credentials, query strings and fragments
  /// are intentionally excluded; API keys never enter this payload.
  private func processingConfigurationHash(
    kind: ProcessingTaskKind,
    providerID: String,
    modelID: String?,
    modelVersion: String?,
    dataLocation: ASRDataLocation?,
    capability: ASRProviderCapability?,
    endpoint: String?,
    language: String,
    includeTimestamps: Bool,
    sourceTrack: AudioTrackKind?,
    meetingMode: MeetingTranscriptionMode?
  ) -> String {
    let endpointIdentity: String
    if let endpoint,
      let url = URL(string: endpoint),
      var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    {
      components.user = nil
      components.password = nil
      components.query = nil
      components.fragment = nil
      components.scheme = components.scheme?.lowercased()
      components.host = components.host?.lowercased()
      endpointIdentity = components.string ?? ""
    } else {
      endpointIdentity = endpoint?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
    let payload = [
      "schema=sha256-v1",
      "kind=\(kind.rawValue)",
      "provider=\(providerID)",
      "model=\(modelID ?? "")",
      "version=\(modelVersion ?? "")",
      "location=\(dataLocation?.rawValue ?? "")",
      "capability=\(capability?.rawValue ?? "")",
      "endpoint=\(endpointIdentity)",
      "language=\(language)",
      "timestamps=\(includeTimestamps)",
      "track=\(sourceTrack?.rawValue ?? "")",
      "meeting=\(meetingMode?.rawValue ?? "")",
    ].joined(separator: "\n")
    let digest = SHA256.hash(data: Data(payload.utf8))
    return "sha256-v1:" + digest.map { String(format: "%02x", $0) }.joined()
  }

  private func writeASRHealthCheckAudio(to url: URL) throws {
    guard let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1),
      let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 5_600)
    else {
      throw WoiceError.microphoneUnavailable
    }
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    buffer.frameLength = 5_600
    guard let samples = buffer.floatChannelData?[0] else {
      throw WoiceError.invalidResponse
    }
    for frame in 0..<Int(buffer.frameLength) {
      samples[frame] = sin(Float(frame) * 2 * .pi * 440 / 16_000) * 0.02
    }
    try file.write(from: buffer)
    if #available(macOS 15.0, *) {
      file.close()
    }
  }

  private func modelValidation(endpoint: String, model: String, name: String) -> String? {
    guard !endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return "已配置\(name)接口时，模型不能为空。"
    }
    return nil
  }

  private func recoverInterruptedRecordingSession() {
    guard let journal = store.loadRecordingSession() else { return }
    if recordings.contains(where: { $0.id == journal.id }) {
      store.clearRecordingSession()
      return
    }

    let microphoneURL = store.recordingsURL.appendingPathComponent(journal.audioFileName)
    let microphone = audioFileMetadata(at: microphoneURL)
    let systemURL = journal.systemAudioFileName.map {
      store.recordingsURL.appendingPathComponent($0)
    }
    let system = systemURL.flatMap(audioFileMetadata(at:))
    guard microphone != nil || system != nil else {
      store.clearRecordingSession()
      return
    }

    let backgroundJournal = store.loadBackgroundTranscriptionJournal(for: journal.id)
    let recoveredSegments =
      backgroundJournal?.results.values
      .flatMap { $0 }
      .sorted { $0.start < $1.start } ?? []
    let recoveredTranscript =
      recoveredSegments.isEmpty
      ? nil : recoveredSegments.map(\.text).joined(separator: "\n")
    var recoveredMeetingMixFileName: String?
    if microphone != nil, system != nil, let systemURL {
      let mixURL = store.recordingsURL.appendingPathComponent(
        "\(journal.id.uuidString).meeting-mix.wav")
      if (try? AudioPreparationService.prepareMeetingMix(
        microphoneURL: microphoneURL,
        systemAudioURL: systemURL,
        outputURL: mixURL)) != nil
      {
        recoveredMeetingMixFileName = mixURL.lastPathComponent
      }
    }
    let recoveredTask: ProcessingTask? = backgroundJournal.map { journal in
      ProcessingTask(
        kind: .transcription,
        idempotencyKey: taskKey(
          recordID: journal.recordID, kind: .transcription, sourceTrack: .microphone),
        status: .interrupted,
        lastError: recoveredSegments.isEmpty
          ? "上次录音未正常结束；请手动转写。"
          : "上次录音未正常结束；已恢复部分后台原文，请手动完成转写。",
        providerID: journal.providerID,
        modelID: journal.modelID,
        modelVersion: journal.modelVersion,
        dataLocation: journal.dataLocation,
        capability: .transcription,
        configurationHash: journal.configurationHash,
        sourceTrack: .microphone)
    }

    let record = RecordingRecord(
      id: journal.id,
      createdAt: journal.createdAt,
      audioFileName: journal.audioFileName,
      duration: max(microphone?.duration ?? 0, system?.duration ?? 0),
      transcript: recoveredTranscript,
      generatedMarkdown: nil,
      processingError: recoveredTranscript == nil
        ? "上次录音未正常结束；已恢复音频，请手动转写。"
        : "上次录音未正常结束；已恢复部分后台原文，请手动完成转写。",
      systemAudioFileName: system == nil ? nil : journal.systemAudioFileName,
      systemAudioDuration: system?.duration,
      meetingMixFileName: recoveredMeetingMixFileName,
      meetingTranscriptionMode: journal.captureSystemAudio && system != nil
        ? .sourceSeparated : nil,
      transcriptSegments: recoveredSegments.isEmpty ? nil : recoveredSegments,
      processingTasks: recoveredTask.map { [$0] } ?? [])
    let previous = recordings
    recordings.insert(record, at: 0)
    guard persistRecordings() else {
      recordings = previous
      return
    }
    store.clearRecordingSession()
    store.clearBackgroundTranscriptionJournal(for: journal.id)
    errorMessage = "检测到上次未完成的录音；音频已恢复，请在详情页手动转写。"
  }

  private func audioFileMetadata(at url: URL) -> (
    duration: TimeInterval, frameCount: AVAudioFramePosition
  )? {
    guard FileManager.default.fileExists(atPath: url.path),
      let file = try? AVAudioFile(forReading: url), file.processingFormat.sampleRate > 0,
      file.length > 0
    else { return nil }
    return (
      duration: Double(file.length) / file.processingFormat.sampleRate,
      frameCount: file.length
    )
  }

  @discardableResult
  private func persistRecordings() -> Bool {
    do {
      try store.saveRecordings(recordings)
      return true
    } catch {
      errorMessage = error.localizedDescription
      return false
    }
  }
}
