@preconcurrency import AVFoundation
import Darwin
import Foundation
import Testing
import WoiceCore

@testable import WoiceApp

private struct ModelBenchmarkSample: Codable, Sendable {
  let providerID: String
  let modelID: String
  let modelVersion: String
  let audioName: String
  let category: String
  let audioDuration: TimeInterval
  let elapsed: TimeInterval
  let realTimeFactor: Double?
  let peakResidentBytes: Int64
  let outputIsEmpty: Bool
  let wordErrorRate: Double?
  let error: String?
  let expectedEmptySignal: Bool
  let errorCode: String?
}

private struct ModelBenchmarkReport: Codable, Sendable {
  let generatedAt: Date
  let machine: String
  let samples: [ModelBenchmarkSample]
  let requiredCategories: [String]
  let missingCategories: [String]
  let minimumAudioDuration: TimeInterval
  let includeQwen: Bool
  let maxRealTimeFactor: Double?
  let maxPeakResidentBytes: Int64
  let thresholds: Thresholds

  struct Thresholds: Codable, Sendable {
    let maxRealTimeFactor: Double
    let maxPeakResidentBytes: Int64
  }
}

private actor PeakMemorySampler {
  private var peak: Int64 = 0

  func sample() {
    peak = max(peak, residentMemoryBytes())
  }

  func value() -> Int64 { peak }
}

@Test("模型性能基准按显式环境生成报告，不默认下载或运行模型")
@MainActor
func modelBenchmarkProducesReport() async throws {
  guard ProcessInfo.processInfo.environment["WOICE_RUN_MODEL_BENCHMARK"] == "1" else {
    return
  }
  let environment = ProcessInfo.processInfo.environment
  let benchmarkLanguage = environment["WOICE_BENCHMARK_LANGUAGE"] ?? ""
  guard let audioDirectoryPath = environment["WOICE_BENCHMARK_AUDIO_DIR"],
    !audioDirectoryPath.isEmpty
  else {
    Issue.record("WOICE_RUN_MODEL_BENCHMARK=1 时必须提供 WOICE_BENCHMARK_AUDIO_DIR")
    return
  }
  let audioDirectory = URL(fileURLWithPath: audioDirectoryPath, isDirectory: true)
  let audioURLs = try FileManager.default.contentsOfDirectory(
    at: audioDirectory, includingPropertiesForKeys: [.isRegularFileKey],
    options: [.skipsHiddenFiles]
  ).filter { ["wav", "aiff", "caf", "m4a"].contains($0.pathExtension.lowercased()) }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }
  guard !audioURLs.isEmpty else {
    Issue.record("基准音频目录没有 WAV/AIFF/CAF/M4A 文件")
    return
  }
  let enforcing = environment["WOICE_ENFORCE_MODEL_BENCHMARK"] == "1"
  let includeQwen = environment["WOICE_BENCHMARK_INCLUDE_QWEN"] == "1"
  let requiredCategories = enforcing ? ["zh", "en", "mixed", "silence", "noise"] : []
  let minimumAudioDuration: TimeInterval = {
    guard enforcing else { return 0 }
    guard let raw = environment["WOICE_BENCHMARK_MIN_DURATION_SECONDS"],
      let value = TimeInterval(raw), value > 0
    else { return 300 }
    return value
  }()
  if enforcing {
    let categories = Set(audioURLs.map(benchmarkCategory(for:)))
    let missing = requiredCategories.filter { !categories.contains($0) }
    if !missing.isEmpty {
      Issue.record("完整模型基准缺少样本类别：\(missing.joined(separator: ", "))")
      return
    }
    let shortSamples = audioURLs.compactMap { url -> String? in
      guard let duration = try? audioDuration(of: url), duration < minimumAudioDuration else {
        return nil
      }
      return "\(url.lastPathComponent) (\(String(format: "%.1f", duration))s)"
    }
    if !shortSamples.isEmpty {
      Issue.record(
        "完整模型基准存在过短样本（要求至少 \(String(format: "%.0f", minimumAudioDuration))s）：\(shortSamples.joined(separator: ", "))"
      )
      return
    }
  }

  let root: URL = {
    if let rawRoot = environment["WOICE_BENCHMARK_MODEL_ROOT"], !rawRoot.isEmpty {
      return URL(fileURLWithPath: rawRoot, isDirectory: true).standardizedFileURL
    }
    return WorkspaceStore().rootURL
  }()
  let store = ModelPackStore(rootURL: root)
  let inventory = try await store.inventory()
  let requestedIDs = Set(
    (environment["WOICE_BENCHMARK_MODEL_PACK_IDS"] ?? "")
      .split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty })
  let allowedProviderIDs: Set<String> =
    includeQwen
    ? ["com.woice.whisperkit", "com.woice.qwen3-asr"]
    : ["com.woice.whisperkit"]
  let manifests =
    inventory
    .filter { allowedProviderIDs.contains($0.manifest.providerID) }
    .filter { requestedIDs.isEmpty || requestedIDs.contains($0.manifest.packID) }
    .map(\.manifest)
  guard !manifests.isEmpty else {
    Issue.record("没有符合条件的已安装本机模型；不会伪造基准结果")
    return
  }

  var samples: [ModelBenchmarkSample] = []
  for manifest in manifests {
    let modelFolder = try await store.installedDirectory(for: manifest)
    let provider = try ModelRuntimeRegistry.makeProvider(
      manifest: manifest, modelFolder: modelFolder)
    for audioURL in audioURLs {
      let duration = try audioDuration(of: audioURL)
      let category = benchmarkCategory(for: audioURL)
      let sampler = PeakMemorySampler()
      await sampler.sample()
      let monitor = Task {
        while !Task.isCancelled {
          await sampler.sample()
          try? await Task.sleep(for: .milliseconds(100))
        }
      }
      let started = ContinuousClock.now
      do {
        let result = try await provider.transcribe(
          audioURL: audioURL, language: benchmarkLanguage)
        let elapsed = started.duration(to: .now).timeInterval
        monitor.cancel()
        await sampler.sample()
        let peak = await sampler.value()
        let reference = referenceText(for: audioURL)
        samples.append(
          ModelBenchmarkSample(
            providerID: manifest.providerID,
            modelID: manifest.modelID,
            modelVersion: manifest.version,
            audioName: audioURL.lastPathComponent,
            category: category,
            audioDuration: duration,
            elapsed: elapsed,
            realTimeFactor: duration > 0 ? elapsed / duration : nil,
            peakResidentBytes: peak,
            outputIsEmpty: result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            wordErrorRate: reference.map { wordErrorRate(reference: $0, hypothesis: result.text) },
            error: nil,
            expectedEmptySignal: isExpectedEmptySignalCategory(category),
            errorCode: nil))
      } catch {
        monitor.cancel()
        await sampler.sample()
        let peak = await sampler.value()
        samples.append(
          ModelBenchmarkSample(
            providerID: manifest.providerID,
            modelID: manifest.modelID,
            modelVersion: manifest.version,
            audioName: audioURL.lastPathComponent,
            category: category,
            audioDuration: duration,
            elapsed: started.duration(to: .now).timeInterval,
            realTimeFactor: nil,
            peakResidentBytes: peak,
            outputIsEmpty: true,
            wordErrorRate: nil,
            error: error.localizedDescription,
            expectedEmptySignal: isExpectedEmptySignalCategory(category),
            errorCode: benchmarkErrorCode(error)))
      }
    }
  }

  let report = ModelBenchmarkReport(
    generatedAt: Date(),
    machine:
      "macOS \(ProcessInfo.processInfo.operatingSystemVersionString) / \(ProcessInfo.processInfo.processorCount) cores",
    samples: samples,
    requiredCategories: requiredCategories,
    missingCategories: requiredCategories.filter {
      !Set(samples.map(\.category)).contains($0)
    },
    minimumAudioDuration: minimumAudioDuration,
    includeQwen: includeQwen,
    maxRealTimeFactor: samples.compactMap(\.realTimeFactor).max(),
    maxPeakResidentBytes: samples.map(\.peakResidentBytes).max() ?? 0,
    thresholds: .init(maxRealTimeFactor: 1.0, maxPeakResidentBytes: 4 * 1024 * 1024 * 1024))
  let outputURL = URL(
    fileURLWithPath: environment["WOICE_BENCHMARK_OUTPUT"] ?? "build/model-benchmark.json")
  try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
  let encoder = JSONEncoder()
  encoder.dateEncodingStrategy = .iso8601
  encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
  try encoder.encode(report).write(to: outputURL, options: .atomic)

  if enforcing {
    #expect(report.missingCategories.isEmpty)
    #expect(samples.allSatisfy { $0.audioDuration >= minimumAudioDuration })
    #expect(report.maxRealTimeFactor != nil)
    #expect((report.maxRealTimeFactor ?? .infinity) <= report.thresholds.maxRealTimeFactor)
    #expect(report.maxPeakResidentBytes <= report.thresholds.maxPeakResidentBytes)
    #expect(samples.allSatisfy(benchmarkSamplePassesStrictOutputGate))
  }
}

@Test("模型严格基准区分预期空信号与异常输出")
func modelBenchmarkOutputGateDistinguishesEmptySignal() {
  #expect(
    benchmarkSamplePassesStrictOutputGate(
      makeBenchmarkSample(category: "silence", outputIsEmpty: true, errorCode: "empty_result")))
  #expect(
    benchmarkSamplePassesStrictOutputGate(
      makeBenchmarkSample(category: "noise", outputIsEmpty: true, errorCode: "empty_result")))
  #expect(
    !benchmarkSamplePassesStrictOutputGate(
      makeBenchmarkSample(category: "silence", outputIsEmpty: false, errorCode: nil)))
  #expect(
    !benchmarkSamplePassesStrictOutputGate(
      makeBenchmarkSample(category: "noise", outputIsEmpty: true, errorCode: "error")))
  #expect(
    !benchmarkSamplePassesStrictOutputGate(
      makeBenchmarkSample(category: "zh", outputIsEmpty: true, errorCode: "empty_result")))
}

private func audioDuration(of url: URL) throws -> TimeInterval {
  let file = try AVAudioFile(forReading: url)
  guard file.processingFormat.sampleRate > 0, file.length > 0 else {
    throw WoiceError.invalidResponse
  }
  return Double(file.length) / file.processingFormat.sampleRate
}

private func referenceText(for audioURL: URL) -> String? {
  let url = audioURL.deletingPathExtension().appendingPathExtension("txt")
  guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8),
    !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  else { return nil }
  return text
}

private func benchmarkCategory(for url: URL) -> String {
  let stem = url.deletingPathExtension().lastPathComponent.lowercased()
  for category in ["zh", "en", "mixed", "silence", "noise"] where stem.hasPrefix(category) {
    return category
  }
  return "other"
}

private func isExpectedEmptySignalCategory(_ category: String) -> Bool {
  category == "silence" || category == "noise"
}

private func benchmarkErrorCode(_ error: Error) -> String {
  if let error = error as? LocalASRError,
    case .emptyResult = error
  {
    return "empty_result"
  }
  return "error"
}

private func benchmarkSamplePassesStrictOutputGate(_ sample: ModelBenchmarkSample) -> Bool {
  if sample.expectedEmptySignal {
    return sample.outputIsEmpty && sample.errorCode == "empty_result"
  }
  return !sample.outputIsEmpty && sample.error == nil
}

private func makeBenchmarkSample(
  category: String,
  outputIsEmpty: Bool,
  errorCode: String?
) -> ModelBenchmarkSample {
  ModelBenchmarkSample(
    providerID: "com.woice.test",
    modelID: "test-model",
    modelVersion: "test-version",
    audioName: "\(category)-benchmark.wav",
    category: category,
    audioDuration: 300,
    elapsed: 30,
    realTimeFactor: 0.1,
    peakResidentBytes: 1,
    outputIsEmpty: outputIsEmpty,
    wordErrorRate: nil,
    error: errorCode == "error" ? "模拟错误" : (errorCode == "empty_result" ? "本机模型没有识别出文字" : nil),
    expectedEmptySignal: isExpectedEmptySignalCategory(category),
    errorCode: errorCode)
}

private func wordErrorRate(reference: String, hypothesis: String) -> Double {
  let referenceTokens = benchmarkTokens(reference)
  let hypothesisTokens = benchmarkTokens(hypothesis)
  guard !referenceTokens.isEmpty else { return hypothesisTokens.isEmpty ? 0 : 1 }
  var previous = Array(0...hypothesisTokens.count)
  for (row, referenceToken) in referenceTokens.enumerated() {
    var current = [row + 1]
    for (column, hypothesisToken) in hypothesisTokens.enumerated() {
      let substitution = previous[column] + (referenceToken == hypothesisToken ? 0 : 1)
      let insertion = current[column] + 1
      let deletion = previous[column + 1] + 1
      current.append(min(substitution, insertion, deletion))
    }
    previous = current
  }
  return Double(previous[hypothesisTokens.count]) / Double(referenceTokens.count)
}

private func benchmarkTokens(_ value: String) -> [String] {
  let normalized = value.lowercased().map { character in
    character.isPunctuation ? " " : character
  }
  if normalized.contains(where: { $0.isWhitespace }) {
    let words = normalized.split(whereSeparator: { $0.isWhitespace }).map { String($0) }
    if words.count > 1 { return words }
  }
  return normalized.filter { !$0.isWhitespace }.map(String.init)
}

private func residentMemoryBytes() -> Int64 {
  var info = mach_task_basic_info()
  var count = mach_msg_type_number_t(
    MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
  let result = withUnsafeMutablePointer(to: &info) { pointer in
    pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
      task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
    }
  }
  guard result == KERN_SUCCESS else { return 0 }
  return Int64(info.resident_size)
}

extension Duration {
  fileprivate var timeInterval: TimeInterval {
    Double(components.seconds) + Double(components.attoseconds) / 1_000_000_000_000_000_000
  }
}
