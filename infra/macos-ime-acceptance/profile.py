#!/usr/bin/env python3
"""Bind native IME evidence to the observed Apple Silicon host, not PR #40 locks."""

import hashlib
import os
from pathlib import Path
import platform
import subprocess

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
MINIMUM_MACOS_MAJOR = 14


class ProfileError(RuntimeError):
    pass


def run(*argv):
    try:
        return subprocess.check_output(list(argv), text=True, stderr=subprocess.STDOUT, timeout=25).strip()
    except (OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
        raise ProfileError("toolchain probe failed: " + " ".join(argv) + ": " + str(error)) from error


def digest(path):
    value = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def deployment_target():
    # ScreenCaptureKit's SCScreenshotManager is supported on macOS 14+.
    return "14.0"


def host_identity():
    if platform.system() != "Darwin" or platform.machine() != "arm64":
        raise ProfileError("live Kotoeri evidence requires Apple Silicon arm64, not a CI/Intel host")
    product = run("sw_vers", "-productVersion")
    try:
        if int(product.split(".")[0]) < MINIMUM_MACOS_MAJOR:
            raise ValueError(product)
    except ValueError as error:
        raise ProfileError("macOS 14 or newer is required") from error
    xcode = run("xcodebuild", "-version").splitlines()
    if len(xcode) != 2:
        raise ProfileError("Xcode version/build identity is incomplete")
    clang = Path(run("xcrun", "--find", "clang")).resolve(strict=True)
    sdk = Path(run("xcrun", "--sdk", "macosx", "--show-sdk-path")).resolve(strict=True)
    settings = sdk / "SDKSettings.plist"
    if not settings.is_file():
        raise ProfileError("SDKSettings.plist is required for toolchain binding")
    return {
        "system": "Darwin",
        "architecture": "arm64",
        "product_version": product,
        "build_version": run("sw_vers", "-buildVersion"),
        "xcode": xcode,
        "xcode_select_path": run("xcode-select", "-p"),
        "sdk_version": run("xcrun", "--sdk", "macosx", "--show-sdk-version"),
        "sdk_path": str(sdk),
        "sdk_settings_sha256": digest(settings),
        "clang_path": str(clang),
        "clang_sha256": digest(clang),
        "clang_version": run(str(clang), "--version").splitlines()[0],
    }


def doctor(root):
    root = Path(root).expanduser().resolve(strict=True)
    repo = REPO.resolve()
    if not root.is_dir() or root == Path("/") or root == repo or repo in root.parents:
        raise ProfileError("profile directory must be dedicated and outside the checkout")
    host_identity()
    return root


def profile_environment(root, base=None):
    doctor(root)
    host = host_identity()
    result = dict(os.environ if base is None else base)
    result["DEVELOPER_DIR"] = host["xcode_select_path"]
    result["SDKROOT"] = host["sdk_path"]
    result["MACOSX_DEPLOYMENT_TARGET"] = deployment_target()
    result["CC"] = host["clang_path"]
    result["GPUI_MACOS_TEXT_CC"] = host["clang_path"]
    # Inherited search paths can substitute another SDK or dylib.
    for key in ("CPATH", "C_INCLUDE_PATH", "CPLUS_INCLUDE_PATH", "LIBRARY_PATH",
                "DYLD_LIBRARY_PATH", "CPPFLAGS", "CFLAGS", "LDFLAGS"):
        result[key] = ""
    return result
