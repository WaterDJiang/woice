import Darwin
import Foundation
import SQLite3
import WoiceCore

enum SQLiteMetadataStoreError: LocalizedError, Equatable {
  case openFailed(String)
  case migrationFailed(String)
  case queryFailed(String)
  case invalidPayload
  case invalidJobState

  var errorDescription: String? {
    switch self {
    case .openFailed(let message): "无法打开 Woice SQLite 数据库：\(message)"
    case .migrationFailed(let message): "Woice SQLite 数据库迁移失败：\(message)"
    case .queryFailed(let message): "Woice SQLite 数据库操作失败：\(message)"
    case .invalidPayload: "Woice SQLite 中的录音数据无法读取。"
    case .invalidJobState: "Woice Job 状态不合法，已拒绝更新。"
    }
  }
}

/// SQLite metadata truth source. Audio and derived documents remain files.
/// The store is MainActor-bound by WorkspaceStore, so each transaction is short
/// and deterministic; no audio or network work is performed here.
@MainActor
final class SQLiteMetadataStore {
  static let schemaVersion = 5

  let databaseURL: URL
  nonisolated(unsafe) private var database: OpaquePointer?
  private let transientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

  init(databaseURL: URL) throws {
    self.databaseURL = databaseURL
    try FileManager.default.createDirectory(
      at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    var opened: OpaquePointer?
    let result = databaseURL.path.withCString { path in
      sqlite3_open_v2(
        path, &opened, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil)
    }
    guard result == SQLITE_OK, let opened else {
      let message = opened.map { String(cString: sqlite3_errmsg($0)) } ?? "未知错误"
      if let opened { sqlite3_close(opened) }
      throw SQLiteMetadataStoreError.openFailed(message)
    }
    database = opened
    do {
      try configure()
      try migrate()
      secureDatabaseFiles()
    } catch {
      sqlite3_close(opened)
      database = nil
      throw error
    }
  }

  deinit {
    if let database { sqlite3_close(database) }
  }

  func loadRecordings() throws -> [RecordingRecord] {
    let statement = try prepare(
      "SELECT payload_json FROM recordings ORDER BY created_at DESC, id DESC")
    defer { sqlite3_finalize(statement) }
    var records: [RecordingRecord] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      guard let bytes = sqlite3_column_blob(statement, 0) else {
        throw SQLiteMetadataStoreError.invalidPayload
      }
      let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
      guard let record = try? JSONDecoder.woice.decode(RecordingRecord.self, from: data) else {
        throw SQLiteMetadataStoreError.invalidPayload
      }
      records.append(record)
    }
    try applyJobProjection(to: &records)
    return records
  }

  func loadModelDownloadTasks() throws -> [ModelDownloadTask] {
    let statement = try prepare(
      """
      SELECT id, pack_id, version, state, completed_bytes, total_bytes,
             staging_path, last_error, intents_json, created_at, updated_at
      FROM model_download_jobs
      ORDER BY updated_at DESC, id DESC
      """
    )
    defer { sqlite3_finalize(statement) }
    var tasks: [ModelDownloadTask] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      guard
        let idText = textColumn(statement, index: 0),
        let id = UUID(uuidString: idText),
        let packID = textColumn(statement, index: 1),
        let version = textColumn(statement, index: 2),
        let stateText = textColumn(statement, index: 3),
        let state = ModelInstallationState(rawValue: stateText)
      else { throw SQLiteMetadataStoreError.invalidPayload }
      do {
        tasks.append(
          try ModelDownloadTask(
            id: id,
            packID: packID,
            version: version,
            state: state,
            completedBytes: sqlite3_column_int64(statement, 4),
            totalBytes: sqlite3_column_int64(statement, 5),
            stagingPath: optionalTextColumn(statement, index: 6),
            lastError: optionalTextColumn(statement, index: 7),
            intents: try decodeModelInstallIntents(from: statement, index: 8),
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 9)),
            updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 10))
          )
        )
      } catch {
        throw SQLiteMetadataStoreError.invalidPayload
      }
    }
    return tasks
  }

  func loadAgentDispatchJobs() throws -> [AgentDispatchJob] {
    let statement = try prepare(
      "SELECT payload_json FROM agent_dispatch_jobs ORDER BY updated_at DESC, id DESC")
    defer { sqlite3_finalize(statement) }
    var jobs: [AgentDispatchJob] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      guard let bytes = sqlite3_column_blob(statement, 0) else {
        throw SQLiteMetadataStoreError.invalidPayload
      }
      let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
      guard let job = try? JSONDecoder.woice.decode(AgentDispatchJob.self, from: data),
        (try? job.validated()) != nil
      else { throw SQLiteMetadataStoreError.invalidPayload }
      jobs.append(job)
    }
    return jobs
  }

  func saveAgentDispatchJob(_ job: AgentDispatchJob) throws {
    _ = try job.validated()
    let payload = try JSONEncoder.woice.encode(job)
    let statement = try prepare(
      """
      INSERT INTO agent_dispatch_jobs(
        id, idempotency_key, connector_id, context_package_id, status,
        created_at, updated_at, payload_json
      ) VALUES(?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        idempotency_key=excluded.idempotency_key,
        connector_id=excluded.connector_id,
        context_package_id=excluded.context_package_id,
        status=excluded.status,
        created_at=excluded.created_at,
        updated_at=excluded.updated_at,
        payload_json=excluded.payload_json
      """
    )
    defer { sqlite3_finalize(statement) }
    try bindText(job.id.uuidString, to: statement, index: 1)
    try bindText(job.idempotencyKey, to: statement, index: 2)
    try bindText(job.connectorID, to: statement, index: 3)
    try bindText(job.contextPackageID.uuidString, to: statement, index: 4)
    try bindText(job.status.rawValue, to: statement, index: 5)
    try bindDouble(job.createdAt.timeIntervalSince1970, to: statement, index: 6)
    try bindDouble(job.updatedAt.timeIntervalSince1970, to: statement, index: 7)
    try bindBlob(payload, to: statement, index: 8)
    try step(statement)
  }

  func saveAgentAuditEvent(_ event: AgentAuditEvent) throws {
    _ = try event.validated()
    let payload = try JSONEncoder.woice.encode(event)
    let statement = try prepare(
      """
      INSERT INTO agent_audit_events(
        id, occurred_at, action, connector_id, job_id, payload_json
      ) VALUES(?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO NOTHING
      """
    )
    defer { sqlite3_finalize(statement) }
    try bindText(event.id.uuidString, to: statement, index: 1)
    try bindDouble(event.occurredAt.timeIntervalSince1970, to: statement, index: 2)
    try bindText(event.action.rawValue, to: statement, index: 3)
    try bindText(event.connectorID, to: statement, index: 4)
    try bindOptionalText(event.jobID?.uuidString, to: statement, index: 5)
    try bindBlob(payload, to: statement, index: 6)
    try step(statement)
  }

  func loadAgentAuditEvents(limit: Int = 200) throws -> [AgentAuditEvent] {
    let boundedLimit = min(max(limit, 1), 1_000)
    let statement = try prepare(
      """
      SELECT payload_json FROM agent_audit_events
      ORDER BY occurred_at DESC, id DESC LIMIT ?
      """
    )
    defer { sqlite3_finalize(statement) }
    try bindInt(boundedLimit, to: statement, index: 1)
    var events: [AgentAuditEvent] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      guard let bytes = sqlite3_column_blob(statement, 0) else {
        throw SQLiteMetadataStoreError.invalidPayload
      }
      let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
      guard let event = try? JSONDecoder.woice.decode(AgentAuditEvent.self, from: data),
        (try? event.validated()) != nil
      else { throw SQLiteMetadataStoreError.invalidPayload }
      events.append(event)
    }
    return events
  }

  @discardableResult
  func recoverAgentDispatchJobs(now: Date = Date()) throws -> Int {
    let jobs = try loadAgentDispatchJobs()
    var recovered = 0
    for var job in jobs {
      guard [.launching, .running, .collecting, .awaitingAgentApproval].contains(job.status) else {
        continue
      }
      job.status = .interrupted
      job.updatedAt = now
      job.lastErrorCode = .invalidContract
      job.lastError = "应用上次关闭时 Agent 任务未完成，请手动重试。"
      try saveAgentDispatchJob(job)
      recovered += 1
    }
    return recovered
  }

  func saveModelDownloadTask(_ task: ModelDownloadTask) throws {
    let statement = try prepare(
      """
      INSERT INTO model_download_jobs(
        id, pack_id, version, state, completed_bytes, total_bytes,
        staging_path, last_error, intents_json, created_at, updated_at
      ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        pack_id=excluded.pack_id,
        version=excluded.version,
        state=excluded.state,
        completed_bytes=excluded.completed_bytes,
        total_bytes=excluded.total_bytes,
        staging_path=excluded.staging_path,
        last_error=excluded.last_error,
        intents_json=excluded.intents_json,
        updated_at=excluded.updated_at
      """
    )
    defer { sqlite3_finalize(statement) }
    try bindText(task.id.uuidString, to: statement, index: 1)
    try bindText(task.packID, to: statement, index: 2)
    try bindText(task.version, to: statement, index: 3)
    try bindText(task.state.rawValue, to: statement, index: 4)
    try bindInt64(task.completedBytes, to: statement, index: 5)
    try bindInt64(task.totalBytes, to: statement, index: 6)
    try bindOptionalText(task.stagingPath, to: statement, index: 7)
    try bindOptionalText(task.lastError, to: statement, index: 8)
    try bindBlob(JSONEncoder.woice.encode(task.intents), to: statement, index: 9)
    try bindDouble(task.createdAt.timeIntervalSince1970, to: statement, index: 10)
    try bindDouble(task.updatedAt.timeIntervalSince1970, to: statement, index: 11)
    try step(statement)
  }

  @discardableResult
  func recoverModelDownloadTasks(now: Date = Date()) throws -> Int {
    let statement = try prepare(
      """
      UPDATE model_download_jobs
      SET state='paused',
          last_error='应用上次关闭时下载被暂停；点击继续即可恢复。',
          updated_at=?
      WHERE state IN ('preflighting','downloading','verifying','installing','activating')
      """
    )
    defer { sqlite3_finalize(statement) }
    try bindDouble(now.timeIntervalSince1970, to: statement, index: 1)
    try step(statement)
    return Int(sqlite3_changes(database))
  }

  func saveRecordings(_ records: [RecordingRecord]) throws {
    try execute("BEGIN IMMEDIATE TRANSACTION")
    do {
      let existingRecordingIDs = try stringColumnValues(
        "SELECT id FROM recordings", column: 0)
      let currentRecordingIDs = Set(records.map { $0.id.uuidString })
      for id in existingRecordingIDs where !currentRecordingIDs.contains(id) {
        try executeDelete(table: "recordings", keyColumn: "id", value: id)
      }

      let existingJobKeys = try stringColumnValues(
        "SELECT idempotency_key FROM processing_jobs", column: 0)
      let currentJobKeys = Set(records.flatMap { $0.processingTasks.map(\.idempotencyKey) })
      for key in existingJobKeys where !currentJobKeys.contains(key) {
        try executeDelete(table: "processing_jobs", keyColumn: "idempotency_key", value: key)
      }

      for record in records {
        let payload = try JSONEncoder.woice.encode(record)
        let statement = try prepare(
          """
          INSERT INTO recordings(id, created_at, audio_file_name, duration, payload_json)
          VALUES(?, ?, ?, ?, ?)
          ON CONFLICT(id) DO UPDATE SET
            created_at=excluded.created_at,
            audio_file_name=excluded.audio_file_name,
            duration=excluded.duration,
            payload_json=excluded.payload_json
          """
        )
        defer { sqlite3_finalize(statement) }
        try bindText(record.id.uuidString, to: statement, index: 1)
        try bindDouble(record.createdAt.timeIntervalSince1970, to: statement, index: 2)
        try bindText(record.audioFileName, to: statement, index: 3)
        try bindDouble(record.duration, to: statement, index: 4)
        try bindBlob(payload, to: statement, index: 5)
        try step(statement)

        for task in record.processingTasks {
          try upsertJob(task, recordingID: record.id.uuidString)
        }
      }
      try execute("COMMIT")
      secureDatabaseFiles()
    } catch {
      try? execute("ROLLBACK")
      throw error
    }
  }

  func hasRecordings() throws -> Bool {
    let statement = try prepare("SELECT 1 FROM recordings LIMIT 1")
    defer { sqlite3_finalize(statement) }
    return sqlite3_step(statement) == SQLITE_ROW
  }

  func isLegacyImportComplete() throws -> Bool {
    let statement = try prepare("SELECT value FROM metadata WHERE key='legacy_imported'")
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW else { return false }
    return textColumn(statement, index: 0) == "1"
  }

  func markLegacyImportComplete() throws {
    let statement = try prepare(
      "INSERT INTO metadata(key, value) VALUES('legacy_imported', '1') ON CONFLICT(key) DO UPDATE SET value='1'"
    )
    defer { sqlite3_finalize(statement) }
    try step(statement)
  }

  /// Marks only expired running leases. Call before loading the read model.
  @discardableResult
  func recoverExpiredLeases(now: Date = Date()) throws -> Int {
    let statement = try prepare(
      """
      UPDATE processing_jobs
      SET status='interrupted',
          last_error='应用上次关闭时 Job Lease 已过期，请手动重试。',
          lease_owner=NULL,
          lease_expires_at=NULL,
          updated_at=?
      WHERE status='running' AND lease_expires_at IS NOT NULL AND lease_expires_at <= ?
      """
    )
    defer { sqlite3_finalize(statement) }
    try bindDouble(now.timeIntervalSince1970, to: statement, index: 1)
    try bindDouble(now.timeIntervalSince1970, to: statement, index: 2)
    try step(statement)
    return Int(sqlite3_changes(database))
  }

  func acquireLease(
    idempotencyKey: String, owner: String, now: Date = Date(), duration: TimeInterval = 60
  ) throws -> Bool {
    guard !idempotencyKey.isEmpty, !owner.isEmpty, duration > 0 else {
      throw SQLiteMetadataStoreError.invalidJobState
    }
    let statement = try prepare(
      """
      UPDATE processing_jobs
      SET status='running', lease_owner=?, lease_expires_at=?, updated_at=?
      WHERE idempotency_key=? AND status IN (
        'queued','waitingForModel','awaitingAuthorization','running',
        'failed','interrupted','cancelled'
      )
        AND (lease_owner IS NULL OR lease_expires_at IS NULL OR lease_expires_at <= ? OR lease_owner=?)
      """
    )
    defer { sqlite3_finalize(statement) }
    let expiry = now.addingTimeInterval(duration).timeIntervalSince1970
    try bindText(owner, to: statement, index: 1)
    try bindDouble(expiry, to: statement, index: 2)
    try bindDouble(now.timeIntervalSince1970, to: statement, index: 3)
    try bindText(idempotencyKey, to: statement, index: 4)
    try bindDouble(now.timeIntervalSince1970, to: statement, index: 5)
    try bindText(owner, to: statement, index: 6)
    try step(statement)
    return sqlite3_changes(database) == 1
  }

  func renewLease(
    idempotencyKey: String, owner: String, now: Date = Date(), duration: TimeInterval = 60
  ) throws -> Bool {
    guard !idempotencyKey.isEmpty, !owner.isEmpty, duration > 0 else {
      throw SQLiteMetadataStoreError.invalidJobState
    }
    let statement = try prepare(
      """
      UPDATE processing_jobs
      SET lease_expires_at=?, updated_at=?
      WHERE idempotency_key=? AND status='running' AND lease_owner=?
      """
    )
    defer { sqlite3_finalize(statement) }
    try bindDouble(now.addingTimeInterval(duration).timeIntervalSince1970, to: statement, index: 1)
    try bindDouble(now.timeIntervalSince1970, to: statement, index: 2)
    try bindText(idempotencyKey, to: statement, index: 3)
    try bindText(owner, to: statement, index: 4)
    try step(statement)
    return sqlite3_changes(database) == 1
  }

  func releaseLease(idempotencyKey: String, owner: String) throws -> Bool {
    let statement = try prepare(
      """
      UPDATE processing_jobs
      SET lease_owner=NULL, lease_expires_at=NULL
      WHERE idempotency_key=? AND lease_owner=?
      """
    )
    defer { sqlite3_finalize(statement) }
    try bindText(idempotencyKey, to: statement, index: 1)
    try bindText(owner, to: statement, index: 2)
    try step(statement)
    return sqlite3_changes(database) == 1
  }

  private func configure() throws {
    try execute("PRAGMA journal_mode=WAL")
    try execute("PRAGMA synchronous=NORMAL")
    try execute("PRAGMA foreign_keys=ON")
    try execute("PRAGMA busy_timeout=5000")
  }

  private func secureDatabaseFiles() {
    let mode = mode_t(S_IRUSR | S_IWUSR)
    _ = chmod(databaseURL.path, mode)
    _ = chmod(databaseURL.path + "-wal", mode)
    _ = chmod(databaseURL.path + "-shm", mode)
  }

  private func migrate() throws {
    let version = try pragmaUserVersion()
    guard version <= Self.schemaVersion else {
      throw SQLiteMetadataStoreError.migrationFailed("不支持的 schema 版本 \(version)。")
    }
    do {
      try execute(
        """
        CREATE TABLE IF NOT EXISTS metadata(
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        )
        """
      )
      var currentVersion = version
      if currentVersion == 0 {
        try execute(
          """
          CREATE TABLE IF NOT EXISTS recordings(
            id TEXT PRIMARY KEY,
            created_at REAL NOT NULL,
            audio_file_name TEXT NOT NULL,
            duration REAL NOT NULL,
            payload_json BLOB NOT NULL
          )
          """
        )
        try execute(
          """
          CREATE TABLE IF NOT EXISTS processing_jobs(
            idempotency_key TEXT PRIMARY KEY,
            recording_id TEXT NOT NULL REFERENCES recordings(id) ON DELETE CASCADE,
            kind TEXT NOT NULL,
            status TEXT NOT NULL,
            attempt INTEGER NOT NULL,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            last_error TEXT,
            lease_owner TEXT,
            lease_expires_at REAL
          )
          """
        )
        try execute(
          "CREATE INDEX IF NOT EXISTS jobs_recording_index ON processing_jobs(recording_id)")
        try execute("PRAGMA user_version=1")
        currentVersion = 1
      }
      if currentVersion == 1 {
        try execute(
          """
          CREATE TABLE IF NOT EXISTS model_download_jobs(
            id TEXT PRIMARY KEY,
            pack_id TEXT NOT NULL,
            version TEXT NOT NULL,
            state TEXT NOT NULL,
            completed_bytes INTEGER NOT NULL,
            total_bytes INTEGER NOT NULL,
            staging_path TEXT,
            last_error TEXT,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL
          )
          """
        )
        try execute(
          "CREATE INDEX IF NOT EXISTS model_download_jobs_updated_index ON model_download_jobs(updated_at DESC)"
        )
        try execute("PRAGMA user_version=2")
        currentVersion = 2
      }
      if currentVersion == 2 {
        try execute(
          """
          CREATE TABLE IF NOT EXISTS agent_dispatch_jobs(
            id TEXT PRIMARY KEY,
            idempotency_key TEXT NOT NULL UNIQUE,
            connector_id TEXT NOT NULL,
            context_package_id TEXT NOT NULL,
            status TEXT NOT NULL,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            payload_json BLOB NOT NULL
          )
          """
        )
        try execute(
          "CREATE INDEX IF NOT EXISTS agent_dispatch_jobs_updated_index ON agent_dispatch_jobs(updated_at DESC)"
        )
        try execute("PRAGMA user_version=3")
        currentVersion = 3
      }
      if currentVersion == 3 {
        try execute(
          """
          CREATE TABLE IF NOT EXISTS agent_audit_events(
            id TEXT PRIMARY KEY,
            occurred_at REAL NOT NULL,
            action TEXT NOT NULL,
            connector_id TEXT NOT NULL,
            job_id TEXT,
            payload_json BLOB NOT NULL
          )
          """
        )
        try execute(
          "CREATE INDEX IF NOT EXISTS agent_audit_events_occurred_index ON agent_audit_events(occurred_at DESC)"
        )
        try execute("PRAGMA user_version=4")
        currentVersion = 4
      }
      if currentVersion == 4 {
        try execute(
          "ALTER TABLE model_download_jobs ADD COLUMN intents_json BLOB NOT NULL DEFAULT '[]'"
        )
        try execute("PRAGMA user_version=5")
      }
    } catch {
      throw SQLiteMetadataStoreError.migrationFailed(error.localizedDescription)
    }
  }

  private func pragmaUserVersion() throws -> Int {
    let statement = try prepare("PRAGMA user_version")
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW else {
      throw SQLiteMetadataStoreError.migrationFailed(message())
    }
    return Int(sqlite3_column_int(statement, 0))
  }

  private func upsertJob(_ task: ProcessingTask, recordingID: String) throws {
    let statement = try prepare(
      """
      INSERT INTO processing_jobs(
        idempotency_key, recording_id, kind, status, attempt, created_at, updated_at, last_error
      ) VALUES(?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(idempotency_key) DO UPDATE SET
        recording_id=excluded.recording_id,
        kind=excluded.kind,
        status=excluded.status,
        attempt=excluded.attempt,
        created_at=excluded.created_at,
        updated_at=excluded.updated_at,
        last_error=excluded.last_error
      """
    )
    defer { sqlite3_finalize(statement) }
    try bindText(task.idempotencyKey, to: statement, index: 1)
    try bindText(recordingID, to: statement, index: 2)
    try bindText(task.kind.rawValue, to: statement, index: 3)
    try bindText(task.status.rawValue, to: statement, index: 4)
    try bindInt(task.attempt, to: statement, index: 5)
    try bindDouble(task.createdAt.timeIntervalSince1970, to: statement, index: 6)
    try bindDouble(task.updatedAt.timeIntervalSince1970, to: statement, index: 7)
    try bindOptionalText(task.lastError, to: statement, index: 8)
    try step(statement)
  }

  private func applyJobProjection(to records: inout [RecordingRecord]) throws {
    let statement = try prepare(
      "SELECT idempotency_key, status, attempt, updated_at, last_error FROM processing_jobs")
    defer { sqlite3_finalize(statement) }
    var jobs: [String: (ProcessingTaskStatus, Int, Date, String?)] = [:]
    while sqlite3_step(statement) == SQLITE_ROW {
      guard let key = textColumn(statement, index: 0),
        let statusValue = textColumn(statement, index: 1),
        let status = ProcessingTaskStatus(rawValue: statusValue)
      else { throw SQLiteMetadataStoreError.invalidJobState }
      let attempt = Int(sqlite3_column_int(statement, 2))
      let updated = Date(timeIntervalSince1970: sqlite3_column_double(statement, 3))
      jobs[key] = (status, attempt, updated, optionalTextColumn(statement, index: 4))
    }
    for recordIndex in records.indices {
      for taskIndex in records[recordIndex].processingTasks.indices {
        let key = records[recordIndex].processingTasks[taskIndex].idempotencyKey
        guard let job = jobs[key] else { continue }
        records[recordIndex].processingTasks[taskIndex].status = job.0
        records[recordIndex].processingTasks[taskIndex].attempt = job.1
        records[recordIndex].processingTasks[taskIndex].updatedAt = job.2
        records[recordIndex].processingTasks[taskIndex].lastError = job.3
      }
    }
  }

  private func stringColumnValues(_ sql: String, column: Int32) throws -> [String] {
    let statement = try prepare(sql)
    defer { sqlite3_finalize(statement) }
    var values: [String] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      if let value = textColumn(statement, index: column) { values.append(value) }
    }
    return values
  }

  private func executeDelete(table: String, keyColumn: String, value: String) throws {
    let statement = try prepare("DELETE FROM \(table) WHERE \(keyColumn)=?")
    defer { sqlite3_finalize(statement) }
    try bindText(value, to: statement, index: 1)
    try step(statement)
  }

  private func prepare(_ sql: String) throws -> OpaquePointer {
    var statement: OpaquePointer?
    let result = sql.withCString { sqlite3_prepare_v2(database, $0, -1, &statement, nil) }
    guard result == SQLITE_OK, let statement else {
      throw SQLiteMetadataStoreError.queryFailed(message())
    }
    return statement
  }

  private func step(_ statement: OpaquePointer) throws {
    guard sqlite3_step(statement) == SQLITE_DONE else {
      throw SQLiteMetadataStoreError.queryFailed(message())
    }
  }

  private func execute(_ sql: String) throws {
    var errorMessage: UnsafeMutablePointer<CChar>?
    let result = sql.withCString {
      sqlite3_exec(database, $0, nil, nil, &errorMessage)
    }
    defer {
      if let errorMessage { sqlite3_free(errorMessage) }
    }
    guard result == SQLITE_OK else { throw SQLiteMetadataStoreError.queryFailed(message()) }
  }

  private func bindText(_ value: String, to statement: OpaquePointer, index: Int32) throws {
    let result = value.withCString {
      sqlite3_bind_text(statement, index, $0, -1, transientDestructor)
    }
    guard result == SQLITE_OK else { throw SQLiteMetadataStoreError.queryFailed(message()) }
  }

  private func bindOptionalText(_ value: String?, to statement: OpaquePointer, index: Int32) throws
  {
    guard let value else {
      guard sqlite3_bind_null(statement, index) == SQLITE_OK else {
        throw SQLiteMetadataStoreError.queryFailed(message())
      }
      return
    }
    try bindText(value, to: statement, index: index)
  }

  private func bindDouble(_ value: Double, to statement: OpaquePointer, index: Int32) throws {
    guard sqlite3_bind_double(statement, index, value) == SQLITE_OK else {
      throw SQLiteMetadataStoreError.queryFailed(message())
    }
  }

  private func bindInt(_ value: Int, to statement: OpaquePointer, index: Int32) throws {
    guard sqlite3_bind_int(statement, index, Int32(value)) == SQLITE_OK else {
      throw SQLiteMetadataStoreError.queryFailed(message())
    }
  }

  private func bindInt64(_ value: Int64, to statement: OpaquePointer, index: Int32) throws {
    guard sqlite3_bind_int64(statement, index, value) == SQLITE_OK else {
      throw SQLiteMetadataStoreError.queryFailed(message())
    }
  }

  private func bindBlob(_ value: Data, to statement: OpaquePointer, index: Int32) throws {
    let result = value.withUnsafeBytes { rawBuffer in
      sqlite3_bind_blob(
        statement, index, rawBuffer.baseAddress, Int32(value.count), transientDestructor)
    }
    guard result == SQLITE_OK else { throw SQLiteMetadataStoreError.queryFailed(message()) }
  }

  private func textColumn(_ statement: OpaquePointer, index: Int32) -> String? {
    guard let value = sqlite3_column_text(statement, index) else { return nil }
    return String(cString: value)
  }

  private func optionalTextColumn(_ statement: OpaquePointer, index: Int32) -> String? {
    guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
    return textColumn(statement, index: index)
  }

  private func decodeModelInstallIntents(
    from statement: OpaquePointer, index: Int32
  ) throws -> [ModelInstallIntent] {
    guard sqlite3_column_type(statement, index) != SQLITE_NULL,
      let bytes = sqlite3_column_blob(statement, index)
    else { return [] }
    let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, index)))
    guard let intents = try? JSONDecoder.woice.decode([ModelInstallIntent].self, from: data) else {
      throw SQLiteMetadataStoreError.invalidPayload
    }
    return intents
  }

  private func message() -> String {
    guard let database else { return "数据库句柄不可用" }
    return String(cString: sqlite3_errmsg(database))
  }
}
