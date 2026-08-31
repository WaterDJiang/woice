#!/usr/bin/env python3

from __future__ import annotations

import importlib.util
import plistlib
import tempfile
import unittest
from pathlib import Path


SCRIPT_PATH = Path(__file__).with_name("cleanup_local_apps.py")
SPEC = importlib.util.spec_from_file_location("cleanup_local_apps", SCRIPT_PATH)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def create_app(path: Path, bundle_id: str) -> None:
    contents = path / "Contents"
    contents.mkdir(parents=True)
    with (contents / "Info.plist").open("wb") as handle:
        plistlib.dump({"CFBundleIdentifier": bundle_id}, handle)


class CleanupLocalAppsTests(unittest.TestCase):
    def test_build_cleanup_removes_only_known_top_level_apps(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            build = root / "build"
            build.mkdir()
            for name in MODULE.KNOWN_BUILD_BUNDLES:
                create_app(build / name, MODULE.DIRECT_BUNDLE_ID)
            unknown = build / "Woice-Custom.app"
            create_app(unknown, MODULE.DIRECT_BUNDLE_ID)
            archive_app = build / "Woice-Store.xcarchive/Products/Applications/Woice.app"
            create_app(archive_app, MODULE.STORE_BUNDLE_ID)

            removed = MODULE.cleanup_build_apps(build)

            self.assertEqual(len(removed), len(MODULE.KNOWN_BUILD_BUNDLES))
            self.assertTrue(unknown.is_dir())
            self.assertTrue(archive_app.is_dir())

    def test_derived_products_cleanup_removes_known_apps_only(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            products = Path(temporary_directory) / "Products"
            create_app(
                products / "Release-Direct" / MODULE.DEV_APP_NAME,
                MODULE.DIRECT_BUNDLE_ID,
            )
            create_app(
                products / "Release-AppStore" / MODULE.LEGACY_APP_NAME,
                MODULE.STORE_BUNDLE_ID,
            )
            unknown = products / "Debug" / "Woice-Custom.app"
            create_app(unknown, MODULE.DIRECT_BUNDLE_ID)

            removed = MODULE.cleanup_derived_product_apps(products)

            self.assertEqual(len(removed), 2)
            self.assertTrue(unknown.is_dir())

    def test_archive_cleanup_trashes_old_archives_and_keeps_current(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            build = root / "build"
            trash = root / "Trash"
            current = build / "Woice-Store-current.xcarchive"
            old = build / "Woice-Store-old.xcarchive"
            create_app(current / "Products/Applications/Woice.app", MODULE.STORE_BUNDLE_ID)
            create_app(old / "Products/Applications/Woice.app", MODULE.STORE_BUNDLE_ID)

            moved = MODULE.trash_obsolete_archives(build, current, trash)

            self.assertTrue(current.is_dir())
            self.assertFalse(old.exists())
            self.assertEqual(len(moved), 1)
            self.assertEqual(len(list(trash.glob("Woice-Store-old-*.xcarchive"))), 1)

    def test_install_cleanup_trashes_legacy_dev_and_replaces_dev_name(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            applications = root / "Applications"
            trash = root / "Trash"
            applications.mkdir()
            create_app(applications / MODULE.DEV_APP_NAME, MODULE.DIRECT_BUNDLE_ID)
            create_app(applications / MODULE.LEGACY_APP_NAME, MODULE.DIRECT_BUNDLE_ID)

            actions = MODULE.prepare_install(applications, trash)

            self.assertFalse((applications / MODULE.DEV_APP_NAME).exists())
            self.assertFalse((applications / MODULE.LEGACY_APP_NAME).exists())
            self.assertEqual(len(list(trash.glob("Woice-legacy-dev-*.app"))), 1)
            self.assertEqual({action for _, action in actions}, {
                "removed-for-replacement",
                "trashed-legacy-dev",
            })

    def test_install_cleanup_preserves_store_app(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            applications = root / "Applications"
            trash = root / "Trash"
            applications.mkdir()
            store_app = applications / MODULE.LEGACY_APP_NAME
            create_app(store_app, MODULE.STORE_BUNDLE_ID)

            actions = MODULE.prepare_install(applications, trash)

            self.assertTrue(store_app.is_dir())
            self.assertEqual(actions, [(store_app.resolve(), "preserved-store")])
            self.assertFalse(trash.exists())

    def test_install_cleanup_rejects_unknown_legacy_identity(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            applications = root / "Applications"
            applications.mkdir()
            create_app(applications / MODULE.LEGACY_APP_NAME, "example.unknown")

            with self.assertRaises(MODULE.CleanupError):
                MODULE.prepare_install(applications, root / "Trash")


if __name__ == "__main__":
    unittest.main()
