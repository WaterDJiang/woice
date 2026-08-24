#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
app_path="${WOICE_STORE_APP_PATH:-$project_root/build/Woice-Store.app}"
clean_home="${WOICE_CLEAN_USER_HOME:-}"

[[ -d "$app_path" ]] || {
  print -u2 "Store App 不存在：$app_path；先运行 make package-store。"
  exit 1
}
[[ -n "$clean_home" ]] || {
  print -u2 "acceptance-app-store-clean-user 需要显式 WOICE_CLEAN_USER_HOME；不会使用或清理当前用户目录。"
  exit 1
}
[[ "$clean_home" == /* && "$clean_home" != "/" ]] || {
  print -u2 "WOICE_CLEAN_USER_HOME 必须是明确的非根绝对路径。"
  exit 1
}
[[ -d "$clean_home" ]] || {
  print -u2 "干净用户目录不存在：$clean_home"
  exit 1
}

print -u2 "当前仅完成安全前置检查；真实干净用户安装、TCC 和 GUI Journey 需要在指定目录和用户会话中人工执行。"
print -u2 "Store App：$app_path"
print -u2 "用户目录：$clean_home"
exit 1
