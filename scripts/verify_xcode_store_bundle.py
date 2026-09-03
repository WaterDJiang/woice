#!/usr/bin/env python3
"""Verify resources and static capability metadata in the formal Xcode Store build."""

from __future__ import annotations

import argparse
import base64
import json
import plistlib
import subprocess
import sys
from pathlib import Path
from typing import Any
from urllib.parse import urlparse


EXPECTED_CAPABILITIES = {
    "allowsProcessProviders": False,
    "allowsExternalAgentConnector": False,
    "allowsSelfUpdater": False,
    "allowsAutomaticPaste": False,
    "allowsUserProvidedExecutables": False,
    "allowsModelImport": True,
    "allowsHTTPProviders": True,
}
REQUIRED_RESOURCES = (
    "AppIcon.icns",
    "Assets.car",
    "DistributionManifest.json",
    "SBOM.json",
    "PrivacyInfo.xcprivacy",
    "NOTICES.md",
)
FORBIDDEN_SYMBOLS = (
    "AgentCLIAdapterCatalog",
    "AgentDispatchService",
    "ControlledCLIRunner",
    "PiConnectorRouter",
    "PiConnectorServer",
    "ProcessProviderRunner",
    "ProviderTrustVerifier",
)


class XcodeStoreBundleError(ValueError):
    pass


def read_plist(path: Path) -> dict[str, Any]:
    try:
        with path.open("rb") as handle:
            value = plistlib.load(handle)
    except (OSError, plistlib.InvalidFileException) as error:
        raise XcodeStoreBundleError(f"无法读取 plist：{path}") from error
    if not isinstance(value, dict):
        raise XcodeStoreBundleError(f"plist 顶层必须是字典：{path}")
    return value


def read_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise XcodeStoreBundleError(f"无法读取 JSON：{path}") from error
    if not isinstance(value, dict):
        raise XcodeStoreBundleError(f"JSON 顶层必须是对象：{path}")
    return value


def verify_model_catalog_config(info: dict[str, Any]) -> None:
    catalog_url = info.get("WOICEModelCatalogURL")
    if not isinstance(catalog_url, str):
        raise XcodeStoreBundleError("Xcode Store Bundle 缺少模型 Catalog URL。")
    parsed = urlparse(catalog_url)
    if parsed.scheme != "https" or parsed.hostname != "raw.githubusercontent.com":
        raise XcodeStoreBundleError("Xcode Store Bundle 的模型 Catalog URL 必须指向受信 HTTPS 主机。")
    if info.get("WOICEModelCatalogID") != "woice-model-catalog":
        raise XcodeStoreBundleError("Xcode Store Bundle 的模型 Catalog ID 不符合发行配置。")
    trusted_keys = info.get("WOICEModelCatalogTrustedKeys")
    if not isinstance(trusted_keys, dict) or set(trusted_keys) != {"woice-release-2026-08"}:
        raise XcodeStoreBundleError("Xcode Store Bundle 的模型 Catalog 信任根不符合发行配置。")
    public_key = trusted_keys["woice-release-2026-08"]
    if not isinstance(public_key, str):
        raise XcodeStoreBundleError("Xcode Store Bundle 的模型 Catalog 公钥格式无效。")
    try:
        decoded = base64.b64decode(public_key, validate=True)
    except (ValueError, base64.binascii.Error) as error:
        raise XcodeStoreBundleError("Xcode Store Bundle 的模型 Catalog 公钥不是 Base64。") from error
    if len(decoded) != 32:
        raise XcodeStoreBundleError("Xcode Store Bundle 的模型 Catalog 公钥长度无效。")
    catalog_hosts = info.get("WOICEModelCatalogAllowedHosts")
    if not isinstance(catalog_hosts, list) or "raw.githubusercontent.com" not in catalog_hosts:
        raise XcodeStoreBundleError("Xcode Store Bundle 缺少模型 Catalog host allowlist。")
    download_hosts = info.get("WOICEModelDownloadAllowedHosts")
    if not isinstance(download_hosts, list) or not {"huggingface.co", "raw.githubusercontent.com"}.issubset(
        set(download_hosts)
    ):
        raise XcodeStoreBundleError("Xcode Store Bundle 缺少模型下载 host allowlist。")


def verify(app: Path) -> None:
    app = app.expanduser().resolve()
    contents = app / "Contents"
    resources = contents / "Resources"
    executable = contents / "MacOS" / "Woice"
    if not app.is_dir() or not executable.is_file():
        raise XcodeStoreBundleError(f"Xcode Store Bundle 或可执行文件缺失：{app}")

    info = read_plist(contents / "Info.plist")
    if info.get("CFBundleIdentifier") != "com.water.woice":
        raise XcodeStoreBundleError("Xcode Store Bundle ID 必须是 com.water.woice。")
    if info.get("CFBundleDisplayName") != "Woice" or info.get("CFBundleName") != "Woice":
        raise XcodeStoreBundleError("Xcode Store Bundle 显示名必须是 Woice。")
    if info.get("WOICEAppChannel") != "store":
        raise XcodeStoreBundleError("Xcode Store Bundle 的 App Channel 必须是 store。")
    if info.get("CFBundlePackageType") != "APPL":
        raise XcodeStoreBundleError("Xcode Store Bundle 不是 macOS App。")
    if not isinstance(info.get("CFBundleShortVersionString"), str) or not info[
        "CFBundleShortVersionString"
    ]:
        raise XcodeStoreBundleError("Xcode Store Bundle 缺少版本号。")
    if not isinstance(info.get("CFBundleVersion"), str) or not info["CFBundleVersion"]:
        raise XcodeStoreBundleError("Xcode Store Bundle 缺少 Build 号。")
    if info.get("LSApplicationCategoryType") != "public.app-category.productivity":
        raise XcodeStoreBundleError(
            "Xcode Store Bundle 缺少有效的 App Store 类别：public.app-category.productivity。"
        )
    if info.get("CFBundleIconName") != "AppIcon" or info.get("CFBundleIconFile") != "AppIcon":
        raise XcodeStoreBundleError("Xcode Store Bundle 缺少 AppIcon 元数据。")
    try:
        minimum_system = tuple(int(part) for part in str(info["LSMinimumSystemVersion"]).split("."))
    except (KeyError, TypeError, ValueError) as error:
        raise XcodeStoreBundleError("Xcode Store Bundle 缺少有效最低 macOS 版本。") from error
    if minimum_system < (14, 0):
        raise XcodeStoreBundleError("Xcode Store Bundle 最低 macOS 版本低于 14.0。")
    for usage_key in (
        "NSMicrophoneUsageDescription",
        "NSScreenCaptureUsageDescription",
        "NSAudioCaptureUsageDescription",
        "NSSpeechRecognitionUsageDescription",
    ):
        if not isinstance(info.get(usage_key), str) or not info[usage_key].strip():
            raise XcodeStoreBundleError(f"Xcode Store Bundle 缺少系统权限用途说明：{usage_key}")
    verify_model_catalog_config(info)

    for resource_name in REQUIRED_RESOURCES:
        resource = resources / resource_name
        if not resource.is_file() or resource.stat().st_size == 0:
            raise XcodeStoreBundleError(f"Xcode Store Bundle 缺少资源：{resource_name}")

    privacy = read_plist(resources / "PrivacyInfo.xcprivacy")
    allowed_privacy_keys = {
        "NSPrivacyTracking",
        "NSPrivacyTrackingDomains",
        "NSPrivacyCollectedDataTypes",
        "NSPrivacyAccessedAPITypes",
    }
    unexpected_privacy_keys = set(privacy) - allowed_privacy_keys
    if unexpected_privacy_keys:
        raise XcodeStoreBundleError(
            "PrivacyInfo.xcprivacy 包含未允许的键：" + ", ".join(sorted(unexpected_privacy_keys))
        )
    if not isinstance(privacy.get("NSPrivacyTracking"), bool):
        raise XcodeStoreBundleError("PrivacyInfo.xcprivacy 缺少布尔 NSPrivacyTracking。")
    for key in ("NSPrivacyCollectedDataTypes", "NSPrivacyTrackingDomains", "NSPrivacyAccessedAPITypes"):
        if not isinstance(privacy.get(key), list):
            raise XcodeStoreBundleError(f"PrivacyInfo.xcprivacy 缺少数组字段：{key}")

    distribution = read_json(resources / "DistributionManifest.json")
    if distribution.get("flavor") != "store":
        raise XcodeStoreBundleError("Xcode Store Bundle 的 DistributionManifest 不是 store edition。")
    if distribution.get("appVersion") != info.get("CFBundleShortVersionString"):
        raise XcodeStoreBundleError("DistributionManifest 的 appVersion 与 Bundle 版本不一致。")
    if distribution.get("buildVersion") != info.get("CFBundleVersion"):
        raise XcodeStoreBundleError("DistributionManifest 的 buildVersion 与 Bundle Build 不一致。")
    if distribution.get("capabilityProfile") != EXPECTED_CAPABILITIES:
        raise XcodeStoreBundleError("Xcode Store Bundle 的 Store 能力清单不符合边界。")
    if distribution.get("bundledModelPackIDs") != []:
        raise XcodeStoreBundleError("正式 Xcode Store Target 不得静态内置未审定模型。")
    if (resources / "Models").exists() or (resources / "BundledModels").exists():
        raise XcodeStoreBundleError("正式 Xcode Store Target 不得包含随包模型目录。")

    sbom = read_json(resources / "SBOM.json")
    if sbom.get("bomFormat") != "CycloneDX" or sbom.get("specVersion") != "1.5":
        raise XcodeStoreBundleError("Xcode Store Bundle 的 SBOM 版本不符合门禁。")
    components = sbom.get("components")
    if not isinstance(components, list) or not any(
        isinstance(component, dict)
        and component.get("name") == "argmax-oss-swift"
        and component.get("version") == "1.0.0"
        for component in components
    ):
        raise XcodeStoreBundleError("Xcode Store Bundle 的 SBOM 缺少固定 argmax-oss-swift 组件。")

    result = subprocess.run(
        ["strings", str(executable)], capture_output=True, text=True, check=False
    )
    if result.returncode != 0:
        raise XcodeStoreBundleError("无法读取 Xcode Store 可执行文件的符号字符串。")
    found = [symbol for symbol in FORBIDDEN_SYMBOLS if symbol in result.stdout]
    if found:
        raise XcodeStoreBundleError("Xcode Store 可执行文件仍包含外部实现：" + ", ".join(found))

    print(f"verify-xcode-store-bundle: passed (unsigned formal Store resources): {app}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", type=Path, required=True)
    args = parser.parse_args()
    try:
        verify(args.app)
    except XcodeStoreBundleError as error:
        print(f"verify-xcode-store-bundle: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
