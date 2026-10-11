from __future__ import annotations

import hashlib
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
CHECKER = ROOT / "scripts/check_linux_text_fonts.sh"


class LinuxTextFontsTests(unittest.TestCase):
    def run_checker(self, sans: str) -> subprocess.CompletedProcess[str]:
        with tempfile.TemporaryDirectory(prefix="font fixture ") as temp:
            directory = Path(temp)
            font = directory / "fixture font.ttf"
            font.write_bytes(b"font fixture bytes")
            matcher = directory / "fc-match"
            matcher.write_text('''#!/bin/sh
case "$3" in
  sans) family=$TEST_SANS ;;
  sans:charset=65e5) family='Noto Sans CJK JP' ;;
  *) family=$3 ;;
esac
printf '%s|%s\\n' "$family" "$TEST_FONT"
''')
            matcher.chmod(0o755)
            env = {**os.environ, "PATH": f"{directory}:{os.environ['PATH']}",
                   "TEST_SANS": sans, "TEST_FONT": str(font),
                   "FONTCONFIG_FILE": str(ROOT / "tests/linux_text/fonts.conf")}
            return subprocess.run(["sh", str(CHECKER)], env=env, text=True,
                                  capture_output=True, timeout=5)

    def test_historical_profile_logs_resolved_files_and_hashes(self) -> None:
        result = self.run_checker("DejaVu Math TeX Gyre")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("sans -> DejaVu Math TeX Gyre", result.stdout)
        self.assertIn("sans:charset=65e5 -> Noto Sans CJK JP", result.stdout)
        self.assertEqual(result.stdout.count("font fixture:"), 5)
        self.assertEqual(len(result.stdout.splitlines()), 10)
        self.assertEqual(result.stdout.count(hashlib.sha256(b"font fixture bytes").hexdigest()), 5)

    def test_missing_extra_font_fails_before_geometry_tests(self) -> None:
        result = self.run_checker("DejaVu Sans")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("expected family 'DejaVu Math TeX Gyre'", result.stderr)
        self.assertIn("fonts-dejavu-extra", result.stderr)


if __name__ == "__main__":
    unittest.main()
