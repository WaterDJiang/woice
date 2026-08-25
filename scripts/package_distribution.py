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
    parser.add_argument("--flavor", choices=("core", "offline", "store"), required=True)
    parser.add_argument("--binary", type=Path, required=True)
    parser.add_argument("--info-plist", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--model-root", type=Path)
    parser.add_argument(
        "--mlx-bundle",
        type=Path,
        help="Xcode 构建的 mlx-swift_Cmlx.bundle；原生 MLX 运行时必须随 App 一起分发。",
    )
    parser.add_argument("--entitlements", type=Path)
    parser.add_argument("--privacy-manifest", type=Path)
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
        if manifest.get("providerID") in {
            "com.woice.whisperkit",
            "com.woice.qwen3-asr",
        }:
            files = manifest.get("files")
            if not isinstance(files, list) or not files:
                continue
            license_info = manifest.get("license")
            if not isinstance(license_info, dict):
                raise SystemExit("模型清单缺少 license 对象，拒绝进入发行包。")
            identifier = license_info.get("identifier")
            source_url = license_info.get("sourceURL")
            notice_path = license_info.get("noticePath")
            if (
                not isinstance(identifier, str)
                or not identifier.strip()
                or identifier.strip().upper() in {"UNKNOWN", "TBD", "PROPRIETARY"}
                or not isinstance(source_url, str)
                or not source_url.startswith("https://")
                or not isinstance(notice_path, str)
                or not notice_path
            ):
                raise SystemExit("模型清单的许可证标识、来源或 NOTICE 路径不完整，拒绝进入发行包。")
            if manifest.get("storeCompatible"):
                provenance = manifest.get("provenance")
                if not isinstance(provenance, dict) or not all(
                    isinstance(provenance.get(key), str) and provenance[key].strip()
                    for key in (
                        "upstreamModelID",
                        "upstreamRevision",
                        "sourceURL",
                        "derivedFormat",
                        "conversionTool",
                        "conversionRevision",
                    )
                ):
                    raise SystemExit("Store 模型清单缺少完整 provenance，拒绝进入发行包。")
            notice_relative = Path(notice_path)
            if (
                notice_relative.is_absolute()
                or ".." in notice_relative.parts
                or "." in notice_relative.parts
            ):
                raise SystemExit("模型清单的 NOTICE 路径不安全，拒绝进入发行包。")
            notice_file = version_dir / notice_relative
            if not notice_file.is_file() or notice_file.is_symlink():
                raise SystemExit(f"模型 NOTICE 文件缺失或为符号链接：{notice_path}")
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
    raise SystemExit("Offline 打包需要一个已校验的本机模型包目录。")


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


def apply_runtime_release_configuration(plist: dict) -> None:
    """Apply explicit release-only catalog/build metadata without guessing."""

    build_version = os.environ.get("WOICE_BUILD_VERSION")
    if build_version:
        if not build_version.isdigit():
            raise SystemExit("WOICE_BUILD_VERSION 必须是数字。")
        plist["CFBundleVersion"] = build_version

    catalog_values = {
        "WOICEModelCatalogURL": os.environ.get("WOICE_CATALOG_URL", ""),
        "WOICEModelCatalogID": os.environ.get("WOICE_CATALOG_ID", ""),
    }
    trusted_keys_json = os.environ.get("WOICE_CATALOG_TRUSTED_KEYS_JSON", "")
    if any(catalog_values.values()) or trusted_keys_json:
        if not all(catalog_values.values()) or not trusted_keys_json:
            raise SystemExit("生产 Catalog 配置必须同时提供 URL、ID 和可信公钥 JSON。")
        try:
            trusted_keys = json.loads(trusted_keys_json)
        except json.JSONDecodeError as error:
            raise SystemExit("WOICE_CATALOG_TRUSTED_KEYS_JSON 不是有效 JSON。") from error
        if not isinstance(trusted_keys, dict) or not trusted_keys:
            raise SystemExit("生产 Catalog 可信公钥 JSON 必须是非空对象。")
        plist["WOICEModelCatalogURL"] = catalog_values["WOICEModelCatalogURL"]
        plist["WOICEModelCatalogID"] = catalog_values["WOICEModelCatalogID"]
        plist["WOICEModelCatalogTrustedKeys"] = trusted_keys
        allowed_hosts = os.environ.get("WOICE_CATALOG_ALLOWED_HOSTS", "")
        download_hosts = os.environ.get("WOICE_CATALOG_DOWNLOAD_ALLOWED_HOSTS", "")
        if allowed_hosts:
            plist["WOICEModelCatalogAllowedHosts"] = [
                host.strip().lower() for host in allowed_hosts.split(",") if host.strip()
            ]
        if download_hosts:
            plist["WOICEModelDownloadAllowedHosts"] = [
                host.strip().lower() for host in download_hosts.split(",") if host.strip()
            ]


def main() -> None:
    args = parse_args()
    project_root = Path(__file__).resolve().parents[1]
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
    apply_runtime_release_configuration(plist)

    brand_exports = project_root / "assets" / "brand" / "exports"
    for asset_name in ("woice-app-icon-64.png", "woice-app-icon-1024.png"):
        asset = brand_exports / asset_name
        if not asset.is_file():
            raise SystemExit(f"缺少已确认的 Woice 品牌资产：{asset}")
        shutil.copy2(asset, resources / asset_name)
    plist.update(compile_app_icon(brand_exports, resources))

    if args.mlx_bundle is None:
        raise SystemExit(
            "缺少 --mlx-bundle；MLX 原生 Runtime 必须携带 Xcode 生成的 mlx-swift_Cmlx.bundle。"
        )
    mlx_bundle = args.mlx_bundle.expanduser().resolve()
    metallib = mlx_bundle / "Contents" / "Resources" / "default.metallib"
    if not mlx_bundle.is_dir() or not metallib.is_file() or metallib.is_symlink():
        raise SystemExit(
            f"MLX Metal 资源不完整：{mlx_bundle}；需要 Contents/Resources/default.metallib。"
        )
    shutil.copytree(mlx_bundle, resources / mlx_bundle.name)

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
    sbom_components.extend(
        [
            {
                "bom-ref": "pkg:github/vfasky/qwen3-asr-swift@4824c95e1e4624200405d639fb4ebe10f93f1075",
                "name": "qwen3-asr-swift",
                "version": "4824c95e1e4624200405d639fb4ebe10f93f1075",
                "source": "https://github.com/vfasky/qwen3-asr-swift",
                "licenses": ["Apache-2.0"],
            },
            {
                "bom-ref": "pkg:github/ml-explore/mlx-swift@0.31.6",
                "name": "mlx-swift",
                "version": "0.31.6",
                "source": "https://github.com/ml-explore/mlx-swift",
                "licenses": ["MIT"],
            },
            {
                "bom-ref": "pkg:github/huggingface/swift-transformers@1.3.3",
                "name": "swift-transformers",
                "version": "1.3.3",
                "source": "https://github.com/huggingface/swift-transformers",
                "licenses": ["Apache-2.0"],
            },
            {
                "bom-ref": "pkg:github/huggingface/swift-huggingface@0.9.0",
                "name": "swift-huggingface",
                "version": "0.9.0",
                "source": "https://github.com/huggingface/swift-huggingface",
                "licenses": ["Apache-2.0"],
            },
            {
                "bom-ref": "pkg:github/huggingface/swift-jinja@2.4.2",
                "name": "swift-jinja",
                "version": "2.4.2",
                "source": "https://github.com/huggingface/swift-jinja",
                "licenses": ["Apache-2.0"],
            },
            {
                "bom-ref": "pkg:github/apple/swift-argument-parser@1.8.2",
                "name": "swift-argument-parser",
                "version": "1.8.2",
                "source": "https://github.com/apple/swift-argument-parser",
                "licenses": ["Apache-2.0"],
            },
            {
                "bom-ref": "pkg:github/apple/swift-collections@1.6.0",
                "name": "swift-collections",
                "version": "1.6.0",
                "source": "https://github.com/apple/swift-collections",
                "licenses": ["Apache-2.0"],
            },
            {
                "bom-ref": "pkg:github/apple/swift-crypto@4.5.1",
                "name": "swift-crypto",
                "version": "4.5.1",
                "source": "https://github.com/apple/swift-crypto",
                "licenses": ["Apache-2.0"],
            },
            {
                "bom-ref": "pkg:github/apple/swift-asn1@1.7.1",
                "name": "swift-asn1",
                "version": "1.7.1",
                "source": "https://github.com/apple/swift-asn1",
                "licenses": ["Apache-2.0"],
            },
            {
                "bom-ref": "pkg:github/apple/swift-numerics@1.1.1",
                "name": "swift-numerics",
                "version": "1.1.1",
                "source": "https://github.com/apple/swift-numerics",
                "licenses": ["Apache-2.0"],
            },
            {
                "bom-ref": "pkg:github/mattt/EventSource@1.5.1",
                "name": "EventSource",
                "version": "1.5.1",
                "source": "https://github.com/mattt/EventSource",
                "licenses": ["MIT"],
            },
            {
                "bom-ref": "pkg:github/ibireme/yyjson@0.12.0",
                "name": "yyjson",
                "version": "0.12.0",
                "source": "https://github.com/ibireme/yyjson",
                "licenses": ["MIT"],
            },
        ]
    )
    if args.flavor in ("offline", "store") and args.model_root is not None:
        model_root = args.model_root.expanduser().resolve()
        version_dir, manifest = find_model_version(model_root)
        pack_id = manifest.get("packID")
        version = manifest.get("version")
        if not isinstance(pack_id, str) or not isinstance(version, str):
            raise SystemExit("随包模型清单缺少 packID/version。")
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
    elif args.flavor == "offline":
        if args.model_root is None:
            raise SystemExit("Offline 打包必须显式提供 --model-root。")
        raise SystemExit("Offline 打包需要显式提供 --model-root。")

    distribution = {
        "schemaVersion": 1,
        "flavor": args.flavor,
        "appVersion": str(plist.get("CFBundleShortVersionString", "0.1.0")),
        "buildVersion": str(plist.get("CFBundleVersion", "1")),
        "bundledModelPackIDs": bundled_ids,
    }
    if args.flavor == "store":
        distribution["capabilityProfile"] = {
            "allowsProcessProviders": False,
            "allowsExternalAgentConnector": False,
            "allowsSelfUpdater": False,
            "allowsAutomaticPaste": False,
            "allowsUserProvidedExecutables": False,
            "allowsModelImport": True,
            "allowsHTTPProviders": True,
        }
    (resources / "DistributionManifest.json").write_text(
        json.dumps(distribution, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    privacy_manifest = args.privacy_manifest
    if privacy_manifest is None and args.flavor == "store":
        privacy_manifest = project_root / "Resources" / "PrivacyInfo.xcprivacy"
    if privacy_manifest is not None:
        privacy_manifest = privacy_manifest.expanduser().resolve()
        if not privacy_manifest.is_file():
            raise SystemExit(f"缺少 PrivacyInfo.xcprivacy：{privacy_manifest}")
        shutil.copy2(privacy_manifest, resources / "PrivacyInfo.xcprivacy")
    notices_source = info_plist.parent / "NOTICES.md"
    if not notices_source.is_file():
        raise SystemExit(f"缺少第三方 Notices：{notices_source}")
    shutil.copy2(notices_source, resources / "NOTICES.md")
    dependency_notices = {
        "argmax-oss-swift": ("LICENSE", "NOTICES"),
        "qwen3-asr-swift": ("LICENSE",),
        "mlx-swift": ("LICENSE",),
        "swift-transformers": ("LICENSE",),
        "swift-huggingface": ("LICENSE",),
        "swift-jinja": ("LICENSE",),
        "swift-argument-parser": ("LICENSE.txt",),
        "swift-collections": ("LICENSE.txt",),
        "swift-crypto": ("LICENSE.txt", "NOTICE.txt"),
        "swift-asn1": ("LICENSE.txt", "NOTICE.txt"),
        "swift-numerics": ("LICENSE.txt",),
        "EventSource": ("LICENSE.md",),
        "yyjson": ("LICENSE",),
    }
    for dependency_name, notice_names in dependency_notices.items():
        dependency_root = Path.cwd() / ".build" / "checkouts" / dependency_name
        if not dependency_root.is_dir():
            raise SystemExit(f"缺少已解析依赖源码，无法生成完整许可证包：{dependency_name}")
        target_notice = resources / "ThirdParty" / dependency_name
        target_notice.mkdir(parents=True)
        for name in notice_names:
            source = dependency_root / name
            if not source.is_file() or source.is_symlink():
                raise SystemExit(f"依赖许可证文件缺失：{dependency_name}/{name}")
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
    codesign_args = ["codesign", "--force", "--deep", "--sign", signing_identity]
    if os.environ.get("WOICE_HARDENED_RUNTIME") == "1":
        codesign_args.extend(["--options", "runtime", "--timestamp"])
    entitlements = args.entitlements or os.environ.get("WOICE_CODESIGN_ENTITLEMENTS")
    if entitlements:
        entitlements_path = Path(entitlements).expanduser().resolve()
        if not entitlements_path.is_file():
            raise SystemExit(f"代码签名需要有效的 Entitlements：{entitlements_path}")
        codesign_args.extend(["--entitlements", str(entitlements_path)])
    elif os.environ.get("WOICE_HARDENED_RUNTIME") == "1":
        raise SystemExit("Hardened Runtime 需要有效的 WOICE_CODESIGN_ENTITLEMENTS。")
    codesign_args.append(str(output))
    subprocess.run(codesign_args, check=True)
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(output)], check=True)
    print(f"package-{args.flavor}: {output}")


if __name__ == "__main__":
    main()
