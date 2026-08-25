import Foundation
import WoiceCore

/// Fixed Qwen3-ASR 0.6B MLX pack. The weights are data-only and are fetched
/// through ModelPackDownloadCoordinator; no runtime downloader or Python tool
/// is allowed to run inside Woice.
struct Qwen3ASRModelCatalogEntry: Equatable, Sendable {
  static let packID = "com.woice.qwen3.asr.0.6b.4bit"
  static let modelID = "qwen3-asr-0.6b-4bit"
  static let derivedRevision = "313d850181767edf09f00a9c289becca70e58cd0"
  static let upstreamRevision = "7f1569a48a89f3e3f4dc3a5c9d28bddd903bc76c"
  static let sourceURL = "https://huggingface.co/mlx-community/Qwen3-ASR-0.6B-4bit"
  static let upstreamSourceURL = "https://huggingface.co/Qwen/Qwen3-ASR-0.6B-hf"
  static let downloadBaseURL =
    "https://huggingface.co/mlx-community/Qwen3-ASR-0.6B-4bit/resolve/\(derivedRevision)"
  static let estimatedBytes: Int64 = 712_699_126

  let displayName: String

  static let recommended = Qwen3ASRModelCatalogEntry(displayName: "Qwen3-ASR 0.6B（本机）")

  var manifest: ModelPackManifest {
    Self.makeManifest(displayName: displayName)
  }

  private static func makeManifest(displayName: String) -> ModelPackManifest {
    let files = [
      try! ModelPackFile(
        relativePath: "model.safetensors",
        byteCount: 708_236_945,
        sha256: "70c7e67e588062adce4f10796e47ad42ead51c6671eda61a0987eae38ca95ddf"),
      try! ModelPackFile(
        relativePath: "merges.txt",
        byteCount: 1_671_853,
        sha256: "8831e4f1a044471340f7c0a83d7bd71306a5b867e95fd870f74d0c5308a904d5"),
      try! ModelPackFile(
        relativePath: "vocab.json",
        byteCount: 2_776_833,
        sha256: "ca10d7e9fb3ed18575dd1e277a2579c16d108e32f27439684afa0e10b1440910"),
      try! ModelPackFile(
        relativePath: "tokenizer_config.json",
        byteCount: 12_487,
        sha256: "4942d005604266809309cabc9f4e9cb89ce855d59b14681fdc0e1cc62ea26c4c"),
      // The model card is retained as the pack's readable notice and records
      // the Apache-2.0 declaration plus the conversion provenance.
      try! ModelPackFile(
        relativePath: "README.md",
        byteCount: 1_008,
        sha256: "4d54132d09a2d3d12410ef13c94d7afcfc936bdca8239a3e6cd0797d6a28dd1c"),
    ]
    let provenance = try! ModelPackProvenance(
      upstreamModelID: "Qwen/Qwen3-ASR-0.6B-hf",
      upstreamRevision: upstreamRevision,
      sourceURL: upstreamSourceURL,
      derivedFormat: "MLX safetensors 4-bit",
      conversionTool: "mlx-audio",
      conversionRevision: "0.3.1",
      upstreamSHA256: "d3f212dd20abecd315d830bc54ae3865e56ebfc3276484e57b771288ba27fd35")
    let license = try! ModelPackLicense(
      identifier: "Apache-2.0",
      noticePath: "README.md",
      sourceURL: sourceURL)
    return try! ModelPackManifest(
      packID: packID,
      modelID: modelID,
      version: derivedRevision,
      providerID: "com.woice.qwen3-asr",
      transport: .inProcess,
      capabilities: [.transcription, .timestamps],
      files: files,
      license: license,
      size: estimatedBytes,
      provenance: provenance,
      displayName: displayName,
      isRecommended: false,
      storeCompatible: true,
      runtimeID: "com.woice.qwen3-asr",
      downloadBaseURL: downloadBaseURL)
  }
}
