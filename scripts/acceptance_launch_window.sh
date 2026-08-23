#!/bin/zsh
set -euo pipefail

script_dir="$(dirname "$0")"
cd "$script_dir/.."
test -f Resources/Info.plist
if /usr/libexec/PlistBuddy -c 'Print :LSUIElement' Resources/Info.plist >/dev/null 2>&1; then
  test "$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' Resources/Info.plist)" = "false"
fi
rg -q 'WoiceWorkspaceWindowController' Sources/WoiceApp/WoiceApp.swift
rg -q 'applicationShouldHandleReopen' Sources/WoiceApp/WoiceApp.swift
rg -q 'window\.makeKeyAndOrderFront' Sources/WoiceApp/WoiceWorkspaceWindowController.swift
rg -q 'NSStatusBar\.system\.statusItem' Sources/WoiceApp/WoiceMenuBarController.swift
rg -q 'LSMultipleInstancesProhibited' Resources/Info.plist
rg -q 'navigationTitle\("Woice 工作台"\)' Sources/WoiceApp/WorkspaceView.swift
rg -Fq '麦克风输入 · \(appState.audioActivity.label)' Sources/WoiceApp/MenuBarPopover.swift
rg -Fq '有声 \(formatDuration(appState.voiceDuration))' Sources/WoiceApp/MenuBarPopover.swift
rg -Fq '时长 \(formatDuration(appState.elapsed))，麦克风 \(appState.audioActivity.label)' Sources/WoiceApp/MenuBarPopover.swift

if [[ "${WOICE_RUN_LAUNCH_JOURNEY:-0}" == "1" ]]; then
  app_path="${WOICE_LAUNCH_APP_PATH:-/Applications/Woice.app}"
  [[ -d "$app_path" ]] || { echo "acceptance-launch-window: app not found: $app_path" >&2; exit 1; }

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

  workspace_window_count() {
    /usr/bin/osascript <<'APPLESCRIPT' 2>/dev/null || true
tell application "System Events"
  tell process "Woice"
    return count of (windows whose name contains "Woice 工作台")
  end tell
end tell
APPLESCRIPT
  }

  /usr/bin/open -a "$app_path"
  /bin/sleep 1
  process_count="$(/usr/bin/pgrep -x Woice | /usr/bin/wc -l | /usr/bin/tr -d ' ')"
  [[ "$process_count" == "1" ]] || {
    echo "acceptance-launch-window: expected one Woice process, got $process_count" >&2
    exit 1
  }
  window_title=""
  for attempt in {1..5}; do
    window_title="$(workspace_window_title)"
    [[ "$window_title" == *"Woice 工作台"* ]] && break
    /bin/sleep 1
  done
  [[ "$window_title" == *"Woice 工作台"* ]] || {
    echo "acceptance-launch-window: expected Woice 工作台, got: $window_title" >&2
    exit 1
  }
  /usr/bin/osascript <<'APPLESCRIPT'
tell application "System Events"
  tell process "Woice"
    set frontmost to true
    set workspaceWindows to (windows whose name contains "Woice 工作台")
    if (count of workspaceWindows) is 0 then error "找不到 Woice 工作台"
    set workspaceWindow to item 1 of workspaceWindows
    perform action "AXRaise" of workspaceWindow
    keystroke "w" using command down
  end tell
end tell
APPLESCRIPT
  closed_window_count=""
  for attempt in {1..5}; do
    closed_window_count="$(workspace_window_count)"
    [[ "$closed_window_count" == "0" ]] && break
    /bin/sleep 1
  done
  [[ "$closed_window_count" == "0" ]] || {
    echo "acceptance-launch-window: expected workspace to close, windows=$closed_window_count" >&2
    exit 1
  }
  /usr/bin/open -a "$app_path"
  reopened_title=""
  for attempt in {1..5}; do
    reopened_title="$(workspace_window_title)"
    [[ "$reopened_title" == *"Woice 工作台"* ]] && break
    /bin/sleep 1
  done
  [[ "$reopened_title" == *"Woice 工作台"* ]] || {
    echo "acceptance-launch-window: reopen did not restore Woice 工作台, got: $reopened_title" >&2
    exit 1
  }
  reopened_process_count="$(/usr/bin/pgrep -x Woice | /usr/bin/wc -l | /usr/bin/tr -d ' ')"
  [[ "$reopened_process_count" == "1" ]] || {
    echo "acceptance-launch-window: expected one Woice process after reopen, got $reopened_process_count" >&2
    exit 1
  }
  echo "acceptance-launch-window: real launch/reopen passed; process=$reopened_process_count window=$reopened_title"
else
  echo "acceptance-launch-window: contract passed; set WOICE_RUN_LAUNCH_JOURNEY=1 for Finder/Dock/open -a runtime check"
fi
