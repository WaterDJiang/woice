import Foundation
import Testing
import WoiceCore

#if !WOICE_APP_STORE
  @testable import WoiceApp

  @Test("PI Router 返回状态和历史摘要，不暴露密钥")
  @MainActor
  func piRouterReadsStatusAndList() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "woice-pi-router-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = WorkspaceStore(storageRootURL: root)
    let record = RecordingRecord(
      id: UUID(), createdAt: Date(), audioFileName: "a.wav", duration: 1,
      transcript: "本地原文", generatedMarkdown: nil, processingError: nil
    )
    try store.saveRecordings([record])
    let state = AppState(store: store)
    let router = PiConnectorRouter(appState: state)

    let status = router.handle(PiConnectorRequest(requestID: "status", method: .status))
    #expect(status.error == nil)
    #expect(status.result?["recording_count"] == "1")
    #expect(status.result?["is_recording"] == "false")
    let list = router.handle(PiConnectorRequest(requestID: "list", method: .listRecordings))
    #expect(list.result?["recording_ids"] == record.id.uuidString)
    #expect(list.result?.values.contains(where: { $0.contains("API") }) == false)
  }

  @Test("PI Router 读取原文并限制处理请求为等待用户确认")
  @MainActor
  func piRouterReadsTranscriptAndRequestsConfirmation() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "woice-pi-router-transform-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = WorkspaceStore(storageRootURL: root)
    let record = RecordingRecord(
      id: UUID(), createdAt: Date(), audioFileName: "a.wav", duration: 1,
      transcript: "会议原文", generatedMarkdown: nil, processingError: nil
    )
    try store.saveRecordings([record])
    let state = AppState(store: store)
    state.settings.llmEndpoint = "https://example.test/v1"
    let router = PiConnectorRouter(appState: state)

    let read = router.handle(
      PiConnectorRequest(
        requestID: "read", method: .readTranscript,
        parameters: ["recording_id": record.id.uuidString]
      )
    )
    #expect(read.result?["text"] == "会议原文")
    let transform = router.handle(
      PiConnectorRequest(
        requestID: "transform", method: .requestTransform,
        parameters: ["recording_id": record.id.uuidString]
      )
    )
    #expect(transform.result?["requires_user_confirmation"] == "true")
    #expect(transform.result?["confirmation_stage"] == "user")
    #expect(state.pendingExternalProcessing != nil)
  }

  @Test("PI Router 在关闭权限后 fail-closed，用户确认阶段不会被绕过")
  @MainActor
  func piRouterRejectsDisabledPermission() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "woice-pi-permission-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let record = RecordingRecord(
      id: UUID(), createdAt: Date(), audioFileName: "a.wav", duration: 1,
      transcript: "会议原文", generatedMarkdown: nil, processingError: nil)
    let state = AppState(store: WorkspaceStore(storageRootURL: root))
    state.recordings = [record]
    state.settings.agentPermissions.canReadMaterials = false
    let router = PiConnectorRouter(appState: state)
    let response = router.handle(
      PiConnectorRequest(
        requestID: "denied", method: .readTranscript,
        parameters: ["recording_id": record.id.uuidString]))
    #expect(response.result == nil)
    #expect(response.error?.code == "PERMISSION_DENIED")
    #expect(state.pendingExternalProcessing == nil)
  }

  @Test("PI read_material 返回稳定素材引用且保持只读")
  @MainActor
  func piRouterReadsMaterialProjectionWithoutStartingWork() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "woice-pi-material-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = WorkspaceStore(storageRootURL: root)
    let record = RecordingRecord(
      id: UUID(), createdAt: Date(), audioFileName: "mic.wav", duration: 3,
      transcript: "<|0.00|>会议原文<|3.00|>", generatedMarkdown: nil, processingError: nil,
      systemAudioFileName: "system.caf", meetingMixFileName: "meeting-mix.wav",
      transcriptSegments: [
        TranscriptSegment(start: 0, end: 3, text: "<|0.00|>会议原文<|3.00|>", sourceTrack: .meetingMix)
      ],
      processingTasks: [
        ProcessingTask(kind: .transcription, idempotencyKey: "material", status: .completed)
      ])
    try store.saveRecordings([record])
    let state = AppState(store: store)
    let router = PiConnectorRouter(appState: state)

    let response = router.handle(
      PiConnectorRequest(
        requestID: "material", method: .readMaterial,
        parameters: ["recording_id": record.id.uuidString]))

    #expect(response.error == nil)
    #expect(response.result?["artifact_id"] == "recording:\(record.id.uuidString)")
    #expect(response.result?["status"] == RecordingMaterialStatus.ready.rawValue)
    #expect(response.result?["transcript"] == "会议原文")
    #expect(response.result?["source_files_json"]?.contains("meeting-mix.wav") == true)
    #expect(state.pendingExternalProcessing == nil)
  }

  @Test("PI Router 搜索素材使用 AND 语义并分页读取长原文")
  @MainActor
  func piRouterSearchesAndPagesReadOnlyMaterial() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "woice-pi-search-page-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = WorkspaceStore(storageRootURL: root)
    let first = RecordingRecord(
      id: UUID(), createdAt: Date(), audioFileName: "first.wav", duration: 4,
      transcript: "会议 预算 讨论 结论", generatedMarkdown: nil, processingError: nil)
    let second = RecordingRecord(
      id: UUID(), createdAt: Date().addingTimeInterval(-1), audioFileName: "second.wav",
      duration: 2,
      transcript: "会议 其他 内容", generatedMarkdown: nil, processingError: nil)
    try store.saveRecordings([first, second])
    let state = AppState(store: store)
    let router = PiConnectorRouter(appState: state)

    let search = router.handle(
      PiConnectorRequest(
        requestID: "search", method: .searchMaterials,
        parameters: ["query": "会议 预算", "offset": "0", "limit": "20"]))
    #expect(search.error == nil)
    #expect(search.result?["count"] == "1")
    #expect(search.result?["results_json"]?.contains(first.id.uuidString) == true)

    let firstPage = router.handle(
      PiConnectorRequest(
        requestID: "page-1", method: .readMaterialPage,
        parameters: [
          "recording_id": first.id.uuidString, "field": "transcript", "offset": "0", "limit": "3",
        ]))
    #expect(firstPage.error == nil)
    let firstText = firstPage.result?["text"] ?? ""
    let nextOffset = firstPage.result?["next_offset"] ?? ""
    #expect(firstText == "会议 ")
    #expect(nextOffset == "3")

    let secondPage = router.handle(
      PiConnectorRequest(
        requestID: "page-2", method: .readMaterialPage,
        parameters: [
          "recording_id": first.id.uuidString, "field": "transcript", "offset": nextOffset,
          "limit": "99",
        ]))
    #expect(secondPage.error == nil)
    #expect(firstText + (secondPage.result?["text"] ?? "") == "会议 预算 讨论 结论")

    let invalidField = router.handle(
      PiConnectorRequest(
        requestID: "page-invalid", method: .readMaterialPage,
        parameters: ["recording_id": first.id.uuidString, "field": "audio", "offset": "0"]))
    #expect(invalidField.error?.code == "ROUTER_ERROR")
  }

  @Test("PI Router 缺少录音或协议错误时返回结构化错误")
  @MainActor
  func piRouterReturnsStructuredErrors() {
    let state = AppState(
      store: WorkspaceStore(storageRootURL: FileManager.default.temporaryDirectory))
    let router = PiConnectorRouter(appState: state)
    let response = router.handle(
      PiConnectorRequest(requestID: "missing", method: .readTranscript)
    )
    #expect(response.result == nil)
    #expect(response.error?.code == "ROUTER_ERROR")
  }
#endif
