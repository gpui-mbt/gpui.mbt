#!/usr/bin/env python3
"""Qualify a local arm64 macOS toolchain for the separate live IME gate.

Unlike #40's broad pinned actrun profile, this adapter does not install
toolchains or claim a reproducible historical Xcode image. Its exact host
identity is recorded by the acceptance runner and checked on revalidation.
"""
import os
from pathlib import Path
import platform
import subprocess

REPO = Path(__file__).resolve().parents[2]
DEPLOYMENT_TARGET = "26.0"


class ProfileError(RuntimeError):
    pass


def run(*argv):
    try:
        return subprocess.check_output(argv, text=True, stderr=subprocess.STDOUT, timeout=15).strip()
    except (OSError, subprocess.SubprocessError) as error:
        raise ProfileError(f"{argv[0]} failed: {error}") from error


def external_path(path):
    candidate = Path(path).expanduser().absolute()
    if candidate.is_symlink():
        raise ProfileError("profile cannot be a symlink")
    resolved = candidate.resolve(strict=True)
    home = Path.home().resolve()
    if not resolved.is_dir() or resolved in (Path("/"), home, REPO) or REPO in resolved.parents:
        raise ProfileError("profile must be an existing dedicated directory outside the checkout")
    return resolved


def host_identity():
    if platform.system() != "Darwin" or platform.machine() != "arm64":
        raise ProfileError("live IME requires a logged-in Apple Silicon Mac; CI builds are not acceptance")
    developer = run("xcode-select", "-p")
    sdk = run("xcrun", "--sdk", "macosx", "--show-sdk-path")
    return {
        "architecture": "arm64",
        "os_version": run("sw_vers", "-productVersion"),
        "os_build": run("sw_vers", "-buildVersion"),
        "xcode_select_path": developer,
        "xcode_version": run("xcodebuild", "-version"),
        "sdk_path": sdk,
        "sdk_version": run("xcrun", "--sdk", "macosx", "--show-sdk-version"),
        "clang_version": run("xcrun", "clang", "--version"),
    }


def doctor(root):
    external_path(root)
    host = host_identity()
    if int(host["os_version"].split(".")[0]) < 26:
        raise ProfileError("this restored #40 collector requires macOS 26 or later")
    return host


def profile_environment(root):
    host = doctor(root)
    return {
        **os.environ,
        "DEVELOPER_DIR": host["xcode_select_path"],
        "SDKROOT": host["sdk_path"],
        "MACOSX_DEPLOYMENT_TARGET": DEPLOYMENT_TARGET,
    }
