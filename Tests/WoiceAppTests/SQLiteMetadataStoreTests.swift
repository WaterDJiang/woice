import Foundation
import SQLite3
import Testing
import WoiceCore

@testable import WoiceApp

private func sqliteTestRoot(_ suffix: String = UUID().uuidString) -> URL {
  FileManager.default.temporaryDirectory.appendingPathComponent(
    "woice-sqlite-\(suffix)", isDirectory: true)
}

private func sqliteTestRecord(taskStatus: ProcessingTaskStatus = .queued) -> RecordingRecord {
  let id = UUID()
  let taskDate = Date(timeIntervalSince1970: 1_700_000_001)
  return RecordingRecord(
    id: id,
    createdAt: Date(timeIntervalSince1970: 1_700_000_000),
    audioFileName: "\(id.uuidString).wav",
    duration: 2.5,
    transcript: "SQLite 测试原文",
    generatedMarkdown: nil,
    processingError: nil,
    processingTasks: [
      ProcessingTask(
        kind: .transcription,
        idempotencyKey: "\(id.uuidString.lowercased()):transcription",
        status: taskStatus,
        createdAt: taskDate,
        updatedAt: taskDate
      )
    ]
  )
}

@Test("SQLite 首次初始化迁移旧 recordings.json 且保持字段等价")
@MainActor
func sqliteStoreMigratesLegacyRecordings() throws {
  let root = sqliteTestRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  let record = sqliteTestRecord()
  let legacyURL = root.appendingPathComponent("recordings.json")
  try JSONEncoder.woice.encode([record]).write(to: legacyURL)

  let store = WorkspaceStore(storageRootURL: root)
  #expect(store.storageErrorDescription == nil)
  #expect(store.loadRecordings() == [record])
  #expect(FileManager.default.fileExists(atPath: store.databaseURL.path))
  let attributes = try FileManager.default.attributesOfItem(atPath: store.databaseURL.path)
  #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
  for suffix in ["-wal", "-shm"] {
    let sidecarURL = URL(fileURLWithPath: store.databaseURL.path + suffix)
    if FileManager.default.fileExists(atPath: sidecarURL.path) {
      let sidecarAttributes = try FileManager.default.attributesOfItem(atPath: sidecarURL.path)
      #expect((sidecarAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }
  }
}

@Test("SQLite v5 数据库升级到摘要投影时保留原始 payload")
@MainActor
func sqliteV5DatabaseUpgradePreservesRecordingPayload() throws {
  let root = sqliteTestRoot("v5-upgrade")
  defer { try? FileManager.default.removeItem(at: root) }
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  let databaseURL = root.appendingPathComponent("woice.sqlite3")
  let record = sqliteTestRecord()
  let payload = try JSONEncoder.woice.encode(record)

  var database: OpaquePointer?
  let openResult = databaseURL.path.withCString { path in
    sqlite3_open_v2(
      path, &database, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil)
  }
  guard openResult == SQLITE_OK, let database else {
    if let database { sqlite3_close(database) }
    throw WoiceError.storageFailure("无法创建 v5 测试数据库。")
  }
  defer { sqlite3_close(database) }
  let schema = """
    CREATE TABLE recordings(
      id TEXT PRIMARY KEY,
      created_at REAL NOT NULL,
      audio_file_name TEXT NOT NULL,
      duration REAL NOT NULL,
      payload_json BLOB NOT NULL
    );
    CREATE TABLE processing_jobs(
      idempotency_key TEXT PRIMARY KEY,
      recording_id TEXT NOT NULL,
      kind TEXT NOT NULL,
      status TEXT NOT NULL,
      attempt INTEGER NOT NULL,
      created_at REAL NOT NULL,
      updated_at REAL NOT NULL,
      last_error TEXT,
      lease_owner TEXT,
      lease_expires_at REAL
    );
    PRAGMA user_version=5;
    """
  guard sqlite3_exec(database, schema, nil, nil, nil) == SQLITE_OK else {
    throw WoiceError.storageFailure("无法写入 v5 测试数据库结构。")
  }
  var statement: OpaquePointer?
  let insertSQL =
    "INSERT INTO recordings(id, created_at, audio_file_name, duration, payload_json) VALUES(?, ?, ?, ?, ?)"
  guard sqlite3_prepare_v2(database, insertSQL, -1, &statement, nil) == SQLITE_OK,
    let statement
  else { throw WoiceError.storageFailure("无法准备 v5 测试记录。") }
  defer { sqlite3_finalize(statement) }
  let transientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
  record.id.uuidString.withCString { value in
    _ = sqlite3_bind_text(statement, 1, value, -1, transientDestructor)
  }
  _ = sqlite3_bind_double(statement, 2, record.createdAt.timeIntervalSince1970)
  record.audioFileName.withCString { value in
    _ = sqlite3_bind_text(statement, 3, value, -1, transientDestructor)
  }
  _ = sqlite3_bind_double(statement, 4, record.duration)
  payload.withUnsafeBytes { bytes in
    _ = sqlite3_bind_blob(
      statement, 5, bytes.baseAddress, Int32(payload.count), transientDestructor)
  }
  guard sqlite3_step(statement) == SQLITE_DONE else {
    throw WoiceError.storageFailure("无法写入 v5 测试记录。")
  }

  let migrated = try SQLiteMetadataStore(databaseURL: databaseURL)
  #expect(try migrated.loadRecordings() == [record])
  #expect(try migrated.loadRecordingSummaries().first?.displayTitle == record.audioFileName)
  // The first AppState hydration replaces the conservative filename seed with
  // the exact immutable payload projection.
  try migrated.saveRecording(record)
  #expect(try migrated.loadRecordingSummaries().first?.displayTitle == record.displayTitle)
}

@Test("SQLite 迁移前副本保留原始音频 SHA 与 Transcript Artifact 数量")
@MainActor
func sqliteMigrationPreservesAudioDigestAndArtifactCount() throws {
  let root = sqliteTestRoot("migration-integrity")
  defer { try? FileManager.default.removeItem(at: root) }
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

  let base = sqliteTestRecord()
  let audioURL = root.appendingPathComponent(base.audioFileName)
  let originalBytes = Data("immutable imported audio fixture".utf8)
  try originalBytes.write(to: audioURL, options: .atomic)
  let originalDigest = try FileSHA256.digest(url: audioURL)
  let artifact = TranscriptArtifact(
    parentRecordingID: base.id,
    text: "迁移前的原文",
    providerID: "com.woice.fixture",
    modelID: "fixture-model",
    modelVersion: "fixture-v1")
  let record = RecordingRecord(
    id: base.id,
    createdAt: base.createdAt,
    audioFileName: base.audioFileName,
    duration: base.duration,
    transcript: artifact.text,
    generatedMarkdown: base.generatedMarkdown,
    processingError: base.processingError,
    transcriptSegments: base.transcriptSegments,
    processingTasks: base.processingTasks,
    transcriptArtifacts: [artifact],
    activeTranscriptArtifactID: artifact.id,
    sourceKind: .importedVideo,
    originalMediaFileName: "会议原件.mp4",
    originalMediaSHA256: originalDigest,
    originalMediaByteCount: Int64(originalBytes.count))
  let payload = try JSONEncoder.woice.encode(record)

  let databaseURL = root.appendingPathComponent("woice.sqlite3")
  var database: OpaquePointer?
  let openResult = databaseURL.path.withCString { path in
    sqlite3_open_v2(
      path, &database, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil)
  }
  guard openResult == SQLITE_OK, let database else {
    if let database { sqlite3_close(database) }
    throw WoiceError.storageFailure("无法创建迁移完整性测试数据库。")
  }
  defer { sqlite3_close(database) }
  let schema = """
    CREATE TABLE recordings(
      id TEXT PRIMARY KEY,
      created_at REAL NOT NULL,
      audio_file_name TEXT NOT NULL,
      duration REAL NOT NULL,
      payload_json BLOB NOT NULL
    );
    CREATE TABLE processing_jobs(
      idempotency_key TEXT PRIMARY KEY,
      recording_id TEXT NOT NULL,
      kind TEXT NOT NULL,
      status TEXT NOT NULL,
      attempt INTEGER NOT NULL,
      created_at REAL NOT NULL,
      updated_at REAL NOT NULL,
      last_error TEXT,
      lease_owner TEXT,
      lease_expires_at REAL
    );
    PRAGMA user_version=5;
    """
  guard sqlite3_exec(database, schema, nil, nil, nil) == SQLITE_OK else {
    throw WoiceError.storageFailure("无法写入迁移完整性测试结构。")
  }

  var statement: OpaquePointer?
  let insertSQL =
    "INSERT INTO recordings(id, created_at, audio_file_name, duration, payload_json) VALUES(?, ?, ?, ?, ?)"
  guard sqlite3_prepare_v2(database, insertSQL, -1, &statement, nil) == SQLITE_OK,
    let statement
  else { throw WoiceError.storageFailure("无法准备迁移完整性测试记录。") }
  defer { sqlite3_finalize(statement) }
  let transientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
  record.id.uuidString.withCString { value in
    _ = sqlite3_bind_text(statement, 1, value, -1, transientDestructor)
  }
  _ = sqlite3_bind_double(statement, 2, record.createdAt.timeIntervalSince1970)
  record.audioFileName.withCString { value in
    _ = sqlite3_bind_text(statement, 3, value, -1, transientDestructor)
  }
  _ = sqlite3_bind_double(statement, 4, record.duration)
  payload.withUnsafeBytes { bytes in
    _ = sqlite3_bind_blob(
      statement, 5, bytes.baseAddress, Int32(payload.count), transientDestructor)
  }
  guard sqlite3_step(statement) == SQLITE_DONE else {
    throw WoiceError.storageFailure("无法写入迁移完整性测试记录。")
  }

  let migrated = try SQLiteMetadataStore(databaseURL: databaseURL)
  let loaded = try migrated.loadRecordings()
  #expect(loaded.count == 1)
  #expect(loaded.first?.transcriptArtifacts.count == 1)
  #expect(loaded.first?.activeTranscriptArtifactID == artifact.id)
  #expect(loaded.first?.originalMediaSHA256 == originalDigest)
  #expect(loaded.first?.originalMediaByteCount == Int64(originalBytes.count))
  #expect(try FileSHA256.digest(url: audioURL) == originalDigest)
}

@Test("SQLite Job Lease 防止抢占并支持过期恢复")
@MainActor
func sqliteJobLeaseIsDurable() throws {
  let root = sqliteTestRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let databaseURL = root.appendingPathComponent("woice.sqlite3")
  let database = try SQLiteMetadataStore(databaseURL: databaseURL)
  let record = sqliteTestRecord()
  try database.saveRecordings([record])
  let taskKey = try #require(record.processingTasks.first?.idempotencyKey)
  let now = Date(timeIntervalSince1970: 1_700_000_100)

  #expect(
    try database.acquireLease(idempotencyKey: taskKey, owner: "owner-a", now: now, duration: 10))
  #expect(
    try !database.acquireLease(
      idempotencyKey: taskKey, owner: "owner-b", now: now.addingTimeInterval(1), duration: 10))
  #expect(
    try database.renewLease(idempotencyKey: taskKey, owner: "owner-a", now: now, duration: 20))
  #expect(try database.releaseLease(idempotencyKey: taskKey, owner: "owner-a"))
  #expect(
    try database.acquireLease(idempotencyKey: taskKey, owner: "owner-b", now: now, duration: 10))

  #expect(try database.recoverExpiredLeases(now: now.addingTimeInterval(11)) == 1)
  let recovered = try #require(database.loadRecordings().first)
  #expect(recovered.processingTasks.first?.status == .interrupted)
  #expect(recovered.processingTasks.first?.lastError != nil)
  #expect(
    try database.acquireLease(
      idempotencyKey: taskKey, owner: "owner-c", now: now.addingTimeInterval(12), duration: 10))
}

@Test("SQLite 摘要投影只读取列表字段并随单条素材更新")
@MainActor
func sqliteRecordingSummaryProjectionStaysBounded() throws {
  let root = sqliteTestRoot("summaries")
  defer { try? FileManager.default.removeItem(at: root) }
  let database = try SQLiteMetadataStore(databaseURL: root.appendingPathComponent("woice.sqlite3"))
  var record = sqliteTestRecord()
  record.userTitle = "季度复盘"
  try database.saveRecording(record)

  let summary = try #require(database.loadRecordingSummaries().first)
  #expect(summary.id == record.id)
  #expect(summary.displayTitle == "季度复盘")
  #expect(summary.duration == record.duration)
  #expect(summary.materialStatus == record.materialStatus)

  record.userTitle = "季度复盘（修订）"
  try database.saveRecording(record)
  #expect(try database.loadRecordingSummaries().first?.displayTitle == "季度复盘（修订）")
  #expect(try database.loadRecordings().first?.transcript == record.transcript)
}

@Test("SQLite 迁移标记阻止数据库为空时重复导入旧索引")
@MainActor
func sqliteLegacyImportIsNotRepeated() throws {
  let root = sqliteTestRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let databaseURL = root.appendingPathComponent("woice.sqlite3")
  let database = try SQLiteMetadataStore(databaseURL: databaseURL)
  try database.markLegacyImportComplete()
  let record = sqliteTestRecord()
  try JSONEncoder.woice.encode([record]).write(to: root.appendingPathComponent("recordings.json"))

  let store = WorkspaceStore(storageRootURL: root)
  #expect(store.loadRecordings().isEmpty)
}

@Test("SQLite 保存失败前不重复创建同一幂等 Job")
@MainActor
func sqliteJobIdempotencyIsUnique() throws {
  let root = sqliteTestRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let database = try SQLiteMetadataStore(databaseURL: root.appendingPathComponent("woice.sqlite3"))
  let record = sqliteTestRecord()
  try database.saveRecordings([record])
  try database.saveRecordings([record])
  #expect(try database.loadRecordings().count == 1)
}

@Test("SQLite Recording 事务失败时回滚素材、Job 与摘要投影")
@MainActor
func sqliteRecordingTransactionRollsBackAfterInjectedFailure() throws {
  let root = sqliteTestRoot("transaction-rollback")
  defer { try? FileManager.default.removeItem(at: root) }
  let databaseURL = root.appendingPathComponent("woice.sqlite3")
  let database = try SQLiteMetadataStore(databaseURL: databaseURL)
  let existing = sqliteTestRecord()
  let rejected = sqliteTestRecord()
  try database.saveRecording(existing)

  var triggerDatabase: OpaquePointer?
  let openResult = databaseURL.path.withCString { path in
    sqlite3_open_v2(
      path, &triggerDatabase,
      SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil)
  }
  guard openResult == SQLITE_OK, let triggerDatabase else {
    if let triggerDatabase { sqlite3_close(triggerDatabase) }
    throw WoiceError.storageFailure("无法打开事务故障注入连接。")
  }
  defer { sqlite3_close(triggerDatabase) }

  let triggerSQL = """
    CREATE TRIGGER reject_recording_insert
    BEFORE INSERT ON recordings
    WHEN NEW.id = '\(rejected.id.uuidString)'
    BEGIN SELECT RAISE(ABORT, 'injected database commit failure'); END;
    """
  guard sqlite3_exec(triggerDatabase, triggerSQL, nil, nil, nil) == SQLITE_OK else {
    throw WoiceError.storageFailure("无法安装事务故障注入触发器。")
  }

  #expect(throws: (any Error).self) {
    try database.saveRecording(rejected)
  }
  #expect(try database.loadRecordings() == [existing])
  #expect(try database.loadRecordingSummaries().map(\.id) == [existing.id])
  #expect(try database.loadRecordingSummaries().contains { $0.id == rejected.id } == false)
}

@Test("SQLite 持久化模型下载任务并在重启后暂停")
@MainActor
func sqliteModelDownloadTaskSurvivesRestartAsPaused() throws {
  let root = sqliteTestRoot("model-download")
  defer { try? FileManager.default.removeItem(at: root) }
  let database = try SQLiteMetadataStore(databaseURL: root.appendingPathComponent("woice.sqlite3"))
  let created = Date(timeIntervalSince1970: 1_700_000_000)
  let recordingID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
  let intent = ModelInstallIntent(
    entryPoint: .material, recordingID: recordingID, sourceTrack: .systemAudio,
    createdAt: created)
  let task = try ModelDownloadTask(
    packID: "com.woice.fixture.model",
    version: "1.0.0",
    state: .downloading,
    completedBytes: 12,
    totalBytes: 100,
    stagingPath: "/tmp/woice.partial",
    intents: [intent],
    createdAt: created,
    updatedAt: created)
  try database.saveModelDownloadTask(task)
  let installingTask = try ModelDownloadTask(
    packID: "com.woice.fixture.installing",
    version: "1.0.0",
    state: .installing,
    completedBytes: 80,
    totalBytes: 100,
    stagingPath: "/tmp/woice.installing.partial",
    createdAt: created,
    updatedAt: created.addingTimeInterval(1))
  try database.saveModelDownloadTask(installingTask)
  let loadedTasks = try database.loadModelDownloadTasks()
  #expect(loadedTasks.contains { $0.id == task.id && $0.state == .downloading })

  #expect(try database.recoverModelDownloadTasks(now: created.addingTimeInterval(20)) == 2)
  let recovered = try #require(
    database.loadModelDownloadTasks().first { $0.id == task.id })
  let recoveredInstalling = try #require(
    database.loadModelDownloadTasks().first { $0.id == installingTask.id })
  #expect(recovered.state == .paused)
  #expect(recovered.completedBytes == 12)
  #expect(recovered.lastError?.contains("点击继续") == true)
  #expect(recovered.intents == [intent])
  #expect(recoveredInstalling.state == .paused)
}

@Test("SQLite Agent Job 持久化幂等更新并在重启后恢复为中断")
@MainActor
func sqliteAgentDispatchJobSurvivesRestartAsInterrupted() throws {
  let root = sqliteTestRoot("agent-dispatch")
  defer { try? FileManager.default.removeItem(at: root) }
  let database = try SQLiteMetadataStore(databaseURL: root.appendingPathComponent("woice.sqlite3"))
  let packageID = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!
  let created = Date(timeIntervalSince1970: 1_700_000_000)
  let hash = String(repeating: "b", count: 64)
  let job = AgentDispatchJob(
    idempotencyKey: "agent:\(packageID.uuidString):com.example.fixture",
    connectorID: "com.example.fixture",
    connectorVersion: "1.0.0",
    contextPackageID: packageID,
    instructionHash: hash,
    permissionSnapshotHash: hash,
    traceID: "trace-agent-1",
    status: .running,
    createdAt: created,
    updatedAt: created)
  try database.saveAgentDispatchJob(job)
  #expect(try database.loadAgentDispatchJobs() == [job])

  var completed = job
  completed.status = .completed
  completed.updatedAt = created.addingTimeInterval(1)
  try database.saveAgentDispatchJob(completed)
  #expect(try database.loadAgentDispatchJobs().count == 1)
  #expect(try database.loadAgentDispatchJobs().first?.status == .completed)

  var active = completed
  active.status = .collecting
  active.updatedAt = created.addingTimeInterval(2)
  try database.saveAgentDispatchJob(active)
  #expect(try database.recoverAgentDispatchJobs(now: created.addingTimeInterval(20)) == 1)
  let recovered = try #require(database.loadAgentDispatchJobs().first)
  #expect(recovered.status == .interrupted)
  #expect(recovered.lastError?.contains("手动重试") == true)
}

@Test("SQLite Agent 审计记录只保存边界元数据并可重启读取")
@MainActor
func sqliteAgentAuditEventSurvivesRestart() throws {
  let root = sqliteTestRoot("agent-audit")
  defer { try? FileManager.default.removeItem(at: root) }
  let database = try SQLiteMetadataStore(databaseURL: root.appendingPathComponent("woice.sqlite3"))
  let jobID = UUID()
  let event = AgentAuditEvent(
    occurredAt: Date(timeIntervalSince1970: 1_700_000_100),
    action: .dispatchCompleted,
    caller: "local-user",
    connectorID: "fixture-echo",
    connectorVersion: "1.0.0",
    jobID: jobID,
    traceID: "trace-audit-1",
    artifactIDs: ["recording:fixture:transcript"],
    dataTypes: [.transcript],
    outcomeCode: "completed")
  try database.saveAgentAuditEvent(event)
  #expect(try database.loadAgentAuditEvents() == [event])
  #expect(try database.loadAgentAuditEvents(limit: 0).count == 1)
}
