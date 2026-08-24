#!/usr/bin/env python3

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from release_artifact_manifest import (
    ManifestError,
    create_local_manifest,
    validate_remote_manifest,
    verify_remote,
)


class ReleaseArtifactManifestTests(unittest.TestCase):
    def test_create_manifest_records_size_and_sha256(self) -> None:
        with tempfile.TemporaryDirectory(prefix="woice-release-manifest-") as directory:
            root = Path(directory)
            core = root / "Woice-Core-20260824.dmg"
            offline = root / "Woice-Offline-20260824.dmg"
            core.write_bytes(b"core fixture")
            offline.write_bytes(b"offline fixture")
            output = root / "ReleaseManifest.json"

            manifest = create_local_manifest(
                output=output,
                build_version="20260824",
                bundle_id="com.woice.app",
                catalog_url="https://models.example.test/catalog.json",
                catalog_id="com.woice.catalog",
                core_dmg=core,
                offline_dmg=offline,
            )

            self.assertEqual(manifest["buildVersion"], "20260824")
            self.assertEqual(manifest["artifacts"]["core"]["size"], len(b"core fixture"))
            self.assertEqual(len(manifest["artifacts"]["offline"]["sha256"]), 64)
            self.assertTrue(output.is_file())

    def test_remote_manifest_must_publish_matching_artifacts(self) -> None:
        local = {
            "schemaVersion": 1,
            "buildVersion": "20260824",
            "bundleID": "com.woice.app",
            "catalog": {
                "url": "https://models.example.test/catalog.json",
                "id": "com.woice.catalog",
            },
            "artifacts": [
                {"flavor": "core", "file": "core.dmg", "size": 4, "sha256": "a" * 64},
                {"flavor": "offline", "file": "offline.dmg", "size": 7, "sha256": "b" * 64},
            ],
        }
        remote = {
            **local,
            "catalog": {
                **local["catalog"],
                "status": "published",
                "size": 3,
                "sha256": "c" * 64,
            },
            "artifacts": [
                {
                    **local["artifacts"][0],
                    "url": "https://downloads.example.test/core.dmg",
                    "status": "published",
                },
                {
                    **local["artifacts"][1],
                    "url": "https://downloads.example.test/offline.dmg",
                    "status": "published",
                },
            ],
        }

        catalog, artifacts = validate_remote_manifest(local, remote)
        self.assertEqual(catalog["status"], "published")
        self.assertEqual(artifacts["core"]["url"], "https://downloads.example.test/core.dmg")

        remote["artifacts"][0]["status"] = "draft"
        with self.assertRaises(ManifestError):
            validate_remote_manifest(local, remote)

    def test_manifest_rejects_bundle_id_drift(self) -> None:
        local = {
            "schemaVersion": 1,
            "buildVersion": "20260824",
            "bundleID": "com.example.other",
            "catalog": {
                "url": "https://models.example.test/catalog.json",
                "id": "com.woice.catalog",
            },
            "artifacts": [
                {"flavor": "core", "file": "core.dmg", "size": 1, "sha256": "a" * 64},
                {"flavor": "offline", "file": "offline.dmg", "size": 1, "sha256": "b" * 64},
            ],
        }
        with self.assertRaises(ManifestError):
            validate_remote_manifest(local, local)

    def test_remote_verification_records_catalog_and_artifact_probes(self) -> None:
        with tempfile.TemporaryDirectory(prefix="woice-release-verify-") as directory:
            root = Path(directory)
            core = root / "core.dmg"
            offline = root / "offline.dmg"
            core.write_bytes(b"core")
            offline.write_bytes(b"offline")
            local_path = root / "ReleaseManifest.json"
            local = create_local_manifest(
                output=local_path,
                build_version="20260824",
                bundle_id="com.woice.app",
                catalog_url="https://models.example.test/catalog.json",
                catalog_id="com.woice.catalog",
                core_dmg=core,
                offline_dmg=offline,
            )
            remote = {
                **local,
                "catalog": {
                    **local["catalog"],
                    "status": "published",
                    "size": 12,
                    "sha256": "c" * 64,
                },
                "artifacts": [
                    {
                        **local["artifacts"]["core"],
                        "url": "https://downloads.example.test/core.dmg",
                        "status": "published",
                    },
                    {
                        **local["artifacts"]["offline"],
                        "url": "https://downloads.example.test/offline.dmg",
                        "status": "published",
                    },
                ],
            }
            with (
                patch("release_artifact_manifest.fetch_remote_manifest", return_value=remote),
                patch(
                    "release_artifact_manifest._fetch_catalog",
                    return_value={"status": 200, "size": 12, "sha256": "c" * 64},
                ),
                patch(
                    "release_artifact_manifest._head",
                    side_effect=lambda url, expected_size, field, timeout: {
                        "status": 200,
                        "size": expected_size,
                    },
                ),
            ):
                evidence = verify_remote(
                    local_manifest_path=local_path,
                    remote_manifest_url="https://downloads.example.test/release.json",
                    output=root / "remote-evidence.json",
                )

            self.assertEqual(evidence["catalog"]["probe"]["sha256"], "c" * 64)
            self.assertEqual(evidence["artifacts"][1]["probe"]["size"], len(b"offline"))
            self.assertTrue((root / "remote-evidence.json").is_file())


if __name__ == "__main__":
    unittest.main()
