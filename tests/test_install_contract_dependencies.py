import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('contract_dependencies', ROOT/'scripts/install_contract_dependencies.py')
deps = importlib.util.module_from_spec(spec)
spec.loader.exec_module(deps)


class DependencyAcquisitionTests(unittest.TestCase):
    def test_only_exact_official_azure_host_is_replaced(self):
        source = ('URIs: http://azure.archive.ubuntu.com/ubuntu/\n'
                  'Suites: noble noble-updates\nComponents: main universe\n'
                  'Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg\n')
        expected = source.replace('http://azure.archive.ubuntu.com', 'http://archive.ubuntu.com')
        self.assertEqual(deps.official_mirror(source), expected)
        self.assertEqual(deps.official_mirror('https://azure.archive.ubuntu.com/ubuntu'), 'https://archive.ubuntu.com/ubuntu')
        untouched = 'https://security.ubuntu.com/ubuntu https://azure.archive.ubuntu.com.example/ubuntu'
        self.assertEqual(deps.official_mirror(untouched), untouched)

    def test_source_copy_keeps_signature_and_original_unchanged(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            apt = root/'original'
            parts = apt/'sources.list.d'
            parts.mkdir(parents=True)
            original = 'deb [signed-by=/keyring.gpg] http://azure.archive.ubuntu.com/ubuntu noble main\n'
            (parts/'ubuntu.list').write_text(original)
            deps.copied_sources(apt, root/'copy')
            self.assertEqual((parts/'ubuntu.list').read_text(), original)
            self.assertEqual((root/'copy/sources.list.d/ubuntu.list').read_text(), deps.official_mirror(original))

    def test_deadlines_retry_bound_and_original_package_list(self):
        commands = deps.commands(Path('/temporary/source'))
        self.assertEqual([deadline for _, deadline in commands], [120, 420])
        self.assertEqual(deps.PACKAGES, 'build-essential pkg-config libx11-dev libwayland-dev wayland-protocols libegl1-mesa-dev libgles2-mesa-dev libxkbcommon-dev libpango1.0-dev libfontconfig1-dev fontconfig fonts-dejavu-core fonts-dejavu-extra fonts-noto-cjk fonts-noto-color-emoji'.split())
        for command, _ in commands:
            self.assertEqual(command[:4], ['sudo', 'timeout', '--signal=TERM', '--kill-after=15s'])
            self.assertIn('Acquire::Retries=1', command)
            self.assertIn('Acquire::http::Timeout=30', command)
            self.assertNotIn('--allow-unauthenticated', command)
            self.assertFalse(any('AllowInsecure' in arg or 'AllowDowngrade' in arg for arg in command))
        self.assertEqual(commands[1][0][-len(deps.PACKAGES):], deps.PACKAGES)


if __name__ == '__main__':
    unittest.main()
