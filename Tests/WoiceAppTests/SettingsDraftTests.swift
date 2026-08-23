import Foundation
import Security
import Testing
import WoiceCore

@testable import WoiceApp

private final class ASRHealthCheckURLProtocol: URLProtocol {
  nonisolated(unsafe) static var request: URLRequest?

  override class func canInit(with request: URLRequest) -> Bool { true }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    Self.request = request
    let response = HTTPURLResponse(
      url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

private final class RecordingKeychainStore: KeychainStoring {
  var values: [String: String]
  var reads: [String] = []
  var writes: [String] = []
  var removals: [String] = []

  init(values: [String: String] = [:]) {
    self.values = values
  }

  func read(account: String) -> String {
    reads.append(account)
    return values[account] ?? ""
  }

  func write(_ value: String, account: String) throws {
    writes.append(account)
    values[account] = value
  }

  func remove(account: String) {
    removals.append(account)
    values.removeValue(forKey: account)
  }

  func resetAccessLog() {
    reads.removeAll()
    writes.removeAll()
    removals.removeAll()
  }
}

/// Uses the real Security.framework API while keeping the suite independent
/// from the user's login keychain password/lock state.
private final class IsolatedKeychainStore: KeychainStoring {
  private let service: String
  private let keychain: SecKeychain

  init(url: URL, service: String) throws {
    self.service = service
    var created: SecKeychain?
    let password = Array("woice-test-keychain-password".utf8)
    let createStatus = password.withUnsafeBytes { bytes in
      SecKeychainCreate(
        url.path, UInt32(password.count), bytes.baseAddress, false, nil, &created)
    }
    guard createStatus == errSecSuccess, let created else {
      throw WoiceError.storageFailure(
        "创建隔离测试钥匙串失败（(createStatus)）。")
    }
    let unlockStatus = password.withUnsafeBytes { bytes in
      SecKeychainUnlock(created, UInt32(password.count), bytes.baseAddress, true)
    }
    guard unlockStatus == errSecSuccess else {
      SecKeychainDelete(created)
      throw WoiceError.storageFailure(
        "解锁隔离测试钥匙串失败（(unlockStatus)）。")
    }
    keychain = created
  }

  deinit {
    SecKeychainDelete(keychain)
  }

  func read(account: String) -> String {
    var query = baseQuery(account: account)
    query[kSecReturnData] = true
    query[kSecMatchLimit] = kSecMatchLimitOne
    var result: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
      let data = result as? Data,
      let value = String(data: data, encoding: .utf8)
    else {
      return ""
    }
    return value
  }

  func write(_ value: String, account: String) throws {
    let data = Data(value.utf8)
    let query = baseQuery(account: account)
    let status = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
    if status == errSecItemNotFound {
      var item = query
      item.removeValue(forKey: kSecMatchSearchList)
      item[kSecUseKeychain] = keychain
      item[kSecValueData] = data
      let addStatus = SecItemAdd(item as CFDictionary, nil)
      guard addStatus == errSecSuccess else {
        throw WoiceError.storageFailure(
          KeychainStoreDiagnostics.failureMessage(operation: "写入", status: addStatus))
      }
    } else if status != errSecSuccess {
      throw WoiceError.storageFailure(
        KeychainStoreDiagnostics.failureMessage(operation: "更新", status: status))
    }
  }

  func remove(account: String) {
    _ = SecItemDelete(baseQuery(account: account) as CFDictionary)
  }

  private func baseQuery(account: String) -> [CFString: Any] {
    [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: service,
      kSecAttrAccount: account,
      kSecMatchSearchList: [keychain],
    ]
  }
}

@Test("候选设置保存前不改变 AppState，成功后一次性提交")
@MainActor
func settingsCandidateCommitsOnlyAfterSuccessfulSave() throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "woice-settings-draft-" + UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }

  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  var keychain: IsolatedKeychainStore? = try IsolatedKeychainStore(
    url: root.appendingPathComponent("test.keychain-db"),
    service: "com.woice.test." + UUID().uuidString)
  defer {
    keychain?.remove(account: "asr-api-key")
    keychain?.remove(account: "llm-api-key")
    keychain = nil
    try? FileManager.default.removeItem(at: root)
  }
  let store = WorkspaceStore(storageRootURL: root)
  let state = AppState(store: store, keychain: keychain!)
  let original = state.settings
  var candidate = original
  candidate.asrEndpoint = "https://example.test/v1"
  candidate.asrModel = "whisper-test"
  candidate.asrAPIKey = "draft-key"

  #expect(state.settings == original)
  #expect(state.saveSettings(candidate: candidate))
  #expect(state.settings == candidate)
  #expect(store.loadSettings().asrEndpoint == candidate.asrEndpoint)
  #expect(store.loadSettings().asrAPIKey.isEmpty)
  #expect(keychain!.read(account: "asr-api-key") == "draft-key")
}

@Test("Agent 连接分区不绑定 AppSettings 或 Keychain 保存")
func agentSettingsSectionHasNoPersistenceScope() {
  #expect(SettingsSection.agents.saveScope == nil)
  #expect(SettingsSection.agents.title == "Agent 与连接")
  #expect(SettingsSection.agents.footerPrivacyMessage.contains("不保存 API Key"))
}

@Test("候选设置校验失败时不提交 AppState")
@MainActor
func invalidSettingsCandidateDoesNotCommit() throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "woice-settings-invalid-" + UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }

  let state = AppState(
    store: WorkspaceStore(storageRootURL: root),
    keychain: KeychainStore(service: "com.woice.test." + UUID().uuidString)
  )
  let original = state.settings
  var candidate = original
  candidate.asrEndpoint = "https://example.test/v1"
  candidate.asrModel = ""

  #expect(!state.saveSettings(candidate: candidate))
  #expect(state.settings == original)
  #expect(state.errorMessage?.contains("模型不能为空") == true)
}

@Test("普通设置保存不访问 Keychain，API Key 按账号独立写入")
@MainActor
func settingsSaveScopesKeychainAccessToChangedAPIKeys() throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "woice-settings-keychain-scope-" + UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }

  let keychain = RecordingKeychainStore(
    values: ["asr-api-key": "asr-old", "llm-api-key": "llm-old"])
  let state = AppState(
    store: WorkspaceStore(storageRootURL: root),
    keychain: keychain
  )
  keychain.resetAccessLog()

  var ordinaryCandidate = state.settings
  ordinaryCandidate.captureSystemAudio.toggle()
  #expect(state.saveSettings(candidate: ordinaryCandidate, scope: .recording))
  #expect(keychain.reads.isEmpty)
  #expect(keychain.writes.isEmpty)
  #expect(keychain.removals.isEmpty)

  keychain.resetAccessLog()
  var asrCandidate = state.settings
  asrCandidate.asrAPIKey = "asr-new"
  #expect(state.saveSettings(candidate: asrCandidate))
  #expect(keychain.reads.isEmpty)
  #expect(keychain.writes == ["asr-api-key"])
  #expect(keychain.removals.isEmpty)
  #expect(keychain.values["llm-api-key"] == "llm-old")
}

@Test("AppState 启动不读取 Keychain，延迟加载保留已有运行时密钥")
@MainActor
func appStateDefersKeychainReadAndPreservesRuntimeSecret() throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "woice-settings-keychain-lazy-" + UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }

  let keychain = RecordingKeychainStore(
    values: ["asr-api-key": "stored-asr", "llm-api-key": "stored-llm"])
  let state = AppState(store: WorkspaceStore(storageRootURL: root), keychain: keychain)
  #expect(keychain.reads.isEmpty)

  state.settings.asrAPIKey = "runtime-asr"
  #expect(state.loadKeychainSecretsIfNeeded())
  #expect(state.settings.asrAPIKey == "runtime-asr")
  #expect(state.settings.llmAPIKey == "stored-llm")
  #expect(keychain.reads == ["llm-api-key"])
  #expect(!state.loadKeychainSecretsIfNeeded())
  #expect(keychain.reads == ["llm-api-key"])
}

@Test("分区保存不会被其他分区的非法草稿阻塞")
@MainActor
func settingsSectionSaveIgnoresUncommittedOtherSection() throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "woice-settings-section-scope-" + UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }

  let state = AppState(
    store: WorkspaceStore(storageRootURL: root),
    keychain: KeychainStore(service: "com.woice.test." + UUID().uuidString)
  )
  let originalEndpoint = state.settings.asrEndpoint
  let originalModel = state.settings.asrModel
  var draft = state.settings
  draft.captureSystemAudio.toggle()
  draft.asrEndpoint = "https://invalid-draft.example/v1"
  draft.asrModel = ""

  #expect(state.saveSettings(candidate: draft, scope: .recording))
  #expect(state.settings.captureSystemAudio)
  #expect(state.settings.asrEndpoint == originalEndpoint)
  #expect(state.settings.asrModel == originalModel)
}

@Test("文件分区保存只提交导出目录")
@MainActor
func settingsFilesSectionSaveIsIndependent() throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "woice-settings-files-scope-" + UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }

  let keychain = RecordingKeychainStore(values: ["asr-api-key": "asr-old"])
  let state = AppState(store: WorkspaceStore(storageRootURL: root), keychain: keychain)
  #expect(keychain.reads.isEmpty)
  #expect(state.loadKeychainSecretsIfNeeded())
  #expect(state.settings.asrAPIKey == "asr-old")
  keychain.resetAccessLog()
  var draft = state.settings
  draft.exportDirectory = root.appendingPathComponent("exports").path
  draft.asrAPIKey = "should-not-write"

  #expect(state.saveSettings(candidate: draft, scope: .files))
  #expect(state.settings.exportDirectory == draft.exportDirectory)
  #expect(state.settings.asrAPIKey == "asr-old")
  #expect(keychain.reads.isEmpty)
  #expect(keychain.writes.isEmpty)
  #expect(keychain.removals.isEmpty)
}

@Test("转写 API 健康检查只发送临时测试音频，不创建历史记录")
@MainActor
func asrHealthCheckUsesTemporaryAudioOnly() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "woice-settings-health-" + UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }

  let configuration = URLSessionConfiguration.ephemeral
  configuration.protocolClasses = [ASRHealthCheckURLProtocol.self]
  ASRHealthCheckURLProtocol.request = nil
  let session = URLSession(configuration: configuration)
  let state = AppState(
    store: WorkspaceStore(storageRootURL: root),
    transcriptionClient: TranscriptionClient(session: session),
    keychain: KeychainStore(service: "com.woice.test." + UUID().uuidString)
  )
  let before = state.settings

  let result = try await state.checkASRConfiguration(
    endpoint: "https://example.test/v1",
    model: "whisper-health",
    apiKey: "health-secret",
    language: "zh"
  )

  #expect(result.statusCode == 204)
  #expect(state.settings == before)
  #expect(state.recordings.isEmpty)
  let request = try #require(ASRHealthCheckURLProtocol.request)
  #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer health-secret")
  let body = try #require(requestBodyData(for: request))
  #expect(body.range(of: Data("RIFF".utf8)) != nil)
  #expect(body.range(of: Data("whisper-health".utf8)) != nil)
}

@Test("本机服务健康检查信任事实可持久化，并在配置变化后失效")
@MainActor
func localASRTrustSnapshotPersistsAndInvalidatesOnConfigurationChange() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "woice-local-asr-trust-" + UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }

  let configuration = URLSessionConfiguration.ephemeral
  configuration.protocolClasses = [ASRHealthCheckURLProtocol.self]
  let session = URLSession(configuration: configuration)
  let keychain = RecordingKeychainStore()
  let store = WorkspaceStore(storageRootURL: root)
  let state = AppState(
    store: store,
    transcriptionClient: TranscriptionClient(session: session),
    keychain: keychain)
  state.settings.language = "zh"
  state.settings.includeTranscriptTimestamps = true

  _ = try await state.checkASRConfiguration(
    endpoint: "http://127.0.0.1:49152/v1",
    model: "whisper-loopback",
    apiKey: "health-secret",
    language: "zh",
    includeTimestamps: true)
  let snapshot = try #require(store.loadLocalASRTrust())
  #expect(snapshot.endpointIdentity == "http://127.0.0.1:49152/v1")
  #expect(snapshot.modelID == "whisper-loopback")
  #expect(snapshot.includeTimestamps)
  #expect(!snapshot.configurationHash.contains("health-secret"))

  var candidate = state.settings
  candidate.asrProviderSelection = .external
  candidate.asrEndpoint = "http://127.0.0.1:49152/v1"
  candidate.asrModel = "whisper-loopback"
  #expect(state.saveSettings(candidate: candidate, scope: .services))
  #expect(store.loadLocalASRTrust() == snapshot)

  candidate.asrModel = "whisper-large"
  #expect(state.saveSettings(candidate: candidate, scope: .services))
  #expect(store.loadLocalASRTrust() == nil)
}

private func requestBodyData(for request: URLRequest) -> Data? {
  if let body = request.httpBody { return body }
  guard let stream = request.httpBodyStream else { return nil }
  stream.open()
  defer { stream.close() }
  var data = Data()
  var buffer = [UInt8](repeating: 0, count: 4_096)
  while stream.hasBytesAvailable {
    let count = stream.read(&buffer, maxLength: buffer.count)
    guard count > 0 else { break }
    data.append(buffer, count: count)
  }
  return data
}
