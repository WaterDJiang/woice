# CLI 默认文字交付与素材删除交互

> 状态：已实现；真实界面只读 Journey 与稳定签名安装通过

## 目标

- 外部 CLI 默认只接收用户确认的规范化原文和任务说明，不强制复制或发送 WAV。
- 素材列表提供可发现、可键盘操作且不会误触的删除入口。
- 删除进入 macOS 废纸篓；任何失败都保留或恢复素材索引与原文件。

## 范围

- `ContextPackage` 默认只包含 `transcript.md`、`context.json` 和 Transcript Artifact 引用。
- CLI 派发 UI、确认文案、审计 `dataTypes` 和权限摘要均只声明文字。
- 素材列表提供尾部侧滑、右键菜单、选中后的删除按钮和 Delete 键。
- 侧滑禁止 full swipe；所有入口先显示同一确认框，再执行“移到废纸篓”。
- 详情页已有删除入口也改为同一确认与废纸篓语义。

## 不在本轮

- 不删除 `ContextPackageBuilder` 的显式音频打包能力；未来只有用户单独选择并确认音频时才复用。
- 不增加批量删除、自动清空废纸篓或永久删除。
- 不删除 Agent 结果或其他 Recording 的文件。

## 验收标准

- AC-001：默认 CLI 派发不检查 WAV 是否存在，只有原文即可创建任务。
- AC-002：默认 Context Package 的 Artifact/File 清单都不含 `.audio`，审计仅记录 `.transcript`。
- AC-003：派发页面只显示并确认“规范化原文”，不再出现“麦克风 WAV”。
- AC-004：素材行支持侧滑和右键“移到废纸篓”；选中素材后显示删除按钮，Delete 键使用同一路径。
- AC-005：侧滑 `allowsFullSwipe = false`，删除前明确显示素材标题、原音频和原文会一起进入废纸篓。
- AC-006：移动、索引持久化或系统废纸篓任一步失败时，素材仍在列表且原路径可读；成功后可在 macOS 废纸篓恢复打包目录。
- AC-007：删除不影响其他 Recording、下载模型、设置或 Keychain。

## 影响面

- `Sources/WoiceApp/AppState.swift`
- `Sources/WoiceApp/AgentDispatchSheet.swift`
- `Sources/WoiceApp/WorkspaceView.swift`
- `Sources/WoiceApp/RecordingDetailView.swift`
- `Tests/WoiceAppTests/AgentDispatchTests.swift`
- `Tests/WoiceAppTests/AppStateRecordingIntegrationTests.swift`
