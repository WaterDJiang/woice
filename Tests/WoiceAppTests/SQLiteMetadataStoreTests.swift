import Foundation
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

@Test("SQLite 持久化模型下载任务并在重启后暂停")
@MainActor
func sqliteModelDownloadTaskSurvivesRestartAsPaused() throws {
  let root = sqliteTestRoot("model-download")
  defer { try? FileManager.default.removeItem(at: root) }
  let database = try SQLiteMetadataStore(databaseURL: root.appendingPathComponent("woice.sqlite3"))
  let created = Date(timeIntervalSince1970: 1_700_000_000)
  let task = try ModelDownloadTask(
    packID: "com.woice.fixture.model",
    version: "1.0.0",
    state: .downloading,
    completedBytes: 12,
    totalBytes: 100,
    stagingPath: "/tmp/woice.partial",
    createdAt: created,
    updatedAt: created)
  try database.saveModelDownloadTask(task)
  #expect(try database.loadModelDownloadTasks().first?.state == .downloading)

  #expect(try database.recoverModelDownloadTasks(now: created.addingTimeInterval(20)) == 1)
  let recovered = try #require(database.loadModelDownloadTasks().first)
  #expect(recovered.id == task.id)
  #expect(recovered.state == .paused)
  #expect(recovered.completedBytes == 12)
  #expect(recovered.lastError?.contains("点击继续") == true)
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
