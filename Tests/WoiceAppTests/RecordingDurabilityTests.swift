@preconcurrency import AVFoundation
import Darwin
import Foundation
import Testing
import WoiceCore

@testable import WoiceApp

private func durabilityTestRoot(_ suffix: String = UUID().uuidString) -> URL {
  FileManager.default.temporaryDirectory.appendingPathComponent(
    "woice-recording-durability-\(suffix)", isDirectory: true)
}

@Test("录音 Manifest 只提交已校验的完整音频块")
func recordingManifestCommitsAndVerifiesChunk() throws {
  let root = durabilityTestRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let sessionID = UUID()
  let manifest = try RecordingChunkManifestStore(
    rootURL: root, sessionID: sessionID, expectedTracks: [.microphone, .systemAudio])
  let chunkURL = manifest.chunkDirectoryURL.appendingPathComponent(
    "microphone-chunk-0000.committed.m4a")
  let bytes = Data("committed audio fixture".utf8)
  try bytes.write(to: chunkURL)
  let digest = try FileSHA256.digest(url: chunkURL)
  try manifest.commit(
    RecordingChunkCommit(
      sessionID: sessionID,
      index: 0,
      track: .microphone,
      url: chunkURL,
      startOffset: 0,
      duration: 10,
      sha256: digest))

  let snapshot = manifest.snapshot()
  #expect(snapshot.isValid)
  #expect(snapshot.expectedTracks == [.microphone, .systemAudio])
  #expect(snapshot.chunks(for: .microphone).count == 1)
  #expect(try manifest.verifiedChunks().count == 1)

  try Data("tampered".utf8).write(to: chunkURL)
  #expect(throws: (any Error).self) { try manifest.verifiedChunks() }
  let quarantine = manifest.chunkDirectoryURL.appendingPathComponent("quarantine")
  #expect(FileManager.default.fileExists(atPath: quarantine.path))
}

@Test("录音 Manifest 原子文件可在新实例中恢复")
func recordingManifestCanRecoverFromDisk() throws {
  let root = durabilityTestRoot("recover")
  defer { try? FileManager.default.removeItem(at: root) }
  let sessionID = UUID()
  let created = Date(timeIntervalSince1970: 1_700_000_000)
  let manifest = try RecordingChunkManifestStore(
    rootURL: root, sessionID: sessionID, expectedTracks: [.microphone], createdAt: created)
  let chunkURL = manifest.chunkDirectoryURL.appendingPathComponent(
    "microphone-chunk-0000.committed.m4a")
  let bytes = Data(repeating: 7, count: 128)
  try bytes.write(to: chunkURL)
  try manifest.commit(
    RecordingChunkCommit(
      sessionID: sessionID,
      index: 0,
      track: .microphone,
      url: chunkURL,
      startOffset: 0,
      duration: 2.5,
      sha256: try FileSHA256.digest(url: chunkURL)))

  let recovered = try RecordingChunkManifestStore(recovering: manifest.manifestURL)
  #expect(recovered.sessionID == sessionID)
  #expect(recovered.snapshot().createdAt == created)
  #expect(recovered.snapshot().committedChunks == manifest.snapshot().committedChunks)
}

@Test("Manifest 写入失败时不发布内存清单并保留已提交块")
func recordingManifestCommitFailureDoesNotPublishInMemory() throws {
  let root = durabilityTestRoot("manifest-failure")
  defer { try? FileManager.default.removeItem(at: root) }
  let fileManager = FileManager.default
  let sessionID = UUID()
  let manifest = try RecordingChunkManifestStore(
    rootURL: root, sessionID: sessionID, expectedTracks: [.microphone], fileManager: fileManager)
  let firstURL = manifest.chunkDirectoryURL.appendingPathComponent(
    "microphone-chunk-0000.committed.m4a")
  try Data(repeating: 1, count: 128).write(to: firstURL)
  try manifest.commit(
    RecordingChunkCommit(
      sessionID: sessionID, index: 0, track: .microphone, url: firstURL,
      startOffset: 0, duration: 1, sha256: try FileSHA256.digest(url: firstURL)))
  let durableManifest = try Data(contentsOf: manifest.manifestURL)

  // The chunk rename has already completed, so a failed Manifest write must
  // not expose the second descriptor in memory or discard the committed file.
  chmod(root.path, mode_t(S_IRUSR | S_IXUSR))
  defer { chmod(root.path, mode_t(S_IRUSR | S_IWUSR | S_IXUSR)) }
  let secondURL = manifest.chunkDirectoryURL.appendingPathComponent(
    "microphone-chunk-0001.committed.m4a")
  try Data(repeating: 2, count: 128).write(to: secondURL)
  #expect(throws: (any Error).self) {
    try manifest.commit(
      RecordingChunkCommit(
        sessionID: sessionID, index: 1, track: .microphone, url: secondURL,
        startOffset: 1, duration: 1, sha256: try FileSHA256.digest(url: secondURL)))
  }
  #expect(manifest.snapshot().committedChunks.map(\.index) == [0])
  #expect(fileManager.fileExists(atPath: secondURL.path))

  // Restore the old durable bytes to prove a fresh recovery sees the same
  // one-chunk snapshot rather than the failed in-memory candidate.
  chmod(root.path, mode_t(S_IRUSR | S_IWUSR | S_IXUSR))
  try durableManifest.write(to: manifest.manifestURL, options: .atomic)
  let recovered = try RecordingChunkManifestStore(recovering: manifest.manifestURL)
  #expect(recovered.snapshot().committedChunks.map(\.index) == [0])
}

@Test("录音块提交队列在回调线程之外完成清单写入")
func recordingChunkCommitterFlushesDurably() throws {
  let root = durabilityTestRoot("committer")
  defer { try? FileManager.default.removeItem(at: root) }
  let sessionID = UUID()
  let manifest = try RecordingChunkManifestStore(
    rootURL: root, sessionID: sessionID, expectedTracks: [.microphone])
  let chunkURL = manifest.chunkDirectoryURL.appendingPathComponent(
    "microphone-chunk-0000.committed.m4a")
  try Data(repeating: 3, count: 256).write(to: chunkURL)
  let committer = RecordingChunkCommitter(manifest: manifest)
  committer.submit(
    RecordingChunkCommit(
      sessionID: sessionID,
      index: 0,
      track: .microphone,
      url: chunkURL,
      startOffset: 0,
      duration: 1,
      sha256: try FileSHA256.digest(url: chunkURL)))
  committer.flush()
  #expect(committer.lastError == nil)
  #expect(manifest.snapshot().committedChunks.count == 1)
}

@Test("录音进程 SIGKILL 后恢复已提交块并保持 SHA")
func recordingProcessSIGKILLRecoversCommittedChunks() throws {
  let environment = ProcessInfo.processInfo.environment
  if environment["WOICE_RECORDING_SIGKILL_CHILD"] == "1" {
    try writeSIGKILLChildFixture(
      root: URL(fileURLWithPath: try #require(environment["WOICE_RECORDING_SIGKILL_ROOT"])))
    return
  }

  let root = durabilityTestRoot("sigkill-process")
  defer { try? FileManager.default.removeItem(at: root) }
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  let readyURL = root.appendingPathComponent("child.ready")
  guard
    let testBinaryArgument = CommandLine.arguments.first(where: {
      $0.contains(".xctest/Contents/MacOS/")
    })
  else {
    Issue.record("找不到当前 Swift 测试 bundle 可执行文件")
    return
  }
  let testBinaryURL = URL(fileURLWithPath: testBinaryArgument).standardizedFileURL
  guard FileManager.default.fileExists(atPath: testBinaryURL.path)
  else {
    Issue.record(
      "当前 Swift 测试 bundle 路径无效：\(testBinaryURL.path)"
    )
    return
  }
  let developerDirectory =
    ProcessInfo.processInfo.environment["DEVELOPER_DIR"]
    ?? "/Applications/Xcode.app/Contents/Developer"
  let testingHelperURL = URL(fileURLWithPath: developerDirectory).appendingPathComponent(
    "Toolchains/XcodeDefault.xctoolchain/usr/libexec/swift/pm/swiftpm-testing-helper")
  guard FileManager.default.isExecutableFile(atPath: testingHelperURL.path) else {
    Issue.record("找不到 Swift Testing helper：\(testingHelperURL.path)")
    return
  }
  let child = Process()
  child.executableURL = testingHelperURL
  child.arguments = [
    "--test-bundle-path", testBinaryURL.path,
    "--no-parallel",
    "--filter", "recordingProcessSIGKILLRecoversCommittedChunks",
    testBinaryURL.path,
    "--testing-library", "swift-testing",
  ]
  var childEnvironment = environment
  childEnvironment["WOICE_RECORDING_SIGKILL_CHILD"] = "1"
  childEnvironment["WOICE_RECORDING_SIGKILL_ROOT"] = root.path
  child.environment = childEnvironment
  try child.run()
  defer {
    if child.isRunning {
      kill(child.processIdentifier, SIGKILL)
      child.waitUntilExit()
    }
  }

  let deadline = Date().addingTimeInterval(20)
  while !FileManager.default.fileExists(atPath: readyURL.path) && Date() < deadline {
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
  }
  #expect(FileManager.default.fileExists(atPath: readyURL.path))
  guard FileManager.default.fileExists(atPath: readyURL.path) else {
    kill(child.processIdentifier, SIGKILL)
    child.waitUntilExit()
    return
  }

  kill(child.processIdentifier, SIGKILL)
  child.waitUntilExit()
  #expect(child.terminationReason == .uncaughtSignal)

  let manifestURLs = try FileManager.default.contentsOfDirectory(
    at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
  ).filter { $0.pathExtension == "json" && $0.lastPathComponent.hasSuffix(".manifest.json") }
  let manifestURL = try #require(manifestURLs.first)
  let recovered = try RecordingChunkManifestStore(recovering: manifestURL)
  recovered.reconcileOrphanedChunks()
  let chunks = try recovered.verifiedChunks()
  #expect(chunks.count == 1)
  #expect(chunks.first?.track == .microphone)
  #expect(chunks.first?.index == 0)
  #expect(chunks.first?.duration ?? 0 > 0.9)
}

private func writeSIGKILLChildFixture(root: URL) throws {
  let sessionID = UUID()
  let manifest = try RecordingChunkManifestStore(
    rootURL: root, sessionID: sessionID, expectedTracks: [.microphone])
  let format = try #require(
    AVAudioFormat(
      commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false))
  let writer = try RollingPCMChunkWriter(
    sessionID: sessionID, track: .microphone, directoryURL: manifest.chunkDirectoryURL,
    format: format, chunkDuration: 1)
  let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 19_200))
  buffer.frameLength = 19_200
  buffer.floatChannelData?[0].initialize(repeating: 0.02, count: 19_200)
  var commits: [RecordingChunkCommit] = []
  for _ in 0..<3 { commits.append(contentsOf: try writer.append(buffer)) }
  for commit in commits { try manifest.commit(commit) }
  guard commits.count == 1 else {
    throw RecordingDurabilityError.rebuildFailed(
      "SIGKILL fixture did not produce one committed block")
  }
  let partialURL = manifest.chunkDirectoryURL.appendingPathComponent(
    "microphone-chunk-0001.partial.m4a")
  try Data(repeating: 0x5A, count: 128).write(to: partialURL, options: .atomic)
  try Data("ready\n".utf8).write(
    to: root.appendingPathComponent("child.ready"), options: .atomic)
  while true { Thread.sleep(forTimeInterval: 1) }
}

@Test("未提交 partial 录音块会进入可恢复隔离区")
func recordingManifestQuarantinesPartialChunk() throws {
  let root = durabilityTestRoot("partial")
  defer { try? FileManager.default.removeItem(at: root) }
  let manifest = try RecordingChunkManifestStore(
    rootURL: root, sessionID: UUID(), expectedTracks: [.microphone])
  let partialURL = manifest.chunkDirectoryURL.appendingPathComponent(
    "microphone-chunk-0000.partial.m4a")
  try Data("unfinished".utf8).write(to: partialURL)
  manifest.reconcileOrphanedChunks()
  #expect(!FileManager.default.fileExists(atPath: partialURL.path))
  #expect(
    FileManager.default.fileExists(
      atPath: manifest.chunkDirectoryURL.appendingPathComponent("quarantine").path))
}

@Test("录音 Manifest 会收编重命名后尚未写入清单的完整块")
func recordingManifestReconcilesCommittedOrphan() throws {
  let root = durabilityTestRoot("orphan")
  defer { try? FileManager.default.removeItem(at: root) }
  let sessionID = UUID()
  let manifest = try RecordingChunkManifestStore(
    rootURL: root, sessionID: sessionID, expectedTracks: [.microphone])
  let format = try #require(
    AVAudioFormat(
      commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false))
  let writer = try RollingPCMChunkWriter(
    sessionID: sessionID, track: .microphone, directoryURL: manifest.chunkDirectoryURL,
    format: format, chunkDuration: 1)
  let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48_000))
  buffer.frameLength = 48_000
  buffer.floatChannelData?[0].initialize(repeating: 0.01, count: 48_000)
  #expect(try writer.append(buffer).count == 1)

  #expect(manifest.snapshot().committedChunks.isEmpty)
  manifest.reconcileOrphanedChunks()
  #expect(manifest.snapshot().committedChunks.count == 1)
  #expect(try manifest.verifiedChunks().count == 1)
}

@Test("录音块重建只读取已校验块并生成新的规范化文件")
func recordingChunkRebuilderPreservesSources() throws {
  let root = durabilityTestRoot("rebuild")
  defer { try? FileManager.default.removeItem(at: root) }
  let sessionID = UUID()
  let manifest = try RecordingChunkManifestStore(
    rootURL: root, sessionID: sessionID, expectedTracks: [.microphone])
  let format = try #require(
    AVAudioFormat(
      commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false))
  let writer = try RollingPCMChunkWriter(
    sessionID: sessionID, track: .microphone, directoryURL: manifest.chunkDirectoryURL,
    format: format, chunkDuration: 1)
  let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48_000))
  buffer.frameLength = 48_000
  buffer.floatChannelData?[0].initialize(repeating: 0.02, count: 48_000)
  let commits = try writer.append(buffer)
  for commit in commits { try manifest.commit(commit) }
  let sourceDigest = try FileSHA256.digest(url: commits[0].url)
  let outputURL = root.appendingPathComponent("rebuilt.m4a")
  let duration = try RecordingChunkRebuilder.rebuild(
    chunks: try manifest.verifiedChunks(), directoryURL: manifest.chunkDirectoryURL,
    outputURL: outputURL)

  #expect(duration > 0.9)
  #expect(FileManager.default.fileExists(atPath: outputURL.path))
  #expect(try FileSHA256.digest(url: commits[0].url) == sourceDigest)
  #expect((try AVAudioFile(forReading: outputURL)).length > 0)
}

@Test("录音 Manifest 拒绝不在清单目录内的提交路径")
func recordingManifestRejectsOutsideChunkPath() throws {
  let root = durabilityTestRoot("outside")
  defer { try? FileManager.default.removeItem(at: root) }
  let sessionID = UUID()
  let manifest = try RecordingChunkManifestStore(
    rootURL: root, sessionID: sessionID, expectedTracks: [.microphone])
  let outsideURL = root.appendingPathComponent("microphone-chunk-0000.committed.m4a")
  try Data(repeating: 1, count: 128).write(to: outsideURL)
  #expect(throws: (any Error).self) {
    try manifest.commit(
      RecordingChunkCommit(
        sessionID: sessionID, index: 0, track: .microphone, url: outsideURL,
        startOffset: 0, duration: 1, sha256: nil))
  }
}

@Test("损坏的录音 Manifest fail-closed 且不猜测恢复内容")
func recordingManifestRejectsCorruptedJSON() throws {
  let root = durabilityTestRoot("corrupt")
  defer { try? FileManager.default.removeItem(at: root) }
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  let manifestURL = root.appendingPathComponent("\(UUID().uuidString).manifest.json")
  try Data("{not-json".utf8).write(to: manifestURL)
  #expect(throws: RecordingDurabilityError.invalidManifest) {
    try RecordingChunkManifestStore(recovering: manifestURL)
  }
}

@Test("滚动录音块按时长关闭并生成可读取的提交文件")
func rollingChunkWriterClosesAndHashesBlocks() throws {
  let root = durabilityTestRoot("rolling")
  defer { try? FileManager.default.removeItem(at: root) }
  let sessionID = UUID()
  let format = try #require(
    AVAudioFormat(
      commonFormat: .pcmFormatFloat32,
      sampleRate: 48_000,
      channels: 1,
      interleaved: false))
  let manifest = try RecordingChunkManifestStore(
    rootURL: root, sessionID: sessionID, expectedTracks: [.microphone])
  let writer = try RollingPCMChunkWriter(
    sessionID: sessionID,
    track: .microphone,
    directoryURL: manifest.chunkDirectoryURL,
    format: format,
    chunkDuration: 1)
  let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 19_200))
  buffer.frameLength = 19_200
  buffer.floatChannelData?[0].initialize(repeating: 0.02, count: 19_200)

  let first = try writer.append(buffer)
  #expect(first.isEmpty)
  let second = try writer.append(buffer)
  #expect(second.isEmpty)
  let third = try writer.append(buffer)
  #expect(third.count == 1)
  #expect(try writer.append(buffer).isEmpty)
  let tail = try writer.finish()
  #expect(tail.count == 1)
  let commits = third + tail
  #expect(commits.map(\.index) == [0, 1])
  for commit in commits {
    #expect(commit.url.lastPathComponent.hasSuffix(".committed.m4a"))
    #expect(FileManager.default.fileExists(atPath: commit.url.path))
    let file = try AVAudioFile(forReading: commit.url)
    #expect(file.length > 0)
    #expect(commit.sha256 == nil)
    try manifest.commit(commit)
    #expect(
      try FileSHA256.digest(url: commit.url)
        == manifest.snapshot().chunks(for: .microphone).first(where: { $0.index == commit.index })?
        .sha256)
  }
  let partialFiles = try FileManager.default.contentsOfDirectory(
    at: manifest.chunkDirectoryURL,
    includingPropertiesForKeys: nil
  )
  .filter { $0.pathExtension == "m4a" && $0.lastPathComponent.contains("partial") }
  #expect(partialFiles.isEmpty)
  #expect(try manifest.verifiedChunks().count == 2)
}

@Test("详情 Loader 的 LRU 缓存最多保留五条素材")
@MainActor
func recordingDetailLoaderUsesBoundedCache() async throws {
  let root = durabilityTestRoot("loader")
  defer { try? FileManager.default.removeItem(at: root) }
  let database = try SQLiteMetadataStore(databaseURL: root.appendingPathComponent("woice.sqlite3"))
  let records = (0..<6).map { index in
    RecordingRecord(
      id: UUID(),
      createdAt: Date(timeIntervalSince1970: Double(index)),
      audioFileName: "\(index).m4a",
      duration: 1,
      transcript: String(repeating: "详情 \(index) ", count: 10),
      generatedMarkdown: nil,
      processingError: nil)
  }
  try database.saveRecordings(records)
  let loader = RecordingDetailLoader(databaseURL: database.databaseURL)
  for record in records { #expect(await loader.load(recordID: record.id) != nil) }
  #expect(await loader.cachedRecordIDs.count == 5)
  #expect(await loader.load(recordID: records[0].id) != nil)
  #expect(await loader.cachedRecordIDs.first == records[0].id)
}

@Test("详情 Loader 合并 SQLite 中最新 Job 状态而非旧 payload 快照")
@MainActor
func recordingDetailLoaderProjectsDurableJobStatus() async throws {
  let root = durabilityTestRoot("loader-job")
  defer { try? FileManager.default.removeItem(at: root) }
  let database = try SQLiteMetadataStore(databaseURL: root.appendingPathComponent("woice.sqlite3"))
  let task = ProcessingTask(
    kind: .transcription, idempotencyKey: "loader-job-key", status: .queued,
    attempt: 1, updatedAt: Date(timeIntervalSince1970: 10))
  let record = RecordingRecord(
    id: UUID(), createdAt: Date(), audioFileName: "job.m4a", duration: 1,
    transcript: nil, generatedMarkdown: nil, processingError: nil,
    processingTasks: [task])
  try database.saveRecordings([record])
  #expect(try database.acquireLease(idempotencyKey: task.idempotencyKey, owner: "loader-test"))

  let loader = RecordingDetailLoader(databaseURL: database.databaseURL)
  let loaded = await loader.load(recordID: record.id)
  #expect(loaded?.processingTasks.first?.status == .running)
  #expect(loaded?.processingTasks.first?.attempt == 1)
}

@Test("素材性能预算的百分位计算可重复")
func materialPerformancePercentileIsDeterministic() {
  let samples: [TimeInterval] = [0.01, 0.02, 0.04, 0.1, 0.2]
  #expect(MaterialPerformanceBudget.percentile(samples, percentile: 0) == 0.01)
  #expect(MaterialPerformanceBudget.percentile(samples, percentile: 1) == 0.2)
  #expect(MaterialPerformanceBudget.percentile(samples, percentile: 0.5) == 0.04)
  #expect(MaterialPerformanceBudget.percentile([], percentile: 0.5) == nil)
}

@Test("音频元数据缓存按文件签名复用并在新文件出现时刷新")
@MainActor
func audioMetadataCacheRefreshesWhenFileChanges() async throws {
  let root = durabilityTestRoot("audio-metadata")
  defer { try? FileManager.default.removeItem(at: root) }
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  let url = root.appendingPathComponent("material.wav")
  let cache = AudioMetadataCache()

  let missing = await cache.read(url: url)
  #expect(!missing.exists)
  let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
  let file = try AVAudioFile(forWriting: url, settings: format.settings)
  let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000))
  buffer.frameLength = 16_000
  try file.write(from: buffer)
  if #available(macOS 15.0, *) { file.close() }

  let loaded = await cache.read(url: url)
  #expect(loaded.exists)
  #expect(loaded.byteCount ?? 0 > 0)
  #expect((loaded.duration ?? 0) > 0.9)
  #expect(await cache.cachedURLCount == 1)
}
