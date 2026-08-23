#!/bin/zsh
set -euo pipefail

strict=0
if [[ "${1:-}" == "--strict" ]]; then
  strict=1
  shift
fi
if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "用法：$0 [--strict] <基准音频目录> [输出 JSON 路径]" >&2
  exit 2
fi

project_root="$(cd "$(dirname "$0")/.." && pwd)"
audio_directory="$1"
output_path="${2:-build/model-benchmark.json}"
if [[ ! -d "$audio_directory" ]]; then
  echo "模型基准音频目录不存在：$audio_directory" >&2
  exit 1
fi

cd "$project_root"
if (( strict )); then
  WOICE_RUN_MODEL_BENCHMARK=1 \
  WOICE_BENCHMARK_AUDIO_DIR="$audio_directory" \
  WOICE_BENCHMARK_OUTPUT="$output_path" \
  WOICE_ENFORCE_MODEL_BENCHMARK="${WOICE_ENFORCE_MODEL_BENCHMARK:-1}" \
  WOICE_BENCHMARK_MIN_DURATION_SECONDS="${WOICE_BENCHMARK_MIN_DURATION_SECONDS:-300}" \
    swift test --no-parallel --filter modelBenchmarkProducesReport
else
  WOICE_RUN_MODEL_BENCHMARK=1 \
  WOICE_BENCHMARK_AUDIO_DIR="$audio_directory" \
  WOICE_BENCHMARK_OUTPUT="$output_path" \
    swift test --no-parallel --filter modelBenchmarkProducesReport
fi
echo "model-benchmark: $output_path"
