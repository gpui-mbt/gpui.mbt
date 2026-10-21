import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "script" / "macos_text_prebuild.mbtx"


class MacOSTextPrebuildTests(unittest.TestCase):
    """Wiring checks for the prebuild hook.

    The hook behavior is covered by the script's own `moon test` cases in the
    job that installs the MoonBit toolchain. This module also runs where only
    Python is available, so it checks the module declaration and the script's
    target package and environment inputs without executing MoonBit code.
    """

    def test_module_declares_the_moonbit_prebuild(self) -> None:
        manifest = (ROOT / "moon.mod").read_text(encoding="utf-8")
        self.assertIn(
            '"--moonbit-unstable-prebuild": "script/macos_text_prebuild.mbtx"',
            manifest,
        )
        self.assertFalse((ROOT / "script/macos_text_prebuild.py").exists())

    def test_script_targets_the_portable_text_package(self) -> None:
        text = SCRIPT.read_text(encoding="utf-8")
        self.assertIn("f4ah6o/gpui/platform/macos_text", text)
        for framework in ("CoreText", "CoreGraphics", "CoreFoundation"):
            self.assertIn(framework, text)
        self.assertIn("MOON_HOST_OS", text)
        self.assertIn("MOON_BACKEND", text)

    def test_script_keeps_its_own_behavior_tests(self) -> None:
        text = SCRIPT.read_text(encoding="utf-8")
        self.assertGreaterEqual(text.count('\ntest "'), 2)


if __name__ == "__main__":
    unittest.main()
