#!/bin/zsh
set -euo pipefail

output_directory="${1:-}"
if [[ -z "$output_directory" ]]; then
  echo "用法：$0 <输出目录>" >&2
  exit 2
fi
if [[ "$output_directory" == "/" ]]; then
  echo "拒绝把官方参考夹具写入根目录" >&2
  exit 2
fi

mkdir -p "$output_directory"

download_fixture() {
  local fixture_name="$1"
  local source_url="$2"
  local expected_sha256="$3"
  local target_file="$output_directory/${fixture_name}.wav"
  local temporary_file="${target_file}.partial.$$"

  if ! curl -sS -L --fail --retry 2 --connect-timeout 20 --max-time 120 \
    "$source_url" -o "$temporary_file"
  then
    rm -f "$temporary_file"
    echo "官方参考夹具下载失败：$fixture_name" >&2
    return 1
  fi
  local actual_sha256
  if ! actual_sha256="$(shasum -a 256 "$temporary_file" | awk '{print $1}')"; then
    rm -f "$temporary_file"
    echo "官方参考夹具摘要读取失败：$fixture_name" >&2
    return 1
  fi
  if [[ "$actual_sha256" != "$expected_sha256" ]]; then
    rm -f "$temporary_file"
    echo "官方参考夹具 SHA-256 不匹配：$fixture_name（实际 $actual_sha256）" >&2
    return 1
  fi
  if ! mv -f "$temporary_file" "$target_file"; then
    rm -f "$temporary_file"
    echo "官方参考夹具安装失败：$fixture_name" >&2
    return 1
  fi
}

download_fixture \
  "zh-official" \
  "https://qianwen-res.oss-cn-beijing.aliyuncs.com/Qwen3-ASR-Repo/asr_zh.wav" \
  "46dbc998c9d1d48111267c40741dd3200f2e5bcf4075f8c4c97f4451160dce50"
download_fixture \
  "en-official" \
  "https://qianwen-res.oss-cn-beijing.aliyuncs.com/Qwen3-ASR-Repo/asr_en.wav" \
  "f9b4440ac8393e47c14a6240e9739dea09b645bb1592b8f2dd48feb9666cea7f"

print -r -- "甚至出现交易几乎停滞的情况。" > "$output_directory/zh-official.txt"
print -r -- "Mm. Oh, yeah, yeah. He wasn't even that big when I started listening to him, but and his solo music didn't do overly well, but he did very well when he started writing for other people." > "$output_directory/en-official.txt"

echo "qwen-reference-fixtures: $output_directory"
