import SwiftUI
import WoiceCore

struct RecordingDetailView: View {
  @Environment(AppState.self) private var appState
  let record: RecordingRecord
  @State private var exportedURL: URL?
  @State private var playback = AudioPlaybackService()
  @State private var selectedPlaybackTrack: AudioTrackKind = .microphone
  @State private var isShowingAgentDispatch = false
  @State private var isConfirmingDeletion = false
  @State private var isEditingTitle = false
  @State private var titleDraft = ""
  @State private var normalizedTranscript = ""
  @State private var normalizedTranscriptChunks: [String] = []
  @State private var isLoadingTranscript = false
  @State private var audioMetadata: [AudioTrackKind: AudioMetadataSnapshot] = [:]

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        HStack(alignment: .top) {
          VStack(alignment: .leading, spacing: 5) {
            if isEditingTitle {
              HStack(spacing: 8) {
                TextField("素材名称", text: $titleDraft)
                  .textFieldStyle(.roundedBorder)
                  .font(.title2.weight(.semibold))
                  .onSubmit(saveTitle)
                  .onExitCommand(perform: cancelTitleEditing)
                Button("保存", action: saveTitle)
                  .buttonStyle(.borderedProminent)
                  .controlSize(.small)
                  .disabled(!appState.canMutateRecordings)
                Button("取消", action: cancelTitleEditing)
                  .buttonStyle(.bordered)
                  .controlSize(.small)
              }
              .accessibilityElement(children: .contain)
              .accessibilityLabel("重命名素材：当前名称 (record.displayTitle)")
            } else {
              HStack(spacing: 8) {
                Text(record.displayTitle).font(.title2.weight(.semibold))
                Button {
                  titleDraft = record.displayTitle
                  isEditingTitle = true
                } label: {
                  Label("重命名", systemImage: "pencil")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .disabled(!appState.canMutateRecordings)
                .help("重命名素材")
                .accessibilityLabel("重命名素材：当前名称 (record.displayTitle)")
              }
            }
            Text("\(record.shortDate) · \(formatDuration(record.duration))")
              .font(.caption).foregroundStyle(.secondary)
          }
          Spacer()
          Menu {
            Button("复制原文") { appState.copyTranscript(record.transcript ?? "") }
              .disabled(record.transcript?.isEmpty != false)
            Button("粘贴到当前应用") { appState.pasteTranscript(for: record) }
              .disabled(record.transcript?.isEmpty != false)
            #if !WOICE_APP_STORE
              if StoreCapabilityProfile.current.allowsExternalAgentConnector {
                Button("发送给 Agent（CLI Beta）…", systemImage: "paperplane") {
                  isShowingAgentDispatch = true
                }
                .disabled(record.transcript?.isEmpty != false)
              }
            #endif
            Button("重新转写") { appState.requestTranscription(for: record) }
              .disabled(!appState.canTranscribe || !appState.canMutateRecordings)
            Divider()
            Menu("导出", systemImage: "square.and.arrow.down") {
              exportButton(.microphoneAudio)
                .disabled(!appState.microphoneAudioFileExists(for: record))
              exportButton(.systemAudio)
                .disabled(!appState.systemAudioFileExists(for: record))
              exportButton(.meetingMixAudio)
                .disabled(!appState.meetingMixFileExists(for: record))
              Divider()
              exportButton(.transcriptText)
                .disabled(record.transcript?.isEmpty != false)
              exportButton(.transcriptJSON)
                .disabled(record.transcript?.isEmpty != false)
              exportButton(.markdown)
                .disabled(record.transcript?.isEmpty != false)
            }
            Divider()
            Menu("打开素材", systemImage: "arrow.up.forward.app") {
              if record.originalMediaFileName != nil {
                Button("打开导入的原始文件") {
                  _ = appState.openOriginalMedia(for: record)
                }
              }
              Button("在 Finder 中显示全部音频") {
                _ = appState.revealMaterialFiles(for: record)
              }
              Button("打开麦克风原始音频") {
                _ = appState.openMaterialFile(for: record, track: .microphone)
              }
              .disabled(!appState.microphoneAudioFileExists(for: record))
              Button("打开电脑声音音频") {
                _ = appState.openMaterialFile(for: record, track: .systemAudio)
              }
              .disabled(!appState.systemAudioFileExists(for: record))
              Button("打开会议合成音频") {
                _ = appState.openMaterialFile(for: record, track: .meetingMix)
              }
              .disabled(!appState.meetingMixFileExists(for: record))
            }
            Button("移到废纸篓", role: .destructive) { isConfirmingDeletion = true }
              .disabled(!appState.canMutateRecordings)
          } label: {
            Label("操作", systemImage: "ellipsis.circle")
          }
        }

        audioFileStatus
        if !playbackTrackOptions.isEmpty {
          unifiedAudioPlayer
        }
        if let voiceSegments = record.voiceSegments, !voiceSegments.isEmpty {
          voiceSegmentList(voiceSegments)
        }

        if let transcript = record.transcript, !transcript.isEmpty {
          let readableTranscript = normalizedTranscript
          let readableTranscriptChunks = normalizedTranscriptChunks
          section("原文", systemImage: "text.alignleft") {
            VStack(alignment: .leading, spacing: 10) {
              Label(transcriptSourceLabel, systemImage: "text.quote")
                .font(.caption)
                .foregroundStyle(.secondary)
              ScrollView {
                if isLoadingTranscript && readableTranscript.isEmpty {
                  HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("正在准备原文…")
                      .foregroundStyle(.secondary)
                  }
                } else {
                  LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(readableTranscriptChunks.enumerated()), id: \.offset) {
                      _, chunk in
                      Text(chunk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                  }
                }
              }
              .textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.trailing, 8)
              .frame(minHeight: 180, idealHeight: 260, maxHeight: 320)
              HStack(spacing: 8) {
                ActionFeedbackButton {
                  appState.copyTranscript(readableTranscript)
                  return .success("已复制原文")
                } label: {
                  Label("复制原文", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .disabled(readableTranscript.isEmpty)
                ActionFeedbackButton {
                  if appState.pasteTranscript(for: record) {
                    return .success("已粘贴")
                  }
                  return .failure(appState.errorMessage ?? "粘贴未完成")
                } label: {
                  Label("粘贴到当前应用", systemImage: "rectangle.on.rectangle")
                }
                .buttonStyle(.bordered)
                .disabled(readableTranscript.isEmpty)
              }
              .controlSize(.small)
            }
          }
          if let segments = record.transcriptSegments, !segments.isEmpty {
            section("时间戳片段", systemImage: "clock") {
              ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                  ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    let readableSegmentText = TranscriptTextNormalizer.normalize(segment.text)
                    Button {
                      playback.play(url: appState.audioURL(for: record))
                      playback.seek(to: segment.start)
                    } label: {
                      HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: "play.circle")
                          .foregroundStyle(.tint)
                        Text(timestamp(segment.start))
                          .font(.caption.monospacedDigit())
                          .foregroundStyle(.secondary)
                          .frame(width: 48, alignment: .leading)
                        if record.meetingTranscriptionMode == .sourceSeparated,
                          let sourceTrack = segment.sourceTrack
                        {
                          Text(sourceTrack.label)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.tint)
                            .frame(width: 64, alignment: .leading)
                        }
                        Text(readableSegmentText)
                          .frame(maxWidth: .infinity, alignment: .leading)
                      }
                      .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!appState.audioFileExists(for: record))
                    .accessibilityLabel("播放 \(timestamp(segment.start)) 的片段：\(readableSegmentText)")
                  }
                }
                .padding(.trailing, 8)
              }
              .frame(minHeight: 180, idealHeight: 300, maxHeight: 360)
            }
          }
        } else {
          section("原文", systemImage: "text.alignleft") {
            VStack(alignment: .leading, spacing: 10) {
              Text(untranscribedMessage)
                .foregroundStyle(.secondary)
              Button(
                appState.canTranscribe ? (record.processingError == nil ? "开始转写" : "重新转写") : "选择模型"
              ) {
                appState.retryProcessing(for: record)
              }
              .buttonStyle(.borderedProminent)
              .disabled(!appState.canTranscribe || !appState.canMutateRecordings)
              Text(
                "本机模型：\(appState.localASRModel.displayName) · 版本 \(appState.localASRModel.version)"
              )
              .font(.caption)
              .foregroundStyle(.secondary)
              if record.voiceSegments?.isEmpty == false {
                Button("按声音片段转写") { appState.requestSegmentTranscription(for: record) }
                  .buttonStyle(.bordered)
                  .disabled(!appState.canMutateRecordings)
              }
              if !appState.hasInstalledLocalModelPack {
                RecommendedModelInstallCard(entryPoint: .material, recordingID: record.id)
              }
            }
          }
        }

        if record.transcriptArtifacts.count > 1 {
          transcriptVersionList
        }

        if !record.processingTasks.isEmpty {
          processingTaskStatus
        }

        #if !WOICE_APP_STORE
          if StoreCapabilityProfile.current.allowsExternalAgentConnector,
            !agentResultJobs.isEmpty
          {
            section("Agent 结果", systemImage: "arrow.down.doc") {
              VStack(alignment: .leading, spacing: 12) {
                ForEach(agentResultJobs) { job in
                  if let artifact = job.resultArtifact {
                    VStack(alignment: .leading, spacing: 8) {
                      HStack {
                        Label(
                          "\(AgentCLIAdapterCatalog.userFacingDisplayName(for: artifact.connectorID)) \(artifact.connectorVersion)",
                          systemImage: artifact.kind == .markdown ? "doc.richtext" : "doc.text"
                        )
                        .font(.callout.weight(.semibold))
                        Spacer()
                        Text(artifact.createdAt, style: .relative)
                          .font(.caption)
                          .foregroundStyle(.secondary)
                      }
                      Text(artifact.preview.isEmpty ? "结果已保存，暂无预览。" : artifact.preview)
                        .font(.body.monospaced())
                        .lineLimit(8)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                      HStack(spacing: 8) {
                        ActionFeedbackButton {
                          appState.copyAgentResultPreview(artifact)
                          return .success("已复制 Agent 结果预览")
                        } label: {
                          Label("复制预览", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.bordered)
                        ActionFeedbackButton {
                          _ = appState.revealAgentResult(artifact)
                          return .success("已在 Finder 中显示 Agent 结果")
                        } label: {
                          Label("在 Finder 中显示", systemImage: "folder")
                        }
                        .buttonStyle(.bordered)
                      }
                      .controlSize(.small)
                    }
                    .padding(12)
                    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
                  }
                }
              }
            }
          }
        #endif

        if let markdown = record.generatedMarkdown, !markdown.isEmpty {
          section("AI 笔记", systemImage: "sparkles") {
            structuredNote(markdown: markdown)
          }
        } else if record.transcript?.isEmpty == false {
          section("AI 笔记", systemImage: "sparkles") {
            VStack(alignment: .leading, spacing: 10) {
              Text(
                appState.settings.llmEndpoint.isEmpty
                  ? "还没有配置 Markdown 笔记 API。" : "原文已保存，可按需生成摘要、要点和待办。"
              )
              .foregroundStyle(.secondary)
              if !appState.settings.llmEndpoint.isEmpty {
                Button("生成 Markdown 笔记") { appState.requestMarkdown(for: record) }
                  .buttonStyle(.bordered)
                  .disabled(!appState.canMutateRecordings)
              }
            }
          }
        }

        if let processingError = record.processingError, record.transcript?.isEmpty == false {
          section("处理提示", systemImage: "exclamationmark.triangle") {
            VStack(alignment: .leading, spacing: 10) {
              Label(processingError, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
              if record.generatedMarkdown == nil {
                Button("重试 Markdown 笔记") { appState.requestMarkdown(for: record) }
                  .buttonStyle(.bordered)
                  .disabled(appState.settings.llmEndpoint.isEmpty || !appState.canMutateRecordings)
              }
            }
          }
        }

        if let exportedURL {
          Label("已导出到 \(exportedURL.path)", systemImage: "checkmark.circle.fill")
            .font(.caption).foregroundStyle(.green)
            .textSelection(.enabled)
        }
      }
      .padding(28)
    }
    .navigationTitle("录音详情")
    #if !WOICE_APP_STORE
      .sheet(isPresented: $isShowingAgentDispatch) {
        AgentDispatchSheet(record: record)
        .environment(appState)
      }
    #endif
    .alert("将素材移到废纸篓？", isPresented: $isConfirmingDeletion) {
      Button("取消", role: .cancel) {}
      Button("移到废纸篓", role: .destructive) {
        playback.stop()
        _ = appState.moveToTrash(record: record)
      }
    } message: {
      Text("“\(record.displayTitle)”的原音频、原文和相关本机文件会一起移到 macOS 废纸篓，可从 Finder 恢复。")
    }
    .onDisappear {
      playback.stop()
    }
    .onAppear {
      MaterialPerformanceInstrumentation.event(.transcriptViewport)
      titleDraft = record.displayTitle
      if playbackTrackOptions.contains(where: { $0.kind == .meetingMix }) {
        selectedPlaybackTrack = .meetingMix
      } else if !playbackTrackOptions.contains(where: { $0.kind == selectedPlaybackTrack }),
        let first = playbackTrackOptions.first
      {
        selectedPlaybackTrack = first.kind
      }
    }
    .task(id: transcriptFingerprint) {
      guard let rawTranscript = record.transcript, !rawTranscript.isEmpty else {
        normalizedTranscript = ""
        normalizedTranscriptChunks = []
        isLoadingTranscript = false
        return
      }
      isLoadingTranscript = true
      let normalizedResult = await Task.detached(priority: .utility) {
        let normalized = TranscriptTextNormalizer.normalize(rawTranscript)
        return (normalized, TranscriptTextNormalizer.chunks(normalized))
      }.value
      guard !Task.isCancelled else { return }
      normalizedTranscript = normalizedResult.0
      normalizedTranscriptChunks = normalizedResult.1
      isLoadingTranscript = false
    }
    .task(id: audioMetadataFingerprint) {
      audioMetadata = await appState.loadAudioMetadata(for: record)
    }
  }

  private var transcriptFingerprint: String {
    let activeArtifactID = record.activeTranscriptArtifactID?.uuidString ?? ""
    return
      "\(record.id.uuidString):\(record.transcript?.utf8.count ?? 0):\(record.transcriptArtifacts.count):\(activeArtifactID)"
  }

  private var audioMetadataFingerprint: String {
    let systemFileName = record.systemAudioFileName ?? ""
    let meetingMixFileName = record.meetingMixFileName ?? ""
    return "\(record.id.uuidString):\(record.audioFileName):\(systemFileName):\(meetingMixFileName)"
  }

  private func hasAudioFile(_ track: AudioTrackKind) -> Bool {
    if let metadata = audioMetadata[track] { return metadata.exists }
    switch track {
    case .microphone: return appState.microphoneAudioFileExists(for: record)
    case .systemAudio: return appState.systemAudioFileExists(for: record)
    case .meetingMix: return appState.meetingMixFileExists(for: record)
    }
  }

  private var hasPrimaryAudioFile: Bool {
    record.audioFileName != record.systemAudioFileName
      ? hasAudioFile(.microphone)
      : hasAudioFile(.systemAudio)
  }

  private var primaryAudioByteCount: Int64? {
    let track: AudioTrackKind =
      record.audioFileName != record.systemAudioFileName ? .microphone : .systemAudio
    return audioMetadata[track]?.byteCount ?? appState.audioFileSize(for: record)
  }

  private func saveTitle() {
    if appState.renameRecording(recordID: record.id, title: titleDraft) {
      isEditingTitle = false
    }
  }

  private func cancelTitleEditing() {
    titleDraft = record.displayTitle
    isEditingTitle = false
  }

  private var agentResultJobs: [AgentDispatchJob] {
    appState.agentDispatchJobs.filter {
      $0.resultArtifact?.parentRecordingID == record.id && $0.resultArtifact != nil
    }
  }

  private func exportButton(_ kind: RecordingExportKind) -> some View {
    Button {
      exportedURL = appState.exportMaterial(for: record, kind: kind)
    } label: {
      Label(kind.title, systemImage: kind.systemImage)
    }
  }

  private func structuredNote(markdown: String) -> some View {
    let sections = MarkdownRenderer.sections(from: markdown)
    return VStack(alignment: .leading, spacing: 12) {
      if !sections.summary.isEmpty {
        noteList("要点", systemImage: "list.bullet", items: sections.summary, tint: .accentColor)
      }
      if !sections.todos.isEmpty {
        noteList(
          "待办", systemImage: "checklist", items: sections.todos, tint: .orange)
      } else if sections.hasTodoSection {
        noteList(
          "待办", systemImage: "checklist", items: ["暂无待办"], tint: .secondary)
      }
      if sections.hasStructuredContent {
        Divider()
      }
      if sections.hasStructuredContent {
        DisclosureGroup("查看 Markdown 原文") {
          Text(markdown)
            .textSelection(.enabled)
            .font(.body.monospaced())
            .padding(.top, 6)
        }
      } else {
        Text(markdown)
          .textSelection(.enabled)
          .font(.body.monospaced())
      }
    }
    .accessibilityElement(children: .contain)
  }

  private func noteList(
    _ title: String, systemImage: String, items: [String], tint: Color
  ) -> some View {
    VStack(alignment: .leading, spacing: 7) {
      Label(title, systemImage: systemImage)
        .font(.callout.weight(.semibold))
        .foregroundStyle(tint)
      ForEach(Array(items.enumerated()), id: \.offset) { _, item in
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Image(systemName: title == "待办" ? "circle" : "checkmark")
            .font(.caption)
            .foregroundStyle(tint)
          Text(item)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
    }
  }

  private struct PlaybackTrackOption: Identifiable {
    let kind: AudioTrackKind
    let title: String
    let systemImage: String
    let url: URL
    let fallbackDuration: TimeInterval

    var id: AudioTrackKind { kind }
  }

  private var playbackTrackOptions: [PlaybackTrackOption] {
    var options: [PlaybackTrackOption] = []
    if hasAudioFile(.microphone) {
      options.append(
        PlaybackTrackOption(
          kind: .microphone,
          title: "麦克风",
          systemImage: "mic.fill",
          url: appState.audioURL(for: record),
          fallbackDuration: audioMetadata[.microphone]?.duration ?? record.duration))
    }
    if let url = appState.systemAudioURL(for: record), hasAudioFile(.systemAudio) {
      options.append(
        PlaybackTrackOption(
          kind: .systemAudio,
          title: "电脑声音",
          systemImage: "speaker.wave.2.fill",
          url: url,
          fallbackDuration: audioMetadata[.systemAudio]?.duration
            ?? record.systemAudioDuration ?? record.duration))
    }
    if hasAudioFile(.meetingMix) {
      let url = appState.meetingMixURL(for: record)
      options.append(
        PlaybackTrackOption(
          kind: .meetingMix,
          title: "会议合成",
          systemImage: "waveform.and.mic",
          url: url,
          fallbackDuration: audioMetadata[.meetingMix]?.duration ?? record.duration))
    }
    return options
  }

  private var selectedPlaybackOption: PlaybackTrackOption? {
    playbackTrackOptions.first(where: { $0.kind == selectedPlaybackTrack })
      ?? playbackTrackOptions.first
  }

  private var unifiedAudioPlayer: some View {
    section("音频回放", systemImage: "waveform") {
      VStack(alignment: .leading, spacing: 12) {
        HStack(spacing: 8) {
          ForEach(playbackTrackOptions) { option in
            Button {
              if selectedPlaybackTrack != option.kind {
                playback.stop()
                selectedPlaybackTrack = option.kind
              }
            } label: {
              Label(option.title, systemImage: option.systemImage)
            }
            .buttonStyle(.borderedProminent)
            .tint(
              selectedPlaybackTrack == option.kind
                ? Color.accentColor : Color.secondary.opacity(0.35)
            )
            .accessibilityValue(selectedPlaybackTrack == option.kind ? "已选择" : "未选择")
          }
        }
        if let option = selectedPlaybackOption {
          Text(playbackTrackDescription(for: option.kind))
            .font(.caption)
            .foregroundStyle(.secondary)
          HStack(spacing: 12) {
            Button {
              playback.toggle(url: option.url)
            } label: {
              let isCurrentPlaying = playback.isPlaying && playback.currentURL == option.url
              Label(
                isCurrentPlaying ? "暂停" : "播放",
                systemImage: isCurrentPlaying ? "pause.fill" : "play.fill")
            }
            .buttonStyle(.borderedProminent)
            Button("停止") { playback.stop() }
              .disabled(!playback.isPlaying && playback.currentTime == 0)
            Spacer()
            Text(
              "\(formatDuration(playback.currentTime)) / \(formatDuration(playback.duration > 0 ? playback.duration : option.fallbackDuration))"
            )
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
          }
          Slider(
            value: Binding(
              get: { playback.currentURL == option.url ? playback.currentTime : 0 },
              set: { playback.seek(to: $0) }
            ),
            in:
              0...max(
                playback.duration > 0 ? playback.duration : option.fallbackDuration, 0.01)
          )
          .disabled(playback.currentURL != option.url || playback.duration <= 0)
          .accessibilityLabel("\(option.title)播放位置")
          if let error = playback.errorMessage {
            Label(error, systemImage: "exclamationmark.triangle.fill")
              .font(.caption)
              .foregroundStyle(.red)
          }
        }
      }
    }
  }

  private func playbackTrackDescription(for kind: AudioTrackKind) -> String {
    switch kind {
    case .microphone:
      return "麦克风原始音轨，只在本机按需加载和播放。"
    case .systemAudio:
      return "电脑播放的视频、会议或其他系统声音，只在本机按需加载和播放。"
    case .meetingMix:
      return "麦克风与电脑声音的会议合成文件，用于完整回放和标准模式转写。"
    }
  }

  private var audioPlayer: some View {
    section("我的声音（麦克风）", systemImage: "mic.fill") {
      VStack(alignment: .leading, spacing: 10) {
        trackBadge("原始音轨", systemImage: "waveform")
        HStack(spacing: 12) {
          Button {
            playback.toggle(url: appState.audioURL(for: record))
          } label: {
            Label(
              playback.isPlaying ? "暂停" : "播放",
              systemImage: playback.isPlaying ? "pause.fill" : "play.fill")
          }
          .buttonStyle(.borderedProminent)
          .disabled(!appState.audioFileExists(for: record))

          Button("停止") { playback.stop() }
            .disabled(!playback.isPlaying && playback.currentTime == 0)
          Spacer()
          Text("\(formatDuration(playback.currentTime)) / \(formatDuration(playback.duration))")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }

        Slider(
          value: Binding(
            get: { playback.currentTime },
            set: { playback.seek(to: $0) }
          ),
          in: 0...max(playback.duration, 0.01)
        )
        .disabled(playback.duration <= 0)
        .accessibilityLabel("录音播放位置")
        .accessibilityValue(
          "\(formatDuration(playback.currentTime)) / \(formatDuration(playback.duration))")

        if let error = playback.errorMessage {
          Label(error, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.red)
        } else {
          Text("麦克风原始音轨只在本机播放，不会发送到网络。")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }
  }

  private var meetingMixPlayer: some View {
    section("会议完整回放", systemImage: "waveform.path.ecg") {
      VStack(alignment: .leading, spacing: 10) {
        trackBadge("合成回放", systemImage: "waveform.and.mic")
        Label(
          record.meetingTranscriptionMode == .standardMix
            ? "由我的声音和电脑声音合成，标准模式只转写一次。"
            : "由两条原始音轨合成，仅用于完整复听。",
          systemImage: "info.circle"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        HStack(spacing: 12) {
          Button {
            playback.toggle(url: appState.meetingMixURL(for: record))
          } label: {
            Label(
              playback.isPlaying && playback.currentURL == appState.meetingMixURL(for: record)
                ? "暂停" : "播放",
              systemImage: playback.isPlaying
                && playback.currentURL == appState.meetingMixURL(for: record)
                ? "pause.fill" : "play.fill")
          }
          .buttonStyle(.borderedProminent)
          .disabled(!appState.meetingMixFileExists(for: record))
          Button("停止") { playback.stop() }
            .disabled(!playback.isPlaying && playback.currentTime == 0)
          Spacer()
          Text(
            "\(formatDuration(playback.currentTime)) / \(formatDuration(playback.duration > 0 ? playback.duration : record.duration))"
          )
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
        }
        Slider(
          value: Binding(
            get: { playback.currentTime },
            set: { playback.seek(to: $0) }
          ), in: 0...max(playback.duration > 0 ? playback.duration : record.duration, 0.01)
        )
        .disabled(
          playback.currentURL != appState.meetingMixURL(for: record) || playback.duration <= 0
        )
        .accessibilityLabel("会议回放进度")
      }
    }
  }

  private var processingTaskStatus: some View {
    section("处理任务", systemImage: "arrow.triangle.2.circlepath") {
      VStack(alignment: .leading, spacing: 9) {
        ForEach(record.processingTasks, id: \.idempotencyKey) { task in
          HStack(alignment: .firstTextBaseline, spacing: 8) {
            Label(task.kind.label, systemImage: task.status.systemImage)
            Spacer()
            Text(task.status.label)
              .font(.caption)
              .foregroundStyle(task.status == .failed ? .orange : .secondary)
            if task.status.isRetryable {
              Button("重试") { appState.retryProcessing(for: record) }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!appState.canMutateRecordings)
            }
          }
          if let reason = task.blockReason {
            Label(reason.label, systemImage: "info.circle")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          if let lastError = task.lastError, !lastError.isEmpty {
            Text(lastError)
              .font(.caption)
              .foregroundStyle(.secondary)
              .textSelection(.enabled)
          }
          if let providerID = task.providerID, let modelID = task.modelID {
            VStack(alignment: .leading, spacing: 2) {
              Text("模型：\(modelID)")
              if let version = task.modelVersion {
                Text("版本：\(version)")
              }
              if let location = task.dataLocation {
                Text("位置：\(location.label)")
              }
              Text("Provider：\(providerID)")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .textSelection(.enabled)
          }
        }
        Text("任务状态保存在本机；授权、模型或本机服务恢复后可重试，外部服务仍需再次确认外发。")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  private var transcriptVersionList: some View {
    let currentID = record.activeTranscriptArtifactID ?? record.transcriptArtifacts.last?.id
    return section("原文版本", systemImage: "clock.arrow.circlepath") {
      VStack(alignment: .leading, spacing: 8) {
        Text("重转写会生成新版本；旧原文和模型快照仍保留在本机。")
          .font(.caption)
          .foregroundStyle(.secondary)
        ForEach(Array(record.transcriptArtifacts.reversed())) { artifact in
          HStack(alignment: .top, spacing: 8) {
            Image(
              systemName: artifact.id == currentID
                ? "checkmark.circle.fill" : "circle"
            )
            .foregroundStyle(artifact.id == currentID ? Color.green : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
              Text(artifact.id == currentID ? "当前版本" : "转写版本")
                .font(.callout.weight(.medium))
              Text(artifact.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
              if let modelID = artifact.modelID {
                Text(
                  "模型：\(modelID)\(artifact.modelVersion.map { " · \($0)" } ?? "")"
                )
                .font(.caption2)
                .foregroundStyle(.tertiary)
              }
              if let sourceTrack = artifact.sourceTrack {
                Text("来源：\(sourceTrack.label)")
                  .font(.caption2)
                  .foregroundStyle(.tertiary)
              }
            }
            Spacer()
            if artifact.id != currentID {
              Button("查看") {
                _ = appState.selectTranscriptArtifact(
                  recordID: record.id, artifactID: artifact.id)
              }
              .buttonStyle(.bordered)
              .controlSize(.small)
              .disabled(!appState.canMutateRecordings)
            }
          }
          .accessibilityElement(children: .combine)
          .accessibilityValue(artifact.id == currentID ? "当前显示" : "可切换")
        }
      }
    }
  }

  private var untranscribedMessage: String {
    if let processingError = record.processingError { return processingError }
    if record.processingTasks.contains(where: { $0.status == .waitingForModel }) {
      return "还没有选择语言转文字模型；录音已安全保存在本机。"
    }
    return "还没有转写原文；可以使用本机模型，或在设置中选择外部语言转文字服务。"
  }

  private var transcriptSourceLabel: String {
    if record.meetingTranscriptionMode == .sourceSeparated {
      return "当前转写来源：两条原始音轨分别转写"
    }
    if record.meetingMixFileName != nil {
      return "当前转写来源：会议完整回放"
    }
    if record.systemAudioFileName != nil {
      return "当前转写来源：我的声音 + 电脑声音"
    }
    return "当前转写来源：我的声音（麦克风）"
  }

  private func voiceSegmentList(_ segments: [VoiceSegment]) -> some View {
    section("转写分析", systemImage: "waveform.path") {
      VStack(alignment: .leading, spacing: 8) {
        DisclosureGroup("检测到的有声片段") {
          Text("这不是独立录音，也不是转写文本。")
            .font(.caption)
            .foregroundStyle(.secondary)
          ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
            Button {
              playback.play(url: appState.audioURL(for: record))
              playback.seek(to: segment.start)
            } label: {
              HStack(spacing: 10) {
                Image(systemName: "play.circle")
                  .foregroundStyle(.tint)
                Text("片段 \(index + 1)")
                  .font(.caption)
                Text("\(timestamp(segment.start))–\(timestamp(segment.end))")
                  .font(.caption.monospacedDigit())
                  .foregroundStyle(.secondary)
                Spacer()
                Text(formatDuration(segment.duration))
                  .font(.caption2.monospacedDigit())
                  .foregroundStyle(.secondary)
              }
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!appState.audioFileExists(for: record))
            .accessibilityLabel(
              "播放声音片段 \(index + 1)，从 \(timestamp(segment.start)) 到 \(timestamp(segment.end))"
            )
          }
        }
      }
    }
  }

  private var systemAudioPlayer: some View {
    section("电脑声音", systemImage: "speaker.wave.2") {
      if let url = appState.systemAudioURL(for: record), appState.systemAudioFileExists(for: record)
      {
        VStack(alignment: .leading, spacing: 10) {
          trackBadge("原始音轨", systemImage: "speaker.wave.2")
          Label(systemAudioCaptureTitle, systemImage: "checkmark.circle.fill")
            .foregroundStyle(.green)
          if let target = record.systemAudioCaptureTarget, target != .display {
            Label(
              "当前没有可共享显示器，本次只保存活动窗口声音，不代表全系统输出。",
              systemImage: "info.circle"
            )
            .font(.caption)
            .foregroundStyle(.orange)
          }
          Text("录音期间电脑播放的视频、会议或其他系统声音；来源分离模式会单独转写并标注来源。")
            .font(.caption)
            .foregroundStyle(.secondary)
          if let evidence = systemAudioEvidence {
            Label(evidence, systemImage: "waveform")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          HStack(spacing: 12) {
            Button {
              playback.toggle(url: url)
            } label: {
              Label(
                playback.isPlaying && playback.currentURL == url ? "暂停" : "播放",
                systemImage: playback.isPlaying && playback.currentURL == url
                  ? "pause.fill" : "play.fill")
            }
            .buttonStyle(.bordered)
            Button("停止") { playback.stop() }
              .disabled(!playback.isPlaying && playback.currentTime == 0)
            Spacer()
            Text(
              "\(formatDuration(playback.currentTime)) / \(formatDuration(playback.duration > 0 ? playback.duration : (record.systemAudioDuration ?? record.duration)))"
            )
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
          }
          Slider(
            value: Binding(
              get: { playback.currentTime },
              set: { playback.seek(to: $0) }
            ),
            in:
              0...max(
                playback.duration > 0
                  ? playback.duration : (record.systemAudioDuration ?? record.duration), 0.01)
          )
          .disabled(playback.currentURL != url || playback.duration <= 0)
          if let error = playback.errorMessage {
            Label(error, systemImage: "exclamationmark.triangle.fill")
              .font(.caption)
              .foregroundStyle(.red)
          } else {
            Text("电脑声音原始音轨只在本机播放。")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      } else {
        Label(
          record.systemAudioError ?? "系统声音文件缺失，麦克风原始录音仍然保留。",
          systemImage: "exclamationmark.triangle.fill"
        )
        .font(.caption)
        .foregroundStyle(.orange)
      }
    }
  }

  private var systemAudioEvidence: String? {
    guard let bufferCount = record.systemAudioBufferCount else { return nil }
    guard let peakLevel = record.systemAudioPeakLevel else {
      return "已写入 \(bufferCount) 个系统音频缓冲"
    }
    if peakLevel <= 0.0001 {
      return "已收到 \(bufferCount) 个缓冲，但未检测到可听见的系统输出"
    }
    let percentage = Int((min(max(peakLevel, 0), 1) * 100).rounded())
    return "已收到 \(bufferCount) 个缓冲 · 峰值约 \(percentage)%"
  }

  private var systemAudioCaptureTitle: String {
    if let target = record.systemAudioCaptureTarget {
      return "已获取\(target.label)"
    }
    return "已获取系统输出"
  }

  @ViewBuilder
  private var audioFileStatus: some View {
    section(
      record.sourceKind == .recorded ? "原始录音" : "原始素材",
      systemImage: record.sourceKind.systemImage
    ) {
      if hasPrimaryAudioFile {
        VStack(alignment: .leading, spacing: 8) {
          Label("已保存到本机", systemImage: "checkmark.circle.fill")
            .foregroundStyle(.green)
          Label(record.materialStatus.label, systemImage: record.materialStatus.systemImage)
            .foregroundStyle(materialStatusColor)
          Label("录音素材", systemImage: record.sourceKind.systemImage)
            .font(.caption)
            .foregroundStyle(.secondary)
          if let originalFileName = record.originalMediaFileName {
            Text("原件：\(originalFileName)")
              .font(.caption)
              .foregroundStyle(.secondary)
              .textSelection(.enabled)
          }
          if let originalSHA256 = record.originalMediaSHA256 {
            Text("原件 SHA-256：\(originalSHA256)")
              .font(.caption.monospaced())
              .foregroundStyle(.tertiary)
              .textSelection(.enabled)
          }
          HStack {
            Button("在 Finder 中显示") { appState.revealAudioFile(for: record) }
            Spacer()
            Text(record.audioFileName).font(.caption).foregroundStyle(.tertiary)
          }
          DisclosureGroup("技术详情") {
            if let size = primaryAudioByteCount {
              Text("原始文件大小：\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Text("文件名：\(record.audioFileName)")
              .font(.caption)
              .foregroundStyle(.tertiary)
              .textSelection(.enabled)
          }
        }
      } else {
        Label("文件缺失，无法播放或转写", systemImage: "exclamationmark.triangle.fill")
          .foregroundStyle(.red)
      }
    }
    .onAppear { MaterialPerformanceInstrumentation.event(.audioMetadata) }
  }

  private var materialStatusColor: Color {
    switch record.materialStatus {
    case .ready: .green
    case .failed, .partiallyReady: .orange
    case .processing, .waitingForModel: .accentColor
    case .saved: .secondary
    }
  }

  private func section<Content: View>(
    _ title: String, systemImage: String, @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Label(title, systemImage: systemImage).font(.headline)
      content()
        .padding(14)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
    }
  }

  private func trackBadge(_ title: String, systemImage: String) -> some View {
    Label(title, systemImage: systemImage)
      .font(.caption.weight(.semibold))
      .foregroundStyle(.secondary)
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(.quaternary, in: Capsule())
      .accessibilityLabel(title)
  }

  private func timestamp(_ seconds: TimeInterval) -> String {
    let totalSeconds = max(0, Int(seconds.rounded()))
    return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
  }
}
