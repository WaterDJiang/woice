import Foundation
import WoiceCore

enum ModelRuntimeAdmission: Equatable, Sendable {
  case admitted
  case unavailable(String)

  var isAdmitted: Bool {
    if case .admitted = self { return true }
    return false
  }
}

enum ModelRuntimeError: LocalizedError, Equatable, Sendable {
  case unavailable(runtimeID: String, reason: String)
  case providerMismatch(expected: String, actual: String)

  var errorDescription: String? {
    switch self {
    case .unavailable(let runtimeID, let reason):
      "模型 Runtime \(runtimeID) 当前不可用：\(reason)"
    case .providerMismatch(let expected, let actual):
      "模型 Runtime 与 Provider 不匹配：期待 \(expected)，收到 \(actual)"
    }
  }
}

/// The finite set of model runtimes shipped with Woice. A model pack can only
/// provide data; this registry is the sole place allowed to turn an admitted
/// manifest into executable inference code.
enum ModelRuntimeRegistry {
  static let whisperKitRuntimeID = "com.woice.whisperkit"
  static let qwen3ASRRuntimeID = "com.woice.qwen3-asr"

  static func admission(for manifest: ModelPackManifest) -> ModelRuntimeAdmission {
    switch manifest.runtimeID ?? manifest.providerID {
    case whisperKitRuntimeID:
      guard manifest.providerID == whisperKitRuntimeID else {
        return .unavailable("Provider ID 不匹配")
      }
      guard manifest.transport == .inProcess,
        manifest.capabilities.contains(.transcription)
      else {
        return .unavailable("模型清单没有声明受信的本机转写能力")
      }
      return .admitted
    case qwen3ASRRuntimeID:
      guard manifest.providerID == qwen3ASRRuntimeID else {
        return .unavailable("Provider ID 不匹配")
      }
      guard manifest.transport == .inProcess,
        manifest.capabilities.contains(.transcription)
      else {
        return .unavailable("模型清单没有声明受信的本机转写能力")
      }
      return .admitted
    default:
      return .unavailable("没有随 App 签名的受信 Runtime")
    }
  }

  static func makeProvider(
    manifest: ModelPackManifest,
    modelFolder: URL
  ) throws -> any LocalASRTranscribing {
    guard manifest.providerID == (manifest.runtimeID ?? manifest.providerID) else {
      throw ModelRuntimeError.providerMismatch(
        expected: manifest.runtimeID ?? manifest.providerID, actual: manifest.providerID)
    }
    guard admission(for: manifest).isAdmitted else {
      let reason: String
      if case .unavailable(let value) = admission(for: manifest) {
        reason = value
      } else {
        reason = "未知原因"
      }
      throw ModelRuntimeError.unavailable(
        runtimeID: manifest.runtimeID ?? manifest.providerID, reason: reason)
    }
    switch manifest.runtimeID ?? manifest.providerID {
    case whisperKitRuntimeID:
      return try WhisperKitTranscriptionService(manifest: manifest, modelFolder: modelFolder)
    case qwen3ASRRuntimeID:
      return try Qwen3ASRTranscriptionService(manifest: manifest, modelFolder: modelFolder)
    default:
      throw ModelRuntimeError.unavailable(
        runtimeID: manifest.runtimeID ?? manifest.providerID, reason: "Runtime 未注册")
    }
  }
}
