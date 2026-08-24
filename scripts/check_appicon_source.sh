#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
iconset="$project_root/assets/brand/exports/AppIcon.appiconset"
xcode_catalog="$project_root/assets/brand/exports/AppIcon.xcassets"

[[ -d "$iconset" ]] || { print -u2 "AppIcon Asset Catalog 不存在：$iconset"; exit 1; }
[[ -f "$iconset/Contents.json" ]] || { print -u2 "AppIcon Contents.json 不存在。"; exit 1; }
[[ -d "$xcode_catalog/AppIcon.appiconset" ]] || { print -u2 "Xcode AppIcon.xcassets 包装目录不存在：$xcode_catalog"; exit 1; }
[[ -f "$xcode_catalog/Contents.json" ]] || { print -u2 "Xcode AppIcon.xcassets/Contents.json 不存在。"; exit 1; }
[[ -f "$xcode_catalog/AppIcon.appiconset/Contents.json" ]] || { print -u2 "Xcode AppIcon.appiconset/Contents.json 不存在。"; exit 1; }
diff -rq "$iconset" "$xcode_catalog/AppIcon.appiconset" >/dev/null \
  || { print -u2 "Xcode AppIcon.appiconset 与发布目录资源不一致。"; exit 1; }
for image in \
  icon_16x16.png icon_16x16@2x.png icon_32x32.png icon_32x32@2x.png \
  icon_128x128.png icon_128x128@2x.png icon_256x256.png icon_256x256@2x.png \
  icon_512x512.png icon_512x512@2x.png; do
  [[ -s "$iconset/$image" ]] || { print -u2 "AppIcon 资源缺失或为空：$image"; exit 1; }
done

grep -q 'compile_app_icon' "$project_root/scripts/package_distribution.py" \
  || { print -u2 "发布脚本未从 Asset Catalog 编译 AppIcon。"; exit 1; }
if rg -n 'NSApplication\.shared\.applicationIconImage|applicationIconImage[[:space:]]*=' \
  "$project_root/Sources" >/dev/null; then
  print -u2 "运行时覆盖 NSApplication.applicationIconImage 已被禁止。"
  exit 1
fi

print "appicon-check: passed (canonical catalog + Xcode bundle wrapper; no runtime square override)"
