import Foundation
import SQLite3
import WoiceCore

/// Read-only SQLite handle used by the detail loader. Opening a separate
/// handle keeps a long transcript decode off the UI store's transaction and
/// makes rapid selection cancellable at the caller.
private final class SQLiteRecordingPayloadReader: @unchecked Sendable {
  private let databaseURL: URL

  init(databaseURL: URL) {
    self.databaseURL = databaseURL
  }

  func read(recordID: UUID) -> RecordingRecord? {
    var database: OpaquePointer?
    guard
      sqlite3_open_v2(
        databaseURL.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil)
        == SQLITE_OK,
      let database
    else {
      if let database { sqlite3_close(database) }
      return nil
    }
    defer { sqlite3_close(database) }
    var statement: OpaquePointer?
    guard
      sqlite3_prepare_v2(
        database,
        "SELECT payload_json FROM recordings WHERE id=?",
        -1,
        &statement,
        nil) == SQLITE_OK,
      let statement
    else { return nil }
    defer { sqlite3_finalize(statement) }
    recordID.uuidString.withCString { value in
      _ = sqlite3_bind_text(
        statement, 1, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    }
    guard sqlite3_step(statement) == SQLITE_ROW,
      let bytes = sqlite3_column_blob(statement, 0)
    else { return nil }
    let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
    guard var record = try? JSONDecoder.woice.decode(RecordingRecord.self, from: data),
      applyJobProjection(to: &record, database: database)
    else { return nil }
    return record
  }

  func readAll() -> [RecordingRecord]? {
    var database: OpaquePointer?
    guard
      sqlite3_open_v2(
        databaseURL.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil)
        == SQLITE_OK,
      let database
    else {
      if let database { sqlite3_close(database) }
      return nil
    }
    defer { sqlite3_close(database) }
    var statement: OpaquePointer?
    guard
      sqlite3_prepare_v2(
        database,
        "SELECT payload_json FROM recordings ORDER BY created_at DESC, id DESC",
        -1,
        &statement,
        nil) == SQLITE_OK,
      let statement
    else { return nil }
    defer { sqlite3_finalize(statement) }
    var records: [RecordingRecord] = []
    var result = sqlite3_step(statement)
    while result == SQLITE_ROW {
      guard let bytes = sqlite3_column_blob(statement, 0) else { return nil }
      let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
      guard let record = try? JSONDecoder.woice.decode(RecordingRecord.self, from: data)
      else { return nil }
      records.append(record)
      result = sqlite3_step(statement)
    }
    guard result == SQLITE_DONE else { return nil }
    guard applyJobProjection(to: &records, database: database) else { return nil }
    return records
  }

  private func applyJobProjection(to record: inout RecordingRecord, database: OpaquePointer)
    -> Bool
  {
    var records = [record]
    guard applyJobProjection(to: &records, database: database) else { return false }
    record = records[0]
    return true
  }

  private func applyJobProjection(to records: inout [RecordingRecord], database: OpaquePointer)
    -> Bool
  {
    var statement: OpaquePointer?
    guard
      sqlite3_prepare_v2(
        database,
        "SELECT idempotency_key, status, attempt, updated_at, last_error FROM processing_jobs",
        -1,
        &statement,
        nil) == SQLITE_OK,
      let statement
    else { return false }
    defer { sqlite3_finalize(statement) }

    var jobs: [String: (ProcessingTaskStatus, Int, Date, String?)] = [:]
    var result = sqlite3_step(statement)
    while result == SQLITE_ROW {
      guard
        let keyPointer = sqlite3_column_text(statement, 0),
        let statusPointer = sqlite3_column_text(statement, 1),
        let status = ProcessingTaskStatus(rawValue: String(cString: statusPointer))
      else { return false }
      let key = String(cString: keyPointer)
      let attempt = Int(sqlite3_column_int(statement, 2))
      let updatedAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 3))
      let lastError: String?
      if sqlite3_column_type(statement, 4) == SQLITE_NULL {
        lastError = nil
      } else if let pointer = sqlite3_column_text(statement, 4) {
        lastError = String(cString: pointer)
      } else {
        lastError = nil
      }
      jobs[key] = (status, attempt, updatedAt, lastError)
      result = sqlite3_step(statement)
    }
    guard result == SQLITE_DONE else { return false }

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
    return true
  }
}

/// Cancellable detail reads with a five-entry LRU cache. The cache is keyed by
/// ID and invalidated precisely when a material changes; it never changes the
/// immutable transcript or artifact payload.
actor RecordingDetailLoader {
  private let reader: SQLiteRecordingPayloadReader
  private var cache: [UUID: RecordingRecord] = [:]
  private var order: [UUID] = []
  private let capacity = 5

  init(databaseURL: URL) {
    reader = SQLiteRecordingPayloadReader(databaseURL: databaseURL)
  }

  func load(recordID: UUID) -> RecordingRecord? {
    let signpostID = MaterialPerformanceInstrumentation.begin(.detailRead)
    defer { MaterialPerformanceInstrumentation.end(.detailRead, signpostID: signpostID) }
    if let cached = cache[recordID] {
      touch(recordID)
      return cached
    }
    guard let record = reader.read(recordID: recordID) else { return nil }
    cache[recordID] = record
    touch(recordID)
    trim()
    return record
  }

  func loadAll() -> [RecordingRecord]? {
    reader.readAll()
  }

  func invalidate(recordID: UUID) {
    cache.removeValue(forKey: recordID)
    order.removeAll { $0 == recordID }
  }

  func invalidateAll() {
    cache.removeAll(keepingCapacity: true)
    order.removeAll(keepingCapacity: true)
  }

  var cachedRecordIDs: [UUID] { order }

  private func touch(_ id: UUID) {
    order.removeAll { $0 == id }
    order.insert(id, at: 0)
  }

  private func trim() {
    guard order.count > capacity else { return }
    for id in order.dropFirst(capacity) { cache.removeValue(forKey: id) }
    order = Array(order.prefix(capacity))
  }
}
