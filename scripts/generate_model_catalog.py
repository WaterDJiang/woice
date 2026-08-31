#!/usr/bin/env python3
"""Build and sign the public Woice model catalog from verified local packs.

The catalog contains only model metadata, hashes, and HTTPS file URLs. The
Ed25519 private key is supplied outside the repository and is never written to
the generated JSON or to stdout.
"""

from __future__ import annotations

import argparse
import base64
import datetime as dt
import json
import subprocess
import tempfile
from pathlib import Path
from typing import Any


MODEL_SPECS: dict[str, dict[str, str]] = {
    "com.woice.whisperkit.tiny": {
        "model_id": "openai-whisper-tiny",
        "model_folder": "openai_whisper-tiny",
        "model_repo": "argmaxinc/whisperkit-coreml",
        "model_revision": "0f63a7800b00dd0226abd051b906c246e1907482",
        "tokenizer_repo": "openai/whisper-tiny",
        "tokenizer_revision": "169d4a4341b33bc18d8881c4b69c2e104e1cc0af",
        "display_name": "WhisperKit Tiny（多语言）",
        "notice_slug": "whisperkit-tiny",
        "notice_source": "https://huggingface.co/argmaxinc/whisperkit-coreml/tree/0f63a7800b00dd0226abd051b906c246e1907482/openai_whisper-tiny",
    },
    "com.woice.whisperkit.large-v3": {
        "model_id": "openai-whisper-large-v3-v20240930-626mb",
        "model_folder": "openai_whisper-large-v3-v20240930_626MB",
        "model_repo": "argmaxinc/whisperkit-coreml",
        "model_revision": "0f63a7800b00dd0226abd051b906c246e1907482",
        "tokenizer_repo": "openai/whisper-large-v3",
        "tokenizer_revision": "06f233fe06e710322aca913c1bc4249a0d71fce1",
        "display_name": "WhisperKit Large-v3（高准确率候选）",
        "notice_slug": "whisperkit-large-v3",
        "notice_source": "https://huggingface.co/argmaxinc/whisperkit-coreml/tree/0f63a7800b00dd0226abd051b906c246e1907482/openai_whisper-large-v3-v20240930_626MB",
    },
    "com.woice.qwen3.asr.0.6b.4bit": {
        "kind": "qwen",
        "model_id": "qwen3-asr-0.6b-4bit",
        "model_repo": "mlx-community/Qwen3-ASR-0.6B-4bit",
        "model_revision": "313d850181767edf09f00a9c289becca70e58cd0",
        "display_name": "Qwen3-ASR 0.6B（本机）",
        "provider_id": "com.woice.qwen3-asr",
        "runtime_id": "com.woice.qwen3-asr",
    },
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--private-key", type=Path, required=True)
    parser.add_argument("--catalog-id", default="woice-model-catalog")
    parser.add_argument("--catalog-version", type=int, required=True)
    parser.add_argument("--key-id", default="woice-release-2026-08")
    parser.add_argument(
        "--model-base-url", default="https://huggingface.co", help="HTTPS model host root"
    )
    parser.add_argument(
        "--notice-base-url",
        default="https://raw.githubusercontent.com/WaterDJiang/woice/main/Resources/ModelCatalog",
        help="HTTPS root containing the public NOTICE files",
    )
    return parser.parse_args()


def read_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise SystemExit(f"无法读取模型清单：{path}") from error
    if not isinstance(value, dict):
        raise SystemExit(f"模型清单顶层必须是对象：{path}")
    return value


def normalized_url(value: str) -> str:
    if not value.startswith("https://") or "?" in value or "#" in value:
        raise SystemExit(f"下载地址必须是无查询参数的 HTTPS URL：{value}")
    return value.rstrip("/")


def file_download_url(
    pack: dict[str, str], relative_path: str, model_base_url: str, notice_base_url: str
) -> str:
    if pack.get("kind") == "qwen":
        return (
            f"{model_base_url}/{pack['model_repo']}/resolve/"
            f"{pack['model_revision']}/{relative_path}"
        )
    if relative_path == "NOTICE.txt":
        return f"{notice_base_url}/{pack['notice_slug']}/NOTICE.txt"
    tokenizer_prefix = "models/openai/"
    if relative_path.startswith(tokenizer_prefix):
        tokenizer_name, _, tokenizer_path = relative_path[len(tokenizer_prefix) :].partition("/")
        expected_name = pack["tokenizer_repo"].split("/", maxsplit=1)[1]
        if tokenizer_name != expected_name or not tokenizer_path:
            raise SystemExit(f"tokenizer 文件路径与固定仓库不一致：{relative_path}")
        return (
            f"{model_base_url}/{pack['tokenizer_repo']}/resolve/"
            f"{pack['tokenizer_revision']}/{tokenizer_path}"
        )
    return (
        f"{model_base_url}/{pack['model_repo']}/resolve/{pack['model_revision']}/"
        f"{pack['model_folder']}/{relative_path}"
    )


def make_entry(
    pack_id: str,
    model_root: Path,
    model_base_url: str,
    notice_base_url: str,
) -> dict[str, Any]:
    spec = MODEL_SPECS[pack_id]
    manifest_paths = sorted(model_root.joinpath(pack_id).glob("*/manifest.json"))
    if len(manifest_paths) != 1:
        raise SystemExit(f"模型包必须恰好有一个已验证本机版本：{pack_id}")
    local = read_json(manifest_paths[0])
    if local.get("packID") != pack_id or local.get("version") != spec["model_revision"]:
        raise SystemExit(f"本机模型版本与固定 revision 不一致：{pack_id}")
    expected_provider = spec.get("provider_id", "com.woice.whisperkit")
    if local.get("providerID") != expected_provider:
        raise SystemExit(f"模型 Provider 与固定配置不一致：{pack_id}")
    files = local.get("files")
    if not isinstance(files, list) or not files:
        raise SystemExit(f"本机模型没有文件清单：{pack_id}")
    transformed_files: list[dict[str, Any]] = []
    for file in files:
        if not isinstance(file, dict):
            raise SystemExit(f"模型文件条目无效：{pack_id}")
        relative_path = file.get("relativePath")
        byte_count = file.get("byteCount")
        sha256 = file.get("sha256")
        if not isinstance(relative_path, str) or not isinstance(byte_count, int) or not isinstance(sha256, str):
            raise SystemExit(f"模型文件条目字段无效：{pack_id}/{relative_path}")
        transformed_files.append(
            {
                "relativePath": relative_path,
                "byteCount": byte_count,
                "sha256": sha256.lower(),
                "downloadURL": file_download_url(
                    spec, relative_path, model_base_url, notice_base_url
                ),
            }
        )

    total_size = sum(item["byteCount"] for item in transformed_files)
    if spec.get("kind") == "qwen":
        if local.get("runtimeID") != spec["runtime_id"]:
            raise SystemExit(f"Qwen Runtime 与固定配置不一致：{pack_id}")
        license_value = local.get("license")
        if not isinstance(license_value, dict) or license_value.get("identifier") != "Apache-2.0":
            raise SystemExit(f"Qwen 模型许可证不是 Apache-2.0：{pack_id}")
        if not any(item["relativePath"] == license_value.get("noticePath") for item in transformed_files):
            raise SystemExit(f"Qwen 模型清单缺少许可证 Notice：{pack_id}")
        entry = dict(local)
        entry.update(
            {
                "files": transformed_files,
                "size": total_size,
                "displayName": spec["display_name"],
                "isRecommended": False,
                "storeCompatible": True,
                "downloadBaseURL": model_base_url,
            }
        )
        return entry

    committed_notice = Path(__file__).resolve().parents[1] / "Resources/ModelCatalog" / spec["notice_slug"] / "NOTICE.txt"
    if not committed_notice.is_file():
        raise SystemExit(f"公开 NOTICE 文件不存在：{committed_notice}")
    notice_bytes = committed_notice.read_bytes()
    notice_file = next((item for item in transformed_files if item["relativePath"] == "NOTICE.txt"), None)
    if notice_file is None:
        raise SystemExit(f"模型清单缺少 NOTICE.txt：{pack_id}")
    notice_file["byteCount"] = len(notice_bytes)
    notice_file["sha256"] = __import__("hashlib").sha256(notice_bytes).hexdigest()

    return {
        "schemaVersion": 1,
        "packID": pack_id,
        "modelID": spec["model_id"],
        "version": spec["model_revision"],
        "providerID": "com.woice.whisperkit",
        "transport": "inProcess",
        "capabilities": ["transcription", "timestamps"],
        "platform": "macOS",
        "architecture": "arm64",
        "minimumOS": "14.0",
        "files": transformed_files,
        "license": {
            "identifier": "MIT",
            "noticePath": "NOTICE.txt",
            "sourceURL": spec["notice_source"],
        },
        "provenance": {
            "upstreamModelID": spec["model_repo"],
            "upstreamRevision": spec["model_revision"],
            "sourceURL": spec["notice_source"],
            "derivedFormat": "WhisperKit Core ML model pack",
            "conversionTool": "WhisperKit Hub snapshot",
            "conversionRevision": "argmax-oss-swift 1.0.0",
        },
        "size": total_size,
        "displayName": spec["display_name"],
        "isRecommended": pack_id.endswith("large-v3"),
        "storeCompatible": True,
        "runtimeID": "com.woice.whisperkit",
        "downloadBaseURL": model_base_url,
    }


def private_key_der_and_public_base64(private_key: Path) -> tuple[bytes, str]:
    if not private_key.is_file():
        raise SystemExit(f"签名私钥不存在：{private_key}")
    with tempfile.TemporaryDirectory(prefix="woice-catalog-key-") as temporary:
        public_der = Path(temporary) / "public.der"
        result = subprocess.run(
            ["openssl", "pkey", "-in", str(private_key), "-pubout", "-outform", "DER", "-out", str(public_der)],
            capture_output=True,
            text=True,
            check=False,
        )
        if result.returncode != 0:
            raise SystemExit(f"无法从签名私钥导出公钥：{result.stderr.strip()}")
        der = public_der.read_bytes()
    if len(der) < 32:
        raise SystemExit("Ed25519 公钥编码无效。")
    return der[-32:], base64.b64encode(der[-32:]).decode("ascii")


def sign_payload(private_key: Path, payload: bytes) -> bytes:
    with tempfile.TemporaryDirectory(prefix="woice-catalog-sign-") as temporary:
        payload_path = Path(temporary) / "payload"
        signature_path = Path(temporary) / "signature"
        payload_path.write_bytes(payload)
        result = subprocess.run(
            [
                "openssl",
                "pkeyutl",
                "-sign",
                "-rawin",
                "-inkey",
                str(private_key),
                "-in",
                str(payload_path),
                "-out",
                str(signature_path),
            ],
            capture_output=True,
            text=True,
            check=False,
        )
        if result.returncode != 0:
            raise SystemExit(f"模型 Catalog 签名失败：{result.stderr.strip()}")
        return signature_path.read_bytes()


def main() -> int:
    args = parse_args()
    if args.catalog_version <= 0:
        raise SystemExit("--catalog-version 必须大于 0。")
    model_base_url = normalized_url(args.model_base_url)
    notice_base_url = normalized_url(args.notice_base_url)
    entries = [
        make_entry(pack_id, args.model_root, model_base_url, notice_base_url)
        for pack_id in sorted(MODEL_SPECS)
    ]
    generated_at = dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    unsigned = {
        "schemaVersion": 1,
        "catalogVersion": args.catalog_version,
        "catalogID": args.catalog_id,
        "generatedAt": generated_at,
        "entries": entries,
    }
    # Match Swift JSONEncoder's canonical output used by ModelCatalog. In
    # particular, JSONEncoder escapes forward slashes in strings as `\/`.
    payload = json.dumps(
        unsigned, ensure_ascii=False, sort_keys=True, separators=(",", ":")
    ).replace("/", "\\/").encode("utf-8")
    _, public_key = private_key_der_and_public_base64(args.private_key)
    signature = sign_payload(args.private_key, payload)
    catalog = {
        **unsigned,
        "signature": {
            "algorithm": "Ed25519",
            "keyID": args.key_id,
            "value": base64.b64encode(signature).decode("ascii"),
        },
    }
    output = args.output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(
        json.dumps(catalog, ensure_ascii=False, sort_keys=True, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"catalog: wrote {output}")
    print(f"catalog: keyID={args.key_id} publicKeyBase64={public_key}")
    print(f"catalog: version={args.catalog_version} entries={len(entries)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
