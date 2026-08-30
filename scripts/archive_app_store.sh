#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
cd "$project_root"

xcode_project="${WOICE_XCODE_PROJECT:-$project_root/Woice.xcodeproj}"
xcode_scheme="${WOICE_XCODE_SCHEME:-Woice-Store}"
[[ -e "$xcode_project" ]] || {
  print -u2 "Xcode 工程不存在：$xcode_project；请先运行 make xcode-project。"
  exit 1
}

store_team_id="${WOICE_STORE_TEAM_ID:-}"
store_signing_identity="${WOICE_STORE_CODE_SIGN_IDENTITY:-}"
[[ -n "$store_team_id" ]] || {
  print -u2 "archive-app-store 缺少 WOICE_STORE_TEAM_ID；不会伪造 Store 签名 Archive。"
  exit 1
}
[[ -n "$store_signing_identity" ]] || {
  print -u2 "archive-app-store 缺少 WOICE_STORE_CODE_SIGN_IDENTITY；不会伪造 Store 签名 Archive。"
  exit 1
}

archive_path="${WOICE_ARCHIVE_PATH:-$project_root/build/Woice-Store.xcarchive}"
configuration="${WOICE_XCODE_CONFIGURATION:-Release-AppStore}"
archive_args=(
  xcodebuild
  -project "$xcode_project" \
  -scheme "$xcode_scheme" \
  -configuration "$configuration" \
  -archivePath "$archive_path" \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM="$store_team_id" \
  CODE_SIGN_IDENTITY="$store_signing_identity" \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGNING_REQUIRED=YES \
  -skipPackagePluginValidation
)
if [[ -n "${WOICE_DERIVED_DATA_PATH:-}" ]]; then
  archive_args+=("-derivedDataPath" "$WOICE_DERIVED_DATA_PATH")
fi
archive_args+=(archive)
"${archive_args[@]}"
print "archive-app-store: $archive_path"
