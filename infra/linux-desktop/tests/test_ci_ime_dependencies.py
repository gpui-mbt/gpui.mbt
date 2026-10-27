"""Host prerequisites complement the unchanged private runtime, not its pins."""
import json
from pathlib import Path
import shlex
import unittest

HERE = Path(__file__).resolve().parents[1]


class ImeHostDependenciesTests(unittest.TestCase):
    def test_ibus_notification_dependency_is_explicitly_installed(self):
        packages = json.loads((HERE/'profile.lock.json').read_text())['packages']
        ibus = next(row for row in packages if row['name'] == 'ibus')
        self.assertIn('libnotify4 (>= 0.7.0)', ibus['depends'])
        workflow = (HERE.parents[1]/'.github/workflows/linux-ime-execute.yml').read_text()
        install = next(line.strip() for line in workflow.splitlines() if 'apt-get install -y' in line)
        arguments = shlex.split(install)
        self.assertEqual(arguments.count('libnotify4'), 1)
        self.assertNotIn('--allow-unauthenticated', arguments)
        self.assertNotIn('LD_PRELOAD', workflow)
        self.assertNotIn('dpkg --force', workflow)


if __name__ == '__main__':
    unittest.main()
