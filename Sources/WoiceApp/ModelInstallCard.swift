import SwiftUI
import WoiceCore

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
}

/// Shared one-click model entry point used by the workspace, material detail
/// and settings surfaces. It renders the durable task projection but does not
/// own download state or provider selection.
struct ModelInstallCard: View {
  @Environment(AppState.self) private var appState

  let entryPoint: ModelInstallEntryPoint
  let recordingID: UUID?
  let model: ModelInstallCardModel

  init(
    entryPoint: ModelInstallEntryPoint,
    recordingID: UUID? = nil,
    model: ModelInstallCardModel = .whisperKit(.recommendedTiny)
  ) {
    self.entryPoint = entryPoint
    self.recordingID = recordingID
    self.model = model
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

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .top, spacing: 10) {
        Image(systemName: "waveform.badge.mic")
          .font(.title3)
          .foregroundStyle(.tint)
          .frame(width: 24)
        VStack(alignment: .leading, spacing: 3) {
          Text(model.displayName)
            .font(.headline)
          Text(
            "约 \(ByteCountFormatter.string(fromByteCount: model.estimatedBytes, countStyle: .file)) · 本机运行"
          )
          .font(.caption)
          .foregroundStyle(.secondary)
          Text("下载到这台 Mac；录音不会因此发送到网络。")
            .font(.caption)
            .foregroundStyle(.secondary)
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
          } else if isInstalled {
            Label("已安装", systemImage: "checkmark")
          } else {
            Label(recordingID == nil ? "下载并使用" : "下载并转写", systemImage: "arrow.down.circle")
          }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .disabled(isInstalled || (appState.isDownloadingModel && !isDownloading))
        .accessibilityLabel(
          recordingID == nil ? "下载并使用\(model.displayName)" : "下载\(model.displayName)并转写素材")
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
