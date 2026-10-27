import importlib.util
import json
import os
from pathlib import Path
import tarfile
import tempfile
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('ci_ime_prepare', HERE / 'ci-ime-prepare.py')
ci = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ci)


class PrepareTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.root = self.base / 'closure'
        self.output = self.base / 'evidence'

    def fixture(self):
        self.root.mkdir()
        self.output.mkdir()
        binary = self.root / 'engine'
        binary.write_bytes(b'not-an-executable-test-fixture')
        binary.chmod(0o755)
        (self.root / 'link').symlink_to('engine')

    def test_roots_must_be_fresh_disjoint_and_canonical(self):
        repo = self.base / 'repo'
        repo.mkdir()
        ci.disjoint_roots(repo, self.root, self.output)
        for root, evidence in [(repo, self.output), (repo / 'build', self.output),
                               (self.root, self.root / 'evidence')]:
            with self.assertRaises(ValueError):
                ci.disjoint_roots(repo, root, evidence)
        self.root.mkdir()
        with self.assertRaises(ValueError):
            ci.disjoint_roots(repo, self.root, self.output)
        link = self.base / 'alias'
        link.symlink_to(repo, target_is_directory=True)
        with self.assertRaises(ValueError):
            ci.disjoint_roots(link, self.base / 'new', self.output)

    def test_export_never_claims_native_pass_or_approval(self):
        self.fixture()
        with patch.dict(os.environ, GPUI_CONTAINER_IMAGE=ci.CONTAINER_IMAGE):
            result = ci.export_closure(self.root, self.output, {'sha': 'test', 'tree': 'tree'}, [])
        self.assertEqual(result['preparation_status'], 'PREPARED')
        self.assertEqual(result['native_status'], 'NOT_RUN')
        self.assertIs(result['approved_for_execution'], False)
        archive = self.output / result['runtime_archive']['name']
        self.assertEqual(ci.digest(archive), result['runtime_archive']['sha256'])
        self.assertEqual(str(self.root), result['exact_restore_root'])
        with tarfile.open(archive) as bundle:
            self.assertEqual(bundle.getmember('closure/engine').mode, 0o755)
            self.assertTrue(bundle.getmember('closure/link').issym())
            self.assertEqual(bundle.getmember('closure/link').linkname, 'engine')
            self.assertTrue(all(not name.startswith('/') and '..' not in Path(name).parts
                                for name in bundle.getnames()))

    def test_unidentified_container_and_failed_stage_are_not_prepared(self):
        self.fixture()
        with patch.dict(os.environ, GPUI_CONTAINER_IMAGE='unverified'):
            with self.assertRaises(ValueError):
                ci.export_closure(self.root, self.output, {}, [])
        with patch.dict(os.environ, GPUI_CONTAINER_IMAGE=ci.CONTAINER_IMAGE):
            with self.assertRaises(ValueError):
                ci.export_closure(self.root, self.output, {}, [{'returncode': 1}])
        self.assertFalse((self.output / 'prepare-result.json').exists())

    def test_special_files_cannot_enter_closure(self):
        self.fixture()
        os.mkfifo(self.root / 'fifo')
        with self.assertRaises(ValueError):
            ci.inventory(self.root)

    def test_inventory_does_not_follow_external_symlinks(self):
        self.fixture()
        outside = self.base / 'outside'
        outside.mkdir()
        (outside / 'private').write_text('not part of closure')
        (self.root / 'external').symlink_to(outside, target_is_directory=True)
        rows = ci.inventory(self.root)
        self.assertEqual(next(row for row in rows if row['path'] == 'external')['target'], str(outside))
        self.assertFalse(any('private' in row['path'] for row in rows))

    def test_git_failure_leaves_explicit_not_run_receipt(self):
        with patch.object(ci.subprocess, 'check_output',
                          side_effect=ci.subprocess.CalledProcessError(1, 'git')):
            code = ci.main(['--root', str(self.root), '--evidence', str(self.output)])
        self.assertEqual(code, 1)
        result = json.loads((self.output / 'prepare-result.json').read_text())
        self.assertEqual(result['preparation_status'], 'FAIL')
        self.assertEqual(result['native_status'], 'NOT_RUN')
        self.assertFalse(result['approved_for_execution'])


if __name__ == '__main__':
    unittest.main()
