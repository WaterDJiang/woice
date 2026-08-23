#!/bin/zsh
set -euo pipefail

script_dir="$(dirname "$0")"
cd "$script_dir/.."
rg -q 'accessibilityReduceMotion' Sources/WoiceApp
rg -q 'accessibilityLabel' Sources/WoiceApp/WorkspaceView.swift
rg -q 'accessibilityHint' Sources/WoiceApp/WorkspaceView.swift

if [[ "${WOICE_RUN_ACCESSIBILITY_JOURNEY:-0}" != "1" ]]; then
  echo "acceptance-accessibility-runtime: contract passed; set WOICE_RUN_ACCESSIBILITY_JOURNEY=1 for System Events AX tree check"
  exit 0
fi

app_path="${WOICE_ACCESSIBILITY_APP_PATH:-/Applications/Woice.app}"
[[ -d "$app_path" ]] || {
  echo "acceptance-accessibility-runtime: app not found: $app_path" >&2
  exit 1
}
/usr/bin/open -a "$app_path"

workspace_window_title() {
  /usr/bin/osascript <<'APPLESCRIPT' 2>/dev/null || true
tell application "System Events"
  tell process "Woice"
    set workspaceWindows to (windows whose name contains "Woice 工作台")
    if (count of workspaceWindows) is 0 then return ""
    return name of item 1 of workspaceWindows
  end tell
end tell
APPLESCRIPT
}

window_title=""
for attempt in {1..5}; do
  window_title="$(workspace_window_title)"
  [[ "$window_title" == *"Woice 工作台"* ]] && break
  /bin/sleep 1
done
[[ "$window_title" == *"Woice 工作台"* ]] || {
  echo "acceptance-accessibility-runtime: workspace window not visible: $window_title" >&2
  exit 1
}

/usr/bin/osascript <<'APPLESCRIPT'
tell application "System Events"
  tell process "Woice"
    set frontmost to true
    keystroke "1" using command down
    delay 0.5
    set workspaceWindows to (windows whose name contains "Woice 工作台")
    if (count of workspaceWindows) is 0 then error "找不到 Woice 工作台"
    set workspaceWindow to item 1 of workspaceWindows
    perform action "AXRaise" of workspaceWindow
    set sidebar to scroll area 1 of group 1 of splitter group 1 of group 1 of workspaceWindow
    set sidebarHelp to {}
    repeat with indexValue from 1 to (count of UI elements of sidebar)
      set elementRef to UI element indexValue of sidebar
      try
        set end of sidebarHelp to (help of elementRef as text)
      end try
    end repeat
    set sidebarText to sidebarHelp as text
    if sidebarText does not contain "导入音频或视频" then error "缺少导入入口的 AX help"
    if sidebarText does not contain "打开处理任务" then error "缺少处理任务入口的 AX help"
    if (count of text fields of sidebar) < 1 then error "素材搜索框未暴露为 AX text field"
  end tell
end tell
APPLESCRIPT

if [[ "${WOICE_RUN_KEYBOARD_JOURNEY:-0}" == "1" ]]; then
  /usr/bin/osascript <<'APPLESCRIPT'
tell application "System Events"
  tell process "Woice"
    set frontmost to true
    set workspaceWindows to (windows whose name contains "Woice 工作台")
    if (count of workspaceWindows) is 0 then error "找不到 Woice 工作台"
    set workspaceWindow to item 1 of workspaceWindows
    perform action "AXRaise" of workspaceWindow
    keystroke "2" using command down
    delay 1
    set foundProcessing to false
    repeat with elementRef in (get entire contents of workspaceWindow)
      try
        if (role of elementRef as text) is "AXStaticText" and (name of elementRef as text) is "处理任务" then
          set foundProcessing to true
          exit repeat
        end if
      end try
    end repeat
    if not foundProcessing then error "⌘2 未将处理任务标记为当前工作区"
  end tell
end tell
APPLESCRIPT
  echo "acceptance-accessibility-runtime: keyboard shortcut journey passed (⌘2 -> 处理任务)"
fi

echo "acceptance-accessibility-runtime: AX tree passed; window=$window_title; VoiceOver/high contrast/reduced motion remain user-run system settings"
