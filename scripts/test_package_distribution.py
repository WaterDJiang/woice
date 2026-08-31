#!/usr/bin/env python3
"""Regression tests for the fail-closed bundled-model packaging gate."""

from __future__ import annotations

import hashlib
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


SCRIPT_PATH = Path(__file__).with_name("package_distribution.py")
SPEC = importlib.util.spec_from_file_location("package_distribution", SCRIPT_PATH)
assert SPEC and SPEC.loader
PACKAGE_DISTRIBUTION = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PACKAGE_DISTRIBUTION)


def create_fixture(root: Path, *, license_info: object, notice_path: str = "NOTICE.txt") -> Path:
    version_dir = root / "com.woice.whisperkit.tiny" / "revision-1"
    version_dir.mkdir(parents=True)
    payload = version_dir / "weights.bin"
    payload.write_bytes(b"fixture model payload")
    notice_relative = Path(notice_path)
    notice = version_dir / notice_relative
    if not notice_relative.is_absolute() and ".." not in notice_relative.parts:
        notice.parent.mkdir(parents=True, exist_ok=True)
        notice.write_text("fixture notice\n", encoding="utf-8")
    digest = hashlib.sha256(payload.read_bytes()).hexdigest()
    manifest = {
        "providerID": "com.woice.whisperkit",
        "packID": "com.woice.whisperkit.tiny",
        "version": "revision-1",
        "license": license_info,
        "files": [
            {
                "relativePath": "weights.bin",
                "byteCount": payload.stat().st_size,
                "sha256": digest,
            }
        ],
    }
    (version_dir / "manifest.json").write_text(
        json.dumps(manifest), encoding="utf-8"
    )
    return version_dir


class PackageDistributionModelGateTests(unittest.TestCase):
    def test_store_flavor_uses_store_bundle_id(self) -> None:
        plist = {"CFBundleIdentifier": "com.woice.app"}

        PACKAGE_DISTRIBUTION.apply_flavor_bundle_identity(plist, "store")

        self.assertEqual(plist["CFBundleIdentifier"], "com.water.woice")

    def test_store_flavor_rejects_any_bundled_model_root(self) -> None:
        with self.assertRaises(SystemExit):
            PACKAGE_DISTRIBUTION.validate_model_embedding_policy(
                "store", Path("/tmp/fixture-model")
            )

        PACKAGE_DISTRIBUTION.validate_model_embedding_policy("store", None)

    def test_direct_flavor_keeps_legacy_bundle_id(self) -> None:
        plist = {"CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)"}

        PACKAGE_DISTRIBUTION.apply_flavor_bundle_identity(plist, "core")

        self.assertEqual(plist["CFBundleIdentifier"], "com.woice.app")
        self.assertEqual(plist["CFBundleDisplayName"], "Woice")
        self.assertEqual(plist["CFBundleName"], "Woice")
        self.assertEqual(plist["WOICEAppChannel"], "release")

    def test_dev_flavor_uses_distinct_local_name(self) -> None:
        plist = {
            "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)",
            "CFBundleDisplayName": "$(WOICE_APP_DISPLAY_NAME)",
            "CFBundleName": "$(WOICE_APP_DISPLAY_NAME)",
        }

        PACKAGE_DISTRIBUTION.apply_flavor_bundle_identity(plist, "dev")

        self.assertEqual(plist["CFBundleIdentifier"], "com.woice.app")
        self.assertEqual(plist["CFBundleDisplayName"], "Woice (Dev)")
        self.assertEqual(plist["CFBundleName"], "Woice (Dev)")
        self.assertEqual(plist["CFBundleExecutable"], "Woice")
        self.assertEqual(plist["WOICEAppChannel"], "dev")

    def test_valid_license_and_notice_are_accepted(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            version_dir = create_fixture(
                root,
                license_info={
                    "identifier": "MIT",
                    "sourceURL": "https://example.invalid/model",
                    "noticePath": "NOTICE.txt",
                },
            )

            resolved_dir, manifest = PACKAGE_DISTRIBUTION.find_model_version(root)

            self.assertEqual(resolved_dir, version_dir)
            self.assertEqual(manifest["packID"], "com.woice.whisperkit.tiny")

    def test_missing_license_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            create_fixture(root, license_info=None)

            with self.assertRaises(SystemExit):
                PACKAGE_DISTRIBUTION.find_model_version(root)

    def test_unsafe_notice_path_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            create_fixture(
                root,
                license_info={
                    "identifier": "MIT",
                    "sourceURL": "https://example.invalid/model",
                    "noticePath": "../NOTICE.txt",
                },
            )

            with self.assertRaises(SystemExit):
                PACKAGE_DISTRIBUTION.find_model_version(root)

    def test_non_https_license_source_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            create_fixture(
                root,
                license_info={
                    "identifier": "MIT",
                    "sourceURL": "http://example.invalid/model",
                    "noticePath": "NOTICE.txt",
                },
            )

            with self.assertRaises(SystemExit):
                PACKAGE_DISTRIBUTION.find_model_version(root)


if __name__ == "__main__":
    unittest.main()
