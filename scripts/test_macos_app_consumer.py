#!/usr/bin/env python3
"""Build and run a headless external consumer of the macOS app helpers.

This exercises the reusable bundle builder and CoreText, not native windows,
input, accessibility, GPU presentation, or the external integration demo.
"""

import argparse
import ctypes
import json
import platform
import plistlib
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP_NAME = "GpuiAppConsumer"
BUNDLE_ID = "org.gpui.mbt.app-consumer"
MARKER = "MACOS_APP_CONSUMER_PASS"
SOURCE = '''///|
fn main {
  @macos_text.require_grayscale_raster().unwrap()
  let painter = @macos_app.MacosTextPainter::new(2).unwrap()
  let measured = painter.measure("CoreText consumer", 16.0).unwrap()
  if measured.width() <= 0.0 || measured.line_height() <= 0.0 {
    abort("CoreText consumer returned empty metrics")
  }
  let adapter = @macos_app.MacosTextFieldAdapter::new(16.0).unwrap()
  let document = @text.TextDocument::new("Hello").unwrap()
  let geometry = adapter.measure(document).unwrap()
  adapter.admit(document, geometry).unwrap()
  if adapter.hit(document, @primitives.Point::new(0.0, 0.0).unwrap())
    .unwrap().resolved_utf16_offset() != 0 {
    abort("CoreText consumer returned an invalid caret")
  }
  println("MACOS_APP_CONSUMER_PASS")
}
'''


def prepare_fixture(workspace: Path) -> Path:
    module = workspace / "consumer"
    module.mkdir()
    (workspace / "moon.work").write_text(
        "members = " + json.dumps([str(ROOT), str(module)]) + "\n"
    )
    # The pinned Moon workspace toolchain resolves member prebuild paths from
    # the workspace root. Keep the module's existing CoreText prebuild hook.
    (workspace / "script").mkdir()
    shutil.copyfile(
        ROOT / "script/macos_text_prebuild.mbtx",
        workspace / "script/macos_text_prebuild.mbtx",
    )
    (module / "moon.mod").write_text(
        'name = "test/macos_app_consumer"\nversion = "0.0.0"\n'
        'import { "f4ah6o/gpui@0.9.0", }\n'
    )
    (module / "moon.pkg").write_text(
        'import { "f4ah6o/gpui/platform/macos_app", '
        '"f4ah6o/gpui/platform/macos_text", "f4ah6o/gpui/primitives", '
        '"f4ah6o/gpui/text", }\n'
        'supported_targets = "native"\npkgtype(kind: "executable")\n'
    )
    (module / "main.mbt").write_text(SOURCE)
    return module


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if platform.system() != "Darwin":
        parser.error("this check requires macOS; it must not silently skip")
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="gpui-macos-app-consumer-") as path:
        workspace = Path(path)
        module = prepare_fixture(workspace)
        command = [
            "/bin/bash", str(ROOT / "script/build_macos_app.sh"),
            "--root", str(workspace), "--name", APP_NAME,
            "--bundle-id", BUNDLE_ID, "--package", str(module),
            "--target-dir", str(output / "bundle"), "--build",
        ]
        subprocess.run(command, check=True)
    bundle = output / "bundle" / (APP_NAME + ".app")
    binary = bundle / "Contents/MacOS" / APP_NAME
    library = bundle / "Contents/Frameworks/libgpui_macos.dylib"
    with (bundle / "Contents/Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    if info["CFBundleExecutable"] != APP_NAME or info["CFBundleIdentifier"] != BUNDLE_ID:
        raise RuntimeError("incorrect application bundle metadata")
    ctypes.CDLL(str(library))
    result = subprocess.run([str(binary)], text=True, capture_output=True)
    (output / "consumer.stdout.log").write_text(result.stdout)
    (output / "consumer.stderr.log").write_text(result.stderr)
    (output / "consumer.mbt").write_text(SOURCE)
    if result.returncode:
        print(result.stderr, end="", flush=True)
        result.check_returncode()
    if result.stdout.strip() != MARKER:
        raise RuntimeError("the packaged CoreText consumer did not pass")
    print(MARKER, flush=True)


if __name__ == "__main__":
    main()
