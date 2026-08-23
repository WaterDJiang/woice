#!/bin/zsh
set -euo pipefail

workspace_file="${0:A:h}/../Sources/WoiceApp/WorkspaceView.swift"
[[ -f "$workspace_file" ]] || { echo "workspace acceptance: missing WorkspaceView.swift"; exit 1; }
rg -q 'NavigationSplitView \{' "$workspace_file"
rg -q 'WorkspaceSidebar\(' "$workspace_file"
rg -q 'frame\(minWidth: 280, idealWidth: 320, maxWidth: 360\)' "$workspace_file"
rg -q 'WorkspaceLibraryEmptyState' "$workspace_file"
rg -q '导入音视频' "$workspace_file"
rg -q 'accessibilityReduceMotion' "$workspace_file"
rg -q 'accessibilityLabel' "$workspace_file"
rg -q 'accessibilityHint' "$workspace_file"
rg -q 'ProcessingTaskProjection\.activeTask\(in: record\.processingTasks\)' "$workspace_file"
rg -q 'ProcessingTaskProjection\.resumableTask\(in: record\.processingTasks\)' "$workspace_file"
rg -Fq 'accessibilityLabel("等待确认的外部处理任务：\(request.confirmationTitle)")' "$workspace_file"
rg -q 'keyboardShortcut' "$workspace_file"
rg -Fq 'return "\(shortcut.displayName) 当前可注册，保存本页后生效。"' Sources/WoiceApp/ShortcutRecorderField.swift
rg -q 'frame\(minWidth: 280, idealWidth: 320, maxWidth: 360\)' "$workspace_file"
echo "acceptance-workspace-sidebar: source contract passed; real screenshot/VoiceOver/high-contrast journey remains required"
