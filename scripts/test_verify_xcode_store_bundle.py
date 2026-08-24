#!/usr/bin/env python3

from __future__ import annotations

import importlib.util
import json
import plistlib
import shutil
import tempfile
import unittest
from pathlib import Path


SCRIPT_PATH = Path(__file__).with_name("verify_xcode_store_bundle.py")
SPEC = importlib.util.spec_from_file_location("verify_xcode_store_bundle", SCRIPT_PATH)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class XcodeStoreBundleTests(unittest.TestCase):
    def make_bundle(self) -> Path:
        root = Path(tempfile.mkdtemp(prefix="woice-xcode-store-bundle-"))
        self.addCleanup(shutil.rmtree, root)
        app = root / "Woice.app"
        contents = app / "Contents"
        resources = contents / "Resources"
        executable = contents / "MacOS" / "Woice"
        resources.mkdir(parents=True)
        executable.parent.mkdir(parents=True)
        shutil.copyfile("/usr/bin/true", executable)
        executable.chmod(0o755)
        with (contents / "Info.plist").open("wb") as handle:
            plistlib.dump(
                {
                    "CFBundleIdentifier": "com.woice.app",
                    "CFBundleIconFile": "AppIcon",
                    "CFBundleIconName": "AppIcon",
                    "CFBundlePackageType": "APPL",
                    "LSMinimumSystemVersion": "14.0",
                    "NSMicrophoneUsageDescription": "fixture",
                    "NSScreenCaptureUsageDescription": "fixture",
                    "NSAudioCaptureUsageDescription": "fixture",
                    "NSSpeechRecognitionUsageDescription": "fixture",
                },
                handle,
            )
        with (resources / "PrivacyInfo.xcprivacy").open("wb") as handle:
            plistlib.dump(
                {
                    "NSPrivacyCollectedDataTypes": [],
                    "NSPrivacyTracking": False,
                    "NSPrivacyTrackingDomains": [],
                    "NSPrivacyAccessedAPITypes": [],
                },
                handle,
            )
        (resources / "DistributionManifest.json").write_text(
            json.dumps(
                {
                    "appVersion": "0.1.0",
                    "buildVersion": "1",
                    "bundledModelPackIDs": [],
                    "capabilityProfile": MODULE.EXPECTED_CAPABILITIES,
                    "flavor": "store",
                    "schemaVersion": 1,
                }
            ),
            encoding="utf-8",
        )
        (resources / "SBOM.json").write_text(
            json.dumps(
                {
                    "bomFormat": "CycloneDX",
                    "components": [
                        {"name": "argmax-oss-swift", "version": "1.0.0"}
                    ],
                    "specVersion": "1.5",
                }
            ),
            encoding="utf-8",
        )
        for name in ("AppIcon.icns", "Assets.car", "NOTICES.md"):
            (resources / name).write_bytes(b"fixture")
        return app

    def test_valid_formal_store_bundle_is_accepted(self) -> None:
        app = self.make_bundle()
        MODULE.verify(app)

    def test_missing_distribution_manifest_is_rejected(self) -> None:
        app = self.make_bundle()
        (app / "Contents/Resources/DistributionManifest.json").unlink()
        with self.assertRaises(MODULE.XcodeStoreBundleError):
            MODULE.verify(app)


if __name__ == "__main__":
    unittest.main()
