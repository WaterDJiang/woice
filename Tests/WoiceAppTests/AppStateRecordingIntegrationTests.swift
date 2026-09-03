import AVFoundation
import Foundation
import SQLite3
import Testing
import WoiceCore

@testable import WoiceApp

private final class AppStateTranscriptionURLProtocol: URLProtocol {
  nonisolated(unsafe) static var requests: [URLRequest] = []

  override class func canInit(with request: URLRequest) -> Bool { true }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    let response = HTTPURLResponse(
      url: request.url!, statusCode: 200, httpVersion: nil,
      headerFields: ["Content-Type": "application/json"]
    )!
    Self.requests.append(request)
    let body: Data
    if request.url?.path.hasSuffix("/chat/completions") == true {
      body = Data(
        "{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"# 会议笔记\\n\\n- 已完成转写\\n- 待办：暂无\"}}]}"
          .utf8
      )
    } else {
      body = Data(
        #"{"text":"现场转写成功","segments":[{"start":0.1,"end":1.8,"text":"现场转写成功"}]}"#.utf8
      )
    }
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: body)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

private final class RetryingTranscriptionURLProtocol: URLProtocol {
  nonisolated(unsafe) static var requestCount = 0

  override class func canInit(with request: URLRequest) -> Bool { true }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    Self.requestCount += 1
    let isRetry = Self.requestCount > 1
    let response = HTTPURLResponse(
      url: request.url!, statusCode: isRetry ? 200 : 503, httpVersion: nil,
      headerFields: ["Content-Type": "application/json"]
    )!
    let body =
      isRetry
      ? Data(#"{"text":"重试后转写成功"}"#.utf8)
      : Data(#"{"error":"暂时不可用"}"#.utf8)
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: body)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

@Test("素材详情 hydrate 未完成时阻止录音导入，避免空集合覆盖数据库")
@MainActor
func appStateHydrationGatesDestructiveActions() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "woice-app-state-hydration-gate-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let store = WorkspaceStore(storageRootURL: root)
  let records = (0..<250).map { index in
    RecordingRecord(
      id: UUID(),
      createdAt: Date(timeIntervalSince1970: Double(index)),
      audioFileName: "material-\(index).m4a",
      duration: 1,
      transcript: nil,
      generatedMarkdown: nil,
      processingError: nil)
  }
  try store.saveRecordings(records)

  let state = AppState(store: store)
  #expect(state.isHydratingRecordings)
  #expect(!state.canStartRecording)
  #expect(!state.canImportMedia)
  state.startRecording()
  #expect(!state.isRecording)

  let imported = await state.importMedia(
    from: root.appendingPathComponent("not-found.wav"))
  #expect(imported == nil)
  #expect(store.loadRecordingSummaries().count == 250)
}

@Test("素材详情 hydrate 失败后保持 fail-closed 并允许显式重试")
@MainActor
func appStateHydrationFailureKeepsMutationGateClosed() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "woice-app-state-hydration-failure-(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let store = WorkspaceStore(storageRootURL: root)
  let records = (0..<250).map { index in
    RecordingRecord(
      id: UUID(),
      createdAt: Date(timeIntervalSince1970: Double(index)),
      audioFileName: "material-(index).m4a",
      duration: 1,
      transcript: nil,
      generatedMarkdown: nil,
      processingError: nil)
  }
  try store.saveRecordings(records)

  var database: OpaquePointer?
  let openResult = store.databaseURL.path.withCString { path in
    sqlite3_open_v2(
      path, &database, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil)
  }
  guard openResult == SQLITE_OK, let database else {
    if let database { sqlite3_close(database) }
    throw WoiceError.storageFailure("无法打开 hydrate 故障测试数据库。")
  }
  defer { sqlite3_close(database) }
  let corruptID = try #require(records.last?.id.uuidString)
  let escapedID = corruptID.replacingOccurrences(of: "'", with: "''")
  let sql = "UPDATE recordings SET payload_json='not-json' WHERE id='\(escapedID)'"
  guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
    throw WoiceError.storageFailure("无法注入 hydrate 故障。")
  }

  let state = AppState(store: store)
  let deadline = Date().addingTimeInterval(2)
  while state.isHydratingRecordings, Date() < deadline {
    try await Task.sleep(for: .milliseconds(10))
  }
  #expect(!state.isHydratingRecordings)
  #expect(state.recordingHydrationError != nil)
  #expect(!state.canStartRecording)
  #expect(!state.canImportMedia)
  state.startRecording()
  #expect(!state.isRecording)
  let imported = await state.importMedia(from: root.appendingPathComponent("not-found.wav"))
  #expect(imported == nil)
  let adoptedRecord = try #require(records.first)
  state.adoptRecordingDetail(adoptedRecord)
  #expect(!state.renameRecording(recordID: adoptedRecord.id, title: "不应保存"))
  #expect(!state.moveToTrash(record: adoptedRecord))
  #expect(store.loadRecordingSummaries().count == 250)
}

@Test("素材删除打包进入废纸篓且索引同步移除")
@MainActor
func materialDeletionMovesRecoverableBundle() throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "woice-material-trash-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let store = WorkspaceStore(storageRootURL: root)
  let record = RecordingRecord(
    id: UUID(), createdAt: Date(), audioFileName: "fixture.wav", duration: 1,
    transcript: "可恢复素材", generatedMarkdown: nil, processingError: nil)
  try Data("audio".utf8).write(to: store.audioURL(for: record))
  try store.saveRecordings([record])
  let recycled = root.appendingPathComponent("recycled", isDirectory: true)
  let state = AppState(
    store: store,
    recycleMaterialDirectory: { directory in
      try FileManager.default.moveItem(at: directory, to: recycled)
    })

  #expect(state.moveToTrash(record: record))
  #expect(state.recordings.isEmpty)
  #expect(store.loadRecordings().isEmpty)
  #expect(!FileManager.default.fileExists(atPath: store.audioURL(for: record).path))
  #expect(
    FileManager.default.fileExists(atPath: recycled.appendingPathComponent("fixture.wav").path))
  #expect(
    FileManager.default.fileExists(atPath: recycled.appendingPathComponent("record.json").path))
}

@Test("废纸篓失败时恢复素材文件和索引")
@MainActor
func materialDeletionRollsBackOnRecycleFailure() throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "woice-material-trash-failure-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let store = WorkspaceStore(storageRootURL: root)
  let record = RecordingRecord(
    id: UUID(), createdAt: Date(), audioFileName: "fixture.wav", duration: 1,
    transcript: "不能丢失", generatedMarkdown: nil, processingError: nil)
  try Data("audio".utf8).write(to: store.audioURL(for: record))
  try store.saveRecordings([record])
  let state = AppState(
    store: store,
    recycleMaterialDirectory: { _ in
      throw CocoaError(.fileWriteNoPermission)
    })

  #expect(!state.moveToTrash(record: record))
  #expect(state.recordings.map(\.id) == [record.id])
  #expect(store.loadRecordings().map(\.id) == [record.id])
  #expect(FileManager.default.fileExists(atPath: store.audioURL(for: record).path))
}

@Test("AppState 会议模式编排麦克风 WAV 与系统音频 CAF")
@MainActor
func appStateMeetingModePersistsDualTrackRecord() async throws {
  guard ProcessInfo.processInfo.environment["WOICE_RUN_APPSTATE_CAPTURE"] == "1" else { return }
  guard AVAudioApplication.shared.recordPermission == .granted else { return }

  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "woice-app-state-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let store = WorkspaceStore(storageRootURL: root)
  let state = AppState(store: store)
  state.settings.captureSystemAudio = true
  state.startRecording()
  let requireSystemAudioSignal =
    ProcessInfo.processInfo.environment["WOICE_REQUIRE_SYSTEM_AUDIO_SIGNAL"] == "1"
  try await Task.sleep(for: requireSystemAudioSignal ? .seconds(15) : .seconds(2))
  #expect(state.isRecording)
  #expect(state.elapsed > 0)
  await state.stopRecording()

  let record = try #require(state.recordings.first)
  #expect(record.duration > 0)
  #expect(abs(state.elapsed - record.duration) <= 0.02)
  #expect(state.audioFileExists(for: record))
  let microphoneFile = try AVAudioFile(forReading: state.audioURL(for: record))
  #expect(microphoneFile.length > 0)
  let microphonePlayback = AudioPlaybackService()
  microphonePlayback.play(url: state.audioURL(for: record))
  #expect(microphonePlayback.duration > 0)
  microphonePlayback.stop()
  if ProcessInfo.processInfo.environment["WOICE_REQUIRE_SYSTEM_AUDIO"] == "1" {
    guard record.systemAudioFileName != nil else {
      Issue.record(
        "真实系统音频验收失败：\(record.systemAudioError ?? "没有生成系统声音文件。")")
      return
    }
    #expect((record.systemAudioBufferCount ?? 0) > 0)
    guard let captureTarget = record.systemAudioCaptureTarget else {
      Issue.record("真实系统音频验收失败：系统声音文件已生成，但没有保存采集目标。")
      return
    }
    #expect(
      [SystemAudioCaptureTarget.display, .activeWindow, .visibleWindow].contains(captureTarget))
    guard state.systemAudioFileExists(for: record) else {
      Issue.record("真实系统音频验收失败：系统声音文件索引存在，但文件不可读。")
      return
    }
    if requireSystemAudioSignal {
      #expect((record.systemAudioPeakLevel ?? 0) > 0.0001)
    }
    let systemAudioURL = try #require(state.systemAudioURL(for: record))
    let systemFile = try AVAudioFile(forReading: systemAudioURL)
    #expect(systemFile.length > 0)
    let systemPlayback = AudioPlaybackService()
    systemPlayback.play(url: systemAudioURL)
    #expect(systemPlayback.duration > 0)
    systemPlayback.stop()
    if requireSystemAudioSignal {
      #expect(record.meetingMixFileName != nil)
      #expect(state.meetingMixFileExists(for: record))
      let meetingMix = try AVAudioFile(forReading: state.meetingMixURL(for: record))
      // The durable meeting mix is the replay/export artifact: it stays at
      // 48 kHz AAC/M4A. ASR providers receive a disposable 16 kHz input from
      // AudioPreparationService. The default source-separated mode still
      // creates one task per usable original track.
      #expect(meetingMix.processingFormat.sampleRate == 48_000)
      #expect(meetingMix.processingFormat.channelCount == 1)
      let taskTracks = Set(record.processingTasks.compactMap(\.sourceTrack))
      #expect(taskTracks.contains(.systemAudio))
      if state.microphoneAudioFileExists(for: record) {
        #expect(taskTracks.contains(.microphone))
      }
      #expect(record.processingTasks.allSatisfy { $0.meetingTranscriptionMode == .sourceSeparated })
    }
  }
}

@Test("AppState 退出清理固化正在录音的 WAV 并保留 Journal")
@MainActor
func appStateTerminationFinalizesRecordingAndRetainsJournal() async throws {
  guard ProcessInfo.processInfo.environment["WOICE_RUN_APPSTATE_CAPTURE"] == "1" else {
    return
  }
  guard AVAudioApplication.shared.recordPermission == .granted else { return }

  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "woice-app-state-termination-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }

  let store = WorkspaceStore(storageRootURL: root)
  let state = AppState(store: store)
  state.settings.captureSystemAudio = false
  state.settings.enableLiveTranscription = false
  state.startRecording()

  let deadline = Date().addingTimeInterval(3)
  while !state.recorder.isRecording || state.recorder.receivedBufferCount == 0, Date() < deadline {
    try await Task.sleep(for: .milliseconds(50))
  }
  guard state.recorder.isRecording, state.recorder.receivedBufferCount > 0 else {
    Issue.record("退出清理测试未等到可用麦克风 PCM 首帧。")
    return
  }

  let journal = try #require(store.loadRecordingSession())
  let audioURL = store.recordingsURL.appendingPathComponent(journal.audioFileName)
  await state.prepareForTermination()

  #expect(!state.recorder.isRecording)
  #expect(store.loadRecordingSession()?.id == journal.id)
  let audioFile = try AVAudioFile(forReading: audioURL)
  #expect(audioFile.length > 0)
  #expect(state.recordings.isEmpty)
}

@Test("AppState 启动时恢复 queued Job 为等待外发确认")
@MainActor
func appStateRestoresQueuedProcessingAuthorization() throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "woice-app-state-queued-" + UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }

  let store = WorkspaceStore(storageRootURL: root)
  var settings = AppSettings.default
  settings.asrProviderSelection = .external
  settings.asrEndpoint = "https://example.test/v1"
  try store.saveSettings(settings)
  let record = RecordingRecord(
    id: UUID(),
    createdAt: Date(),
    audioFileName: "queued.wav",
    duration: 1,
    transcript: nil,
    generatedMarkdown: nil,
    processingError: nil,
    processingTasks: [
      ProcessingTask(kind: .transcription, idempotencyKey: "queued-transcription")
    ]
  )
  try store.saveRecordings([record])

  let state = AppState(store: store)
  #expect(state.pendingExternalProcessing?.recordID == record.id)
  #expect(state.pendingExternalProcessing?.kind.title == "发送录音并转写")
  #expect(
    state.recordings.first?.processingTasks.first?.status == .awaitingAuthorization
  )
}

@Test("稍后处理的外发任务重启后仍可继续")
@MainActor
func deferredExternalProcessingRestoresAfterRestart() throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "woice-deferred-restart-" + UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }

  let store = WorkspaceStore(storageRootURL: root)
  var settings = AppSettings.default
  settings.asrProviderSelection = .external
  settings.asrEndpoint = "https://example.test/v1"
  try store.saveSettings(settings)
  let record = RecordingRecord(
    id: UUID(), createdAt: Date(), audioFileName: "deferred.wav", duration: 1,
    transcript: nil, generatedMarkdown: nil, processingError: nil,
    processingTasks: [ProcessingTask(kind: .transcription, idempotencyKey: "deferred")])
  try store.saveRecordings([record])

  let firstLaunch = AppState(store: store)
  firstLaunch.dismissExternalProcessing()
  #expect(firstLaunch.pendingExternalProcessing == nil)
  #expect(
    firstLaunch.recordings.first?.processingTasks.first?.status == .queued)

  let restarted = AppState(store: WorkspaceStore(storageRootURL: root))
  #expect(restarted.pendingExternalProcessing?.recordID == record.id)
  #expect(
    restarted.recordings.first?.processingTasks.first?.status == .awaitingAuthorization)
}

@Test("来源分离模式按音轨分别请求外部转写确认")
@MainActor
func appStateQueuesSourceSeparatedTranscriptionByTrack() throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "woice-source-separated-" + UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }

  let store = WorkspaceStore(storageRootURL: root)
  var settings = AppSettings.default
  settings.asrProviderSelection = .external
  settings.asrEndpoint = "https://example.test/v1"
  settings.meetingTranscriptionMode = .sourceSeparated
  try store.saveSettings(settings)
  let recordID = UUID()
  let record = RecordingRecord(
    id: recordID,
    createdAt: Date(),
    audioFileName: "mic.wav",
    duration: 2,
    transcript: nil,
    generatedMarkdown: nil,
    processingError: nil,
    systemAudioFileName: "system.caf",
    meetingTranscriptionMode: .sourceSeparated,
    processingTasks: [
      ProcessingTask(
        kind: .transcription,
        idempotencyKey: "\(recordID.uuidString.lowercased()):transcription:microphone",
        status: .failed,
        sourceTrack: .microphone,
        meetingTranscriptionMode: .sourceSeparated),
      ProcessingTask(
        kind: .transcription,
        idempotencyKey: "\(recordID.uuidString.lowercased()):transcription:systemAudio",
        status: .failed,
        sourceTrack: .systemAudio,
        meetingTranscriptionMode: .sourceSeparated),
    ])
  try store.saveRecordings([record])
  let state = AppState(store: store)
  state.requestTranscription(for: record)
  #expect(state.pendingExternalProcessing?.sourceTrack == .microphone)
  #expect(state.pendingExternalProcessing?.dataDescription == "麦克风原始录音（M4A）")
  #expect(state.pendingExternalProcessingCount == 2)
  state.dismissExternalProcessing()
  #expect(state.pendingExternalProcessing == nil)
  #expect(state.pendingExternalProcessingCount == 2)
  #expect(
    state.recordings.first?.processingTasks.first?.status == .queued)
  let deferredRecord = try #require(state.recordings.first)
  state.resumeProcessing(for: deferredRecord)
  #expect(state.pendingExternalProcessing?.sourceTrack == .systemAudio)
  #expect(state.pendingExternalProcessing?.dataDescription == "电脑声音音轨（标准化 WAV）")
}

@Test("历史单次混音双轨素材重新转写时升级为两条原轨任务")
@MainActor
func legacyMeetingMixRetryUsesBothRawTracks() throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "woice-retry-reliable-meeting-" + UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let store = WorkspaceStore(storageRootURL: root)
  var settings = AppSettings.default
  settings.asrProviderSelection = .external
  settings.asrEndpoint = "https://example.test/v1"
  try store.saveSettings(settings)
  let id = UUID()
  let microphoneURL = store.recordingsURL.appendingPathComponent("\(id.uuidString).wav")
  let systemURL = store.recordingsURL.appendingPathComponent("\(id.uuidString).caf")
  try writeTestAudioFile(to: microphoneURL)
  try writeTestAudioFile(to: systemURL)
  let record = RecordingRecord(
    id: id, createdAt: Date(), audioFileName: microphoneURL.lastPathComponent, duration: 1,
    transcript: "旧版原文", generatedMarkdown: nil, processingError: nil,
    systemAudioFileName: systemURL.lastPathComponent,
    meetingTranscriptionMode: .standardMix,
    processingTasks: [
      ProcessingTask(
        kind: .transcription,
        idempotencyKey: "\(id.uuidString.lowercased()):transcription:meetingMix",
        status: .failed,
        sourceTrack: .meetingMix,
        meetingTranscriptionMode: .standardMix)
    ])
  try store.saveRecordings([record])

  let state = AppState(store: store)
  state.requestTranscription(for: try #require(state.recordings.first))

  let updated = try #require(state.recordings.first)
  #expect(updated.meetingTranscriptionMode == .sourceSeparated)
  let rawTasks = updated.processingTasks.filter {
    $0.kind == .transcription && ($0.sourceTrack == .microphone || $0.sourceTrack == .systemAudio)
  }
  #expect(Set(rawTasks.compactMap(\.sourceTrack)) == [.microphone, .systemAudio])
  #expect(updated.transcript == "旧版原文")
}

@Test("旧版来源前缀迁移为干净原文且保留历史版本")
@MainActor
func legacySourceLabelsMigrateToCleanTranscriptArtifact() throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "woice-clean-source-labels-" + UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let store = WorkspaceStore(storageRootURL: root)
  let id = UUID()
  let segments = [
    TranscriptSegment(start: 0, end: 1, text: "我先说", sourceTrack: .microphone),
    TranscriptSegment(start: 1, end: 2, text: "视频回答", sourceTrack: .systemAudio),
  ]
  let legacyArtifact = TranscriptArtifact(
    parentRecordingID: id,
    text: "[我的麦克风] 我先说\n[电脑声音] 视频回答",
    segments: segments,
    sourceTrack: .systemAudio,
    meetingTranscriptionMode: .sourceSeparated)
  let record = RecordingRecord(
    id: id, createdAt: Date(), audioFileName: "meeting.wav", duration: 2,
    transcript: legacyArtifact.text, generatedMarkdown: nil, processingError: nil,
    meetingTranscriptionMode: .sourceSeparated,
    transcriptSegments: segments,
    transcriptArtifacts: [legacyArtifact],
    activeTranscriptArtifactID: legacyArtifact.id)
  try store.saveRecordings([record])

  let state = AppState(store: store)
  let migrated = try #require(state.recordings.first)
  #expect(migrated.transcript == "我先说\n视频回答")
  #expect(migrated.transcriptArtifacts.count == 2)
  #expect(migrated.transcriptArtifacts.first?.text.contains("[我的麦克风]") == true)
  #expect(
    migrated.transcriptArtifacts.first(where: { $0.id == migrated.activeTranscriptArtifactID })?
      .text == "我先说\n视频回答")
  #expect(
    Set(migrated.transcriptSegments?.compactMap(\.sourceTrack) ?? []) == [
      .microphone, .systemAudio,
    ])
}

private func writeTestAudioFile(to url: URL) throws {
  let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
  let file = try AVAudioFile(forWriting: url, settings: format.settings)
  let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_600))
  buffer.frameLength = 1_600
  for frame in 0..<1_600 {
    buffer.floatChannelData![0][frame] = Float(sin(Double(frame) * 0.04)) * 0.05
  }
  try file.write(from: buffer)
  if #available(macOS 15.0, *) { file.close() }
}

@Test("主转写等待时不创建声音片段任务")
@MainActor
func appStateDoesNotDuplicateSegmentTaskWhileMainTranscriptionIsQueued() throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "woice-main-segment-guard-" + UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }

  let store = WorkspaceStore(storageRootURL: root)
  var settings = AppSettings.default
  settings.asrProviderSelection = .external
  settings.asrEndpoint = "https://example.test/v1"
  try store.saveSettings(settings)
  let record = RecordingRecord(
    id: UUID(),
    createdAt: Date(),
    audioFileName: "guard.wav",
    duration: 2,
    transcript: nil,
    generatedMarkdown: nil,
    processingError: nil,
    processingTasks: [
      ProcessingTask(
        kind: .transcription,
        idempotencyKey: "guard-transcription",
        status: .queued,
        blockReason: .authorizationRequired)
    ],
    voiceSegments: [VoiceSegment(start: 0, end: 1)])
  try store.saveRecordings([record])

  let state = AppState(store: store)
  state.requestSegmentTranscription(for: record)
  #expect(state.recordings.first?.processingTasks.count == 1)
  #expect(state.recordings.first?.processingTasks.first?.kind == .transcription)
}

@Test("ProcessingTask 配置摘要忽略 API Key 和 Endpoint 凭据")
@MainActor
func processingConfigurationHashExcludesSecrets() throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "woice-processing-config-hash-" + UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }

  let store = WorkspaceStore(storageRootURL: root)
  let record = RecordingRecord(
    id: UUID(),
    createdAt: Date(),
    audioFileName: "hash.wav",
    duration: 1,
    transcript: nil,
    generatedMarkdown: nil,
    processingError: nil)
  try store.saveRecordings([record])
  let state = AppState(store: store)
  state.settings.asrProviderSelection = .external
  state.settings.asrEndpoint = "https://first-user:first-password@example.test/v1?token=first#one"
  state.settings.asrAPIKey = "first-api-key"
  state.requestTranscription(for: record)
  let firstHash = try #require(state.recordings.first?.processingTasks.first?.configurationHash)
  #expect(firstHash.hasPrefix("sha256-v1:"))
  #expect(!firstHash.contains("first"))
  state.dismissExternalProcessing()

  state.settings.asrEndpoint =
    "https://second-user:second-password@example.test/v1?token=second#two"
  state.settings.asrAPIKey = "second-api-key"
  let retriedRecord = try #require(state.recordings.first)
  state.requestTranscription(for: retriedRecord)
  #expect(state.recordings.first?.processingTasks.first?.configurationHash == firstHash)
}

@Test("AppState 按顺序暴露多条 queued Job 的外发确认")
@MainActor
func appStateQueuesMultipleExternalProcessingConfirmations() throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "woice-app-state-queued-many-" + UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }

  let store = WorkspaceStore(storageRootURL: root)
  var settings = AppSettings.default
  settings.asrProviderSelection = .external
  settings.asrEndpoint = "https://example.test/v1"
  try store.saveSettings(settings)

  let firstID = UUID()
  let secondID = UUID()
  let first = RecordingRecord(
    id: firstID,
    createdAt: Date(timeIntervalSince1970: 2),
    audioFileName: "first.wav",
    duration: 1,
    transcript: nil,
    generatedMarkdown: nil,
    processingError: nil,
    processingTasks: [
      ProcessingTask(kind: .transcription, idempotencyKey: "first-transcription")
    ]
  )
  let second = RecordingRecord(
    id: secondID,
    createdAt: Date(timeIntervalSince1970: 1),
    audioFileName: "second.wav",
    duration: 1,
    transcript: nil,
    generatedMarkdown: nil,
    processingError: nil,
    processingTasks: [
      ProcessingTask(kind: .transcription, idempotencyKey: "second-transcription")
    ]
  )
  try store.saveRecordings([first, second])

  let state = AppState(store: store)
  #expect(state.pendingExternalProcessing?.recordID == firstID)
  #expect(state.pendingExternalProcessingCount == 2)
  #expect(state.recordings.first?.processingTasks.first?.status == .awaitingAuthorization)

  state.dismissExternalProcessing()
  #expect(state.pendingExternalProcessing == nil)
  #expect(state.pendingExternalProcessingCount == 2)
  #expect(
    state.recordings.first(where: { $0.id == firstID })?.processingTasks.first?.status
      == .queued)
  #expect(
    state.recordings.first(where: { $0.id == secondID })?.processingTasks.first?.status
      == .awaitingAuthorization)

  let secondRecord = try #require(state.recordings.first(where: { $0.id == secondID }))
  state.resumeProcessing(for: secondRecord)
  #expect(state.pendingExternalProcessing?.recordID == secondID)
  #expect(state.pendingExternalProcessingCount == 2)
  state.dismissExternalProcessing()
  #expect(state.pendingExternalProcessing == nil)
  #expect(state.pendingExternalProcessingCount == 2)
}

@Test("AppState 录音文件可通过自定义 ASR 完成转写")
@MainActor
func appStateRecordingTranscribesWithCustomASR() async throws {
  guard ProcessInfo.processInfo.environment["WOICE_RUN_APPSTATE_TRANSCRIPTION"] == "1" else {
    return
  }
  guard AVAudioApplication.shared.recordPermission == .granted else { return }

  let configuration = URLSessionConfiguration.ephemeral
  configuration.protocolClasses = [AppStateTranscriptionURLProtocol.self]
  let session = URLSession(configuration: configuration)
  AppStateTranscriptionURLProtocol.requests = []

  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "woice-app-state-transcription-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let store = WorkspaceStore(storageRootURL: root)
  let state = AppState(
    store: store,
    transcriptionClient: TranscriptionClient(session: session),
    llmClient: LLMClient(session: session)
  )
  state.settings.asrProviderSelection = .external
  state.settings.asrEndpoint = "https://example.test/v1"
  state.settings.asrAPIKey = "test-key"
  state.settings.includeTranscriptTimestamps = true
  state.settings.llmEndpoint = "https://example.test/v1"
  state.settings.llmAPIKey = "llm-key"
  state.settings.captureSystemAudio = false

  state.startRecording()
  try await Task.sleep(for: .seconds(2))
  #expect(state.isRecording)
  await state.stopRecording()
  #expect(state.pendingExternalProcessing != nil)
  let queuedRecord = try #require(state.recordings.first)
  #expect(
    queuedRecord.processingTasks.first(where: { $0.kind == .transcription })?.status
      == .awaitingAuthorization
  )

  await state.confirmExternalProcessing()
  #expect(state.pendingExternalProcessing != nil)
  let asrCompletedRecord = try #require(state.recordings.first)
  #expect(
    asrCompletedRecord.processingTasks.first(where: { $0.kind == .transcription })?.status
      == .completed
  )
  #expect(
    asrCompletedRecord.processingTasks.first(where: { $0.kind == .languageModel })?.status
      == .awaitingAuthorization
  )
  await state.confirmExternalProcessing()
  let record = try #require(state.recordings.first)
  #expect(record.duration > 0)
  #expect(record.transcript == "现场转写成功")
  #expect(record.transcriptSegments == [TranscriptSegment(start: 0.1, end: 1.8, text: "现场转写成功")])
  #expect(record.generatedMarkdown?.contains("会议笔记") == true)
  #expect(record.processingTasks.allSatisfy { $0.status == .completed })
  #expect(Set(record.processingTasks.map(\.idempotencyKey)).count == 2)
  #expect(state.processingState == .saved)
  #expect(state.audioFileExists(for: record))

  let requests = AppStateTranscriptionURLProtocol.requests
  let transcriptionRequest = try #require(
    requests.first(where: { $0.url?.path == "/v1/audio/transcriptions" }))
  #expect(transcriptionRequest.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
  #expect(transcriptionRequest.httpBody != nil || transcriptionRequest.httpBodyStream != nil)
  #expect(requests.contains(where: { $0.url?.path == "/v1/chat/completions" }))
  let audioData = try Data(contentsOf: state.audioURL(for: record))
  #expect(audioData.count > 12)
  #expect(audioData[4..<8] == Data("ftyp".utf8))
}

@Test("ASR 失败保留录音并可通过显式重试恢复")
@MainActor
func appStateRetriesFailedTranscription() async throws {
  let configuration = URLSessionConfiguration.ephemeral
  configuration.protocolClasses = [RetryingTranscriptionURLProtocol.self]
  let session = URLSession(configuration: configuration)
  RetryingTranscriptionURLProtocol.requestCount = 0

  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "woice-app-state-retry-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let store = WorkspaceStore(storageRootURL: root)
  let audioURL = store.recordingsURL.appendingPathComponent("retry.wav")
  let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
  let audioFile = try AVAudioFile(forWriting: audioURL, settings: format.settings)
  let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000)!
  buffer.frameLength = 16_000
  try audioFile.write(from: buffer)
  let record = RecordingRecord(
    id: UUID(),
    createdAt: Date(),
    audioFileName: audioURL.lastPathComponent,
    duration: 1,
    transcript: nil,
    generatedMarkdown: nil,
    processingError: nil,
    processingTasks: [
      ProcessingTask(
        kind: .transcription,
        idempotencyKey: "retry-transcription"
      )
    ]
  )
  try store.saveRecordings([record])
  let state = AppState(store: store, transcriptionClient: TranscriptionClient(session: session))
  state.settings.asrProviderSelection = .external
  state.settings.asrEndpoint = "https://example.test/v1"
  state.settings.asrAPIKey = "test-key"

  let loaded = try #require(state.recordings.first)
  state.requestTranscription(for: loaded)
  #expect(state.pendingExternalProcessing != nil)
  let initialConfigurationHash = try #require(
    state.recordings.first?.processingTasks.first?.configurationHash)
  #expect(initialConfigurationHash.hasPrefix("sha256-v1:"))
  await state.confirmExternalProcessing()
  let failed = try #require(state.recordings.first)
  #expect(failed.transcript == nil)
  #expect(failed.processingTasks.first?.status == .failed)
  #expect(state.audioFileExists(for: failed))

  state.settings.asrAPIKey = "different-key-not-in-snapshot"
  state.retryProcessing(for: failed)
  #expect(state.pendingExternalProcessing != nil)
  #expect(
    state.recordings.first?.processingTasks.first?.configurationHash == initialConfigurationHash)
  await state.confirmExternalProcessing()
  let recovered = try #require(state.recordings.first)
  #expect(recovered.transcript == "重试后转写成功")
  #expect(recovered.processingTasks.first?.status == .completed)
  #expect(recovered.processingTasks.first?.attempt == 2)
  #expect(RetryingTranscriptionURLProtocol.requestCount == 2)
}

@Test("VAD 声音片段可串行转写并保存时间范围")
@MainActor
func appStateTranscribesPersistedVoiceSegments() async throws {
  let configuration = URLSessionConfiguration.ephemeral
  configuration.protocolClasses = [AppStateTranscriptionURLProtocol.self]
  let session = URLSession(configuration: configuration)
  AppStateTranscriptionURLProtocol.requests = []

  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "woice-app-state-segments-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let store = WorkspaceStore(storageRootURL: root)
  let audioURL = store.recordingsURL.appendingPathComponent("segments.wav")
  let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
  do {
    let file = try AVAudioFile(forWriting: audioURL, settings: format.settings)
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000))
    buffer.frameLength = 16_000
    for frame in 0..<16_000 {
      buffer.floatChannelData![0][frame] = Float(sin(Double(frame) * 0.02)) * 0.05
    }
    try file.write(from: buffer)
  }
  let record = RecordingRecord(
    id: UUID(),
    createdAt: Date(),
    audioFileName: audioURL.lastPathComponent,
    duration: 1,
    transcript: nil,
    generatedMarkdown: nil,
    processingError: nil,
    voiceSegments: [VoiceSegment(start: 0.1, end: 0.4), VoiceSegment(start: 0.5, end: 0.8)]
  )
  try store.saveRecordings([record])
  let state = AppState(store: store, transcriptionClient: TranscriptionClient(session: session))
  state.settings.asrProviderSelection = .external
  state.settings.asrEndpoint = "https://example.test/v1"
  state.settings.asrAPIKey = "test-key"

  let loaded = try #require(state.recordings.first)
  state.requestSegmentTranscription(for: loaded)
  #expect(state.pendingExternalProcessing != nil)
  await state.confirmExternalProcessing()

  let result = try #require(state.recordings.first)
  #expect(result.transcript == "现场转写成功\n现场转写成功")
  #expect(
    result.transcriptSegments
      == [
        TranscriptSegment(start: 0.1, end: 0.4, text: "现场转写成功"),
        TranscriptSegment(start: 0.5, end: 0.8, text: "现场转写成功"),
      ]
  )
  #expect(
    result.processingTasks.first(where: { $0.kind == .segmentTranscription })?.status == .completed)
  #expect(state.audioFileExists(for: result))
  #expect(
    AppStateTranscriptionURLProtocol.requests.filter {
      $0.url?.path == "/v1/audio/transcriptions"
    }.count == 2
  )
}
