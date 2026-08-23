@preconcurrency import AVFoundation
import CryptoKit
import Foundation
import Testing
import WoiceCore

@testable import WoiceApp

@Test("WhisperKit 模型目录固定 Tiny 与 Large-v3 候选版本")
func whisperKitCatalogPinsModelAndTokenizerRevisions() {
  let tiny = WhisperKitModelCatalogEntry.recommendedTiny
  #expect(tiny.modelRevision == "0f63a7800b00dd0226abd051b906c246e1907482")
  #expect(tiny.tokenizerRevision == "169d4a4341b33bc18d8881c4b69c2e104e1cc0af")
  let large = WhisperKitModelCatalogEntry.candidateLargeV3
  #expect(large.modelFolderName == "openai_whisper-large-v3-v20240930_626MB")
  #expect(large.tokenizerRevision == "06f233fe06e710322aca913c1bc4249a0d71fce1")
  #expect(large.estimatedBytes == 626_000_000)
  #expect(WhisperKitModelCatalogEntry.frozenDefaultPackID == large.packID)
}

@Test("未显式选择时已安装模型优先冻结的 Large-v3 默认")
@MainActor
func defaultWhisperKitRoutePrefersFrozenLargeModel() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "woice-default-model-route-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let source = root.appendingPathComponent("source", isDirectory: true)
  try FileManager.default.createDirectory(
    at: source.appendingPathComponent("weights", isDirectory: true),
    withIntermediateDirectories: true)
  let bytes = Data(repeating: 0x42, count: 96)
  try bytes.write(to: source.appendingPathComponent("weights/model.bin"))
  let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
  let file = try ModelPackFile(
    relativePath: "weights/model.bin", byteCount: Int64(bytes.count), sha256: hash)
  let license = try ModelPackLicense(
    identifier: "MIT", noticePath: "LICENSE", sourceURL: "https://example.com/model")
  func manifest(packID: String, modelID: String) throws -> ModelPackManifest {
    try ModelPackManifest(
      packID: packID, modelID: modelID, version: "0f63a7800b00dd0226abd051b906c246e1907482",
      providerID: "com.woice.whisperkit", files: [file], license: license, size: Int64(bytes.count))
  }
  let store = ModelPackStore(rootURL: root)
  _ = try await store.install(
    manifest: manifest(
      packID: WhisperKitModelCatalogEntry.recommendedTiny.packID,
      modelID: WhisperKitModelCatalogEntry.recommendedTiny.modelID),
    from: source)
  _ = try await store.install(
    manifest: manifest(
      packID: WhisperKitModelCatalogEntry.candidateLargeV3.packID,
      modelID: WhisperKitModelCatalogEntry.candidateLargeV3.modelID),
    from: source)

  let state = AppState(store: WorkspaceStore(storageRootURL: root))
  #expect(state.localASRModel.modelID == WhisperKitModelCatalogEntry.candidateLargeV3.modelID)
}

@Test("切换已安装模型同时切回本机转写路线并保留自定义服务草稿")
@MainActor
func selectingInstalledModelActivatesOnDeviceRoute() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "woice-select-local-route-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let source = root.appendingPathComponent("source", isDirectory: true)
  try FileManager.default.createDirectory(
    at: source.appendingPathComponent("weights", isDirectory: true),
    withIntermediateDirectories: true)
  let bytes = Data(repeating: 0x42, count: 96)
  try bytes.write(to: source.appendingPathComponent("weights/model.bin"))
  let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
  let file = try ModelPackFile(
    relativePath: "weights/model.bin", byteCount: Int64(bytes.count), sha256: hash)
  let manifest = try ModelPackManifest(
    packID: WhisperKitModelCatalogEntry.candidateLargeV3.packID,
    modelID: WhisperKitModelCatalogEntry.candidateLargeV3.modelID,
    version: WhisperKitModelCatalogEntry.candidateLargeV3.modelRevision,
    providerID: "com.woice.whisperkit",
    files: [file],
    license: try ModelPackLicense(
      identifier: "MIT", noticePath: "LICENSE", sourceURL: "https://example.com/model"),
    size: Int64(bytes.count))
  _ = try await ModelPackStore(rootURL: root).install(manifest: manifest, from: source)

  let workspace = WorkspaceStore(storageRootURL: root)
  var settings = AppSettings.default
  settings.asrProviderSelection = .external
  settings.asrEndpoint = "http://127.0.0.1:8080/v1"
  settings.asrModel = "whisper-1"
  try workspace.saveSettings(settings)
  let record = RecordingRecord(
    id: UUID(), createdAt: Date(), audioFileName: "queued.wav", duration: 1,
    transcript: nil, generatedMarkdown: nil, processingError: nil,
    processingTasks: [
      ProcessingTask(
        kind: .transcription, idempotencyKey: "queued-external", status: .queued,
        providerID: "openai-compatible.asr", modelID: "whisper-1",
        dataLocation: .onDevice, capability: .transcription,
        blockReason: .authorizationRequired)
    ])
  try workspace.saveRecordings([record])
  let state = AppState(store: workspace)
  #expect(state.pendingExternalProcessing != nil)

  #expect(
    await state.selectInstalledModel(packID: manifest.packID, version: manifest.version))
  #expect(state.settings.asrProviderSelection == .onDevice)
  #expect(state.settings.asrEndpoint == "http://127.0.0.1:8080/v1")
  #expect(state.localASRModel.modelID == manifest.modelID)
  #expect(state.isUsingLocalASR)
  #expect(state.pendingExternalProcessing == nil)
  #expect(state.pendingExternalProcessingCount == 0)
  #expect(state.recordings.first?.processingTasks.first?.status == .interrupted)
  #expect(state.recordings.first?.processingTasks.first?.blockReason == nil)
}

@Test("真实 WhisperKit 模型包可下载、安装并完成本机转写（显式验收）")
@MainActor
func realWhisperKitModelPackDownloadsAndTranscribes() async throws {
  guard ProcessInfo.processInfo.environment["WOICE_RUN_REAL_WHISPERKIT"] == "1" else {
    return
  }
  let installInAppSupport =
    ProcessInfo.processInfo.environment["WOICE_INSTALL_REAL_WHISPERKIT"] == "1"
  let root: URL
  var temporaryRoot: URL?
  if installInAppSupport {
    root = WorkspaceStore().rootURL
  } else {
    root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "woice-real-whisperkit-\(UUID().uuidString)", isDirectory: true)
    temporaryRoot = root
  }
  defer {
    if let temporaryRoot { try? FileManager.default.removeItem(at: temporaryRoot) }
  }

  let result: (manifest: ModelPackManifest, installedURL: URL)
  let catalog = WhisperKitModelCatalogEntry.recommendedTiny
  if installInAppSupport,
    let current = try await ModelPackStore(rootURL: root).currentManifest(packID: catalog.packID)
  {
    result = (
      current,
      root.appendingPathComponent("Models", isDirectory: true)
        .appendingPathComponent(catalog.packID, isDirectory: true)
        .appendingPathComponent(current.version, isDirectory: true)
    )
  } else {
    let installer = WhisperKitModelInstaller(rootURL: root)
    result = try await installer.install(entry: catalog)
  }
  #expect(result.manifest.providerID == "com.woice.whisperkit")
  #expect(result.manifest.version == WhisperKitModelCatalogEntry.recommendedTiny.modelRevision)
  #expect(result.manifest.files.count > 10)

  let audioURL = root.appendingPathComponent("fixture.aiff")
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
  process.arguments = ["-v", "Samantha", "-o", audioURL.path, "Woice local transcription test"]
  try process.run()
  process.waitUntilExit()
  #expect(process.terminationStatus == 0)

  let provider = try WhisperKitTranscriptionService(
    manifest: result.manifest, modelFolder: result.installedURL)
  let transcription = try await provider.transcribe(audioURL: audioURL, language: "en-US")
  #expect(!transcription.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
  #expect(FileManager.default.fileExists(atPath: result.installedURL.path))
}

@Test("已安装 Large 模型可加载并完成已有 WAV 的本机重转写（显式验收）")
@MainActor
func installedLargeWhisperKitPackTranscribesExistingWAV() async throws {
  guard ProcessInfo.processInfo.environment["WOICE_RUN_LARGE_WHISPERKIT"] == "1" else {
    return
  }
  let root = WorkspaceStore().rootURL
  let modelStore = ModelPackStore(rootURL: root)
  let manifest = try #require(
    await modelStore.inventory().first(where: {
      $0.manifest.packID == WhisperKitModelCatalogEntry.candidateLargeV3.packID
        && $0.manifest.providerID == "com.woice.whisperkit"
    })?.manifest)
  let modelFolder = try await modelStore.installedDirectory(for: manifest)
  let audioURL = FileManager.default.temporaryDirectory.appendingPathComponent(
    "woice-large-existing-\(UUID().uuidString).aiff")
  defer { try? FileManager.default.removeItem(at: audioURL) }
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
  process.arguments = ["-v", "Samantha", "-o", audioURL.path, "Woice Large model retry test"]
  try process.run()
  process.waitUntilExit()
  #expect(process.terminationStatus == 0)

  let provider = try WhisperKitTranscriptionService(
    manifest: manifest, modelFolder: modelFolder)
  let transcription = try await provider.transcribe(audioURL: audioURL, language: "en-US")
  #expect(!transcription.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
}

@Test("当前安装的 WhisperKit 模型完成真实麦克风录音到文字闭环（显式验收）")
@MainActor
func installedWhisperKitRecordsAndTranscribes() async throws {
  guard ProcessInfo.processInfo.environment["WOICE_RUN_INSTALLED_WHISPERKIT"] == "1" else {
    return
  }
  let hasMicrophonePermission = AVAudioApplication.shared.recordPermission == .granted
  if ProcessInfo.processInfo.environment["WOICE_REQUIRE_MIC_AUDIO"] == "1" {
    #expect(hasMicrophonePermission)
  }
  guard hasMicrophonePermission else {
    return
  }

  let state = AppState()
  #expect(state.localASRModel.providerID == "com.woice.whisperkit")
  let expectedModelID = state.localASRModel.modelID
  let expectedModelVersion = state.localASRModel.version
  state.settings.asrProviderSelection = .onDevice
  state.settings.asrEndpoint = ""
  state.startRecording()
  try await Task.sleep(for: .seconds(3))
  #expect(state.isRecording)
  await state.stopRecording()

  for _ in 0..<240 {
    switch state.processingState {
    case .saved, .failed(_):
      break
    default:
      try await Task.sleep(for: .milliseconds(500))
      continue
    }
    break
  }
  let record = try #require(state.recordings.first)
  #expect(record.transcript?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
  #expect(record.processingTasks.first?.status == .completed)
  #expect(record.processingTasks.first?.providerID == "com.woice.whisperkit")
  #expect(record.processingTasks.first?.modelID == expectedModelID)
  #expect(record.processingTasks.first?.modelVersion == expectedModelVersion)
  #expect(state.audioFileExists(for: record))
}
