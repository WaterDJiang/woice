#!/usr/bin/env python3

import json
import tempfile
import unittest
from pathlib import Path

import generate_model_catalog


class GenerateModelCatalogTests(unittest.TestCase):
    def test_whisper_entry_recalculates_size_after_notice_normalization(self) -> None:
        pack_id = "com.woice.whisperkit.tiny"
        spec = generate_model_catalog.MODEL_SPECS[pack_id]
        with tempfile.TemporaryDirectory() as temporary:
            model_root = Path(temporary)
            version_root = model_root / pack_id / spec["model_revision"]
            version_root.mkdir(parents=True)
            manifest = {
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
                "files": [
                    {
                        "relativePath": "weights.bin",
                        "byteCount": 10,
                        "sha256": "a" * 64,
                    },
                    {
                        "relativePath": "NOTICE.txt",
                        "byteCount": 1,
                        "sha256": "b" * 64,
                    },
                ],
                "license": {
                    "identifier": "MIT",
                    "noticePath": "NOTICE.txt",
                    "sourceURL": spec["notice_source"],
                },
                "size": 11,
            }
            (version_root / "manifest.json").write_text(
                json.dumps(manifest), encoding="utf-8"
            )

            entry = generate_model_catalog.make_entry(
                pack_id,
                model_root,
                "https://huggingface.co",
                "https://models.example.test/notices",
            )

        self.assertEqual(entry["size"], sum(item["byteCount"] for item in entry["files"]))

    def test_qwen_is_a_signed_catalog_candidate(self) -> None:
        pack_id = "com.woice.qwen3.asr.0.6b.4bit"
        spec = generate_model_catalog.MODEL_SPECS[pack_id]
        with tempfile.TemporaryDirectory() as temporary:
            model_root = Path(temporary)
            version_root = model_root / pack_id / spec["model_revision"]
            version_root.mkdir(parents=True)
            manifest = {
                "schemaVersion": 1,
                "packID": pack_id,
                "modelID": spec["model_id"],
                "version": spec["model_revision"],
                "providerID": spec["provider_id"],
                "transport": "inProcess",
                "capabilities": ["transcription", "timestamps"],
                "platform": "macOS",
                "architecture": "arm64",
                "minimumOS": "14.0",
                "files": [
                    {
                        "relativePath": "model.safetensors",
                        "byteCount": 10,
                        "sha256": "a" * 64,
                    },
                    {
                        "relativePath": "README.md",
                        "byteCount": 5,
                        "sha256": "b" * 64,
                    },
                ],
                "license": {
                    "identifier": "Apache-2.0",
                    "noticePath": "README.md",
                    "sourceURL": "https://huggingface.co/mlx-community/Qwen3-ASR-0.6B-4bit",
                },
                "size": 15,
                "displayName": spec["display_name"],
                "isRecommended": False,
                "storeCompatible": True,
                "runtimeID": spec["runtime_id"],
            }
            (version_root / "manifest.json").write_text(
                json.dumps(manifest), encoding="utf-8"
            )

            entry = generate_model_catalog.make_entry(
                pack_id,
                model_root,
                "https://huggingface.co",
                "https://models.example.test/notices",
            )

        self.assertEqual(entry["packID"], pack_id)
        self.assertEqual(entry["providerID"], "com.woice.qwen3-asr")
        self.assertEqual(entry["runtimeID"], "com.woice.qwen3-asr")
        self.assertTrue(entry["storeCompatible"])
        self.assertEqual(entry["license"]["identifier"], "Apache-2.0")
        self.assertEqual(
            entry["files"][0]["downloadURL"],
            "https://huggingface.co/mlx-community/Qwen3-ASR-0.6B-4bit/resolve/"
            f"{spec['model_revision']}/model.safetensors",
        )


if __name__ == "__main__":
    unittest.main()
