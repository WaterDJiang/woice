@preconcurrency import AVFoundation
import Foundation
import Qwen3ASR
import Qwen3Common
import WoiceCore

enum Qwen3ASRError: LocalizedError, Equatable, Sendable {
  case modelDirectoryMissing
  case modelFilesMissing
  case modelLoadFailed(String)
  case audioReadFailed(String)
  case transcriptionFailed(String)

  var errorDescription: String? {
    switch self {
    case .modelDirectoryMissing:
      "Qwen3-ASR 模型目录不存在；原始录音仍保存在本机。"
    case .modelFilesMissing:
      "Qwen3-ASR 模型文件不完整；原始录音仍保存在本机。"
    case .modelLoadFailed(let message):
      "Qwen3-ASR 本机模型加载失败：\(message)；原始录音仍保存在本机。"
    case .audioReadFailed(let message):
      "Qwen3-ASR 音频准备失败：\(message)；原始录音仍保存在本机。"
    case .transcriptionFailed(let message):
      "Qwen3-ASR 本机转写失败：\(message)；原始录音仍保存在本机。"
    }
  }
}

/// Serializes the non-Sendable MLX graph and keeps model loading/inference off
/// the main actor. A model pack remains data-only; this session is the sole
/// in-process boundary that turns verified Qwen files into executable code.
private final class Qwen3ASRSession: @unchecked Sendable {
  private let lock = NSLock()
  private let modelFolder: URL
  private var model: Qwen3ASRModel?

  init(modelFolder: URL) throws {
    guard FileManager.default.fileExists(atPath: modelFolder.path) else {
      throw Qwen3ASRError.modelDirectoryMissing
    }
    self.modelFolder = modelFolder.standardizedFileURL
    try validateRequiredFiles()
  }

  func transcribe(
    audioURL: URL,
    language: String
  ) throws -> TranscriptionResult {
    lock.lock()
    defer { lock.unlock() }
    let model = try loadedModel()
    return try transcribeAudioFile(model: model, audioURL: audioURL, language: language)
  }

  private func validateRequiredFiles() throws {
    let required = ["model.safetensors", "vocab.json", "merges.txt", "tokenizer_config.json"]
    guard
      required.allSatisfy({
        FileManager.default.fileExists(atPath: modelFolder.appendingPathComponent($0).path)
      })
    else {
      throw Qwen3ASRError.modelFilesMissing
    }
  }

  private func loadedModel() throws -> Qwen3ASRModel {
    if let model { return model }
    do {
      let loaded = Qwen3ASRModel(
        audioConfig: .small,
        textConfig: .small)
      let tokenizer = Qwen3Tokenizer()
      try tokenizer.load(from: modelFolder.appendingPathComponent("vocab.json"))
      loaded.setTokenizer(tokenizer)
      try WeightLoader.loadWeights(into: loaded.audioEncoder, from: modelFolder)
      loaded.initializeTextDecoder()
      guard let textDecoder = loaded.textDecoder else {
        throw Qwen3ASRError.modelLoadFailed("文本解码器未初始化")
      }
      try WeightLoader.loadTextDecoderWeights(into: textDecoder, from: modelFolder)
      model = loaded
      return loaded
    } catch let error as Qwen3ASRError {
      throw error
    } catch {
      throw Qwen3ASRError.modelLoadFailed(error.localizedDescription)
    }
  }

  private func transcribeAudioFile(
    model: Qwen3ASRModel,
    audioURL: URL,
    language: String
  ) throws -> TranscriptionResult {
    guard FileManager.default.fileExists(atPath: audioURL.path) else {
      throw LocalASRError.audioMissing
    }

    let normalizedURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("woice-qwen-\(UUID().uuidString).wav")
    defer { try? FileManager.default.removeItem(at: normalizedURL) }
    do {
      try AudioPreparationService.prepareTranscriptionAudio(
        sourceURL: audioURL, outputURL: normalizedURL)
    } catch {
      throw Qwen3ASRError.audioReadFailed(error.localizedDescription)
    }

    do {
      let audioFile = try AVAudioFile(forReading: normalizedURL)
      let sampleRate = max(1, Int(audioFile.processingFormat.sampleRate.rounded()))
      let maximumFrames = AVAudioFrameCount(sampleRate * 30)
      var chunks: [String] = []
      var segments: [TranscriptSegment] = []
      var frameOffset: AVAudioFramePosition = 0

      while audioFile.framePosition < audioFile.length {
        let remaining = audioFile.length - audioFile.framePosition
        let frameCount = AVAudioFrameCount(min(Int64(maximumFrames), remaining))
        guard frameCount > 0,
          let buffer = AVAudioPCMBuffer(
            pcmFormat: audioFile.processingFormat, frameCapacity: frameCount)
        else { break }
        try audioFile.read(into: buffer, frameCount: frameCount)
        guard buffer.frameLength > 0,
          let channel = buffer.floatChannelData?.pointee
        else { throw Qwen3ASRError.audioReadFailed("无法读取浮点音频帧") }

        let samples = Array(
          UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
        let text = TranscriptTextNormalizer.normalize(
          model.transcribe(
            audio: samples,
            sampleRate: sampleRate,
            language: qwenLanguage(for: language)))
        if !text.isEmpty {
          chunks.append(text)
          let start = Double(frameOffset) / Double(sampleRate)
          let end =
            Double(frameOffset + AVAudioFramePosition(buffer.frameLength))
            / Double(sampleRate)
          segments.append(TranscriptSegment(start: start, end: end, text: text))
        }
        frameOffset += AVAudioFramePosition(buffer.frameLength)
      }

      let text = TranscriptTextNormalizer.normalize(chunks.joined(separator: "\n"))
      guard !text.isEmpty else { throw LocalASRError.emptyResult }
      return TranscriptionResult(text: text, segments: segments)
    } catch let error as Qwen3ASRError {
      throw error
    } catch let error as LocalASRError {
      throw error
    } catch {
      throw Qwen3ASRError.transcriptionFailed(error.localizedDescription)
    }
  }

  private func qwenLanguage(for value: String) -> String? {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !normalized.isEmpty else { return nil }
    switch normalized {
    case "zh", "zh-cn", "zh-hans", "chinese": return "Chinese"
    case "en", "en-us", "en-gb", "english": return "English"
    case "yue", "zh-yue", "cantonese": return "Cantonese"
    case "ja", "ja-jp", "japanese": return "Japanese"
    case "ko", "ko-kr", "korean": return "Korean"
    default: return value
    }
  }
}

/// Native Qwen3-ASR adapter. It accepts only an already verified model pack
/// directory and performs all inference in a detached task, leaving UI state
/// and the durable recording pipeline in AppState.
final class Qwen3ASRTranscriptionService: LocalASRTranscribing, @unchecked Sendable {
  let model: ASRModelDescriptor
  private let session: Qwen3ASRSession

  init(manifest: ModelPackManifest, modelFolder: URL) throws {
    try manifest.validate()
    guard manifest.providerID == "com.woice.qwen3-asr" else {
      throw Qwen3ASRError.modelLoadFailed("Provider ID 不匹配：\(manifest.providerID)")
    }
    self.session = try Qwen3ASRSession(modelFolder: modelFolder)
    self.model = ASRModelDescriptor(
      providerID: manifest.providerID,
      modelID: manifest.modelID,
      displayName: manifest.displayName ?? "Qwen3-ASR 本机模型",
      version: manifest.version,
      dataLocation: .onDevice)
  }

  func transcribe(audioURL: URL, language: String) async throws -> TranscriptionResult {
    try await Task.detached(priority: .userInitiated) { [session] in
      try Task.checkCancellation()
      return try session.transcribe(audioURL: audioURL, language: language)
    }.value
  }
}
