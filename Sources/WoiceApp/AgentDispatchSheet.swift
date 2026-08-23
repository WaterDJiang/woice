import SwiftUI
import WoiceCore

struct AgentDispatchSheet: View {
  @Environment(AppState.self) private var appState
  @Environment(\.dismiss) private var dismiss

  let record: RecordingRecord
  @State private var step = 0
  @State private var connectors: [AgentConnectorDescriptor] = []
  @State private var selectedConnectorID: String?
  @State private var instruction = "请基于这份录音素材整理出可执行的结论和待办。"
  @State private var permissionLevel: AgentPermissionLevel = .createTasks
  @State private var confirmedExternalShare = false
  @State private var isDiscovering = false
  @State private var isDispatching = false

  private var selectedConnector: AgentConnectorDescriptor? {
    connectors.first { $0.id == selectedConnectorID }
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        progressHeader
        Divider()
        ScrollView {
          stepContent
            .frame(maxWidth: 620, alignment: .leading)
            .padding(28)
        }
        Divider()
        footer
      }
      .navigationTitle("发送给 Agent（CLI Beta）")
      .task {
        await discoverConnectors()
      }
    }
    .frame(minWidth: 700, idealWidth: 760, minHeight: 560, idealHeight: 640)
  }

  private var progressHeader: some View {
    HStack(spacing: 12) {
      ForEach(0..<3, id: \.self) { index in
        HStack(spacing: 6) {
          Text("\(index + 1)")
            .font(.caption.weight(.semibold).monospacedDigit())
            .frame(width: 22, height: 22)
            .background(
              index == step ? Color.accentColor : Color.secondary.opacity(0.15), in: Circle()
            )
            .foregroundStyle(index == step ? .white : .secondary)
          Text(stepTitle(index))
            .font(.caption.weight(index == step ? .semibold : .regular))
            .foregroundStyle(index == step ? .primary : .secondary)
        }
        if index < 2 {
          Rectangle()
            .fill(.quaternary)
            .frame(height: 1)
        }
      }
    }
    .padding(.horizontal, 28)
    .padding(.vertical, 14)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("发送给 Agent（CLI Beta），第 \(step + 1) 步，共 3 步")
  }

  @ViewBuilder
  private var stepContent: some View {
    switch step {
    case 0:
      targetStep
    case 1:
      materialStep
    default:
      confirmationStep
    }
  }

  private var targetStep: some View {
    VStack(alignment: .leading, spacing: 18) {
      header(
        title: "选择目标",
        message: "Woice 只显示已在本机找到、并且有固定非交互适配契约的 CLI Beta。不会扫描或安装其他工具。",
        systemImage: "point.3.connected.trianglepath.dotted")
      HStack {
        Label(
          connectors.isEmpty ? "没有发现已验证 CLI Beta" : "发现 \(connectors.count) 个可用 CLI Beta",
          systemImage: connectors.isEmpty ? "exclamationmark.triangle" : "checkmark.circle"
        )
        .foregroundStyle(connectors.isEmpty ? .orange : .green)
        Spacer()
        Button {
          Task { await discoverConnectors() }
        } label: {
          Label(
            "重新检查", systemImage: isDiscovering ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
        }
        .buttonStyle(.bordered)
        .disabled(isDiscovering)
      }
      if isDiscovering {
        ProgressView("正在读取 CLI Beta 版本…")
          .controlSize(.small)
      } else if connectors.isEmpty {
        emptyState
      } else {
        VStack(spacing: 8) {
          ForEach(connectors) { connector in
            Button {
              selectedConnectorID = connector.id
              confirmedExternalShare = false
            } label: {
              HStack(spacing: 12) {
                Image(systemName: connectorIcon(for: connector))
                  .foregroundStyle(connectorColor(for: connector))
                VStack(alignment: .leading, spacing: 3) {
                  Text(connector.displayName)
                    .font(.body.weight(.medium))
                  Text("版本 \(connector.version) · \(connector.executablePath)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                  if connector.isUnsigned {
                    Text("未签名 CLI Beta；下一步会再次显示外发确认")
                      .font(.caption2)
                      .foregroundStyle(.orange)
                  }
                }
                Spacer()
              }
              .padding(12)
              .contentShape(Rectangle())
              .background(
                selectedConnectorID == connector.id
                  ? Color.accentColor.opacity(0.1)
                  : Color.secondary.opacity(0.06),
                in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(connector.displayName)，版本 \(connector.version)")
            .accessibilityValue(selectedConnectorID == connector.id ? "已选择" : "未选择")
          }
        }
      }
    }
  }

  private var materialStep: some View {
    VStack(alignment: .leading, spacing: 18) {
      header(
        title: "确认素材与任务",
        message: "默认只发送当前录音的规范化原文。音频保留在 Woice，不会复制到 CLI 上下文。",
        systemImage: "doc.badge.arrow.up")
      materialCard
      VStack(alignment: .leading, spacing: 8) {
        Text("任务说明")
          .font(.headline)
        TextEditor(text: $instruction)
          .font(.body)
          .frame(minHeight: 150)
          .padding(8)
          .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
          .overlay {
            RoundedRectangle(cornerRadius: 10)
              .stroke(.quaternary)
          }
        Text("\(instruction.count) / 8,192 字符")
          .font(.caption2.monospacedDigit())
          .foregroundStyle(instruction.count > 8_192 ? .red : .secondary)
      }
    }
  }

  private var confirmationStep: some View {
    VStack(alignment: .leading, spacing: 18) {
      header(
        title: "确认派发",
        message: "任务开始后，Woice 只等待目标 CLI 返回结果，不会执行它返回的命令、补丁或脚本。",
        systemImage: "hand.raised")
      VStack(alignment: .leading, spacing: 12) {
        summaryRow("目标", selectedConnector?.displayName ?? "未选择")
        summaryRow("版本", selectedConnector?.version ?? "—")
        summaryRow("素材", "规范化原文")
        summaryRow("任务", instruction.trimmingCharacters(in: .whitespacesAndNewlines))
      }
      .padding(16)
      .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
      permissionSummary
      HStack(alignment: .top, spacing: 10) {
        Image(systemName: "lock.shield")
          .foregroundStyle(.tint)
        Text("外发前会记录目标 CLI、版本、素材引用、权限摘要和 trace ID。原始录音不会被覆盖。")
          .font(.callout)
          .foregroundStyle(.secondary)
      }
    }
  }

  private var permissionSummary: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label("本次权限", systemImage: "lock.shield")
        .font(.headline)
      Picker("权限层级", selection: $permissionLevel) {
        ForEach(AgentPermissionLevel.allCases, id: \.self) { level in
          Text(level.label).tag(level)
        }
      }
      .pickerStyle(.segmented)
      .disabled(true)
      Text("当前 CLI 仅授予“创建任务”：读取你选中的素材并返回结果；不启动录音、不读取 Keychain，也不能控制正在录音。")
        .font(.caption)
        .foregroundStyle(.secondary)
      Toggle(
        "我确认将这条录音的规范化原文发送给 \(selectedConnector?.displayName ?? "目标 CLI")",
        isOn: $confirmedExternalShare
      )
      .toggleStyle(.checkbox)
    }
    .padding(14)
    .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
  }

  private var materialCard: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label(record.title, systemImage: "waveform")
        .font(.body.weight(.medium))
      Text("\(record.shortDate) · \(formatDuration(record.duration))")
        .font(.caption)
        .foregroundStyle(.secondary)
      Divider()
      Label("规范化原文", systemImage: "text.alignleft")
      Label("音频不会发送", systemImage: "waveform.slash")
      Label("文字 Context Package 临时副本，完成后清理", systemImage: "trash")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .padding(16)
    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
  }

  private var emptyState: some View {
    ContentUnavailableView(
      "尚未发现已验证 CLI Beta",
      systemImage: "terminal",
      description: Text("先安装 Codex CLI 或 Claude Code CLI，再点击重新检查。Woice 不会代你安装或读取它们的凭据。"))
  }

  private var footer: some View {
    HStack {
      Button("取消") { dismiss() }
        .keyboardShortcut(.cancelAction)
      Spacer()
      if step > 0 {
        Button("上一步") { step -= 1 }
          .buttonStyle(.bordered)
      }
      if step < 2 {
        Button("下一步") { step += 1 }
          .buttonStyle(.borderedProminent)
          .disabled(step == 0 ? selectedConnector == nil : !canContinue)
      } else {
        Button {
          Task { await dispatch() }
        } label: {
          Label(
            isDispatching ? "正在派发…" : "确认派发",
            systemImage: isDispatching ? "arrow.triangle.2.circlepath" : "paperplane.fill")
        }
        .buttonStyle(.borderedProminent)
        .disabled(
          isDispatching || selectedConnector == nil || !canContinue || !confirmedExternalShare)
      }
    }
    .padding(.horizontal, 28)
    .padding(.vertical, 14)
  }

  private var canContinue: Bool {
    !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && instruction.count <= 8_192
  }

  private func header(title: String, message: String, systemImage: String) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: systemImage)
        .font(.title2)
        .foregroundStyle(.tint)
        .frame(width: 28)
      VStack(alignment: .leading, spacing: 4) {
        Text(title).font(.title2.weight(.semibold))
        Text(message)
          .font(.callout)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private func summaryRow(_ title: String, _ value: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(width: 54, alignment: .leading)
      Text(value)
        .font(.callout)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private func stepTitle(_ index: Int) -> String {
    switch index {
    case 0: "目标"
    case 1: "素材与任务"
    default: "确认"
    }
  }

  private func connectorIcon(for connector: AgentConnectorDescriptor) -> String {
    selectedConnectorID == connector.id ? "checkmark.circle.fill" : "circle"
  }

  private func connectorColor(for connector: AgentConnectorDescriptor) -> Color {
    selectedConnectorID == connector.id ? .accentColor : .secondary
  }

  private func discoverConnectors() async {
    isDiscovering = true
    let catalog = AgentCLIAdapterCatalog()
    let found = await Task.detached(priority: .userInitiated) {
      catalog.discover()
    }.value
    connectors = found
    if selectedConnectorID == nil {
      selectedConnectorID = found.first?.id
    } else if !found.contains(where: { $0.id == selectedConnectorID }) {
      selectedConnectorID = found.first?.id
    }
    isDiscovering = false
  }

  private func dispatch() async {
    guard let connector = selectedConnector else { return }
    isDispatching = true
    if await appState.dispatchToAgent(
      record: record, manifest: connector.manifest, instruction: instruction,
      permissionLevel: permissionLevel) != nil
    {
      dismiss()
    }
    isDispatching = false
  }
}
