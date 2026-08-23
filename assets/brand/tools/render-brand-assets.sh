#!/bin/zsh
set -euo pipefail

root="$(cd "$(dirname "$0")/../../.." && pwd)"
source="$root/assets/brand/source/woice-final-ribbon-1254.png"
export_root="$root/assets/brand/exports"
iconset_root="$export_root/Woice.iconset"
asset_catalog_root="$export_root/AppIcon.appiconset"

if [[ ! -f "$source" ]]; then
    print -u2 "Woice brand source not found: $source"
    exit 1
fi

mkdir -p "$export_root" "$iconset_root" "$asset_catalog_root"

for size in 16 32 64 128 256 512 1024; do
    sips -z "$size" "$size" "$source" --out "$export_root/woice-app-icon-$size.png" >/dev/null
done

typeset -a icon_files=(
    "icon_16x16.png:16"
    "icon_16x16@2x.png:32"
    "icon_32x32.png:32"
    "icon_32x32@2x.png:64"
    "icon_128x128.png:128"
    "icon_128x128@2x.png:256"
    "icon_256x256.png:256"
    "icon_256x256@2x.png:512"
    "icon_512x512.png:512"
    "icon_512x512@2x.png:1024"
)

for item in $icon_files; do
    name="${item%%:*}"
    size="${item##*:}"
    cp "$export_root/woice-app-icon-$size.png" "$iconset_root/$name"
    cp "$export_root/woice-app-icon-$size.png" "$asset_catalog_root/$name"
done

print "Woice brand assets rendered from the approved raster master."
