import os
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CC_WRAPPER = ROOT / "script" / "linux_text_cc.sh"
AR_WRAPPER = ROOT / "script" / "ar"
RANLIB_WRAPPER = ROOT / "script" / "ranlib"

FAKE_PKG_CONFIG = """#!/bin/sh
case "$1" in
  --atleast-version=1.50) exit {version_status} ;;
  --cflags)
    printf '%s\\n' "{cflags}"
    exit {cflags_status}
    ;;
  --libs) printf '%s\\n' "{libs}" ;;
  *) exit 9 ;;
esac
"""

FAKE_COMPILER = """#!/bin/sh
printf '%s\\n' "$@" > "$CAPTURE"
"""

FAKE_TOOL = """#!/bin/sh
printf '%s\\n' "$@" > "$CAPTURE"
"""


def write_tool(path: Path, text: str) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
    path.chmod(0o755)
    return path


class LinuxTextCCWrapperTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix="gpui-linux-text-cc-")
        self.root = Path(self.temp.name)
        self.addCleanup(self.temp.cleanup)
        self.capture = self.root / "capture.txt"
        self.compiler = write_tool(self.root / "fakecc", FAKE_COMPILER)

    def run_wrapper(
        self,
        *args: str,
        env: dict[str, str] | None = None,
    ) -> subprocess.CompletedProcess[str]:
        base = {
            **os.environ,
            "GPUI_LINUX_TEXT_CC": str(self.compiler),
            "CAPTURE": str(self.capture),
            "CPPFLAGS": "",
            "CFLAGS": "",
            "LDFLAGS": "",
        }
        if env:
            base.update(env)
        return subprocess.run(
            ["/bin/sh", str(CC_WRAPPER), *args],
            capture_output=True,
            text=True,
            env=base,
        )

    def captured(self) -> list[str]:
        return self.capture.read_text(encoding="utf-8").splitlines()

    def pkg_config(self, **values: object) -> str:
        defaults = {
            "version_status": 0,
            "cflags_status": 0,
            "cflags": "-I/fake/pango -DPANGO=1",
            "libs": "-lpangoft2 -lfontconfig",
        }
        defaults.update(values)
        return str(write_tool(self.root / "fake-pkg-config", FAKE_PKG_CONFIG.format(**defaults)))

    def test_composes_flags_in_the_legacy_order(self) -> None:
        pkg = self.pkg_config()
        result = self.run_wrapper(
            "-c",
            "foo.c",
            "-o",
            "foo.o",
            env={
                "PKG_CONFIG": pkg,
                "CPPFLAGS": "-DCPP",
                "CFLAGS": "-DCFLAGS",
                "LDFLAGS": "-LLD",
            },
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.captured(),
            [
                "-I/fake/pango",
                "-DPANGO=1",
                "-DCPP",
                "-c",
                "foo.c",
                "-o",
                "foo.o",
                "-DCFLAGS",
                "-LLD",
                "-lpangoft2",
                "-lfontconfig",
            ],
        )

    def test_empty_project_flags_do_not_add_arguments(self) -> None:
        result = self.run_wrapper("main.c", env={"PKG_CONFIG": self.pkg_config()})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("", self.captured())

    def test_compiler_path_with_spaces_stays_one_argument(self) -> None:
        spaced = write_tool(self.root / "fake tools" / "cc compiler", FAKE_COMPILER)
        result = self.run_wrapper(
            "-c",
            "foo.c",
            env={"PKG_CONFIG": self.pkg_config(), "GPUI_LINUX_TEXT_CC": str(spaced)},
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        captured = self.captured()
        self.assertIn("-c", captured)
        self.assertIn("foo.c", captured)
        self.assertIn("-I/fake/pango", captured)

    def test_outdated_pangoft2_fails_with_the_version_message(self) -> None:
        pkg = self.pkg_config(version_status=1)
        result = self.run_wrapper(
            "main.c",
            env={"PKG_CONFIG": pkg},
        )
        self.assertEqual(result.returncode, 2)
        self.assertIn("PangoFT2 1.50 or newer", result.stderr)

    def test_missing_pkg_config_fails_with_the_install_message(self) -> None:
        result = self.run_wrapper(
            "main.c",
            env={"PKG_CONFIG": str(self.root / "missing-pkg-config")},
        )
        self.assertEqual(result.returncode, 2)
        self.assertIn("requires pkg-config metadata for pangoft2", result.stderr)

    def test_cflags_failure_reports_the_discovery_error(self) -> None:
        pkg = self.pkg_config(cflags_status=1)
        result = self.run_wrapper("main.c", env={"PKG_CONFIG": pkg})
        self.assertEqual(result.returncode, 2)
        self.assertIn("requires pkg-config metadata for pangoft2", result.stderr)

    def test_empty_compiler_is_rejected(self) -> None:
        result = self.run_wrapper(
            "main.c",
            env={"PKG_CONFIG": self.pkg_config(), "GPUI_LINUX_TEXT_CC": ""},
        )
        self.assertEqual(result.returncode, 2)
        self.assertIn("GPUI_LINUX_TEXT_CC must name a compiler", result.stderr)

    def test_ar_forwards_the_selected_tool(self) -> None:
        tool = write_tool(self.root / "fake-ar", FAKE_TOOL)
        result = subprocess.run(
            ["/bin/sh", str(AR_WRAPPER), "-q", "lib.a", "a.o"],
            capture_output=True,
            text=True,
            env={**os.environ, "AR": str(tool), "CAPTURE": str(self.capture)},
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.captured(), ["-q", "lib.a", "a.o"])

    def test_ranlib_forwards_the_selected_tool(self) -> None:
        tool = write_tool(self.root / "fake-ranlib", FAKE_TOOL)
        result = subprocess.run(
            ["/bin/sh", str(RANLIB_WRAPPER), "lib.a"],
            capture_output=True,
            text=True,
            env={**os.environ, "RANLIB": str(tool), "CAPTURE": str(self.capture)},
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.captured(), ["lib.a"])

    def test_empty_ar_is_rejected(self) -> None:
        result = subprocess.run(
            ["/bin/sh", str(AR_WRAPPER)],
            capture_output=True,
            text=True,
            env={**os.environ, "AR": ""},
        )
        self.assertEqual(result.returncode, 1)
        self.assertIn("AR must name an archiver", result.stderr)

    def test_packages_reference_the_shell_wrapper_only(self) -> None:
        manifests = [
            path
            for path in ROOT.rglob("moon.pkg")
            if "_build" not in path.parts and ".mooncakes" not in path.parts
        ]
        referencing = [path for path in manifests if "linux_text_cc" in path.read_text()]
        self.assertTrue(referencing)
        for path in referencing:
            text = path.read_text()
            self.assertIn('"script/linux_text_cc.sh"', text)
            self.assertNotIn(".py", text)

    def test_wrappers_are_executable_and_use_posix_sh(self) -> None:
        for path in (CC_WRAPPER, AR_WRAPPER, RANLIB_WRAPPER):
            self.assertTrue(os.access(path, os.X_OK), f"{path} is not executable")
            self.assertEqual(path.read_text().splitlines()[0], "#!/bin/sh")


if __name__ == "__main__":
    unittest.main()
