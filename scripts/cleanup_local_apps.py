#!/usr/bin/env python3
"""Remove only known rebuildable Woice app copies before a local Dev build/install."""

from __future__ import annotations

import argparse
import plistlib
import shutil
from datetime import datetime
from pathlib import Path


DIRECT_BUNDLE_ID = "com.woice.app"
STORE_BUNDLE_ID = "com.water.woice"
DEV_APP_NAME = "Woice (Dev).app"
LEGACY_APP_NAME = "Woice.app"
KNOWN_BUILD_BUNDLES = (
    DEV_APP_NAME,
    LEGACY_APP_NAME,
    "Woice-Core.app",
    "Woice-Offline.app",
    "Woice-Store.app",
    "Woice-Stable-A.app",
    "Woice-Stable-B.app",
    "Woice-Development.app",
)
KNOWN_DERIVED_CONFIGURATIONS = ("Release-Direct", "Release-AppStore")


class CleanupError(ValueError):
    pass


def read_bundle_id(app: Path) -> str:
    info_path = app / "Contents" / "Info.plist"
    try:
        with info_path.open("rb") as handle:
            info = plistlib.load(handle)
    except (OSError, plistlib.InvalidFileException) as error:
        raise CleanupError(f"Unable to read app identity: {app}") from error
    bundle_id = info.get("CFBundleIdentifier")
    if not isinstance(bundle_id, str) or not bundle_id:
        raise CleanupError(f"App bundle identifier is missing: {app}")
    return bundle_id


def remove_exact_app(app: Path, expected_bundle_id: str | None = None) -> None:
    if not app.exists() and not app.is_symlink():
        return
    if app.suffix != ".app" or app.is_symlink() or not app.is_dir():
        raise CleanupError(f"Refusing to remove unsafe app target: {app}")
    if expected_bundle_id is not None and read_bundle_id(app) != expected_bundle_id:
        raise CleanupError(f"Refusing to remove app with unexpected identity: {app}")
    shutil.rmtree(app)


def cleanup_build_apps(build_dir: Path) -> list[Path]:
    build_dir = build_dir.expanduser().resolve()
    if build_dir.name != "build":
        raise CleanupError(f"Build cleanup requires a directory named build: {build_dir}")
    if not build_dir.exists():
        return []
    if not build_dir.is_dir() or build_dir.is_symlink():
        raise CleanupError(f"Build cleanup target is not a safe directory: {build_dir}")
    removed: list[Path] = []
    for bundle_name in KNOWN_BUILD_BUNDLES:
        target = build_dir / bundle_name
        if target.exists() or target.is_symlink():
            remove_exact_app(target)
            removed.append(target)
    return removed


def cleanup_derived_product_apps(products_dir: Path) -> list[Path]:
    products_dir = products_dir.expanduser().resolve()
    if products_dir.name != "Products":
        raise CleanupError(
            f"Derived product cleanup requires a directory named Products: {products_dir}"
        )
    if not products_dir.exists():
        return []
    if not products_dir.is_dir() or products_dir.is_symlink():
        raise CleanupError(f"Derived products target is not a safe directory: {products_dir}")

    removed: list[Path] = []
    for configuration in KNOWN_DERIVED_CONFIGURATIONS:
        configuration_dir = products_dir / configuration
        for bundle_name in KNOWN_BUILD_BUNDLES:
            target = configuration_dir / bundle_name
            if target.exists() or target.is_symlink():
                remove_exact_app(target)
                removed.append(target)
    return removed


def unique_trash_target(trash_dir: Path) -> Path:
    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    candidate = trash_dir / f"Woice-legacy-dev-{timestamp}.app"
    suffix = 1
    while candidate.exists():
        candidate = trash_dir / f"Woice-legacy-dev-{timestamp}-{suffix}.app"
        suffix += 1
    return candidate


def unique_archive_trash_target(trash_dir: Path, archive: Path) -> Path:
    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    candidate = trash_dir / f"{archive.stem}-{timestamp}{archive.suffix}"
    suffix = 1
    while candidate.exists():
        candidate = trash_dir / f"{archive.stem}-{timestamp}-{suffix}{archive.suffix}"
        suffix += 1
    return candidate


def trash_obsolete_archives(
    build_dir: Path, keep_archive: Path, trash_dir: Path
) -> list[Path]:
    build_dir = build_dir.expanduser().resolve()
    keep_archive = keep_archive.expanduser().resolve()
    trash_dir = trash_dir.expanduser().resolve()
    if build_dir.name != "build" or not build_dir.is_dir() or build_dir.is_symlink():
        raise CleanupError(f"Archive cleanup requires a safe build directory: {build_dir}")
    if keep_archive.parent != build_dir or keep_archive.suffix != ".xcarchive":
        raise CleanupError(f"Archive to keep must be a direct build child: {keep_archive}")
    if not keep_archive.is_dir() or keep_archive.is_symlink():
        raise CleanupError(f"Archive to keep does not exist or is unsafe: {keep_archive}")

    moved: list[Path] = []
    for archive in sorted(build_dir.glob("Woice*.xcarchive")):
        if archive.resolve() == keep_archive:
            continue
        if not archive.is_dir() or archive.is_symlink():
            raise CleanupError(f"Refusing to move unsafe archive target: {archive}")
        trash_dir.mkdir(parents=True, exist_ok=True)
        destination = unique_archive_trash_target(trash_dir, archive)
        shutil.move(str(archive), destination)
        moved.append(destination)
    return moved


def prepare_install(applications_dir: Path, trash_dir: Path) -> list[tuple[Path, str]]:
    applications_dir = applications_dir.expanduser().resolve()
    trash_dir = trash_dir.expanduser().resolve()
    if not applications_dir.is_dir() or applications_dir.is_symlink():
        raise CleanupError(f"Applications directory is not safe: {applications_dir}")

    actions: list[tuple[Path, str]] = []
    dev_app = applications_dir / DEV_APP_NAME
    if dev_app.exists() or dev_app.is_symlink():
        remove_exact_app(dev_app, DIRECT_BUNDLE_ID)
        actions.append((dev_app, "removed-for-replacement"))

    legacy_app = applications_dir / LEGACY_APP_NAME
    if legacy_app.exists() or legacy_app.is_symlink():
        if legacy_app.is_symlink() or not legacy_app.is_dir():
            raise CleanupError(f"Refusing to inspect unsafe legacy app target: {legacy_app}")
        bundle_id = read_bundle_id(legacy_app)
        if bundle_id == DIRECT_BUNDLE_ID:
            trash_dir.mkdir(parents=True, exist_ok=True)
            destination = unique_trash_target(trash_dir)
            shutil.move(str(legacy_app), destination)
            actions.append((destination, "trashed-legacy-dev"))
        elif bundle_id != STORE_BUNDLE_ID:
            raise CleanupError(f"Refusing to move app with unexpected identity: {legacy_app}")
        else:
            actions.append((legacy_app, "preserved-store"))
    return actions


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--build-dir", type=Path)
    parser.add_argument("--derived-products-dir", type=Path, action="append", default=[])
    parser.add_argument("--archive-root", type=Path)
    parser.add_argument("--keep-archive", type=Path)
    parser.add_argument("--prepare-install", action="store_true")
    parser.add_argument("--applications-dir", type=Path, default=Path("/Applications"))
    parser.add_argument("--trash-dir", type=Path, default=Path.home() / ".Trash")
    args = parser.parse_args()
    if (
        args.build_dir is None
        and not args.derived_products_dir
        and args.archive_root is None
        and not args.prepare_install
    ):
        parser.error(
            "Provide --build-dir, --derived-products-dir, --archive-root, and/or --prepare-install"
        )
    if (args.archive_root is None) != (args.keep_archive is None):
        parser.error("--archive-root and --keep-archive must be provided together")
    try:
        if args.build_dir is not None:
            for removed in cleanup_build_apps(args.build_dir):
                print(f"cleanup-local-apps: removed rebuildable bundle: {removed}")
        for products_dir in args.derived_products_dir:
            for removed in cleanup_derived_product_apps(products_dir):
                print(f"cleanup-local-apps: removed derived bundle: {removed}")
        if args.archive_root is not None and args.keep_archive is not None:
            for moved in trash_obsolete_archives(
                args.archive_root, args.keep_archive, args.trash_dir
            ):
                print(f"cleanup-local-apps: trashed obsolete archive: {moved}")
        if args.prepare_install:
            for path, action in prepare_install(args.applications_dir, args.trash_dir):
                print(f"cleanup-local-apps: {action}: {path}")
    except CleanupError as error:
        print(f"cleanup-local-apps: {error}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
