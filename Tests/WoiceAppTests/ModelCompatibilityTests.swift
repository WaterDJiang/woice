import Foundation
import Testing
import WoiceCore

@testable import WoiceApp

@Test("旧设置和历史录音 JSON 缺少双轨字段时仍可读取")
func legacyModelsDecodeWithoutDualTrackFields() throws {
  let settingsJSON = Data(#"{"asrModel":"whisper-1","language":"zh"}"#.utf8)
  let settings = try JSONDecoder.woice.decode(AppSettings.self, from: settingsJSON)
  #expect(settings.captureMicrophone)
  #expect(settings.captureSystemAudio)
  #expect(settings.meetingTranscriptionMode == .sourceSeparated)
  #expect(settings.includeTranscriptTimestamps == false)
  #expect(settings.autoPasteTranscript == false)
  #expect(settings.recordingShortcut == .optionSpace)
  #expect(settings.asrProviderSelection == .onDevice)
  let invalidShortcut = try JSONDecoder.woice.decode(
    AppSettings.self, from: Data(#"{"recordingShortcut":"futureKey"}"#.utf8))
  #expect(invalidShortcut.recordingShortcut == .optionSpace)
  var persistedSettings = settings
  persistedSettings.captureSystemAudio = true
  let persistedJSON = try JSONEncoder.woice.encode(persistedSettings)
  #expect(String(data: persistedJSON, encoding: .utf8)?.contains("captureSystemAudio") == true)

  let id = UUID()
  let recordingJSON = Data(
    """
    {"id":"\(id.uuidString)","createdAt":"2026-08-22T00:00:00Z","audioFileName":"old.wav","duration":1.2}
    """.utf8
  )
  let record = try JSONDecoder.woice.decode(RecordingRecord.self, from: recordingJSON)
  #expect(record.systemAudioFileName == nil)
  #expect(record.systemAudioBufferCount == nil)
  #expect(record.systemAudioPeakLevel == nil)
  #expect(record.systemAudioDuration == nil)
  #expect(record.systemAudioStartOffset == nil)
  #expect(record.systemAudioCaptureTarget == nil)
  #expect(record.meetingMixFileName == nil)
  #expect(record.meetingTranscriptionMode == nil)
  #expect(record.systemAudioError == nil)
  #expect(record.transcriptSegments == nil)
  #expect(record.transcriptArtifacts.isEmpty)
  #expect(record.activeTranscriptArtifactID == nil)
  #expect(record.voiceSegments == nil)
  #expect(record.processingTasks.isEmpty)
}

@Test("旧版单次混音设置迁移为可靠双轨转写，迁移后显式选择可往返")
func legacyMeetingModeMigratesOnce() throws {
  let legacy = Data(#"{"meetingTranscriptionMode":"standardMix"}"#.utf8)
  let migrated = try JSONDecoder.woice.decode(AppSettings.self, from: legacy)
  #expect(migrated.meetingTranscriptionMode == .sourceSeparated)

  var explicit = AppSettings.default
  explicit.meetingTranscriptionMode = .standardMix
  let encoded = try JSONEncoder.woice.encode(explicit)
  let roundTrip = try JSONDecoder.woice.decode(AppSettings.self, from: encoded)
  #expect(roundTrip.meetingTranscriptionMode == .standardMix)
}

@Test("旧 ASR 字段迁移到统一 Provider 配置且新编码不含 API Key")
func legacyASRSettingsMigrateToProviderConfiguration() throws {
  let legacy = Data(
    #"{"asrProviderSelection":"external","asrEndpoint":"http://127.0.0.1:9000/v1","asrModel":"whisper-local","asrAPIKey":"must-not-persist","language":"zh"}"#
      .utf8
  )
  let settings = try JSONDecoder.woice.decode(AppSettings.self, from: legacy)
  #expect(settings.asrConfiguration.selection == .external)
  #expect(settings.asrConfiguration.endpoint == "http://127.0.0.1:9000/v1")
  #expect(settings.asrConfiguration.modelID == "whisper-local")
  #expect(settings.asrConfiguration.apiKey == "must-not-persist")
  #expect(settings.asrConfiguration.effectiveProviderID == "com.woice.openai-compatible-asr")
  #expect(settings.asrConfiguration.transport == .http)
  #expect(settings.asrConfiguration.dataLocation == .localNetwork)
  #expect(settings.asrConfiguration.isConfigured)

  let encoded = try JSONEncoder.woice.encode(settings)
  let encodedText = try #require(String(data: encoded, encoding: .utf8))
  #expect(encodedText.contains("asrConfiguration"))
  #expect(!encodedText.contains("asrAPIKey"))
  #expect(!encodedText.contains("llmAPIKey"))

  let roundTrip = try JSONDecoder.woice.decode(AppSettings.self, from: encoded)
  #expect(roundTrip.asrConfiguration == settings.asrConfiguration.withoutAPIKey)
}

@Test("统一 Provider 配置按 Endpoint 识别局域网和云端位置")
func providerConfigurationProjectsDataLocation() {
  #expect(AppSettings.default.asrProviderSelection == .onDevice)
  let local = ASRProviderConfiguration(
    selection: .external, endpoint: "http://192.168.1.12:8080/v1", modelID: "whisper")
  #expect(local.dataLocation == .localNetwork)
  let cloud = ASRProviderConfiguration(
    selection: .external, endpoint: "https://api.example.test/v1", modelID: "whisper")
  #expect(cloud.dataLocation == .cloud)
  let automatic = ASRProviderConfiguration(
    selection: .automatic, endpoint: "http://127.0.0.1:8080/v1", modelID: "whisper")
  #expect(automatic.effectiveProviderID == "com.woice.local-asr")
  #expect(automatic.transport == .inProcess)
  #expect(!automatic.usesExternalService)
}

@Test("会议轨道和转写模式契约可编码并保留来源")
func meetingTrackModelsRoundTrip() throws {
  let segment = TranscriptSegment(
    start: 0.2, end: 1.1, text: "电脑声音", sourceTrack: .systemAudio)
  let task = ProcessingTask(
    kind: .transcription,
    idempotencyKey: "recording:transcription:meetingMix",
    sourceTrack: .meetingMix,
    meetingTranscriptionMode: .standardMix)
  let record = RecordingRecord(
    id: UUID(),
    createdAt: Date(),
    audioFileName: "mic.wav",
    duration: 2,
    transcript: "电脑声音",
    generatedMarkdown: nil,
    processingError: nil,
    systemAudioFileName: "system.caf",
    systemAudioDuration: 2,
    systemAudioStartOffset: 0.1,
    meetingMixFileName: "meeting-mix.wav",
    meetingTranscriptionMode: .standardMix,
    systemAudioCaptureTarget: .activeWindow,
    transcriptSegments: [segment],
    processingTasks: [task])
  let data = try JSONEncoder.woice.encode(record)
  let decoded = try JSONDecoder.woice.decode(RecordingRecord.self, from: data)
  #expect(decoded.meetingTranscriptionMode == .standardMix)
  #expect(decoded.transcriptSegments?.first?.sourceTrack == .systemAudio)
  #expect(decoded.processingTasks.first?.sourceTrack == .meetingMix)
  #expect(decoded.processingTasks.first?.meetingTranscriptionMode == .standardMix)
  #expect(decoded.systemAudioCaptureTarget == .activeWindow)
}

@Test("录音素材就绪状态由持久化原文和转写任务确定性投影")
func recordingMaterialStatusProjectsDurableFacts() {
  let base = RecordingRecord(
    id: UUID(), createdAt: Date(), audioFileName: "saved.wav", duration: 1,
    transcript: nil, generatedMarkdown: nil, processingError: nil)
  #expect(base.materialStatus == .saved)

  var waiting = base
  waiting.processingTasks = [
    ProcessingTask(
      kind: .transcription, idempotencyKey: "waiting", status: .waitingForModel)
  ]
  #expect(waiting.materialStatus == .waitingForModel)

  var processing = base
  processing.processingTasks = [
    ProcessingTask(kind: .transcription, idempotencyKey: "running", status: .running)
  ]
  #expect(processing.materialStatus == .processing)

  var ready = base
  ready.transcript = "完成"
  ready.processingTasks = [
    ProcessingTask(kind: .transcription, idempotencyKey: "completed", status: .completed)
  ]
  #expect(ready.materialStatus == .ready)

  var partial = ready
  partial.processingTasks.append(
    ProcessingTask(kind: .transcription, idempotencyKey: "failed", status: .failed))
  #expect(partial.materialStatus == .partiallyReady)
}

@Test("启动时遗留的 ASR 任务会标记为中断并持久化")
@MainActor
func appStateRecoversInterruptedProcessingTask() throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "woice-task-recovery-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let store = WorkspaceStore(storageRootURL: root)
  let recordID = UUID()
  let task = ProcessingTask(
    kind: .transcription,
    idempotencyKey: "\(recordID.uuidString.lowercased()):transcription",
    status: .running
  )
  let record = RecordingRecord(
    id: recordID,
    createdAt: Date(),
    audioFileName: "recovery.wav",
    duration: 1,
    transcript: nil,
    generatedMarkdown: nil,
    processingError: nil,
    processingTasks: [task]
  )
  try store.saveRecordings([record])

  let state = AppState(store: store)
  let recovered = try #require(state.recordings.first?.processingTasks.first)
  #expect(recovered.status == .interrupted)
  #expect(recovered.lastError?.contains("上次关闭") == true)
  let persisted = try #require(store.loadRecordings().first?.processingTasks.first)
  #expect(persisted.status == .interrupted)
}
