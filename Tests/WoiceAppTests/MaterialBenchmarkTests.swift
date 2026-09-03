import Foundation
import Testing
import WoiceCore

@testable import WoiceApp

private struct MaterialBenchmarkFixtureSummary: Decodable, Sendable {
  let id: UUID
  let createdAt: Date
  let audioFileName: String
  let duration: TimeInterval
  let displayTitle: String
  let sourceKind: RecordingSourceKind
  let hasSystemAudio: Bool
  let materialStatus: RecordingMaterialStatus
}

private struct MaterialBenchmarkSample: Codable, Sendable {
  let operation: String
  let p50Milliseconds: Double
  let p95Milliseconds: Double
  let itemCount: Int
  let budgetMilliseconds: Double
}

private struct MaterialBenchmarkReport: Codable, Sendable {
  let generatedAt: Date
  let fixtureDirectory: String
  let samples: [MaterialBenchmarkSample]
  let notes: [String]
}

@Test("素材列表/详情/音频元数据基准只在显式环境生成报告")
@MainActor
func materialBenchmarkProducesReport() async throws {
  let environment = ProcessInfo.processInfo.environment
  guard environment["WOICE_RUN_MATERIAL_BENCHMARK"] == "1" else { return }
  guard let fixturePath = environment["WOICE_MATERIAL_BENCHMARK_DIR"], !fixturePath.isEmpty else {
    Issue.record("WOICE_RUN_MATERIAL_BENCHMARK=1 时必须提供 WOICE_MATERIAL_BENCHMARK_DIR")
    return
  }
  let fixtureDirectory = URL(fileURLWithPath: fixturePath, isDirectory: true)
  let summaryURL = fixtureDirectory.appendingPathComponent("summaries-500.json")
  guard let summaryData = try? Data(contentsOf: summaryURL) else {
    Issue.record("素材基准缺少 summaries-500.json")
    return
  }
  let decoder = JSONDecoder()
  decoder.dateDecodingStrategy = .iso8601
  let summaries = try decoder.decode([MaterialBenchmarkFixtureSummary].self, from: summaryData)
  guard !summaries.isEmpty else {
    Issue.record("素材基准摘要为空")
    return
  }

  let root = fixtureDirectory.appendingPathComponent("runtime", isDirectory: true)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  let database = try SQLiteMetadataStore(databaseURL: root.appendingPathComponent("woice.sqlite3"))
  let records = summaries.map { summary in
    RecordingRecord(
      id: summary.id,
      createdAt: summary.createdAt,
      audioFileName: summary.audioFileName,
      duration: summary.duration,
      transcript: nil,
      generatedMarkdown: nil,
      processingError: nil,
      systemAudioFileName: summary.hasSystemAudio ? "\(summary.id.uuidString).system.m4a" : nil,
      sourceKind: summary.sourceKind,
      userTitle: summary.displayTitle)
  }
  try database.saveRecordings(records)

  let detailID = try #require(records.first?.id)
  let longAudioURL = fixtureDirectory.appendingPathComponent("long-audio.m4a")
  let metadataProbe = await AudioMetadataCache().read(url: longAudioURL)
  #expect(metadataProbe.exists)
  let loadedSummaries = try database.loadRecordingSummaries()
  let listSamples = await measureSamples(20) {
    _ = try? database.loadRecordingSummaries()
  }
  let detailSamples = await measureSamples(20) {
    let detailLoader = RecordingDetailLoader(databaseURL: database.databaseURL)
    _ = await detailLoader.load(recordID: detailID)
  }
  let metadataSamples = await measureSamples(10) {
    let metadataCache = AudioMetadataCache()
    _ = await metadataCache.read(url: longAudioURL)
  }

  let segmentRoot = fixtureDirectory.appendingPathComponent("segments-runtime", isDirectory: true)
  try FileManager.default.createDirectory(at: segmentRoot, withIntermediateDirectories: true)
  let segmentDatabase = try SQLiteMetadataStore(
    databaseURL: segmentRoot.appendingPathComponent("woice.sqlite3"))
  let segmentRecord = RecordingRecord(
    id: UUID(), createdAt: Date(), audioFileName: "10k-segments.m4a", duration: 600,
    transcript: String(repeating: "长素材 ", count: 100), generatedMarkdown: nil,
    processingError: nil,
    transcriptSegments: (0..<10_000).map { index in
      let start = Double(index) * 0.06
      return TranscriptSegment(start: start, end: start + 0.05, text: "片段 \(index)")
    })
  try segmentDatabase.saveRecordings([segmentRecord])
  let segmentSamples = await measureSamples(10) {
    let detailLoader = RecordingDetailLoader(databaseURL: segmentDatabase.databaseURL)
    _ = await detailLoader.load(recordID: segmentRecord.id)
  }

  func sample(
    _ operation: String, values: [Double], itemCount: Int, budgetMilliseconds: Double
  ) -> MaterialBenchmarkSample {
    MaterialBenchmarkSample(
      operation: operation,
      p50Milliseconds: MaterialPerformanceBudget.percentile(values, percentile: 0.5) ?? .infinity,
      p95Milliseconds: MaterialPerformanceBudget.percentile(values, percentile: 0.95) ?? .infinity,
      itemCount: itemCount,
      budgetMilliseconds: budgetMilliseconds)
  }

  let report = MaterialBenchmarkReport(
    generatedAt: Date(),
    fixtureDirectory: fixtureDirectory.path,
    samples: [
      sample(
        "summary-load", values: listSamples, itemCount: loadedSummaries.count,
        budgetMilliseconds: 500),
      sample("detail-load", values: detailSamples, itemCount: 1, budgetMilliseconds: 400),
      sample("long-audio-metadata", values: metadataSamples, itemCount: 1, budgetMilliseconds: 400),
      sample(
        "detail-load-10000-segments", values: segmentSamples, itemCount: 10_000,
        budgetMilliseconds: 400),
    ],
    notes: [
      "基准只使用合成音频和确定性摘要，不包含用户原文。",
      "每次 detail-load 和音频元数据读取都重新创建冷缓存；详情缓存命中由 RecordingDurabilityTests 覆盖。",
      "10,000 个时间戳片段只测量详情 payload 冷读；SwiftUI 滚动渲染仍需真实 Mac signpost/主线程门禁。",
    ])
  let outputURL = URL(
    fileURLWithPath: environment["WOICE_MATERIAL_BENCHMARK_OUTPUT"]
      ?? "build/material-benchmark.json")
  try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
  let encoder = JSONEncoder()
  encoder.dateEncodingStrategy = .iso8601
  encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
  try encoder.encode(report).write(to: outputURL, options: .atomic)

  if environment["WOICE_ENFORCE_MATERIAL_BENCHMARK"] == "1" {
    #expect(loadedSummaries.count == summaries.count)
    #expect(report.samples.allSatisfy { $0.p95Milliseconds <= $0.budgetMilliseconds })
  }
}

@MainActor
private func measureSamples(
  _ count: Int, operation: @escaping () async -> Void
) async -> [Double] {
  guard count > 0 else { return [] }
  var values: [Double] = []
  values.reserveCapacity(count)
  for _ in 0..<count {
    let start = ContinuousClock.now
    await operation()
    values.append(elapsedMilliseconds(start.duration(to: .now)))
  }
  return values
}

private func elapsedMilliseconds(_ duration: Duration) -> Double {
  Double(duration.components.seconds) * 1_000
    + Double(duration.components.attoseconds) / 1_000_000_000_000_000
}
