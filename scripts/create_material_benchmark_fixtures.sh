#!/bin/zsh
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "用法：$0 <输出目录>" >&2
  exit 2
fi

fixture_directory="$1"
if [[ -e "$fixture_directory" && ! -d "$fixture_directory" ]]; then
  echo "Fixture 输出路径不是目录：$fixture_directory" >&2
  exit 1
fi
mkdir -p "$fixture_directory"

for required_name in small-audio.m4a long-audio.m4a summaries-500.json qwen-byte-token.json manifest.json; do
  if [[ -e "$fixture_directory/$required_name" ]]; then
    echo "拒绝覆盖已有 Fixture：$fixture_directory/$required_name" >&2
    exit 1
  fi
done

command -v ffmpeg >/dev/null 2>&1 || { echo "缺少系统命令：ffmpeg" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "缺少系统命令：python3" >&2; exit 1; }

ffmpeg -hide_banner -loglevel error -y \
  -f lavfi -i 'sine=frequency=440:sample_rate=16000' \
  -t 12 -ar 16000 -ac 1 -c:a aac -b:a 32k "$fixture_directory/small-audio.m4a"
ffmpeg -hide_banner -loglevel error -y \
  -f lavfi -i 'sine=frequency=440:sample_rate=16000' \
  -t 3600 -ar 16000 -ac 1 -c:a aac -b:a 32k "$fixture_directory/long-audio.m4a"

WOICE_MATERIAL_FIXTURE_DIRECTORY="$fixture_directory" python3 - <<'PY'
import datetime as dt
import json
import os
import uuid

root = os.environ["WOICE_MATERIAL_FIXTURE_DIRECTORY"]
created = dt.datetime(2026, 1, 1, tzinfo=dt.timezone.utc)
summaries = []
for index in range(500):
    record_id = uuid.uuid5(uuid.NAMESPACE_URL, f"https://woice.test/material/{index}")
    summaries.append(
        {
            "id": str(record_id).upper(),
            "createdAt": (created + dt.timedelta(minutes=index)).isoformat().replace("+00:00", "Z"),
            "audioFileName": f"fixture-{index:04d}.m4a",
            "duration": 60.0 + (index % 17),
            "displayTitle": f"性能素材 {index:04d}",
            "sourceKind": "recorded",
            "hasSystemAudio": index % 2 == 0,
            "materialStatus": "ready",
        }
    )

with open(os.path.join(root, "summaries-500.json"), "w", encoding="utf-8") as handle:
    json.dump(summaries, handle, ensure_ascii=False, indent=2)

with open(os.path.join(root, "qwen-byte-token.json"), "w", encoding="utf-8") as handle:
    json.dump(
        {
            "description": "跨 token UTF-8 bytes; 不包含用户音频或完整模型权重",
            "cases": [
                {"text": "中文", "bytes": [228, 184, 173, 230, 150, 135]},
                {"text": "会议记录 ✅", "bytes": list("会议记录 ✅".encode("utf-8"))},
            ],
        },
        handle,
        ensure_ascii=False,
        indent=2,
    )

with open(os.path.join(root, "manifest.json"), "w", encoding="utf-8") as handle:
    json.dump(
        {
            "schemaVersion": 1,
            "purpose": "MRQ-00 / MRQ-04 本地性能与 Qwen 输出基线",
            "smallAudio": "small-audio.m4a",
            "longAudio": "long-audio.m4a",
            "summaryCount": 500,
            "qwenFixture": "qwen-byte-token.json",
            "privacy": "synthetic audio and deterministic metadata only",
        },
        handle,
        ensure_ascii=False,
        indent=2,
    )
PY

echo "material-benchmark-fixtures: $fixture_directory (12s + 60min + 500 summaries)"
