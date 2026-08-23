#!/bin/zsh
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
sound_fixture="/System/Library/Sounds/Funk.aiff"
if [[ ! -f "$sound_fixture" ]]; then
  echo "acceptance-meeting: 缺少系统声音 Fixture：$sound_fixture" >&2
  exit 1
fi

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "acceptance-meeting: 缺少 ffmpeg，无法生成可见播放源。" >&2
  exit 1
fi

fixture_dir="$(mktemp -d "${TMPDIR:-/tmp}/woice-meeting-source.XXXXXX")"
source_audio="$fixture_dir/system-source.aiff"
cleanup() {
  osascript - "$source_audio" <<'APPLESCRIPT' >/dev/null 2>&1 || true
on run argv
  set sourcePath to item 1 of argv
  tell application "QuickTime Player"
    repeat with candidate in documents
      try
        if POSIX path of ((file of candidate) as alias) is sourcePath then close candidate
      end try
    end repeat
  end tell
end run
APPLESCRIPT
  rm -rf "$fixture_dir"
}
trap cleanup EXIT

if ! ffmpeg -hide_banner -loglevel error -stream_loop 40 -i "$sound_fixture" \
  -t 20 -acodec pcm_s16be "$source_audio"; then
  echo "acceptance-meeting: 无法生成可见播放源：$source_audio" >&2
  exit 1
fi

cd "$project_root"

# Window-level ScreenCaptureKit fallback needs an application-owned window.
# `afplay` is a windowless process and can produce zero-peak buffers, so use a
# visible QuickTime document as the deterministic playback source.
if ! open -a "QuickTime Player" "$source_audio" >/dev/null 2>&1; then
  echo "acceptance-meeting: 无法启动 QuickTime Player；需要解锁的可见用户会话。" >&2
  exit 1
fi
if ! osascript - "$source_audio" <<'APPLESCRIPT' >/dev/null 2>&1
on run argv
  set sourcePath to item 1 of argv
  tell application "QuickTime Player"
    activate
    repeat 20 times
      if (count of documents) > 0 then exit repeat
      delay 0.25
    end repeat
    if (count of documents) is 0 then error "没有打开播放文档"
    set movie to document 1
    set audio volume of movie to 1.0
    set looping of movie to true
    play movie
  end tell
end run
APPLESCRIPT
then
  echo "acceptance-meeting: QuickTime 播放源未能开始播放。" >&2
  exit 1
fi

WOICE_RUN_APPSTATE_CAPTURE=1 \
WOICE_REQUIRE_SYSTEM_AUDIO=1 \
WOICE_REQUIRE_SYSTEM_AUDIO_SIGNAL=1 \
  swift test --no-parallel --filter appStateMeetingModePersistsDualTrackRecord
