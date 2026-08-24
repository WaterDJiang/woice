#!/bin/zsh
set -euo pipefail

workspace_file="${0:A:h}/../Sources/WoiceApp/WorkspaceView.swift"
[[ -f "$workspace_file" ]] || { echo "workspace acceptance: missing WorkspaceView.swift"; exit 1; }
rg -q 'NavigationSplitView \{' "$workspace_file"
rg -q 'WorkspaceSidebar\(' "$workspace_file"
layout_file="${0:A:h}/../Sources/WoiceCore/WorkspaceSidebarLayout.swift"
[[ -f "$layout_file" ]] || { echo "workspace acceptance: missing WorkspaceSidebarLayout.swift"; exit 1; }
rg -q 'minimumWidth: Double = 280' "$layout_file"
rg -q 'idealWidth: Double = 320' "$layout_file"
rg -q 'maximumWidth: Double = 360' "$layout_file"
rg -q 'minWidth: WorkspaceSidebarLayout\.minimumWidth' "$workspace_file"
rg -q 'idealWidth: WorkspaceSidebarLayout\.idealWidth' "$workspace_file"
rg -q 'maxWidth: WorkspaceSidebarLayout\.maximumWidth' "$workspace_file"
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
rg -q 'WorkspaceSidebarLayout\.minimumWidth' "$workspace_file"
echo "acceptance-workspace-sidebar: source contract passed; real screenshot/VoiceOver/high-contrast journey remains required"
