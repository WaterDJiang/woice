#!/usr/bin/env python3
"""Create and verify a local Core/Offline Woice DMG.

This is a reproducible packaging helper, not a Developer ID or notarization
step. The app must already be built and strict-signed by package_distribution.
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import tempfile
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--volume-name", required=True)
    return parser.parse_args()


def run(command: list[str]) -> None:
    subprocess.run(command, check=True)


def main() -> None:
    args = parse_args()
    app = args.app.resolve()
    output = args.output.resolve()
    if app.suffix != ".app" or not app.is_dir():
        raise SystemExit(f"DMG 输入必须是有效 App Bundle：{app}")
    if output.suffix != ".dmg" or output.parent.name != "build":
        raise SystemExit(f"拒绝写入 build 目录之外的 DMG：{output}")
    if output.exists():
        output.unlink()

    run(["codesign", "--verify", "--deep", "--strict", str(app)])
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="woice-dmg-") as temporary_directory:
        staging = Path(temporary_directory)
        shutil.copytree(app, staging / app.name)
        os.symlink("/Applications", staging / "Applications")
        run(
            [
                "hdiutil",
                "create",
                "-volname",
                args.volume_name,
                "-srcfolder",
                str(staging),
                "-ov",
                "-format",
                "UDZO",
                str(output),
            ]
        )
    run(["hdiutil", "verify", str(output)])
    print(f"package-dmg: {output}")


if __name__ == "__main__":
    main()
