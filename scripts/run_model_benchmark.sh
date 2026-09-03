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

if [[ "${WOICE_BENCHMARK_INCLUDE_QWEN:-0}" == "1" ]]; then
  metallib_path="${WOICE_MLX_METALLIB:-}"
  if [[ -z "$metallib_path" ]]; then
    metallib_path="$({
      find .build/xcode-derived .build/xcode-direct-derived \
        -path '*/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib' \
        -type f -print 2>/dev/null || true
    } | head -n 1)"
  fi
  if [[ -z "$metallib_path" || ! -f "$metallib_path" ]]; then
    echo "Qwen 基准缺少 MLX Metal shader：请先运行 make xcode-build-store，或显式设置 WOICE_MLX_METALLIB。" >&2
    exit 1
  fi
  swift_bin_path="$(swift build --show-bin-path)"
  test_bin_path="$swift_bin_path/WoicePackageTests.xctest/Contents/MacOS"
  mkdir -p "$test_bin_path"
  ln -sf "$(cd "$(dirname "$metallib_path")" && pwd)/$(basename "$metallib_path")" \
    "$test_bin_path/mlx.metallib"
fi

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
