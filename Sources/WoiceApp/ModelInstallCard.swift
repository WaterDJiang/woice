import SwiftUI
import WoiceCore

struct ModelInstallGuidance: Equatable, Sendable {
  let resourceImpact: String
  let resourceDetail: String
  let qualityImpact: String
  let qualityDetail: String
  let selectionHint: String

  static let tiny = ModelInstallGuidance(
    resourceImpact: "低",
    resourceDetail: "约 79 MB；下载和运行占用较少，启动更快",
    qualityImpact: "基础",
    qualityDetail: "适合快速记录；复杂口音、噪声和重叠讲话的准确度低于 Large-v3",
    selectionHint: "适合空间紧张或更在意响应速度的 Mac")

  static let qwen3ASR = ModelInstallGuidance(
    resourceImpact: "中",
    resourceDetail: "约 713 MB；4-bit 本机运行会占用更多内存和电量",
    qualityImpact: "平衡（预览）",
    qualityDetail: "适合中文/多语言本机识别尝试；正式性能矩阵仍在收口",
    selectionHint: "适合愿意体验预览模型、可接受更高资源占用的 Mac")

  static let largeV3 = ModelInstallGuidance(
    resourceImpact: "高",
    resourceDetail: "约 626 MB；运行时更占内存和电量，长录音期间更吃资源",
    qualityImpact: "最高（已验证）",
    qualityDetail: "当前本机模型中准确率优先；已通过五类各 300 秒性能门禁，真实音频仍可能有偏差",
    selectionHint: "适合更在意复杂会议准确度、且有足够空间和内存的 Mac")
}

enum ModelInstallCardModel: Equatable, Sendable {
  case whisperKit(WhisperKitModelCatalogEntry)
  case qwen3ASR

  var packID: String {
    switch self {
    case .whisperKit(let entry): entry.packID
    case .qwen3ASR: Qwen3ASRModelCatalogEntry.packID
    }
  }

  var version: String {
    switch self {
    case .whisperKit(let entry): entry.modelRevision
    case .qwen3ASR: Qwen3ASRModelCatalogEntry.derivedRevision
    }
  }

  var displayName: String {
    switch self {
    case .whisperKit(let entry): entry.displayName
    case .qwen3ASR: Qwen3ASRModelCatalogEntry.recommended.displayName
    }
  }

  var estimatedBytes: Int64 {
    switch self {
    case .whisperKit(let entry): entry.estimatedBytes
    case .qwen3ASR: Qwen3ASRModelCatalogEntry.estimatedBytes
    }
  }

  var guidance: ModelInstallGuidance {
    switch self {
    case .whisperKit(let entry):
      entry.packID == WhisperKitModelCatalogEntry.candidateLargeV3.packID
        ? .largeV3 : .tiny
    case .qwen3ASR:
      .qwen3ASR
    }
  }
}

struct RecommendedModelPolicy: Equatable, Sendable {
  struct Recommendation: Equatable, Sendable {
    let model: ModelInstallCardModel
    let reason: String
  }

  static let qwenMinimumMemoryBytes: UInt64 = 16 * 1_024 * 1_024 * 1_024
  static let largeModelMinimumMemoryBytes: UInt64 = 32 * 1_024 * 1_024 * 1_024

  static let candidates: [ModelInstallCardModel] = [
    .whisperKit(.recommendedTiny),
    .qwen3ASR,
    .whisperKit(.candidateLargeV3),
  ]

  static var current: Recommendation {
    recommendation(physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory)!
  }

  static func recommendation(
    physicalMemoryBytes: UInt64,
    availablePackIDs: Set<String>? = nil
  ) -> Recommendation? {
    let memory = ByteCountFormatter.string(
      fromByteCount: Int64(clamping: physicalMemoryBytes), countStyle: .memory)
    let preference: [ModelInstallCardModel]
    if physicalMemoryBytes >= largeModelMinimumMemoryBytes {
      preference = [
        .whisperKit(.candidateLargeV3), .qwen3ASR, .whisperKit(.recommendedTiny),
      ]
    } else if physicalMemoryBytes >= qwenMinimumMemoryBytes {
      preference = [
        .qwen3ASR, .whisperKit(.recommendedTiny), .whisperKit(.candidateLargeV3),
      ]
    } else {
      preference = [
        .whisperKit(.recommendedTiny), .qwen3ASR, .whisperKit(.candidateLargeV3),
      ]
    }
    guard
      let model = preference.first(where: { model in
        availablePackIDs?.contains(model.packID) ?? true
      })
    else { return nil }
    let description =
      switch model {
      case .qwen3ASR: "兼顾中文转写和本机占用的 Qwen3-ASR 0.6B"
      case .whisperKit(let entry)
      where entry.packID == WhisperKitModelCatalogEntry.candidateLargeV3.packID:
        "准确率更高的 Large-v3"
      case .whisperKit:
        "占用更小的 Tiny"
      }
    return Recommendation(model: model, reason: "这台 Mac 有 \(memory) 内存，推荐\(description)。")
  }
}

struct ModelInstallTradeoffSummary: View {
  let guidance: ModelInstallGuidance

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      tradeoffRow(
        title: "设备影响", value: guidance.resourceImpact, detail: guidance.resourceDetail,
        systemImage: "memorychip")
      tradeoffRow(
        title: "产出质量", value: guidance.qualityImpact, detail: guidance.qualityDetail,
        systemImage: "text.badge.checkmark")
      Text("选择提示：\(guidance.selectionHint)")
        .font(.caption2)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  @ViewBuilder
  private func tradeoffRow(
    title: String,
    value: String,
    detail: String,
    systemImage: String
  ) -> some View {
    HStack(alignment: .top, spacing: 6) {
      Label(title, systemImage: systemImage)
        .font(.caption.weight(.medium))
        .frame(width: 78, alignment: .leading)
      Text("\(value) · \(detail)")
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .accessibilityElement(children: .combine)
  }
}

/// Shared one-click model entry point used by the workspace, material detail
/// and settings surfaces. It renders the durable task projection but does not
/// own download state or provider selection.
struct ModelInstallCard: View {
  @Environment(AppState.self) private var appState

  let entryPoint: ModelInstallEntryPoint
  let recordingID: UUID?
  let model: ModelInstallCardModel
  let recommendation: RecommendedModelPolicy.Recommendation?

  init(
    entryPoint: ModelInstallEntryPoint,
    recordingID: UUID? = nil,
    model: ModelInstallCardModel = RecommendedModelPolicy.current.model,
    recommendation: RecommendedModelPolicy.Recommendation? = RecommendedModelPolicy.current
  ) {
    self.entryPoint = entryPoint
    self.recordingID = recordingID
    self.model = model
    self.recommendation = recommendation
  }

  private var isInstalled: Bool {
    appState.isModelPackInstalled(packID: model.packID, version: model.version)
  }
  private var isDownloading: Bool {
    appState.isDownloadingModel(packID: model.packID, version: model.version)
  }
  private var task: ModelDownloadTask? {
    appState.modelDownloadTasks.first {
      $0.packID == model.packID && $0.version == model.version
    }
  }
  private var isStoreCatalogEntryAvailable: Bool {
    guard StoreCapabilityProfile.current.isStoreEdition else { return true }
    return appState.verifiedModelCatalogEntries.contains {
      $0.packID == model.packID
        && $0.version == model.version
        && $0.downloadBaseURL != nil
    }
  }
  private var isBlockedByStoreCatalog: Bool {
    StoreCapabilityProfile.current.isStoreEdition && !isStoreCatalogEntryAvailable
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .top, spacing: 10) {
        Image(systemName: "waveform.badge.mic")
          .font(.title3)
          .foregroundStyle(.tint)
          .frame(width: 24)
        VStack(alignment: .leading, spacing: 3) {
          HStack(spacing: 6) {
            Text(model.displayName)
              .font(.headline)
            if recommendation?.model.packID == model.packID {
              Label("为这台 Mac 推荐", systemImage: "sparkles")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tint)
            }
          }
          Text(
            "约 \(ByteCountFormatter.string(fromByteCount: model.estimatedBytes, countStyle: .file)) · 本机运行"
          )
          .font(.caption)
          .foregroundStyle(.secondary)
          Text("下载到这台 Mac；录音不会因此发送到网络。")
            .font(.caption)
            .foregroundStyle(.secondary)
          if recommendation?.model.packID == model.packID, let recommendation {
            Text(recommendation.reason)
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
        }
        Spacer(minLength: 8)
        Button {
          if isDownloading {
            appState.cancelModelDownload()
          } else {
            let intent = ModelInstallIntent(entryPoint: entryPoint, recordingID: recordingID)
            switch model {
            case .whisperKit(let entry):
              appState.startModelInstall(entry: entry, intent: intent)
            case .qwen3ASR:
              appState.startQwen3ASRModelDownload(intent: intent)
            }
          }
        } label: {
          if isDownloading {
            ProgressView().controlSize(.small)
            Text("取消")
          } else if isBlockedByStoreCatalog {
            Label("等待模型清单", systemImage: "lock")
          } else if isInstalled {
            Label("已安装", systemImage: "checkmark")
          } else {
            Label(recordingID == nil ? "下载并使用" : "下载并转写", systemImage: "arrow.down.circle")
          }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .disabled(
          (isBlockedByStoreCatalog && !isDownloading) || isInstalled
            || (appState.isDownloadingModel && !isDownloading)
        )
        .accessibilityLabel(
          isBlockedByStoreCatalog
            ? "\(model.displayName)等待已验证模型清单"
            : (recordingID == nil ? "下载并使用\(model.displayName)" : "下载\(model.displayName)并转写素材"))
      }
      ModelInstallTradeoffSummary(guidance: model.guidance)
      if isBlockedByStoreCatalog {
        Label(
          appState.canUpdateModelCatalog
            ? "请先在模型清单中检查更新，验证后才可下载。"
            : "当前商店版本未配置已验证模型清单，暂不能下载此模型。",
          systemImage: "info.circle"
        )
        .font(.caption2)
        .foregroundStyle(.orange)
        .fixedSize(horizontal: false, vertical: true)
      }
      if isDownloading, let progress = appState.modelDownloadProgress {
        ProgressView(value: progress.fractionCompleted)
        HStack(spacing: 8) {
          Text(progress.filePath)
          Spacer()
          Text("\(Int(progress.fractionCompleted * 100))%")
            .monospacedDigit()
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
      } else if let task, task.state != .installed, let lastError = task.lastError,
        !lastError.isEmpty
      {
        Label(lastError, systemImage: "exclamationmark.triangle")
          .font(.caption2)
          .foregroundStyle(.orange)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(14)
    .frame(maxWidth: 620, alignment: .leading)
    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    .overlay {
      RoundedRectangle(cornerRadius: 12)
        .strokeBorder(Color.accentColor.opacity(0.18), lineWidth: 1)
    }
    .accessibilityElement(children: .contain)
  }
}

struct RecommendedModelInstallCard: View {
  @Environment(AppState.self) private var appState

  let entryPoint: ModelInstallEntryPoint
  let recordingID: UUID?

  init(entryPoint: ModelInstallEntryPoint, recordingID: UUID? = nil) {
    self.entryPoint = entryPoint
    self.recordingID = recordingID
  }

  private var recommendation: RecommendedModelPolicy.Recommendation? {
    RecommendedModelPolicy.recommendation(
      physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory,
      availablePackIDs: StoreCapabilityProfile.current.isStoreEdition
        ? Set(
          appState.verifiedModelCatalogEntries.compactMap {
            $0.downloadBaseURL == nil ? nil : $0.packID
          })
        : nil)
  }

  var body: some View {
    let displayedRecommendation = recommendation
    ModelInstallCard(
      entryPoint: entryPoint,
      recordingID: recordingID,
      model: displayedRecommendation?.model ?? RecommendedModelPolicy.current.model,
      recommendation: displayedRecommendation)
  }
}
