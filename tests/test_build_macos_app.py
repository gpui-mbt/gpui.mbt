"""Inert build-helper regressions. These do not compile or run a macOS app."""

import importlib.util
import json
import os
import plistlib
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class MacosAppBuilderTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="gpui-app-builder-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        gpui = self.root / "gpui"
        (gpui / "script").mkdir(parents=True)
        (gpui / "platform/macos").mkdir(parents=True)
        self.script = gpui / "script/build_macos_app.sh"
        shutil.copyfile(ROOT / "script/build_macos_app.sh", self.script)
        bins = self.root / "bin"
        bins.mkdir()
        stubs = {
            "uname": '#!/bin/bash\nprintf "Darwin\\n"\n',
            "xcrun": '''#!/usr/bin/env python3
import json, os, pathlib, sys
pathlib.Path(os.environ["XCRUN_LOG"]).write_text(json.dumps(sys.argv[1:]))
pathlib.Path(sys.argv[-1]).write_text("inert library\\n")
''',
            "moon": '''#!/bin/bash
set -euo pipefail
target=""
previous=""
for argument in "$@"; do
  if [[ "$previous" == --target-dir ]]; then target="$argument"; fi
  previous="$argument"
done
package="${!#}"
if [[ "${MOON_NO_EXECUTABLE:-}" == 1 ]]; then exit 0; fi
executable="${EXECUTABLE_NAME:-$(basename "$package")}.exe"
output="$target/native/debug/build/$package/$executable"
mkdir -p "$(dirname "$output")"
printf '%s\\n' "$package" > "$output"
if [[ "${MAKE_RUNNABLE:-}" == 1 ]]; then
  cat > "$output" <<'PY'
#!/usr/bin/env python3
import json, os, pathlib, sys
pathlib.Path(os.environ["APP_ARGS_LOG"]).write_text(json.dumps(sys.argv[1:]))
PY
  chmod +x "$output"
fi
if [[ "${DUPLICATE_EXECUTABLE:-}" == 1 ]]; then
  mkdir -p "$target/native/debug/build/duplicate"
  cp "$output" "$target/native/debug/build/duplicate/$executable"
fi
''',
        }
        for name, stub in stubs.items():
            path = bins / name
            path.write_text(stub)
            path.chmod(0o755)
        self.app = self.root / "app"
        for package in ["src/app", "src/tools/app"]:
            (self.app / package).mkdir(parents=True)
        (self.app / "moon.work").write_text("members = []\n")
        self.env = os.environ | {
            "PATH": str(bins) + ":" + os.environ["PATH"],
            "XCRUN_LOG": str(self.root / "xcrun-args.json"),
            "APP_ARGS_LOG": str(self.root / "app-args.json"),
        }

    def build(self, package="src/app", name="Fixture", mode="build", options=(), app_args=None, **env):
        return subprocess.run(
            ["/bin/bash", str(self.script), "--root", str(self.app), "--name", name,
             "--bundle-id", "org.example.fixture", "--package", package,
             *options, "--" + mode, *([] if app_args is None else ["--", *app_args])],
            env=self.env | env, capture_output=True, text=True,
        )

    def test_repeated_same_basename_builds_package_the_requested_source(self):
        for package in ["src/app", "src/tools/app", "src/app"]:
            result = self.build(package)
            self.assertEqual(result.returncode, 0, result.stderr)
            binary = self.app / "build/Fixture.app/Contents/MacOS/Fixture"
            self.assertEqual(binary.read_text().strip(), str(self.app / package))

    def test_ambiguous_outputs_fail_instead_of_packaging_a_random_binary(self):
        result = self.build(DUPLICATE_EXECUTABLE="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("expected exactly one built executable", result.stderr)
        self.assertFalse((self.app / "build/Fixture.app/Contents/MacOS/Fixture").exists())

    def test_module_root_name_need_not_match_its_directory(self):
        result = self.build(EXECUTABLE_NAME="module_name")
        self.assertEqual(result.returncode, 0, result.stderr)
        binary = self.app / "build/Fixture.app/Contents/MacOS/Fixture"
        self.assertEqual(binary.read_text().strip(), str(self.app / "src/app"))

    def test_successful_build_without_an_executable_rejects_stale_output(self):
        self.assertEqual(self.build().returncode, 0)
        result = self.build(MOON_NO_EXECUTABLE="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("expected exactly one built executable", result.stderr)

    def test_zero_one_multiple_native_options_preserve_argument_boundaries(self):
        for sources, frameworks in [
            ([], []),
            (["/tmp/source one.m"], ["AudioToolbox"]),
            (["/tmp/source one.m", "/tmp/source two.m"], ["AudioToolbox", "Test Framework"]),
        ]:
            with self.subTest(sources=sources, frameworks=frameworks):
                options = [arg for source in sources for arg in ["--native-source", source]]
                options += [arg for framework in frameworks for arg in ["--framework", framework]]
                result = self.build(options=options)
                self.assertEqual(result.returncode, 0, result.stderr)
                args = json.loads((self.root / "xcrun-args.json").read_text())
                self.assertNotIn("", args)
                self.assertEqual([arg for arg in args if arg in sources], sources)
                selected = [args[i + 1] for i, arg in enumerate(args[:-1]) if arg == "-framework"]
                self.assertEqual(selected, ["AppKit", "QuartzCore", "Metal", "CoreText", "CoreGraphics", "CoreFoundation", *frameworks])

    def test_smoke_preserves_zero_one_multiple_application_arguments(self):
        for app_args in [[], ["one argument"], ["one argument", "", "two"]]:
            with self.subTest(app_args=app_args):
                result = self.build(mode="smoke", app_args=app_args, MAKE_RUNNABLE="1")
                self.assertEqual(result.returncode, 0, result.stderr)
                actual = json.loads((self.root / "app-args.json").read_text())
                self.assertEqual(actual, ["--smoke", *app_args])

    def test_bundle_name_is_xml_escaped(self):
        name = 'Research & Planning <test> "v1"'
        result = self.build(name=name)
        self.assertEqual(result.returncode, 0, result.stderr)
        plist = self.app / "build" / (name + ".app") / "Contents/Info.plist"
        info = plistlib.loads(plist.read_bytes())
        self.assertEqual(info["CFBundleExecutable"], name)
        self.assertEqual(info["CFBundleName"], name)

    def test_app_name_cannot_escape_bundle_directory(self):
        result = self.build(name="../outside")
        self.assertEqual(result.returncode, 2)
        self.assertIn("single filename", result.stderr)

    def test_consumer_fixture_imports_actual_helpers(self):
        spec = importlib.util.spec_from_file_location(
            "consumer", ROOT / "scripts/test_macos_app_consumer.py"
        )
        consumer = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(consumer)
        fixture = self.root / "fixture"
        fixture.mkdir()
        module = consumer.prepare_fixture(fixture)
        self.assertIn("f4ah6o/gpui/platform/macos_app", (module / "moon.pkg").read_text())
        self.assertIn("require_grayscale_raster().unwrap()", (module / "main.mbt").read_text())
        self.assertEqual(
            (fixture / "script/macos_text_prebuild.mbtx").read_bytes(),
            (ROOT / "script/macos_text_prebuild.mbtx").read_bytes(),
        )


if __name__ == "__main__":
    unittest.main()
