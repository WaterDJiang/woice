#!/usr/bin/env python3
"""Create and verify the signed-release readback manifest.

The local manifest records facts produced by the release machine.  After the
DMGs and production Catalog are uploaded, ``verify`` reads a remote manifest,
compares those facts, probes every HTTPS endpoint, and hashes the Catalog
body.  DMGs are intentionally not downloaded by default; their remote
manifest digest must match the local digest and their HTTP Content-Length must
match the local byte count.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import urlparse
from urllib.request import HTTPRedirectHandler, Request, build_opener


SCHEMA_VERSION = 1
DEFAULT_BUNDLE_ID = "com.woice.app"
MAX_MANIFEST_BYTES = 1 * 1024 * 1024
MAX_CATALOG_BYTES = 2 * 1024 * 1024
SHA256_PATTERN = re.compile(r"^[0-9a-fA-F]{64}$")
FLAVORS = ("core", "offline")


class ManifestError(ValueError):
    """A release manifest or remote readback failed a fail-closed check."""


class NoRedirectHandler(HTTPRedirectHandler):
    def redirect_request(self, request, file, code, msg, headers, newurl):  # type: ignore[override]
        return None


def _https_url(value: Any, field: str) -> str:
    if not isinstance(value, str) or not value:
        raise ManifestError(f"{field} 必须是非空 HTTPS URL。")
    parsed = urlparse(value)
    if parsed.scheme.lower() != "https" or not parsed.hostname or parsed.username or parsed.password:
        raise ManifestError(f"{field} 必须是无凭据的 HTTPS URL：{value}")
    return value


def _positive_int(value: Any, field: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value <= 0:
        raise ManifestError(f"{field} 必须是正整数。")
    return value


def _sha256(value: Any, field: str) -> str:
    if not isinstance(value, str) or not SHA256_PATTERN.fullmatch(value):
        raise ManifestError(f"{field} 必须是 64 位 SHA-256。")
    return value.lower()


def _build_version(value: Any) -> str:
    if not isinstance(value, str) or not value.isdigit() or not value:
        raise ManifestError("buildVersion 必须是数字字符串。")
    return value


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _read_json_file(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise ManifestError(f"无法读取 Release manifest：{path}") from error
    if not isinstance(value, dict):
        raise ManifestError("Release manifest 顶层必须是 JSON 对象。")
    return value


def _validate_local_manifest(manifest: dict[str, Any]) -> dict[str, Any]:
    if manifest.get("schemaVersion") != SCHEMA_VERSION:
        raise ManifestError("Release manifest schemaVersion 不受支持。")
    build_version = _build_version(manifest.get("buildVersion"))
    bundle_id = manifest.get("bundleID")
    if bundle_id != DEFAULT_BUNDLE_ID:
        raise ManifestError(
            f"Release manifest bundleID 必须保持固定值 {DEFAULT_BUNDLE_ID}。"
        )

    catalog = manifest.get("catalog")
    if not isinstance(catalog, dict):
        raise ManifestError("Release manifest 缺少 catalog 对象。")
    catalog_url = _https_url(catalog.get("url"), "catalog.url")
    catalog_id = catalog.get("id")
    if not isinstance(catalog_id, str) or not catalog_id:
        raise ManifestError("catalog.id 必须是非空字符串。")

    artifacts = manifest.get("artifacts")
    if not isinstance(artifacts, list) or len(artifacts) != len(FLAVORS):
        raise ManifestError("Release manifest 必须包含 Core 和 Offline 两个产物。")
    by_flavor: dict[str, dict[str, Any]] = {}
    for artifact in artifacts:
        if not isinstance(artifact, dict):
            raise ManifestError("artifacts 中的项目必须是 JSON 对象。")
        flavor = artifact.get("flavor")
        if flavor not in FLAVORS or flavor in by_flavor:
            raise ManifestError("artifacts 必须恰好包含唯一的 core/offline。")
        filename = artifact.get("file")
        if not isinstance(filename, str) or not filename or "/" in filename or "\\" in filename:
            raise ManifestError(f"{flavor}.file 必须是安全的文件名。")
        by_flavor[flavor] = {
            "flavor": flavor,
            "file": filename,
            "size": _positive_int(artifact.get("size"), f"{flavor}.size"),
            "sha256": _sha256(artifact.get("sha256"), f"{flavor}.sha256"),
        }
    if set(by_flavor) != set(FLAVORS):
        raise ManifestError("artifacts 必须包含 core 和 offline。")
    return {
        "schemaVersion": SCHEMA_VERSION,
        "buildVersion": build_version,
        "bundleID": bundle_id,
        "catalog": {"url": catalog_url, "id": catalog_id},
        "artifacts": by_flavor,
    }


def create_local_manifest(
    *,
    output: Path,
    build_version: str,
    bundle_id: str,
    catalog_url: str,
    catalog_id: str,
    core_dmg: Path,
    offline_dmg: Path,
) -> dict[str, Any]:
    """Write local immutable facts and return the normalized manifest."""

    normalized_build = _build_version(build_version)
    if not isinstance(bundle_id, str) or not bundle_id:
        raise ManifestError("bundleID 必须是非空字符串。")
    _https_url(catalog_url, "catalog.url")
    artifact_values = []
    for flavor, path in (("core", core_dmg), ("offline", offline_dmg)):
        resolved = path.expanduser().resolve()
        if not resolved.is_file():
            raise ManifestError(f"缺少 {flavor} DMG：{resolved}")
        artifact_values.append(
            {
                "flavor": flavor,
                "file": resolved.name,
                "size": resolved.stat().st_size,
                "sha256": sha256_file(resolved),
            }
        )
    manifest = {
        "schemaVersion": SCHEMA_VERSION,
        "buildVersion": normalized_build,
        "bundleID": bundle_id,
        "catalog": {"url": catalog_url, "id": catalog_id},
        "artifacts": artifact_values,
    }
    normalized = _validate_local_manifest(manifest)
    output = output.expanduser().resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return normalized


def _open(request: Request, timeout: float):
    opener = build_opener(NoRedirectHandler)
    try:
        response = opener.open(request, timeout=timeout)
    except HTTPError as error:
        if 300 <= error.code < 400:
            location = error.headers.get("Location", "<unknown>")
            raise ManifestError(f"远程发行地址禁止重定向：{request.full_url} -> {location}") from error
        raise ManifestError(f"远程发行地址返回 HTTP {error.code}：{request.full_url}") from error
    except URLError as error:
        raise ManifestError(f"远程发行地址不可达：{request.full_url}：{error.reason}") from error
    status = getattr(response, "status", None)
    if status is None or not 200 <= status < 300:
        response.close()
        raise ManifestError(f"远程发行地址返回无效状态：{request.full_url}")
    return response


def _bounded_read(response, maximum: int) -> bytes:
    content_length = response.headers.get("Content-Length")
    if content_length:
        try:
            declared = int(content_length)
        except ValueError as error:
            raise ManifestError("远程响应 Content-Length 无效。") from error
        if declared > maximum:
            raise ManifestError(f"远程响应超过上限：{declared} bytes")
    data = response.read(maximum + 1)
    if len(data) > maximum:
        raise ManifestError(f"远程响应超过上限：{len(data)} bytes")
    return data


def fetch_remote_manifest(url: str, timeout: float = 10.0) -> dict[str, Any]:
    _https_url(url, "remoteManifestURL")
    request = Request(url, headers={"Accept": "application/json"}, method="GET")
    response = _open(request, timeout)
    try:
        content_type = response.headers.get("Content-Type", "")
        media_type = content_type.split(";", 1)[0].strip().lower()
        if media_type and media_type != "application/json" and not media_type.endswith("+json"):
            raise ManifestError(f"远程 Release manifest 不是 JSON：{content_type}")
        data = _bounded_read(response, MAX_MANIFEST_BYTES)
    finally:
        response.close()
    try:
        value = json.loads(data.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ManifestError("远程 Release manifest 不是有效 JSON。") from error
    if not isinstance(value, dict):
        raise ManifestError("远程 Release manifest 顶层必须是 JSON 对象。")
    return value


def _head(url: str, expected_size: int, field: str, timeout: float) -> dict[str, Any]:
    _https_url(url, field)
    response = _open(Request(url, method="HEAD"), timeout)
    try:
        content_length = response.headers.get("Content-Length")
        if not content_length:
            raise ManifestError(f"{field} 缺少 Content-Length，拒绝通过远程大小门禁。")
        try:
            actual_size = int(content_length)
        except ValueError as error:
            raise ManifestError(f"{field} Content-Length 无效。") from error
        if actual_size != expected_size:
            raise ManifestError(
                f"{field} 大小不一致：manifest={expected_size}，远程={actual_size}。"
            )
        return {"status": response.status, "size": actual_size}
    finally:
        response.close()


def _fetch_catalog(url: str, expected_size: int, expected_sha256: str, timeout: float) -> dict[str, Any]:
    _https_url(url, "catalog.url")
    request = Request(url, headers={"Accept": "application/json"}, method="GET")
    response = _open(request, timeout)
    try:
        content_type = response.headers.get("Content-Type", "")
        media_type = content_type.split(";", 1)[0].strip().lower()
        if media_type and media_type != "application/json" and not media_type.endswith("+json"):
            raise ManifestError(f"catalog.url 响应不是 JSON：{content_type}")
        data = _bounded_read(response, MAX_CATALOG_BYTES)
    finally:
        response.close()
    actual_sha256 = hashlib.sha256(data).hexdigest()
    if len(data) != expected_size:
        raise ManifestError(f"catalog.url 大小不一致：manifest={expected_size}，远程={len(data)}。")
    if actual_sha256 != expected_sha256.lower():
        raise ManifestError(
            f"catalog.url SHA-256 不一致：manifest={expected_sha256}，远程={actual_sha256}。"
        )
    return {"status": 200, "size": len(data), "sha256": actual_sha256}


def validate_remote_manifest(
    local: dict[str, Any], remote: dict[str, Any]
) -> tuple[dict[str, Any], dict[str, Any]]:
    normalized_local = _validate_local_manifest(local)
    normalized_remote = _validate_local_manifest(
        {
            "schemaVersion": remote.get("schemaVersion"),
            "buildVersion": remote.get("buildVersion"),
            "bundleID": remote.get("bundleID"),
            "catalog": remote.get("catalog"),
            "artifacts": remote.get("artifacts"),
        }
    )
    if normalized_local["buildVersion"] != normalized_remote["buildVersion"]:
        raise ManifestError("远程 Release manifest 的 buildVersion 与本地不一致。")
    if normalized_local["bundleID"] != normalized_remote["bundleID"]:
        raise ManifestError("远程 Release manifest 的 bundleID 与本地不一致。")
    if normalized_local["catalog"] != normalized_remote["catalog"]:
        raise ManifestError("远程 Release manifest 的 Catalog URL/ID 与本地不一致。")

    remote_catalog = remote.get("catalog")
    if not isinstance(remote_catalog, dict) or remote_catalog.get("status") != "published":
        raise ManifestError("远程 Catalog 必须标记为 published。")
    catalog_size = _positive_int(remote_catalog.get("size"), "catalog.size")
    catalog_sha256 = _sha256(remote_catalog.get("sha256"), "catalog.sha256")

    remote_artifacts = remote.get("artifacts")
    if not isinstance(remote_artifacts, list) or len(remote_artifacts) != len(FLAVORS):
        raise ManifestError("远程 artifacts 必须包含两个产物。")
    remote_by_flavor: dict[str, dict[str, Any]] = {}
    for artifact in remote_artifacts:
        if not isinstance(artifact, dict):
            raise ManifestError("远程 artifacts 项目必须是 JSON 对象。")
        flavor = artifact.get("flavor")
        if flavor not in FLAVORS or flavor in remote_by_flavor:
            raise ManifestError("远程 artifacts 必须恰好包含唯一的 core/offline。")
        if artifact.get("status") != "published":
            raise ManifestError(f"远程 {flavor} 产物必须标记为 published。")
        url = _https_url(artifact.get("url"), f"{flavor}.url")
        size = _positive_int(artifact.get("size"), f"{flavor}.size")
        sha256 = _sha256(artifact.get("sha256"), f"{flavor}.sha256")
        local_artifact = normalized_local["artifacts"][flavor]
        if artifact.get("file") != local_artifact["file"]:
            raise ManifestError(f"远程 {flavor} 文件名与本地不一致。")
        if size != local_artifact["size"] or sha256 != local_artifact["sha256"]:
            raise ManifestError(f"远程 {flavor} 大小或 SHA-256 与本地不一致。")
        remote_by_flavor[flavor] = {
            "flavor": flavor,
            "file": local_artifact["file"],
            "url": url,
            "size": size,
            "sha256": sha256,
            "status": "published",
        }
    if set(remote_by_flavor) != set(FLAVORS):
        raise ManifestError("远程 artifacts 缺少 core 或 offline。")

    catalog = {
        "url": normalized_local["catalog"]["url"],
        "id": normalized_local["catalog"]["id"],
        "status": "published",
        "size": catalog_size,
        "sha256": catalog_sha256,
    }
    return catalog, remote_by_flavor


def verify_remote(
    *, local_manifest_path: Path, remote_manifest_url: str, output: Path | None, timeout: float = 10.0
) -> dict[str, Any]:
    local = _read_json_file(local_manifest_path)
    remote = fetch_remote_manifest(remote_manifest_url, timeout)
    catalog, artifacts = validate_remote_manifest(local, remote)
    catalog_probe = _fetch_catalog(catalog["url"], catalog["size"], catalog["sha256"], timeout)
    artifact_probes = {
        flavor: _head(value["url"], value["size"], f"{flavor}.url", timeout)
        for flavor, value in artifacts.items()
    }
    evidence = {
        "schemaVersion": SCHEMA_VERSION,
        "buildVersion": _build_version(local.get("buildVersion")),
        "bundleID": local["bundleID"],
        "remoteManifestURL": remote_manifest_url,
        "catalog": {**catalog, "probe": catalog_probe},
        "artifacts": [
            {**artifacts[flavor], "probe": artifact_probes[flavor]} for flavor in FLAVORS
        ],
    }
    if output is not None:
        output = output.expanduser().resolve()
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(evidence, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return evidence


def _create_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    create = subparsers.add_parser("create", help="生成本地产物事实 manifest")
    create.add_argument("--output", type=Path, required=True)
    create.add_argument("--build-version", required=True)
    create.add_argument("--bundle-id", default=DEFAULT_BUNDLE_ID)
    create.add_argument("--catalog-url", required=True)
    create.add_argument("--catalog-id", required=True)
    create.add_argument("--core-dmg", type=Path, required=True)
    create.add_argument("--offline-dmg", type=Path, required=True)

    verify = subparsers.add_parser("verify", help="读回生产 manifest 并验证远程状态/大小/摘要")
    verify.add_argument("--local-manifest", type=Path, required=True)
    verify.add_argument("--remote-manifest-url", required=True)
    verify.add_argument("--output", type=Path)
    verify.add_argument("--timeout", type=float, default=10.0)
    return parser


def main() -> int:
    args = _create_parser().parse_args()
    try:
        if args.command == "create":
            create_local_manifest(
                output=args.output,
                build_version=args.build_version,
                bundle_id=args.bundle_id,
                catalog_url=args.catalog_url,
                catalog_id=args.catalog_id,
                core_dmg=args.core_dmg,
                offline_dmg=args.offline_dmg,
            )
            print(f"release-manifest: {args.output}")
        else:
            evidence = verify_remote(
                local_manifest_path=args.local_manifest,
                remote_manifest_url=args.remote_manifest_url,
                output=args.output,
                timeout=min(max(args.timeout, 0.1), 30.0),
            )
            print(
                "release-verify-remote: passed "
                f"(Build {evidence['buildVersion']}; Catalog/2 artifacts status, size and SHA-256 verified)"
            )
    except ManifestError as error:
        print(f"release-manifest: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
