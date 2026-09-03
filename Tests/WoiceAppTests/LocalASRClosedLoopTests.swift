import AVFoundation
import Foundation
import Speech
import Testing
import WoiceCore

@testable import WoiceApp

private final class FixtureLocalASR: LocalASRTranscribing, @unchecked Sendable {
  let model = ASRModelDescriptor(
    providerID: "com.woice.fixture.local-asr",
    modelID: "fixture-speech",
    displayName: "Fixture 本机模型",
    version: "14.0.0",
    dataLocation: .onDevice
  )

  func transcribe(audioURL: URL, language: String) async throws -> TranscriptionResult {
    guard FileManager.default.fileExists(atPath: audioURL.path) else {
      throw LocalASRError.audioMissing
    }
    return TranscriptionResult(text: "本机模型转写成功")
  }
}

private final class UnauthorizedLocalASR: LocalASRTranscribing, LocalASRAuthorizationProviding,
  @unchecked Sendable
{
  let model = ASRModelDescriptor(
    providerID: "com.woice.fixture.unauthorized",
    modelID: "fixture-speech",
    displayName: "Fixture 未授权模型",
    version: "14.0.0",
    dataLocation: .onDevice
  )
  private(set) var transcribeCallCount = 0

  var authorizationState: LocalASRAuthorizationState { .notDetermined }

  func requestAuthorization() async -> LocalASRAuthorizationState { .notDetermined }

  func transcribe(audioURL: URL, language: String) async throws -> TranscriptionResult {
    transcribeCallCount += 1
    return TranscriptionResult(text: "不应调用")
  }
}

private actor FixtureCallCounter {
  private(set) var value = 0

  func increment() {
    value += 1
  }
}

private final class DelayedFixtureLocalASR: LocalASRTranscribing, @unchecked Sendable {
  let model = ASRModelDescriptor(
    providerID: "com.woice.fixture.delayed-local-asr",
    modelID: "fixture-large",
    displayName: "Fixture Large 模型",
    version: "large-revision",
    dataLocation: .onDevice
  )
  private let counter = FixtureCallCounter()

  var transcribeCallCount: Int { get async { await counter.value } }

  func transcribe(audioURL: URL, language: String) async throws -> TranscriptionResult {
    guard FileManager.default.fileExists(atPath: audioURL.path) else {
      throw LocalASRError.audioMissing
    }
    await counter.increment()
    try await Task.sleep(for: .milliseconds(120))
    return TranscriptionResult(text: "Large 模型重转写成功")
  }
}

@Test("本机模型版本格式稳定且明确数据位置")
func localASRModelDescriptorHasVersionAndLocation() {
  let model = LocalASRModelCatalog.onDeviceSpeech
  #expect(model.providerID == "com.apple.speech.on-device")
  #expect(model.modelID == "apple-speech-on-device")
  #expect(model.dataLocation == .onDevice)
  #expect(model.version.range(of: #"^[0-9]+\.[0-9]+\.[0-9]+$"#, options: .regularExpression) != nil)
}

@Test("录音详情可通过本机模型完成转写并持久化模型快照")
@MainActor
func localASRClosedLoopPersistsTranscriptAndModelSnapshot() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "woice-local-asr-" + UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }

  let store = WorkspaceStore(storageRootURL: root)
  let audioURL = store.recordingsURL.appendingPathComponent("local.wav")
  let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
  let file = try AVAudioFile(forWriting: audioURL, settings: format.settings)
  let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000))
  buffer.frameLength = 16_000
  try file.write(from: buffer)

  let record = RecordingRecord(
    id: UUID(), createdAt: Date(), audioFileName: audioURL.lastPathComponent, duration: 1,
    transcript: nil, generatedMarkdown: nil, processingError: nil)
  try store.saveRecordings([record])

  let state = AppState(store: store, localTranscription: FixtureLocalASR())
  state.settings.asrProviderSelection = .onDevice
  state.settings.asrEndpoint = ""
  state.requestTranscription(for: record)

  for _ in 0..<20 {
    if state.processingState == .saved { break }
    try await Task.sleep(for: .milliseconds(20))
  }
  let result = try #require(state.recordings.first)
  let task = try #require(result.processingTasks.first(where: { $0.kind == .transcription }))
  #expect(result.transcript == "本机模型转写成功")
  #expect(result.transcriptArtifacts.count == 1)
  #expect(result.activeTranscriptArtifactID == result.transcriptArtifacts.first?.id)
  #expect(result.transcriptArtifacts.first?.modelVersion == "14.0.0")
  #expect(task.status == .completed)
  #expect(task.providerID == "com.woice.fixture.local-asr")
  #expect(task.modelID == "fixture-speech")
  #expect(task.modelVersion == "14.0.0")
  #expect(task.dataLocation == .onDevice)
  #expect(task.capability == .transcription)
  #expect(task.configurationHash?.hasPrefix("sha256-v1:") == true)
  #expect(task.configurationHash?.count == 74)
  #expect(task.blockReason == nil)
  #expect(state.audioFileExists(for: result))
  let persisted = store.loadRecordings()
  #expect(persisted.first?.processingTasks.first?.modelVersion == "14.0.0")
}

@Test("失败的本机转写可在切换模型后重试且重复点击只启动一次")
@MainActor
func failedLocalTranscriptionCanRetryAfterModelSwitchWithoutDuplicateCalls() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "woice-local-asr-retry-" + UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }

  let store = WorkspaceStore(storageRootURL: root)
  let audioURL = store.recordingsURL.appendingPathComponent("retry-large.wav")
  let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
  let file = try AVAudioFile(forWriting: audioURL, settings: format.settings)
  let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000))
  buffer.frameLength = 16_000
  try file.write(from: buffer)

  let recordID = UUID()
  let record = RecordingRecord(
    id: recordID, createdAt: Date(), audioFileName: audioURL.lastPathComponent, duration: 1,
    transcript: "Tiny 模型旧原文", generatedMarkdown: nil,
    processingError: "上一轮本机转写失败。",
    processingTasks: [
      ProcessingTask(
        kind: .transcription,
        idempotencyKey: "\(recordID.uuidString.lowercased()):transcription",
        status: .failed,
        lastError: "上一轮本机转写失败。",
        providerID: "com.woice.whisperkit",
        modelID: "openai-whisper-tiny",
        modelVersion: "tiny-revision",
        dataLocation: .onDevice,
        capability: .transcription)
    ])
  try store.saveRecordings([record])

  let provider = DelayedFixtureLocalASR()
  let state = AppState(store: store, localTranscription: provider)
  state.settings.asrProviderSelection = .onDevice
  state.settings.asrEndpoint = ""
  let loaded = try #require(state.recordings.first)
  state.requestTranscription(for: loaded)
  state.requestTranscription(for: loaded)

  for _ in 0..<40 {
    if state.processingState == .saved { break }
    try await Task.sleep(for: .milliseconds(25))
  }

  let updated = try #require(state.recordings.first)
  #expect(updated.transcript == "Large 模型重转写成功")
  #expect(updated.transcriptArtifacts.count == 2)
  #expect(updated.transcriptArtifacts.first?.text == "Tiny 模型旧原文")
  #expect(updated.transcriptArtifacts.last?.text == "Large 模型重转写成功")
  #expect(updated.transcriptArtifacts.allSatisfy { $0.parentRecordingID == recordID })
  #expect(
    updated.transcriptArtifacts.last?.supersedesID == updated.transcriptArtifacts.first?.id)
  #expect(updated.processingTasks.first?.status == .completed)
  #expect(updated.processingTasks.first?.modelID == "fixture-large")
  #expect(updated.processingTasks.first?.modelVersion == "large-revision")
  #expect(updated.processingTasks.first?.configurationHash?.hasPrefix("sha256-v1:") == true)
  #expect(await provider.transcribeCallCount == 1)

  let oldArtifactID = try #require(updated.transcriptArtifacts.first?.id)
  #expect(state.selectTranscriptArtifact(recordID: recordID, artifactID: oldArtifactID))
  #expect(state.recordings.first?.transcript == "Tiny 模型旧原文")
  #expect(state.recordings.first?.transcriptArtifacts.count == 2)
}

@Test("已完成的本机转写任务可再次转写且不重复启动")
@MainActor
func completedLocalTranscriptionCanBeExplicitlyRetried() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "woice-local-asr-completed-retry-" + UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }

  let store = WorkspaceStore(storageRootURL: root)
  let audioURL = store.recordingsURL.appendingPathComponent("completed.wav")
  let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
  let file = try AVAudioFile(forWriting: audioURL, settings: format.settings)
  let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000))
  buffer.frameLength = 16_000
  try file.write(from: buffer)

  let recordID = UUID()
  let record = RecordingRecord(
    id: recordID, createdAt: Date(), audioFileName: audioURL.lastPathComponent, duration: 1,
    transcript: "上一版本机原文", generatedMarkdown: nil, processingError: nil,
    processingTasks: [
      ProcessingTask(
        kind: .transcription,
        idempotencyKey: "\(recordID.uuidString.lowercased()):transcription",
        status: .completed,
        providerID: "com.woice.whisperkit",
        modelID: "openai-whisper-tiny",
        modelVersion: "tiny-revision",
        dataLocation: .onDevice,
        capability: .transcription)
    ])
  try store.saveRecordings([record])

  let provider = DelayedFixtureLocalASR()
  let state = AppState(store: store, localTranscription: provider)
  state.settings.asrProviderSelection = .onDevice
  state.settings.asrEndpoint = ""
  let before = try FileSHA256.digest(url: audioURL)
  let loaded = try #require(state.recordings.first)
  state.requestTranscription(for: loaded)
  state.requestTranscription(for: loaded)

  for _ in 0..<60 {
    if await provider.transcribeCallCount > 0 { break }
    try await Task.sleep(for: .milliseconds(25))
  }
  for _ in 0..<60 {
    if state.recordings.first?.processingTasks.first?.status == .completed,
      state.recordings.first?.transcript == "Large 模型重转写成功"
    {
      break
    }
    try await Task.sleep(for: .milliseconds(25))
  }

  let updated = try #require(state.recordings.first)
  #expect(await provider.transcribeCallCount == 1)
  #expect(updated.processingTasks.first?.status == .completed)
  #expect(updated.transcript == "Large 模型重转写成功")
  #expect(updated.transcriptArtifacts.count == 2)
  #expect(updated.transcriptArtifacts.first?.text == "上一版本机原文")
  #expect(updated.transcriptArtifacts.last?.text == "Large 模型重转写成功")
  #expect(try FileSHA256.digest(url: audioURL) == before)
}

@Test("失败的外部任务切回本机后重试会刷新实际 Provider 快照")
@MainActor
func failedExternalTranscriptionRetriesWithSelectedLocalProvider() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "woice-external-to-local-retry-" + UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let store = WorkspaceStore(storageRootURL: root)
  let audioURL = store.recordingsURL.appendingPathComponent("retry-local.wav")
  let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
  let file = try AVAudioFile(forWriting: audioURL, settings: format.settings)
  let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000))
  buffer.frameLength = 16_000
  try file.write(from: buffer)

  let recordID = UUID()
  let record = RecordingRecord(
    id: recordID, createdAt: Date(), audioFileName: audioURL.lastPathComponent, duration: 1,
    transcript: nil, generatedMarkdown: nil,
    processingError: "Could not connect to the server.",
    processingTasks: [
      ProcessingTask(
        kind: .transcription,
        idempotencyKey: "\(recordID.uuidString.lowercased()):transcription:microphone",
        status: .failed,
        lastError: "Could not connect to the server.",
        providerID: "openai-compatible.asr",
        modelID: "whisper-1",
        dataLocation: .onDevice,
        capability: .transcription,
        sourceTrack: .microphone)
    ])
  try store.saveRecordings([record])
  var settings = AppSettings.default
  settings.asrProviderSelection = .external
  settings.asrEndpoint = "http://127.0.0.1:8080/v1"
  try store.saveSettings(settings)

  let state = AppState(store: store, localTranscription: FixtureLocalASR())
  state.settings.asrProviderSelection = .onDevice
  state.retryProcessing(for: try #require(state.recordings.first))
  for _ in 0..<20 {
    if state.processingState == .saved { break }
    try await Task.sleep(for: .milliseconds(20))
  }

  let updated = try #require(state.recordings.first)
  let task = try #require(updated.processingTasks.first)
  #expect(updated.transcript == "本机模型转写成功")
  #expect(task.status == .completed)
  #expect(task.providerID == "com.woice.fixture.local-asr")
  #expect(task.modelID == "fixture-speech")
  #expect(task.modelVersion == "14.0.0")
  #expect(task.dataLocation == .onDevice)
  #expect(state.pendingExternalProcessing == nil)
}

@Test("没有可用 Provider 时录音任务进入等待选择模型而不是伪造成功")
@MainActor
func missingASRProviderPersistsWaitingForModel() throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "woice-waiting-model-" + UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let store = WorkspaceStore(storageRootURL: root)
  let record = RecordingRecord(
    id: UUID(),
    createdAt: Date(),
    audioFileName: "waiting.wav",
    duration: 1,
    transcript: nil,
    generatedMarkdown: nil,
    processingError: nil,
    processingTasks: [
      ProcessingTask(
        kind: .transcription,
        idempotencyKey: "waiting-transcription",
        status: .waitingForModel,
        capability: .transcription,
        blockReason: .noModelSelected
      )
    ])
  try store.saveRecordings([record])
  let state = AppState(store: store, localTranscription: FixtureLocalASR())
  state.settings.asrProviderSelection = .external
  state.settings.asrEndpoint = ""
  state.requestTranscription(for: record)
  let updated = try #require(state.recordings.first?.processingTasks.first)
  #expect(updated.status == .waitingForModel)
  #expect(updated.blockReason == .noModelSelected)
  #expect(updated.lastError?.contains("原始录音") == true)
}

@Test("本机未授权时不触发系统弹窗，录音保留并等待用户授权后重试")
@MainActor
func localASRAuthorizationIsExplicitAndFailClosed() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "woice-local-asr-auth-" + UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let store = WorkspaceStore(storageRootURL: root)
  let record = RecordingRecord(
    id: UUID(), createdAt: Date(), audioFileName: "auth.wav", duration: 1, transcript: nil,
    generatedMarkdown: nil, processingError: nil,
    processingTasks: [
      ProcessingTask(
        kind: .transcription,
        idempotencyKey: "auth-transcription",
        status: .queued,
        capability: .transcription)
    ])
  try store.saveRecordings([record])
  let provider = UnauthorizedLocalASR()
  let state = AppState(store: store, localTranscription: provider)
  state.settings.asrProviderSelection = .onDevice
  state.settings.asrEndpoint = ""

  state.requestTranscription(for: record)
  try await Task.sleep(for: .milliseconds(50))

  let updated = try #require(state.recordings.first)
  let task = try #require(updated.processingTasks.first)
  #expect(task.status == .failed)
  #expect(task.blockReason == .authorizationRequired)
  #expect(task.lastError?.contains("点击“允许”") == true)
  #expect(updated.processingError?.contains("原始录音") == true)
  #expect(provider.transcribeCallCount == 0)
}

@Test("真实麦克风录音在无外部 Endpoint 时走本机 ASR 闭环")
@MainActor
func realMicrophoneRoutesToLocalASRWithoutExternalEndpoint() async throws {
  guard ProcessInfo.processInfo.environment["WOICE_RUN_APPSTATE_LOCAL_ASR"] == "1" else {
    return
  }
  guard AVAudioApplication.shared.recordPermission == .granted else { return }

  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "woice-real-local-asr-" + UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let state = AppState(
    store: WorkspaceStore(storageRootURL: root), localTranscription: FixtureLocalASR())
  state.settings.asrProviderSelection = .automatic
  state.settings.asrEndpoint = ""
  state.startRecording()
  try await Task.sleep(for: .seconds(2))
  #expect(state.isRecording)
  await state.stopRecording()

  let record = try #require(state.recordings.first)
  #expect(record.transcript == "本机模型转写成功")
  #expect(record.processingTasks.first?.dataLocation == .onDevice)
  #expect(state.audioFileExists(for: record))
}

@Test("本机 Speech Provider 可读取本机生成的语音文件（可选真实烟测）")
func nativeLocalASRSmokeWhenAuthorized() async throws {
  guard ProcessInfo.processInfo.environment["WOICE_RUN_NATIVE_LOCAL_ASR"] == "1" else {
    return
  }
  guard SFSpeechRecognizer.authorizationStatus() == .authorized else { return }
  guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
    recognizer.isAvailable, recognizer.supportsOnDeviceRecognition
  else { return }

  let url = FileManager.default.temporaryDirectory.appendingPathComponent(
    "woice-native-asr-\(UUID().uuidString).aiff")
  defer { try? FileManager.default.removeItem(at: url) }
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
  process.arguments = ["-v", "Samantha", "-o", url.path, "Woice local transcription test"]
  try process.run()
  process.waitUntilExit()
  #expect(process.terminationStatus == 0)

  let result = try await OnDeviceSpeechTranscriptionService().transcribe(
    audioURL: url, language: "en-US")
  #expect(!result.text.isEmpty)
}
