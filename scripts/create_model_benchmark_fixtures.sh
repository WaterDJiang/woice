#!/bin/zsh
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "用法：$0 <输出目录> [每类秒数]" >&2
  exit 2
fi

fixture_directory="$1"
duration_seconds="${2:-300}"
if [[ ! "$duration_seconds" =~ ^[0-9]+$ || "$duration_seconds" -le 0 ]]; then
  echo "每类秒数必须是正整数：$duration_seconds" >&2
  exit 2
fi

if [[ -e "$fixture_directory" && ! -d "$fixture_directory" ]]; then
  echo "Fixture 输出路径不是目录：$fixture_directory" >&2
  exit 1
fi
mkdir -p "$fixture_directory"

for required_name in \
  zh-benchmark.wav zh-benchmark.txt \
  en-benchmark.wav en-benchmark.txt \
  mixed-benchmark.wav mixed-benchmark.txt \
  silence-benchmark.wav noise-benchmark.wav; do
  if [[ -e "$fixture_directory/$required_name" ]]; then
    echo "拒绝覆盖已有 Fixture：$fixture_directory/$required_name" >&2
    exit 1
  fi
done

for command_name in say ffmpeg afinfo; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "缺少系统命令：$command_name" >&2
    exit 1
  fi
done

temporary_directory="$(mktemp -d -t woice-model-fixtures)"
trap 'rm -rf "$temporary_directory"' EXIT

zh_text='这是 Woice 的中文模型基准样本。录音内容用于验证本机语音转文字的速度、稳定性和长音频处理能力。我们会保留原始声音，并在本机完成转写。'
en_text='This is the Woice English benchmark sample. It measures local speech recognition speed, stability, and long audio handling. The original recording stays on this Mac.'
mixed_text='这是 Woice 的 mixed language benchmark sample. We test English in the same recording.'

say -v Tingting -o "$temporary_directory/zh.aiff" "$zh_text"
say -v Samantha -o "$temporary_directory/en.aiff" "$en_text"
say -v Tingting -o "$temporary_directory/mixed-zh.aiff" '这是 Woice 的'
say -v Samantha -o "$temporary_directory/mixed-en.aiff" 'mixed language benchmark sample. We test English in the same recording.'

ffmpeg -hide_banner -loglevel error -y \
  -i "$temporary_directory/mixed-zh.aiff" \
  -i "$temporary_directory/mixed-en.aiff" \
  -filter_complex '[0:a][1:a]concat=n=2:v=0:a=1' \
  -ar 16000 -ac 1 -c:a pcm_s16le "$temporary_directory/mixed-base.wav"

make_looped_voice() {
  local input_path="$1"
  local output_path="$2"
  ffmpeg -hide_banner -loglevel error -y \
    -stream_loop 1000 -i "$input_path" \
    -t "$duration_seconds" -ar 16000 -ac 1 -c:a pcm_s16le "$output_path"
}

make_looped_voice "$temporary_directory/zh.aiff" "$fixture_directory/zh-benchmark.wav"
make_looped_voice "$temporary_directory/en.aiff" "$fixture_directory/en-benchmark.wav"
make_looped_voice "$temporary_directory/mixed-base.wav" "$fixture_directory/mixed-benchmark.wav"

ffmpeg -hide_banner -loglevel error -y \
  -f lavfi -i 'anullsrc=r=16000:cl=mono' \
  -t "$duration_seconds" -c:a pcm_s16le "$fixture_directory/silence-benchmark.wav"

ffmpeg -hide_banner -loglevel error -y \
  -f lavfi -i 'anoisesrc=color=white:amplitude=0.05:sample_rate=16000' \
  -t "$duration_seconds" -c:a pcm_s16le "$fixture_directory/noise-benchmark.wav"

write_repeated_reference() {
  local source_text="$1"
  local source_audio="$2"
  local reference_path="$3"
  local base_duration
  base_duration="$(afinfo "$source_audio" | awk '/estimated duration:/ { print $3; exit }')"
  if [[ -z "$base_duration" || "$base_duration" == "0.000000" ]]; then
    echo "无法读取语音 Fixture 时长：$source_audio" >&2
    exit 1
  fi
  integer repeat_count=$(( duration_seconds / base_duration + 2 ))
  : > "$reference_path"
  for ((index = 1; index <= repeat_count; index++)); do
    printf '%s\n' "$source_text" >> "$reference_path"
  done
}

write_repeated_reference "$zh_text" "$temporary_directory/zh.aiff" "$fixture_directory/zh-benchmark.txt"
write_repeated_reference "$en_text" "$temporary_directory/en.aiff" "$fixture_directory/en-benchmark.txt"
write_repeated_reference "$mixed_text" "$temporary_directory/mixed-base.wav" "$fixture_directory/mixed-benchmark.txt"

echo "model-benchmark-fixtures: $fixture_directory ($duration_seconds seconds per category)"
