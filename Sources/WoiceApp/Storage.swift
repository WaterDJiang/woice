import Foundation
import WoiceCore

struct RecordingSessionJournal: Codable, Equatable, Sendable {
  let id: UUID
  let createdAt: Date
  let audioFileName: String
  let systemAudioFileName: String?
  let captureMicrophone: Bool
  let captureSystemAudio: Bool
  let meetingTranscriptionMode: MeetingTranscriptionMode

  init(
    id: UUID,
    createdAt: Date,
    audioFileName: String,
    systemAudioFileName: String?,
    captureMicrophone: Bool = true,
    captureSystemAudio: Bool,
    meetingTranscriptionMode: MeetingTranscriptionMode
  ) {
    self.id = id
    self.createdAt = createdAt
    self.audioFileName = audioFileName
    self.systemAudioFileName = systemAudioFileName
    self.captureMicrophone = captureMicrophone
    self.captureSystemAudio = captureSystemAudio
    self.meetingTranscriptionMode = meetingTranscriptionMode
  }

  private enum CodingKeys: String, CodingKey {
    case id, createdAt, audioFileName, systemAudioFileName, captureMicrophone,
      captureSystemAudio, meetingTranscriptionMode
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    createdAt = try container.decode(Date.self, forKey: .createdAt)
    audioFileName = try container.decode(String.self, forKey: .audioFileName)
    systemAudioFileName = try container.decodeIfPresent(String.self, forKey: .systemAudioFileName)
    captureMicrophone =
      try container.decodeIfPresent(Bool.self, forKey: .captureMicrophone) ?? true
    captureSystemAudio = try container.decode(Bool.self, forKey: .captureSystemAudio)
    meetingTranscriptionMode = try container.decode(
      MeetingTranscriptionMode.self, forKey: .meetingTranscriptionMode)
  }
}

/// Durable results from VAD-closed microphone segments. This is a derived
/// processing journal; the source recording remains the immutable artifact.
struct BackgroundTranscriptionJournal: Codable, Equatable, Sendable {
  let recordID: UUID
  var results: [Int: [TranscriptSegment]]
  var failedSegmentIndexes: [Int]
  var updatedAt: Date
  var providerID: String?
  var modelID: String?
  var modelVersion: String?
  var dataLocation: ASRDataLocation?
  var configurationHash: String?

  init(
    recordID: UUID,
    results: [Int: [TranscriptSegment]] = [:],
    failedSegmentIndexes: [Int] = [],
    updatedAt: Date = Date(),
    providerID: String? = nil,
    modelID: String? = nil,
    modelVersion: String? = nil,
    dataLocation: ASRDataLocation? = nil,
    configurationHash: String? = nil
  ) {
    self.recordID = recordID
    self.results = results
    self.failedSegmentIndexes = failedSegmentIndexes
    self.updatedAt = updatedAt
    self.providerID = providerID
    self.modelID = modelID
    self.modelVersion = modelVersion
    self.dataLocation = dataLocation
    self.configurationHash = configurationHash
  }

  var isValid: Bool {
    guard failedSegmentIndexes.allSatisfy({ $0 >= 0 }) else { return false }
    for (index, segments) in results {
      guard index >= 0, !segments.isEmpty else { return false }
      for segment in segments {
        guard segment.start >= 0, segment.end >= segment.start,
          !segment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return false }
      }
    }
    return true
  }
}

@MainActor
final class WorkspaceStore {
  let rootURL: URL
  let recordingsURL: URL
  let indexURL: URL
  let settingsURL: URL
  let localASRTrustURL: URL
  let databaseURL: URL
  let recordingSessionURL: URL
  private var sqliteStore: SQLiteMetadataStore?
  private(set) var storageErrorDescription: String?

  init(fileManager: FileManager = .default, storageRootURL: URL? = nil) {
    let applicationSupport =
      fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent(
        "Library/Application Support")
    rootURL =
      storageRootURL ?? WoiceTestRuntimeConfiguration.storageRoot
      ?? applicationSupport.appendingPathComponent("Woice", isDirectory: true)
    recordingsURL = rootURL.appendingPathComponent("recordings", isDirectory: true)
    indexURL = rootURL.appendingPathComponent("recordings.json")
    settingsURL = rootURL.appendingPathComponent("settings.json")
    localASRTrustURL = rootURL.appendingPathComponent("local-asr-trust.json")
    databaseURL = rootURL.appendingPathComponent("woice.sqlite3")
    recordingSessionURL = rootURL.appendingPathComponent("recording-session.json")
    sqliteStore = nil
    storageErrorDescription = nil
    try? fileManager.createDirectory(at: recordingsURL, withIntermediateDirectories: true)

    var resolvedDatabase: SQLiteMetadataStore?
    var initializationError: String?
    do {
      let database = try SQLiteMetadataStore(databaseURL: databaseURL)
      if try !database.isLegacyImportComplete() {
        if let legacy = loadLegacyRecordings() {
          try database.saveRecordings(legacy)
        }
        try database.markLegacyImportComplete()
      }
      resolvedDatabase = database
    } catch {
      initializationError = error.localizedDescription
    }
    sqliteStore = resolvedDatabase
    storageErrorDescription = initializationError
  }

  func loadRecordings() -> [RecordingRecord] {
    if let sqliteStore {
      do {
        try sqliteStore.recoverExpiredLeases()
        return try sqliteStore.loadRecordings()
      } catch {
        storageErrorDescription = error.localizedDescription
      }
    }
    return loadLegacyRecordings() ?? []
  }

  func loadModelDownloadTasks() -> [ModelDownloadTask] {
    guard let sqliteStore else { return [] }
    do {
      return try sqliteStore.loadModelDownloadTasks()
    } catch {
      storageErrorDescription = error.localizedDescription
      return []
    }
  }

  func loadAgentDispatchJobs() -> [AgentDispatchJob] {
    guard let sqliteStore else { return [] }
    do {
      return try sqliteStore.loadAgentDispatchJobs()
    } catch {
      storageErrorDescription = error.localizedDescription
      return []
    }
  }

  @discardableResult
  func recoverAgentDispatchJobs() throws -> Int {
    guard let sqliteStore else {
      throw WoiceError.storageFailure(
        storageErrorDescription ?? "SQLite 元数据存储不可用。")
    }
    return try sqliteStore.recoverAgentDispatchJobs()
  }

  func saveAgentDispatchJob(_ job: AgentDispatchJob) throws {
    guard let sqliteStore else {
      throw WoiceError.storageFailure(
        storageErrorDescription ?? "SQLite 元数据存储不可用。")
    }
    try sqliteStore.saveAgentDispatchJob(job)
  }

  func saveAgentAuditEvent(_ event: AgentAuditEvent) throws {
    guard let sqliteStore else {
      throw WoiceError.storageFailure(
        storageErrorDescription ?? "Woice SQLite 元数据存储不可用。")
    }
    try sqliteStore.saveAgentAuditEvent(event)
  }

  func loadAgentAuditEvents(limit: Int = 200) -> [AgentAuditEvent] {
    guard let sqliteStore else { return [] }
    do {
      return try sqliteStore.loadAgentAuditEvents(limit: limit)
    } catch {
      storageErrorDescription = error.localizedDescription
      return []
    }
  }

  @discardableResult
  func recoverModelDownloadTasks() throws -> Int {
    guard let sqliteStore else {
      throw WoiceError.storageFailure(
        storageErrorDescription ?? "SQLite 元数据存储不可用。")
    }
    return try sqliteStore.recoverModelDownloadTasks()
  }

  func saveModelDownloadTask(_ task: ModelDownloadTask) throws {
    guard let sqliteStore else {
      throw WoiceError.storageFailure(
        storageErrorDescription ?? "SQLite 元数据存储不可用。")
    }
    try sqliteStore.saveModelDownloadTask(task)
  }

  func saveRecordings(_ recordings: [RecordingRecord]) throws {
    let data = try JSONEncoder.woice.encode(recordings)
    if let sqliteStore {
      try sqliteStore.saveRecordings(recordings)
    } else {
      throw WoiceError.storageFailure(
        storageErrorDescription ?? "SQLite 元数据存储不可用。")
    }
    try data.write(to: indexURL, options: .atomic)
  }

  func acquireJobLease(
    idempotencyKey: String, owner: String, duration: TimeInterval = 60
  ) throws -> Bool {
    guard let sqliteStore else {
      throw WoiceError.storageFailure(storageErrorDescription ?? "SQLite 元数据存储不可用。")
    }
    return try sqliteStore.acquireLease(
      idempotencyKey: idempotencyKey, owner: owner, duration: duration)
  }

  @discardableResult
  func renewJobLease(
    idempotencyKey: String, owner: String, duration: TimeInterval = 60
  ) throws -> Bool {
    guard let sqliteStore else {
      throw WoiceError.storageFailure(storageErrorDescription ?? "SQLite 元数据存储不可用。")
    }
    return try sqliteStore.renewLease(
      idempotencyKey: idempotencyKey, owner: owner, duration: duration)
  }

  @discardableResult
  func releaseJobLease(idempotencyKey: String, owner: String) throws -> Bool {
    guard let sqliteStore else {
      throw WoiceError.storageFailure(storageErrorDescription ?? "SQLite 元数据存储不可用。")
    }
    return try sqliteStore.releaseLease(idempotencyKey: idempotencyKey, owner: owner)
  }

  private func loadLegacyRecordings() -> [RecordingRecord]? {
    guard let data = try? Data(contentsOf: indexURL),
      let recordings = try? JSONDecoder.woice.decode([RecordingRecord].self, from: data)
    else { return nil }
    return recordings.sorted { $0.createdAt > $1.createdAt }
  }

  func loadSettings() -> AppSettings {
    guard let data = try? Data(contentsOf: settingsURL),
      let settings = try? JSONDecoder.woice.decode(AppSettings.self, from: data)
    else {
      return .default
    }
    return settings
  }

  func saveSettings(_ settings: AppSettings) throws {
    let data = try JSONEncoder.woice.encode(settings)
    try data.write(to: settingsURL, options: .atomic)
  }

  func loadLocalASRTrust() -> LocalASRTrustSnapshot? {
    guard let data = try? Data(contentsOf: localASRTrustURL) else { return nil }
    return try? JSONDecoder.woice.decode(LocalASRTrustSnapshot.self, from: data)
  }

  func saveLocalASRTrust(_ snapshot: LocalASRTrustSnapshot) throws {
    let data = try JSONEncoder.woice.encode(snapshot)
    try data.write(to: localASRTrustURL, options: .atomic)
  }

  func clearLocalASRTrust() {
    try? FileManager.default.removeItem(at: localASRTrustURL)
  }

  func saveRecordingSession(_ journal: RecordingSessionJournal) throws {
    let data = try JSONEncoder.woice.encode(journal)
    try data.write(to: recordingSessionURL, options: .atomic)
  }

  func backgroundTranscriptionURL(for recordID: UUID) -> URL {
    recordingsURL.appendingPathComponent(
      "\(recordID.uuidString).background.json", isDirectory: false)
  }

  func saveBackgroundTranscriptionJournal(_ journal: BackgroundTranscriptionJournal) throws {
    guard journal.isValid else {
      throw WoiceError.storageFailure("后台转写结果格式无效。")
    }
    let data = try JSONEncoder.woice.encode(journal)
    try data.write(to: backgroundTranscriptionURL(for: journal.recordID), options: .atomic)
  }

  func loadBackgroundTranscriptionJournal(for recordID: UUID) -> BackgroundTranscriptionJournal? {
    let url = backgroundTranscriptionURL(for: recordID)
    guard let data = try? Data(contentsOf: url),
      let journal = try? JSONDecoder.woice.decode(BackgroundTranscriptionJournal.self, from: data),
      journal.recordID == recordID, journal.isValid
    else { return nil }
    return journal
  }

  func clearBackgroundTranscriptionJournal(for recordID: UUID) {
    try? FileManager.default.removeItem(at: backgroundTranscriptionURL(for: recordID))
  }

  func loadRecordingSession() -> RecordingSessionJournal? {
    guard let data = try? Data(contentsOf: recordingSessionURL) else { return nil }
    return try? JSONDecoder.woice.decode(RecordingSessionJournal.self, from: data)
  }

  func clearRecordingSession() {
    try? FileManager.default.removeItem(at: recordingSessionURL)
  }

  func audioURL(for record: RecordingRecord) -> URL {
    recordingsURL.appendingPathComponent(record.audioFileName)
  }

  func originalMediaURL(for record: RecordingRecord) -> URL? {
    guard let fileName = record.originalMediaFileName, !fileName.isEmpty else { return nil }
    return recordingsURL.appendingPathComponent(fileName)
  }

  func systemAudioURL(for record: RecordingRecord) -> URL? {
    guard let fileName = record.systemAudioFileName, !fileName.isEmpty else { return nil }
    return recordingsURL.appendingPathComponent(fileName)
  }

  func meetingMixURL(for record: RecordingRecord) -> URL {
    let fileName = record.meetingMixFileName ?? "\(record.id.uuidString).meeting-mix.wav"
    return recordingsURL.appendingPathComponent(fileName)
  }

  func agentResultURL(for artifact: AgentResultArtifact) -> URL {
    rootURL.appendingPathComponent("agent-results", isDirectory: true)
      .appendingPathComponent(URL(fileURLWithPath: artifact.relativePath).lastPathComponent)
  }

  func markdownURL(for record: RecordingRecord, directory: URL? = nil) -> URL {
    exportURL(for: record, suffix: "md", directory: directory)
  }

  func exportURL(for record: RecordingRecord, suffix: String, directory: URL? = nil) -> URL {
    let target = directory ?? rootURL.appendingPathComponent("exports", isDirectory: true)
    try? FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
    let safeTitle = record.title
      .replacingOccurrences(of: "/", with: "-")
      .replacingOccurrences(of: "\\", with: "-")
      .prefix(40)
    let date = record.createdAt.formatted(.iso8601.year().month().day())
    let safeSuffix = suffix.trimmingCharacters(in: CharacterSet(charactersIn: "."))
    let filename = "\(date)-\(safeTitle).\(safeSuffix)"
    return target.appendingPathComponent(filename)
  }
}

extension JSONEncoder {
  static let woice: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return encoder
  }()
}

extension JSONDecoder {
  static let woice: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }()
}
