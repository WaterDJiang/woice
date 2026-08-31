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

app_path="${WOICE_ACCESSIBILITY_APP_PATH:-/Applications/Woice (Dev).app}"
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
    set requiredHelp to {"打开素材库，快捷键 ⌘1", "打开处理任务，快捷键 ⌘2", "打开文字转音频，快捷键 ⌘3", "打开设置，快捷键 ⌘4"}
    set foundHelp to {}
    set windowPosition to position of workspaceWindow
    set windowSize to size of workspaceWindow
    repeat with elementRef in (get entire contents of workspaceWindow)
      set elementHelp to ""
      try
        set elementHelp to help of elementRef as text
      end try
      if requiredHelp contains elementHelp then
        set elementPosition to position of elementRef
        if (item 2 of elementPosition) < (item 2 of windowPosition) or (item 2 of elementPosition) ≥ ((item 2 of windowPosition) + (item 2 of windowSize)) then
          error "侧栏导航位于窗口可视区外：" & elementHelp
        end if
        set end of foundHelp to elementHelp
      end if
    end repeat
    repeat with expectedHelp in requiredHelp
      if foundHelp does not contain expectedHelp then error "缺少侧栏导航：" & expectedHelp
    end repeat
    if (count of text fields of workspaceWindow) < 1 then error "素材搜索框未暴露为 AX text field"
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
