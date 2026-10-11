from __future__ import annotations

import configparser
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
LAUNCHER = ROOT / "scripts/start_ubuntu_test_compositor.sh"
CONFIG = ROOT / "tests/ubuntu/weston.ini"


class UbuntuCompositorTests(unittest.TestCase):
    def test_launcher_uses_explicit_desktop_profile_and_preserves_exit_status(self) -> None:
        with tempfile.TemporaryDirectory(prefix="weston profile ") as temp:
            directory = Path(temp)
            weston = directory / "weston"
            weston.write_text('#!/bin/sh\nprintf "%s\\n" "$$" "$@"\nexit 23\n')
            weston.chmod(0o755)
            env = {**os.environ, "PATH": f"{directory}:{os.environ['PATH']}"}
            command = ["sh", str(LAUNCHER), "--scale=2", "--socket=test-socket",
                       "--log=/a path/weston.log"]
            with subprocess.Popen(command, cwd=directory, env=env, text=True,
                                  stdout=subprocess.PIPE) as process:
                output, _ = process.communicate(timeout=5)
                self.assertEqual(process.returncode, 23)
                lines = output.splitlines()
                self.assertEqual(int(lines[0]), process.pid)
            self.assertEqual(lines[1:], [
                "--backend=headless-backend.so", "--use-gl", "--shell=desktop-shell.so",
                f"--config={CONFIG}", "--idle-time=0", "--scale=2",
                "--socket=test-socket", "--log=/a path/weston.log",
            ])

    def test_profile_disables_animations_and_both_drivers_use_it(self) -> None:
        config = configparser.ConfigParser()
        config.read(CONFIG)
        for key in ("animation", "close-animation", "startup-animation", "focus-animation",
                    "panel-position"):
            self.assertEqual(config["shell"][key], "none")
        self.assertFalse(config.getboolean("shell", "locking"))
        for name in ("test_ubuntu.sh", "capture_ubuntu_wayland_trace.sh"):
            driver = (ROOT / "scripts" / name).read_text()
            self.assertEqual(driver.count("sh scripts/start_ubuntu_test_compositor.sh"), 1)
            self.assertNotIn("kiosk-shell.so", driver)
            self.assertNotIn("--no-config", driver)
            self.assertIn('for scale in 1 2; do', driver)


if __name__ == "__main__":
    unittest.main()
