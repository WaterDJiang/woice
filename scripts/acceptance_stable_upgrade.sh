#!/bin/zsh
set -euo pipefail

cd "${0:A:h}/.."

if [[ "${WOICE_RUN_STABLE_UPGRADE:-0}" != "1" ]]; then
  echo "acceptance-stable-upgrade: skipped; set WOICE_RUN_STABLE_UPGRADE=1 after choosing an Apple Development or Developer ID identity"
  exit 0
fi

stable_identity="${WOICE_STABLE_SIGNING_IDENTITY:-${WOICE_CODESIGN_IDENTITY:-}}"
if [[ -z "$stable_identity" || "$stable_identity" == "-" ]]; then
  echo "acceptance-stable-upgrade: WOICE_STABLE_SIGNING_IDENTITY must be an explicit stable signing identity; ad hoc is rejected" >&2
  exit 1
fi

if ! /usr/bin/security find-identity -v -p codesigning 2>/dev/null | rg -F "$stable_identity" >/dev/null; then
  echo "acceptance-stable-upgrade: signing identity is not available in the current keychain: $stable_identity" >&2
  exit 1
fi

source_binary="${WOICE_STABLE_SOURCE_BINARY:-}"
mlx_bundle="${WOICE_STABLE_MLX_BUNDLE:-$PWD/.build/xcode-direct-derived/Build/Products/Release-Direct/Woice (Dev).app/Contents/Resources/mlx-swift_Cmlx.bundle}"

app_path="${WOICE_STABLE_APP_PATH:-/Applications/Woice (Dev).app}"
phase="${WOICE_STABLE_PHASE:-build}"
backup_tag="${WOICE_STABLE_BACKUP_TAG:-next-step}"
[[ "$backup_tag" =~ '^[A-Za-z0-9._-]+$' ]] || {
  echo "acceptance-stable-upgrade: WOICE_STABLE_BACKUP_TAG contains unsafe characters" >&2
  exit 1
}
case "$phase" in
  build|A|B|both) ;;
  *)
    echo "acceptance-stable-upgrade: WOICE_STABLE_PHASE must be build, A, B, or both" >&2
    exit 1
    ;;
esac

output_root="${WOICE_STABLE_OUTPUT_ROOT:-/private/tmp/woice-stable-ab-$(date +%Y%m%d-%H%M%S)}"
reuse_output="${WOICE_STABLE_REUSE_OUTPUT:-0}"
if [[ -e "$output_root" && "$reuse_output" != "1" ]]; then
  echo "acceptance-stable-upgrade: refusing to reuse existing evidence directory: $output_root" >&2
  echo "acceptance-stable-upgrade: set WOICE_STABLE_REUSE_OUTPUT=1 only for a later B install" >&2
  exit 1
fi
mkdir -p "$output_root"

info_root="$(mktemp -d /private/tmp/woice-stable-info.XXXXXX)"
cleanup_info() { /bin/rm -rf "$info_root"; }
trap cleanup_info EXIT
/bin/cp Resources/NOTICES.md "$info_root/NOTICES.md"

build_version_a="${WOICE_STABLE_BUILD_A:-2026082301}"
build_version_b="${WOICE_STABLE_BUILD_B:-2026082302}"
[[ "$build_version_a" != "$build_version_b" ]] || {
  echo "acceptance-stable-upgrade: Build A and B must have different CFBundleVersion values" >&2
  exit 1
}

package_one() {
  local label="$1"
  local build_version="$2"
  local info_plist="$info_root/Info-$label.plist"
  local build_app="build/Woice-Stable-$label.app"
  cp Resources/Info.plist "$info_plist"
  /usr/bin/plutil -replace CFBundleVersion -string "$build_version" "$info_plist"
  WOICE_CODESIGN_IDENTITY="$stable_identity" \
    /usr/bin/python3 scripts/package_distribution.py \
      --flavor dev \
      --binary "$source_binary" \
      --mlx-bundle "$mlx_bundle" \
      --info-plist "$info_plist" \
      --output "$build_app"
  /usr/bin/ditto "$build_app" "$output_root/Woice-Stable-$label.app"
  /bin/rm -rf "$build_app"
}

if [[ "$phase" == "build" || "$reuse_output" != "1" ]]; then
  if [[ -z "$source_binary" ]]; then
    source_binary="$(/usr/bin/swift build -c release --show-bin-path)/Woice"
  fi
  if [[ "${WOICE_STABLE_SKIP_BUILD:-0}" != "1" ]]; then
    /usr/bin/swift build -c release
  fi
  [[ -f "$source_binary" ]] || {
    echo "acceptance-stable-upgrade: release binary not found: $source_binary" >&2
    exit 1
  }
  if [[ ! -d "$mlx_bundle" ]]; then
    make xcode-build-direct
  fi
  [[ -f "$mlx_bundle/Contents/Resources/default.metallib" ]] || {
    echo "acceptance-stable-upgrade: MLX Metal Bundle not found: $mlx_bundle" >&2
    exit 1
  }
  package_one A "$build_version_a"
  package_one B "$build_version_b"
fi

app_a="$output_root/Woice-Stable-A.app"
app_b="$output_root/Woice-Stable-B.app"
[[ -d "$app_a" && -d "$app_b" ]] || {
  echo "acceptance-stable-upgrade: both A/B app artifacts are required under $output_root" >&2
  exit 1
}

inspect_app() {
  local label="$1"
  local app="$2"
  local details="$output_root/$label-codesign.txt"
  /usr/bin/codesign --verify --deep --strict "$app"
  /usr/bin/codesign -dvv "$app" > "$details" 2>&1
  if rg -q 'Signature=adhoc|TeamIdentifier=not set' "$details"; then
    echo "acceptance-stable-upgrade: $label is ad hoc or missing Team ID" >&2
    exit 1
  fi
  rg -q '^Identifier=com\.woice\.app$' "$details"
  rg -q '^TeamIdentifier=[A-Za-z0-9]+$' "$details"
  /usr/bin/codesign -d -r- "$app" > "$output_root/$label-requirements.raw.txt" 2>&1
  rg '^designated =>' "$output_root/$label-requirements.raw.txt" > "$output_root/$label-requirements.txt" || true
  /usr/bin/codesign -d --entitlements :- "$app" > "$output_root/$label-entitlements.raw.txt" 2>&1 || true
  rg -v '^(Executable=|warning:)' "$output_root/$label-entitlements.raw.txt" > "$output_root/$label-entitlements.txt" || true
  /usr/bin/shasum -a 256 "$app/Contents/MacOS/Woice" >> "$output_root/manifest.txt"
  printf '%s\n' "[$label]" >> "$output_root/manifest.txt"
  /usr/bin/plutil -p "$app/Contents/Info.plist" >> "$output_root/manifest.txt"
}

: > "$output_root/manifest.txt"
inspect_app A "$app_a"
inspect_app B "$app_b"

id_a="$(/usr/bin/awk -F= '/^Identifier=/{print $2; exit}' "$output_root/A-codesign.txt")"
id_b="$(/usr/bin/awk -F= '/^Identifier=/{print $2; exit}' "$output_root/B-codesign.txt")"
team_a="$(/usr/bin/awk -F= '/^TeamIdentifier=/{print $2; exit}' "$output_root/A-codesign.txt")"
team_b="$(/usr/bin/awk -F= '/^TeamIdentifier=/{print $2; exit}' "$output_root/B-codesign.txt")"
[[ "$id_a" == "$id_b" && "$id_a" == "com.woice.app" ]] || {
  echo "acceptance-stable-upgrade: Bundle ID changed between A and B" >&2
  exit 1
}
[[ "$team_a" == "$team_b" && -n "$team_a" ]] || {
  echo "acceptance-stable-upgrade: Team ID changed or is missing between A and B" >&2
  exit 1
}
cmp "$output_root/A-requirements.txt" "$output_root/B-requirements.txt"
cmp "$output_root/A-entitlements.txt" "$output_root/B-entitlements.txt"

permission_keys=(
  NSMicrophoneUsageDescription
  NSAudioCaptureUsageDescription
  NSScreenCaptureUsageDescription
  NSSpeechRecognitionUsageDescription
)
for key in "${permission_keys[@]}"; do
  value_a="$(/usr/bin/plutil -extract "$key" xml1 -o - "$app_a/Contents/Info.plist")"
  value_b="$(/usr/bin/plutil -extract "$key" xml1 -o - "$app_b/Contents/Info.plist")"
  [[ "$value_a" == "$value_b" ]] || {
    echo "acceptance-stable-upgrade: permission declaration changed for $key" >&2
    exit 1
  }
done

short_version_a="$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$app_a/Contents/Info.plist")"
short_version_b="$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$app_b/Contents/Info.plist")"
version_a="$(/usr/bin/plutil -extract CFBundleVersion raw -o - "$app_a/Contents/Info.plist")"
version_b="$(/usr/bin/plutil -extract CFBundleVersion raw -o - "$app_b/Contents/Info.plist")"
[[ "$short_version_a" == "$short_version_b" && "$version_a" != "$version_b" ]] || {
  echo "acceptance-stable-upgrade: A/B version boundary is invalid" >&2
  exit 1
}

printf '%s\n' \
  "stableIdentity=$stable_identity" \
  "bundleIdentifier=$id_a" \
  "teamIdentifier=$team_a" \
  "shortVersion=$short_version_a" \
  "buildA=$version_a" \
  "buildB=$version_b" \
  "outputRoot=$output_root" >> "$output_root/manifest.txt"

stop_running_instance() {
  local lock="$HOME/Library/Application Support/Woice Dev/instance.lock"
  [[ -f "$lock" ]] || return 0
  local pid="$(tr -d '[:space:]' < "$lock")"
  [[ "$pid" =~ '^[0-9]+$' ]] || return 0
  local process_path="$(/bin/ps -p "$pid" -o command= 2>/dev/null | sed 's/^[[:space:]]*//' || true)"
  [[ "$process_path" == */Contents/MacOS/Woice* ]] || return 0
  kill -TERM "$pid"
  for _ in {1..30}; do
    kill -0 "$pid" 2>/dev/null || return 0
    sleep 0.2
  done
  echo "acceptance-stable-upgrade: Woice did not exit after SIGTERM: $pid" >&2
  exit 1
}

install_one() {
  local label="$1"
  local source_app="$output_root/Woice-Stable-$label.app"
  local backup="$output_root/Woice-installed-$label-before-$backup_tag.app"
  stop_running_instance
  if [[ -d "$app_path" ]]; then
    [[ ! -e "$backup" ]] || {
      echo "acceptance-stable-upgrade: refusing to overwrite backup: $backup" >&2
      exit 1
    }
    /usr/bin/ditto "$app_path" "$backup"
  fi
  /usr/bin/ditto "$source_app" "$app_path"
  /usr/bin/codesign --verify --deep --strict "$app_path"
  /usr/bin/codesign -dvv "$app_path" > "$output_root/installed-$label-codesign.txt" 2>&1
  echo "acceptance-stable-upgrade: installed $label at $app_path; backup=$backup"
}

case "$phase" in
  A) install_one A ;;
  B) install_one B ;;
  both)
    install_one A
    install_one B
    ;;
  build) ;;
esac

echo "acceptance-stable-upgrade: A/B stable identity and permission declarations passed"
echo "acceptance-stable-upgrade: evidence=$output_root"
echo "acceptance-stable-upgrade: TCC grant/continuity remains manual; no tccutil reset was performed"
