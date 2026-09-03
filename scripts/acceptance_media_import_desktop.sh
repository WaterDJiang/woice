#!/bin/zsh
set -euo pipefail

script_dir="$(dirname "$0")"
cd "$script_dir/.."
rg -q 'MediaImportSheet' Sources/WoiceApp/WorkspaceView.swift
rg -q 'importMedia\(from' Sources/WoiceApp/MediaImportSheet.swift
rg -q 'originalFileName' Sources/WoiceApp/MediaImportService.swift
rg -q 'WOICE_TEST_STORAGE_ROOT|woice-test-storage-root' Sources/WoiceApp/WoiceTestRuntimeConfiguration.swift
rg -q 'WOICE_TEST_IMPORT_SOURCE|woice-test-import-source' Sources/WoiceApp/WoiceTestRuntimeConfiguration.swift
rg -q 'WOICE_TEST_TRANSCRIBE|woice-test-transcribe' Sources/WoiceApp/WoiceTestRuntimeConfiguration.swift
rg -q 'WOICE_TEST_PRESENT_IMPORT_SHEET|woice-test-present-import-sheet' Sources/WoiceApp/WoiceTestRuntimeConfiguration.swift
rg -q 'WOICE_TEST_TRANSCRIPTION_DELAY_SECONDS|woice-test-transcription-delay' Sources/WoiceApp/WoiceTestRuntimeConfiguration.swift
rg -q 'WOICE_MEDIA_IMPORT_EXPECT_FAILURE' scripts/acceptance_media_import_desktop.sh
rg -q 'WoiceTestRuntimeConfiguration.storageRoot' Sources/WoiceApp/Storage.swift
rg -q 'WoiceTestRuntimeConfiguration.storageRoot' Sources/WoiceApp/SingleInstanceGuard.swift
rg -q 'WoiceTestRuntimeConfiguration.usesFixtureTranscription' Sources/WoiceApp/AppState.swift
rg -q 'WoiceTestRuntimeConfiguration.importSource' Sources/WoiceApp/WoiceApp.swift

if [[ "${WOICE_RUN_MEDIA_IMPORT_JOURNEY:-0}" != "1" ]]; then
  echo "acceptance-media-import-desktop: contract passed; set WOICE_RUN_MEDIA_IMPORT_JOURNEY=1 and WOICE_MEDIA_IMPORT_SOURCE=/path/to/audio.wav for isolated desktop runtime check"
  exit 0
fi

app_path="${WOICE_MEDIA_IMPORT_APP_PATH:-/Applications/Woice (Dev).app}"
source_path="${WOICE_MEDIA_IMPORT_SOURCE:-}"
if [[ "$app_path" != /* ]]; then
  app_path="$PWD/$app_path"
fi
[[ -d "$app_path" ]] || {
  echo "acceptance-media-import-desktop: app not found: $app_path" >&2
  exit 1
}
[[ -f "$source_path" ]] || {
  echo "acceptance-media-import-desktop: source file not found: $source_path" >&2
  exit 1
}
app_binary="$app_path/Contents/MacOS/Woice"
[[ -x "$app_binary" ]] || {
  echo "acceptance-media-import-desktop: app executable not found: $app_binary" >&2
  exit 1
}
if /usr/bin/pgrep -x Woice >/dev/null 2>&1; then
  echo "acceptance-media-import-desktop: another Woice process is already running; close it before the isolated desktop Journey" >&2
  exit 1
fi

source_basename="${source_path:t}"
source_title="${source_basename%.*}"
test_root="${WOICE_MEDIA_IMPORT_STORAGE_ROOT:-}"
owns_test_root=0
if [[ -z "$test_root" ]]; then
  test_root="$(/usr/bin/mktemp -d "${TMPDIR:-/private/tmp}/woice-media-import.XXXXXX")"
  owns_test_root=1
else
  /bin/mkdir -p "$test_root"
fi
log_path="${TMPDIR:-/private/tmp}/woice-media-import-$$.log"
transcription_delay="${WOICE_MEDIA_IMPORT_TRANSCRIPTION_DELAY_SECONDS:-10}"

if [[ ! "$transcription_delay" =~ ^[0-9]+([.][0-9]+)?$ ]] || (( $(printf '%.0f' "$transcription_delay") < 1 )); then
  echo "acceptance-media-import-desktop: transcription delay must be a positive number of seconds: $transcription_delay" >&2
  exit 1
fi

cleanup() {
  /usr/bin/osascript -e 'tell application "Woice (Dev)" to quit' >/dev/null 2>&1 || true
  if [[ "$owns_test_root" == "1" ]] && [[ -d "$test_root" ]]; then
    /bin/rm -rf "$test_root"
  fi
}
trap cleanup EXIT INT TERM

/usr/bin/open -n "$app_path" --args \
  --woice-test-mode \
  --woice-test-storage-root "$test_root" \
  --woice-test-transcription fixture \
  --woice-test-import-source "$source_path" \
  --woice-test-transcribe \
  --woice-test-present-import-sheet \
  --woice-test-transcription-delay "$transcription_delay" >"$log_path" 2>&1

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
for attempt in {1..15}; do
  window_title="$(workspace_window_title)"
  [[ "$window_title" == *"Woice 工作台"* ]] && break
  /bin/sleep 1
done
[[ "$window_title" == *"Woice 工作台"* ]] || {
  echo "acceptance-media-import-desktop: workspace window did not open: $window_title; log=$log_path" >&2
  exit 1
}

sheet_text=""
background_closed=0
expected_failure="${WOICE_MEDIA_IMPORT_EXPECT_FAILURE:-0}"
if [[ "$expected_failure" == "1" ]]; then
  expected_failure_text="${WOICE_MEDIA_IMPORT_EXPECTED_ERROR:-导入失败}"
  for attempt in {1..20}; do
    sheet_text="$(/usr/bin/osascript <<'APPLESCRIPT' 2>/dev/null || true
tell application "System Events"
  tell process "Woice"
    set workspaceWindows to (windows whose name contains "Woice 工作台")
    if (count of workspaceWindows) is 0 then return ""
    return entire contents of item 1 of workspaceWindows
  end tell
end tell
APPLESCRIPT
)"
    if [[ "$sheet_text" == *"$expected_failure_text"* ]]; then
      break
    fi
    /bin/sleep 1
  done
  [[ "$sheet_text" == *"$expected_failure_text"* ]] || {
    echo "acceptance-media-import-desktop: expected import failure was not visible: expected=$expected_failure_text; log=$log_path" >&2
    exit 1
  }
  if /usr/bin/find "$test_root/recordings" -maxdepth 1 -type f \( -name '*.source.*' -o -name '*.wav' -o -name '*.m4a' \) -print -quit 2>/dev/null | /usr/bin/grep -q .; then
    echo "acceptance-media-import-desktop: failed import left a partial original or derived file" >&2
    exit 1
  fi
  echo "acceptance-media-import-desktop: expected import failure passed; source=$source_path error=$expected_failure_text isolated_root=$test_root"
  exit 0
fi

for attempt in {1..20}; do
  sheet_text="$(/usr/bin/osascript <<'APPLESCRIPT' 2>/dev/null || true
tell application "System Events"
  tell process "Woice"
    set workspaceWindows to (windows whose name contains "Woice 工作台")
    if (count of workspaceWindows) is 0 then return ""
    return entire contents of item 1 of workspaceWindows
  end tell
end tell
APPLESCRIPT
)"
  if [[ "$sheet_text" == *"转文字"* || "$sheet_text" == *"正在转写"* || "$sheet_text" == *"关闭并后台继续"* ]]; then
    break
  fi
  /bin/sleep 1
done
[[ "$sheet_text" == *"转文字"* || "$sheet_text" == *"正在转写"* || "$sheet_text" == *"关闭并后台继续"* ]] || {
  echo "acceptance-media-import-desktop: import Sheet did not reach transcribe-ready state: $sheet_text" >&2
  exit 1
}

if [[ "${WOICE_MEDIA_IMPORT_VERIFY_BACKGROUND_CLOSE:-1}" == "1" ]]; then
  for attempt in {1..20}; do
    if [[ "$sheet_text" == *"关闭并后台继续"* ]]; then
      break
    fi
    /bin/sleep 1
    sheet_text="$(/usr/bin/osascript <<'APPLESCRIPT' 2>/dev/null || true
tell application "System Events"
  tell process "Woice"
    set workspaceWindows to (windows whose name contains "Woice 工作台")
    if (count of workspaceWindows) is 0 then return ""
    return entire contents of item 1 of workspaceWindows
  end tell
end tell
APPLESCRIPT
)"
  done
  [[ "$sheet_text" == *"关闭并后台继续"* ]] || {
    echo "acceptance-media-import-desktop: running import Sheet did not expose background close: $sheet_text; log=$log_path" >&2
    exit 1
  }
  /usr/bin/osascript <<'APPLESCRIPT'
tell application "System Events"
  tell process "Woice"
    set workspaceWindows to (windows whose name contains "Woice 工作台")
    if (count of workspaceWindows) is 0 then error "找不到 Woice 工作台"
    set workspaceWindow to item 1 of workspaceWindows
    perform action "AXRaise" of workspaceWindow
    set closeButton to missing value
    repeat with elementRef in (get entire contents of workspaceWindow)
      try
        set elementText to ""
        try
          set elementText to elementText & " " & (name of elementRef as text)
        end try
        try
          set elementText to elementText & " " & (description of elementRef as text)
        end try
        try
          set elementText to elementText & " " & (title of elementRef as text)
        end try
        try
          set elementText to elementText & " " & (value of elementRef as text)
        end try
        try
          set elementText to elementText & " " & (help of elementRef as text)
        end try
        if elementText contains "关闭并后台继续" or elementText contains "关闭浮窗，转写任务会继续" then
          set closeButton to contents of elementRef
          exit repeat
        end if
      end try
    end repeat
    if closeButton is missing value then
      set importSheets to sheets of workspaceWindow
      if (count of importSheets) > 0 then
        set importSheet to item 1 of importSheets
        set sheetButtons to buttons of importSheet
        -- SwiftUI exposes the disabled “正在转写” action first, followed by
        -- the enabled “关闭并后台继续” action. Keep this as a deterministic
        -- AX fallback when System Events drops SwiftUI button labels.
        if (count of sheetButtons) is greater than or equal to 2 then
          set closeButton to item 2 of sheetButtons
        end if
      end if
    end if
    if closeButton is missing value then error "导入 Sheet 未找到关闭并后台继续按钮"
    click closeButton
  end tell
end tell
APPLESCRIPT
  background_closed=1
  for attempt in {1..10}; do
    sheet_text="$(/usr/bin/osascript <<'APPLESCRIPT' 2>/dev/null || true
tell application "System Events"
  tell process "Woice"
    set workspaceWindows to (windows whose name contains "Woice 工作台")
    if (count of workspaceWindows) is 0 then return ""
    return entire contents of item 1 of workspaceWindows
  end tell
end tell
APPLESCRIPT
)"
    [[ "$sheet_text" != *"关闭并后台继续"* ]] && break
    /bin/sleep 1
  done
  [[ "$sheet_text" != *"关闭并后台继续"* ]] || {
    echo "acceptance-media-import-desktop: background close did not dismiss the Sheet: $sheet_text; log=$log_path" >&2
    exit 1
  }
  workspace_window_title="$(workspace_window_title)"
  [[ "$workspace_window_title" == *"Woice 工作台"* ]] || {
    echo "acceptance-media-import-desktop: workspace disappeared after background close: $workspace_window_title; log=$log_path" >&2
    exit 1
  }
else
  /usr/bin/osascript <<'APPLESCRIPT'
tell application "System Events"
  tell process "Woice"
    set workspaceWindows to (windows whose name contains "Woice 工作台")
    if (count of workspaceWindows) is 0 then error "找不到 Woice 工作台"
    set workspaceWindow to item 1 of workspaceWindows
    perform action "AXRaise" of workspaceWindow
    set transcribeButton to missing value
    repeat with elementRef in (get entire contents of workspaceWindow)
      try
        if (name of elementRef as text) contains "转文字" or (help of elementRef as text) contains "转文字" then
          set transcribeButton to contents of elementRef
          exit repeat
        end if
      end try
    end repeat
    if transcribeButton is missing value then error "导入 Sheet 未找到转文字按钮"
    click transcribeButton
  end tell
end tell
APPLESCRIPT
fi

record_text=""
for attempt in {1..20}; do
  record_text="$(/usr/bin/osascript <<'APPLESCRIPT' 2>/dev/null || true
tell application "System Events"
  tell process "Woice"
    set workspaceWindows to (windows whose name contains "Woice 工作台")
    if (count of workspaceWindows) is 0 then return ""
    return entire contents of item 1 of workspaceWindows
  end tell
end tell
APPLESCRIPT
)"
  if [[ -f "$test_root/recordings.json" ]] \
    && rg -q -F "$source_title" "$test_root/recordings.json" \
    && rg -q -F "桌面导入验收素材" "$test_root/recordings.json"; then
    break
  fi
  /bin/sleep 1
done
[[ -f "$test_root/recordings.json" ]] \
  && rg -q -F "$source_title" "$test_root/recordings.json" \
  && rg -q -F "桌面导入验收素材" "$test_root/recordings.json" || {
  echo "acceptance-media-import-desktop: imported material or fixture transcript was not durable: $source_title" >&2
  exit 1
}

original_path="$(/usr/bin/find "$test_root/recordings" -maxdepth 1 -type f -name '*.source.*' -print -quit 2>/dev/null || true)"
derived_path="$(/usr/bin/find "$test_root/recordings" -maxdepth 1 -type f -name '*.wav' -print -quit 2>/dev/null || true)"
[[ -n "$original_path" && -f "$original_path" ]] || {
  echo "acceptance-media-import-desktop: immutable original was not persisted" >&2
  exit 1
}
[[ -n "$derived_path" && -s "$derived_path" ]] || {
  echo "acceptance-media-import-desktop: derived transcription WAV was not persisted" >&2
  exit 1
}
/usr/bin/cmp -s "$source_path" "$original_path" || {
  echo "acceptance-media-import-desktop: persisted original differs from source" >&2
  exit 1
}
echo "acceptance-media-import-desktop: desktop import/transcription passed; closed_background=$background_closed source=$source_path title=$source_title isolated_root=$test_root"
