#!/usr/bin/env python3
"""Fail-closed checks for a locally packaged Store-edition app.

This is a local composition and bundle check. It does not claim Apple
signature, Archive validation, TestFlight processing, or App Review status.
Those facts can only be established with the real Store target and account.
"""

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

FORBIDDEN_STORE_SYMBOLS = (
    "AgentCLIAdapterCatalog",
    "AgentDispatchService",
    "ControlledCLIRunner",
    "PiConnectorRouter",
    "PiConnectorServer",
    "ProcessProviderRunner",
    "ProviderTrustVerifier",
    "TextInsertionService",
    "AXIsProcessTrusted",
    "AXIsProcessTrustedWithOptions",
)


class StoreBundleError(ValueError):
    pass


def read_plist(path: Path) -> dict[str, Any]:
    try:
        with path.open("rb") as handle:
            value = plistlib.load(handle)
    except (OSError, plistlib.InvalidFileException) as error:
        raise StoreBundleError(f"无法读取 plist：{path}") from error
    if not isinstance(value, dict):
        raise StoreBundleError(f"plist 顶层必须是字典：{path}")
    return value


def read_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise StoreBundleError(f"无法读取 JSON：{path}") from error
    if not isinstance(value, dict):
        raise StoreBundleError(f"JSON 顶层必须是对象：{path}")
    return value


def verify_model_catalog_config(info: dict[str, Any]) -> None:
    catalog_url = info.get("WOICEModelCatalogURL")
    if not isinstance(catalog_url, str):
        raise StoreBundleError("Store Bundle 缺少模型 Catalog URL。")
    parsed = urlparse(catalog_url)
    if parsed.scheme != "https" or parsed.hostname != "raw.githubusercontent.com":
        raise StoreBundleError("Store Bundle 的模型 Catalog URL 必须指向受信 HTTPS 主机。")
    if info.get("WOICEModelCatalogID") != "woice-model-catalog":
        raise StoreBundleError("Store Bundle 的模型 Catalog ID 不符合发行配置。")
    trusted_keys = info.get("WOICEModelCatalogTrustedKeys")
    if not isinstance(trusted_keys, dict) or set(trusted_keys) != {"woice-release-2026-08"}:
        raise StoreBundleError("Store Bundle 的模型 Catalog 信任根不符合发行配置。")
    public_key = trusted_keys["woice-release-2026-08"]
    if not isinstance(public_key, str):
        raise StoreBundleError("Store Bundle 的模型 Catalog 公钥格式无效。")
    try:
        decoded = base64.b64decode(public_key, validate=True)
    except (ValueError, base64.binascii.Error) as error:
        raise StoreBundleError("Store Bundle 的模型 Catalog 公钥不是 Base64。") from error
    if len(decoded) != 32:
        raise StoreBundleError("Store Bundle 的模型 Catalog 公钥长度无效。")
    catalog_hosts = info.get("WOICEModelCatalogAllowedHosts")
    if not isinstance(catalog_hosts, list) or "raw.githubusercontent.com" not in catalog_hosts:
        raise StoreBundleError("Store Bundle 缺少模型 Catalog host allowlist。")
    download_hosts = info.get("WOICEModelDownloadAllowedHosts")
    if not isinstance(download_hosts, list) or not {"huggingface.co", "raw.githubusercontent.com"}.issubset(
        set(download_hosts)
    ):
        raise StoreBundleError("Store Bundle 缺少模型下载 host allowlist。")


def signed_entitlements(app: Path) -> dict[str, Any]:
    result = subprocess.run(
        ["codesign", "-d", "--entitlements", ":-", str(app)],
        capture_output=True,
        text=False,
        check=False,
    )
    output = result.stdout + result.stderr
    start = output.find(b"<?xml")
    end = output.find(b"</plist>", start)
    if result.returncode != 0 or start < 0 or end < 0:
        raise StoreBundleError("Store Bundle 没有可读取的签名 Entitlements。")
    try:
        value = plistlib.loads(output[start : end + len(b"</plist>")])
    except plistlib.InvalidFileException as error:
        raise StoreBundleError("Store Bundle 的签名 Entitlements 不是有效 plist。") from error
    if not isinstance(value, dict):
        raise StoreBundleError("Store Bundle 的签名 Entitlements 顶层必须是字典。")
    return value


def check_source_contract(project_root: Path) -> None:
    package = (project_root / "Package.swift").read_text(encoding="utf-8")
    profile = (project_root / "Sources/WoiceApp/DistributionCapabilities.swift").read_text(
        encoding="utf-8"
    )
    if '"WOICE_DISTRIBUTION"' not in package or '"app-store"' not in package:
        raise StoreBundleError("Package.swift 缺少 app-store 编译条件。")
    if "WOICE_APP_STORE" not in package or "allowsExternalAgentConnector" not in profile:
        raise StoreBundleError("StoreCapabilityProfile 没有进入 App 组合根。")
    app_source = (project_root / "Sources/WoiceApp/WoiceApp.swift").read_text(encoding="utf-8")
    if "StoreCapabilityProfile.current.allowsExternalAgentConnector" not in app_source:
        raise StoreBundleError("WoiceApp 启动入口没有受 Store 能力配置保护。")
    insertion_source = (project_root / "Sources/WoiceApp/TextInsertionService.swift").read_text(
        encoding="utf-8"
    )
    if not insertion_source.lstrip().startswith("#if !WOICE_APP_STORE"):
        raise StoreBundleError("Store 版未在编译期排除辅助功能文本粘贴实现。")
    detail_source = (project_root / "Sources/WoiceApp/RecordingDetailView.swift").read_text(
        encoding="utf-8"
    )
    if "NSSavePanel" not in detail_source or "exportMaterial(for: record, kind: kind, to:" not in detail_source:
        raise StoreBundleError("Store 版素材导出未使用标准另存为面板和用户选定目标。")
    capture_source = (project_root / "Sources/WoiceApp/SystemAudioCaptureService.swift").read_text(
        encoding="utf-8"
    )
    if "addStreamOutput(output, type: .audio" not in capture_source:
        raise StoreBundleError("系统声音捕获没有明确注册音频输出。")
    if "addStreamOutput(output, type: .screen" in capture_source:
        raise StoreBundleError("Store 版不得注册 ScreenCaptureKit 屏幕画面输出。")


def check_store_binary_boundary(executable: Path) -> None:
    result = subprocess.run(
        ["strings", str(executable)], capture_output=True, text=True, check=False
    )
    if result.returncode != 0:
        raise StoreBundleError("无法读取 Store 可执行文件的符号字符串。")
    found = [symbol for symbol in FORBIDDEN_STORE_SYMBOLS if symbol in result.stdout]
    if found:
        raise StoreBundleError(
            "Store 可执行文件仍包含被排除的外部 Agent/Provider 实现：" + ", ".join(found)
        )


def verify(app: Path, project_root: Path) -> None:
    app = app.expanduser().resolve()
    contents = app / "Contents"
    resources = contents / "Resources"
    executable = contents / "MacOS" / "Woice"
    if not app.is_dir() or not executable.is_file():
        raise StoreBundleError(f"Store Bundle 或可执行文件缺失：{app}")
    info = read_plist(contents / "Info.plist")
    source_info = read_plist(project_root / "Resources/Info.plist")
    if info.get("CFBundleIdentifier") != "com.water.woice":
        raise StoreBundleError("Store Bundle ID 必须是 com.water.woice。")
    if info.get("CFBundleDisplayName") != "Woice" or info.get("CFBundleName") != "Woice":
        raise StoreBundleError("Store Bundle 显示名必须是 Woice。")
    if info.get("WOICEAppChannel") != "store":
        raise StoreBundleError("Store Bundle 的 App Channel 必须是 store。")
    if info.get("CFBundlePackageType") != "APPL":
        raise StoreBundleError("Store Bundle 不是 macOS App。")
    for key in ("CFBundleShortVersionString", "CFBundleVersion"):
        expected = source_info.get(key)
        if not isinstance(expected, str) or not expected:
            raise StoreBundleError(f"发行源 Info.plist 缺少 {key}。")
        if info.get(key) != expected:
            raise StoreBundleError(
                f"Store Bundle 的 {key} 与发行源不一致：{info.get(key)!r} != {expected!r}。"
            )
    if info.get("LSApplicationCategoryType") != "public.app-category.productivity":
        raise StoreBundleError(
            "Store Bundle 缺少有效的 App Store 类别：public.app-category.productivity。"
        )
    if info.get("CFBundleIconName") != "AppIcon" or info.get("CFBundleIconFile") != "AppIcon":
        raise StoreBundleError("Store Bundle 缺少 AppIcon Asset Catalog 元数据。")
    if str(info.get("LSMinimumSystemVersion", "")) < "14.0":
        raise StoreBundleError("Store Bundle 最低 macOS 版本不符合项目边界。")
    for usage_key in (
        "NSMicrophoneUsageDescription",
        "NSScreenCaptureUsageDescription",
        "NSAudioCaptureUsageDescription",
        "NSSpeechRecognitionUsageDescription",
    ):
        if not isinstance(info.get(usage_key), str) or not info[usage_key].strip():
            raise StoreBundleError(f"Store Bundle 缺少系统权限用途说明：{usage_key}")
    verify_model_catalog_config(info)

    privacy = read_plist(resources / "PrivacyInfo.xcprivacy")
    allowed_privacy_keys = {
        "NSPrivacyTracking",
        "NSPrivacyTrackingDomains",
        "NSPrivacyCollectedDataTypes",
        "NSPrivacyAccessedAPITypes",
    }
    unexpected_privacy_keys = set(privacy) - allowed_privacy_keys
    if unexpected_privacy_keys:
        raise StoreBundleError(
            "PrivacyInfo.xcprivacy 包含未允许的键：" + ", ".join(sorted(unexpected_privacy_keys))
        )
    if not isinstance(privacy.get("NSPrivacyTracking"), bool):
        raise StoreBundleError("PrivacyInfo.xcprivacy 缺少布尔 NSPrivacyTracking。")
    for key in ("NSPrivacyCollectedDataTypes", "NSPrivacyTrackingDomains", "NSPrivacyAccessedAPITypes"):
        if not isinstance(privacy.get(key), list):
            raise StoreBundleError(f"PrivacyInfo.xcprivacy 缺少数组字段：{key}")

    entitlements = signed_entitlements(app)
    required_entitlements = {
        "com.apple.security.app-sandbox": True,
        "com.apple.security.device.audio-input": True,
        "com.apple.security.files.user-selected.read-write": True,
        "com.apple.security.network.client": True,
    }
    for key, expected in required_entitlements.items():
        if entitlements.get(key) is not expected:
            raise StoreBundleError(f"Store Bundle 缺少或错误的沙盒权限：{key}")

    distribution = read_json(resources / "DistributionManifest.json")
    if distribution.get("flavor") != "store":
        raise StoreBundleError("DistributionManifest 不是 store edition。")
    if distribution.get("appVersion") != info.get("CFBundleShortVersionString"):
        raise StoreBundleError("DistributionManifest 的 appVersion 与 Bundle 版本不一致。")
    if distribution.get("buildVersion") != info.get("CFBundleVersion"):
        raise StoreBundleError("DistributionManifest 的 buildVersion 与 Bundle Build 不一致。")
    if distribution.get("capabilityProfile") != EXPECTED_CAPABILITIES:
        raise StoreBundleError("Store capability profile 与关闭边界不一致。")
    bundled_model_ids = distribution.get("bundledModelPackIDs")
    if not isinstance(bundled_model_ids, list) or not all(
        isinstance(value, str) for value in bundled_model_ids
    ):
        raise StoreBundleError("Store 模型包清单必须是字符串数组。")
    if bundled_model_ids:
        raise StoreBundleError("Store 安装包不得携带任何模型。")
    if (resources / "Models").exists() or (resources / "BundledModels").exists():
        raise StoreBundleError("Store 安装包不得包含随包模型目录。")

    notices = resources / "NOTICES.md"
    if not notices.is_file() or notices.stat().st_size == 0:
        raise StoreBundleError("Store Bundle 缺少第三方 NOTICES.md。")
    sbom = read_json(resources / "SBOM.json")
    if sbom.get("bomFormat") != "CycloneDX" or sbom.get("specVersion") != "1.5":
        raise StoreBundleError("Store Bundle 的 SBOM 版本不符合门禁。")

    check_source_contract(project_root)
    check_store_binary_boundary(executable)
    print(f"verify-app-store: passed (local Store bundle checks; not Apple Archive/App Review): {app}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", type=Path, required=True)
    parser.add_argument("--project-root", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    try:
        verify(args.app, args.project_root)
    except StoreBundleError as error:
        print(f"verify-app-store: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
