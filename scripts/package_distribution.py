#!/usr/bin/env python3
"""Build a signed Core or Offline Woice app from the same release binary."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import plistlib
import shutil
import subprocess
import tempfile
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--flavor", choices=("core", "offline"), required=True)
    parser.add_argument("--binary", type=Path, required=True)
    parser.add_argument("--info-plist", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--model-root", type=Path)
    return parser.parse_args()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def find_model_version(root: Path) -> tuple[Path, dict]:
    manifests = sorted(root.glob("*/*/manifest.json"))
    if not manifests:
        manifests = sorted(root.glob("**/manifest.json"))
    for manifest_path in manifests:
        version_dir = manifest_path.parent
        if version_dir.parent == root and version_dir.name == "current.json":
            continue
        try:
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        if manifest.get("providerID") == "com.woice.whisperkit":
            files = manifest.get("files")
            if not isinstance(files, list) or not files:
                continue
            for entry in files:
                relative = entry.get("relativePath")
                relative_path = Path(relative) if isinstance(relative, str) else Path()
                if (
                    not isinstance(relative, str)
                    or not relative
                    or relative_path.is_absolute()
                    or ".." in relative_path.parts
                    or "." in relative_path.parts
                ):
                    raise SystemExit("Offline 模型清单包含不安全路径。")
                file_path = version_dir / relative
                if not file_path.is_file() or file_path.is_symlink():
                    raise SystemExit(f"Offline 模型文件缺失或为符号链接：{relative}")
                digest = sha256_file(file_path)
                if file_path.stat().st_size != entry.get("byteCount") or digest != entry.get("sha256"):
                    raise SystemExit(f"Offline 模型文件校验失败：{relative}")
            return version_dir, manifest
    raise SystemExit("Offline 打包需要一个已校验的 WhisperKit 模型包目录。")


def compile_app_icon(brand_exports: Path, resources: Path) -> dict[str, str]:
    """Compile the confirmed AppIcon asset catalog into Bundle resources."""

    source_iconset = brand_exports / "AppIcon.appiconset"
    if not source_iconset.is_dir():
        raise SystemExit(f"缺少已确认的 AppIcon Asset Catalog：{source_iconset}")
    try:
        actool = subprocess.run(
            ["xcrun", "--find", "actool"],
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()
    except (OSError, subprocess.CalledProcessError) as error:
        raise SystemExit("无法定位 Xcode actool，拒绝生成缺少 Bundle 图标的发布包。") from error
    if not actool:
        raise SystemExit("xcrun 未返回 actool 路径，拒绝生成缺少 Bundle 图标的发布包。")

    with tempfile.TemporaryDirectory(prefix="woice-actool-") as temporary_directory:
        staging = Path(temporary_directory)
        catalog = staging / "Assets.xcassets"
        catalog.mkdir()
        shutil.copytree(source_iconset, catalog / "AppIcon.appiconset")
        compiled = staging / "compiled"
        compiled.mkdir()
        partial_plist = staging / "partial-info.plist"
        subprocess.run(
            [
                actool,
                "--platform",
                "macosx",
                "--minimum-deployment-target",
                "14.0",
                "--app-icon",
                "AppIcon",
                "--compile",
                str(compiled),
                "--output-partial-info-plist",
                str(partial_plist),
                str(catalog),
            ],
            check=True,
        )
        for artifact_name in ("Assets.car", "AppIcon.icns"):
            artifact = compiled / artifact_name
            if not artifact.is_file() or artifact.stat().st_size == 0:
                raise SystemExit(f"actool 未生成有效的 {artifact_name}，拒绝生成发布包。")
            shutil.copy2(artifact, resources / artifact_name)
        try:
            with partial_plist.open("rb") as handle:
                partial = plistlib.load(handle)
        except (OSError, plistlib.InvalidFileException) as error:
            raise SystemExit("无法读取 actool 生成的 Bundle 图标元数据。") from error
    metadata = {
        key: partial.get(key, "") for key in ("CFBundleIconFile", "CFBundleIconName")
    }
    if metadata != {"CFBundleIconFile": "AppIcon", "CFBundleIconName": "AppIcon"}:
        raise SystemExit(f"actool 返回的 Bundle 图标元数据不符合预期：{metadata}")
    return metadata


def main() -> None:
    args = parse_args()
    binary = args.binary.resolve()
    info_plist = args.info_plist.resolve()
    output = args.output.resolve()
    if not binary.is_file():
        raise SystemExit(f"缺少 Release binary：{binary}")
    if not info_plist.is_file():
        raise SystemExit(f"缺少 Info.plist：{info_plist}")
    if output.exists():
        if output.suffix != ".app" or output.parent.name != "build":
            raise SystemExit(f"拒绝覆盖非 build 目录下的目标：{output}")
        shutil.rmtree(output)

    contents = output / "Contents"
    macos = contents / "MacOS"
    resources = contents / "Resources"
    macos.mkdir(parents=True)
    resources.mkdir(parents=True)
    shutil.copy2(binary, macos / "Woice")
    with info_plist.open("rb") as handle:
        plist = plistlib.load(handle)

    project_root = Path(__file__).resolve().parents[1]
    brand_exports = project_root / "assets" / "brand" / "exports"
    for asset_name in ("woice-app-icon-64.png", "woice-app-icon-1024.png"):
        asset = brand_exports / asset_name
        if not asset.is_file():
            raise SystemExit(f"缺少已确认的 Woice 品牌资产：{asset}")
        shutil.copy2(asset, resources / asset_name)
    plist.update(compile_app_icon(brand_exports, resources))

    bundled_ids: list[str] = []
    sbom_components = [
        {
            "bom-ref": "pkg:github/argmaxinc/argmax-oss-swift@1.0.0",
            "name": "argmax-oss-swift",
            "version": "1.0.0",
            "source": "https://github.com/argmaxinc/argmax-oss-swift",
            "licenses": ["MIT"],
        }
    ]
    if args.flavor == "offline":
        if args.model_root is None:
            raise SystemExit("Offline 打包必须显式提供 --model-root。")
        model_root = args.model_root.expanduser().resolve()
        version_dir, manifest = find_model_version(model_root)
        pack_id = manifest.get("packID")
        version = manifest.get("version")
        if not isinstance(pack_id, str) or not isinstance(version, str):
            raise SystemExit("Offline 模型清单缺少 packID/version。")
        destination = resources / "Models" / pack_id / version
        shutil.copytree(version_dir, destination)
        bundled_ids.append(pack_id)
        sbom_components.append(
            {
                "bom-ref": f"model:{pack_id}@{version}",
                "name": pack_id,
                "version": version,
                "source": manifest.get("license", {}).get("sourceURL", ""),
                "licenses": [manifest.get("license", {}).get("identifier", "UNKNOWN")],
            }
        )

    distribution = {
        "schemaVersion": 1,
        "flavor": args.flavor,
        "appVersion": str(plist.get("CFBundleShortVersionString", "0.1.0")),
        "buildVersion": str(plist.get("CFBundleVersion", "1")),
        "bundledModelPackIDs": bundled_ids,
    }
    (resources / "DistributionManifest.json").write_text(
        json.dumps(distribution, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    notices_source = info_plist.parent / "NOTICES.md"
    if not notices_source.is_file():
        raise SystemExit(f"缺少第三方 Notices：{notices_source}")
    shutil.copy2(notices_source, resources / "NOTICES.md")
    dependency_notice = Path.cwd() / ".build" / "checkouts" / "argmax-oss-swift"
    if dependency_notice.is_dir():
        target_notice = resources / "ThirdParty" / "argmax-oss-swift"
        target_notice.mkdir(parents=True)
        for name in ("LICENSE", "NOTICES"):
            source = dependency_notice / name
            if source.is_file():
                shutil.copy2(source, target_notice / name)
    sbom = {
        "schema": "cyclonedx-json-1.5",
        "bomFormat": "CycloneDX",
        "specVersion": "1.5",
        "components": sbom_components,
    }
    (resources / "SBOM.json").write_text(
        json.dumps(sbom, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    with (contents / "Info.plist").open("wb") as handle:
        plistlib.dump(plist, handle, sort_keys=True)
    (macos / "Woice").chmod(0o755)
    signing_identity = os.environ.get("WOICE_CODESIGN_IDENTITY", "-")
    if not signing_identity:
        raise SystemExit("WOICE_CODESIGN_IDENTITY 不能为空；默认使用 - 生成 ad hoc 包。")
    subprocess.run(
        ["codesign", "--force", "--deep", "--sign", signing_identity, str(output)],
        check=True,
    )
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(output)], check=True)
    print(f"package-{args.flavor}: {output}")


if __name__ == "__main__":
    main()
