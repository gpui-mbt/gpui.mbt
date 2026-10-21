import json
import os
import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "script" / "macos_text_prebuild.mbtx"


class MacOSTextPrebuildTests(unittest.TestCase):
    def run_prebuild(self, host_os: str, backend: str) -> dict[str, object]:
        result = subprocess.run(
            ["moon", "run", str(SCRIPT.relative_to(ROOT))],
            cwd=ROOT,
            capture_output=True,
            check=True,
            env={
                **os.environ,
                "MOON_HOST_OS": host_os,
                "MOON_BACKEND": backend,
            },
            text=True,
        )
        return json.loads(result.stdout)

    def test_macos_native_propagates_coretext_frameworks(self) -> None:
        result = self.run_prebuild("macos", "native")
        self.assertEqual(
            result,
            {
                "link_configs": [
                    {
                        "package": "f4ah6o/gpui/platform/macos_text",
                        "link_flags": (
                            "-framework CoreText -framework CoreGraphics "
                            "-framework CoreFoundation"
                        ),
                    }
                ]
            },
        )

    def test_other_hosts_do_not_receive_macos_frameworks(self) -> None:
        self.assertEqual(self.run_prebuild("linux", "native"), {})
        self.assertEqual(self.run_prebuild("macos", "wasm-gc"), {})

    def test_module_declares_the_moonbit_prebuild(self) -> None:
        manifest = (ROOT / "moon.mod").read_text(encoding="utf-8")
        self.assertIn(
            '"--moonbit-unstable-prebuild": "script/macos_text_prebuild.mbtx"',
            manifest,
        )
        self.assertFalse((ROOT / "script/macos_text_prebuild.py").exists())


if __name__ == "__main__":
    unittest.main()
