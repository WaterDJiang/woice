#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
cd "$project_root"

required=(
  WOICE_CODESIGN_IDENTITY
  WOICE_NOTARY_PROFILE
  WOICE_OFFLINE_MODEL_ROOT
  WOICE_BUILD_VERSION
  WOICE_CATALOG_URL
  WOICE_CATALOG_ID
  WOICE_CATALOG_TRUSTED_KEYS_JSON
)
for variable in $required; do
  [[ -n "${(P)variable:-}" ]] || {
    print -u2 "正式 Developer ID 发布缺少 $variable；不会伪造签名、公证或生产 Catalog。"
    exit 1
  }
done

[[ "$WOICE_CODESIGN_IDENTITY" == Developer\ ID\ Application:* ]] || {
  print -u2 "WOICE_CODESIGN_IDENTITY 必须是 Developer ID Application 身份。"
  exit 1
}
[[ "$WOICE_BUILD_VERSION" == <-> ]] || {
  print -u2 "WOICE_BUILD_VERSION 必须是数字 Build。"
  exit 1
}
[[ -d "$WOICE_OFFLINE_MODEL_ROOT" ]] || {
  print -u2 "Offline 模型目录不存在：$WOICE_OFFLINE_MODEL_ROOT"
  exit 1
}
[[ "$WOICE_CATALOG_URL" == https://* ]] || {
  print -u2 "WOICE_CATALOG_URL 必须使用 HTTPS。"
  exit 1
}
[[ "$WOICE_CATALOG_TRUSTED_KEYS_JSON" == \{*\} ]] || {
  print -u2 "WOICE_CATALOG_TRUSTED_KEYS_JSON 必须是 JSON 对象。"
  exit 1
}

security find-identity -v -p codesigning | grep -Fq "$WOICE_CODESIGN_IDENTITY" || {
  print -u2 "当前钥匙串没有可用的 Developer ID 身份：$WOICE_CODESIGN_IDENTITY"
  exit 1
}
command -v xcrun >/dev/null || { print -u2 "缺少 xcrun，无法执行公证门禁。"; exit 1; }
xcrun notarytool history --keychain-profile "$WOICE_NOTARY_PROFILE" >/dev/null 2>&1 || {
  print -u2 "Notarytool 凭据不可用：$WOICE_NOTARY_PROFILE"
  exit 1
}

output_root="${WOICE_RELEASE_OUTPUT_ROOT:-/private/tmp/woice-developer-id-$WOICE_BUILD_VERSION}"
mkdir -p "$output_root"

WOICE_CODESIGN_IDENTITY="$WOICE_CODESIGN_IDENTITY" \
WOICE_HARDENED_RUNTIME=1 \
WOICE_CODESIGN_ENTITLEMENTS="$project_root/Resources/Woice.entitlements" \
WOICE_BUILD_VERSION="$WOICE_BUILD_VERSION" \
WOICE_CATALOG_URL="$WOICE_CATALOG_URL" \
WOICE_CATALOG_ID="$WOICE_CATALOG_ID" \
WOICE_CATALOG_TRUSTED_KEYS_JSON="$WOICE_CATALOG_TRUSTED_KEYS_JSON" \
WOICE_CATALOG_ALLOWED_HOSTS="${WOICE_CATALOG_ALLOWED_HOSTS:-}" \
WOICE_CATALOG_DOWNLOAD_ALLOWED_HOSTS="${WOICE_CATALOG_DOWNLOAD_ALLOWED_HOSTS:-}" \
make build

WOICE_CODESIGN_IDENTITY="$WOICE_CODESIGN_IDENTITY" \
WOICE_HARDENED_RUNTIME=1 \
WOICE_CODESIGN_ENTITLEMENTS="$project_root/Resources/Woice.entitlements" \
WOICE_BUILD_VERSION="$WOICE_BUILD_VERSION" \
WOICE_CATALOG_URL="$WOICE_CATALOG_URL" \
WOICE_CATALOG_ID="$WOICE_CATALOG_ID" \
WOICE_CATALOG_TRUSTED_KEYS_JSON="$WOICE_CATALOG_TRUSTED_KEYS_JSON" \
WOICE_CATALOG_ALLOWED_HOSTS="${WOICE_CATALOG_ALLOWED_HOSTS:-}" \
WOICE_CATALOG_DOWNLOAD_ALLOWED_HOSTS="${WOICE_CATALOG_DOWNLOAD_ALLOWED_HOSTS:-}" \
  make package-core package-offline WOICE_OFFLINE_MODEL_ROOT="$WOICE_OFFLINE_MODEL_ROOT"

core_app="$project_root/build/Woice-Core.app"
offline_app="$project_root/build/Woice-Offline.app"
core_dmg="$project_root/build/Woice-Core-$WOICE_BUILD_VERSION.dmg"
offline_dmg="$project_root/build/Woice-Offline-$WOICE_BUILD_VERSION.dmg"
python3 scripts/package_dmg.py --app "$core_app" --output "$core_dmg" --volume-name Woice-Core
python3 scripts/package_dmg.py --app "$offline_app" --output "$offline_dmg" --volume-name Woice-Offline

release_team_identifier=""
for app in "$core_app" "$offline_app"; do
  bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")"
  build_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")"
  [[ "$bundle_id" == "com.woice.app" ]] || {
    print -u2 "发行包 Bundle ID 不符合固定升级边界：$bundle_id"
    exit 1
  }
  [[ "$build_version" == "$WOICE_BUILD_VERSION" ]] || {
    print -u2 "发行包 Build 与请求不一致：$build_version != $WOICE_BUILD_VERSION"
    exit 1
  }
  codesign --verify --deep --strict --verbose=2 "$app"
  codesign_details="$(codesign --display --verbose=4 "$app" 2>&1)"
  print -r -- "$codesign_details" > "$output_root/$(basename "$app").codesign.txt"
  team_identifier="$(print -r -- "$codesign_details" | sed -n 's/^TeamIdentifier=//p' | head -n 1)"
  [[ -n "$team_identifier" && "$team_identifier" != "not set" ]] || {
    print -u2 "发行包缺少稳定 Team ID：$app"
    exit 1
  }
  if [[ -z "$release_team_identifier" ]]; then
    release_team_identifier="$team_identifier"
  elif [[ "$release_team_identifier" != "$team_identifier" ]]; then
    print -u2 "Core/Offline Team ID 不一致：$release_team_identifier != $team_identifier"
    exit 1
  fi
  designated_requirement="$(codesign -d -r- "$app" 2>&1)"
  print -r -- "$designated_requirement" > "$output_root/$(basename "$app").designated-requirement.txt"
  print -r -- "$designated_requirement" | grep -Fq 'identifier "com.woice.app"' || {
    print -u2 "发行包 Designated Requirement 不符合固定 Bundle ID：$app"
    exit 1
  }
  spctl --assess --type execute --verbose=4 "$app"
done
for dmg in "$core_dmg" "$offline_dmg"; do
  hdiutil verify "$dmg" >/dev/null
  xcrun notarytool submit "$dmg" --keychain-profile "$WOICE_NOTARY_PROFILE" --wait \
    --output-format json > "$output_root/$(basename "$dmg").notary.json"
  xcrun stapler staple "$dmg"
  xcrun stapler validate "$dmg"
done

ditto "$core_dmg" "$output_root/$(basename "$core_dmg")"
ditto "$offline_dmg" "$output_root/$(basename "$offline_dmg")"
python3 scripts/release_artifact_manifest.py create \
  --output "$output_root/ReleaseManifest.json" \
  --build-version "$WOICE_BUILD_VERSION" \
  --bundle-id com.woice.app \
  --catalog-url "$WOICE_CATALOG_URL" \
  --catalog-id "$WOICE_CATALOG_ID" \
  --core-dmg "$output_root/$(basename "$core_dmg")" \
  --offline-dmg "$output_root/$(basename "$offline_dmg")"
(cd "$output_root" && shasum -a 256 *.dmg > SHA256SUMS.txt)
print "release-developer-id: $output_root"
