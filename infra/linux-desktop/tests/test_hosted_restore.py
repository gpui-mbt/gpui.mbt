import importlib.util
import io
import json
from pathlib import Path
import tarfile
import tempfile
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('hosted_restore', HERE / 'wayland-ime/recovery/hosted_restore.py')
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


class RestoreTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.root = self.base / 'restored'

    def bundle(self, name='closure/file', kind='file', target='file'):
        archive, inventory = self.base / 'runtime.tar.gz', self.base / 'inventory.json'
        item = tarfile.TarInfo(name)
        item.mode = 0o644
        if kind == 'file':
            item.size = 4
            row = {'path': 'file', 'mode': item.mode, 'kind': 'file', 'size': 4,
                   'sha256': __import__('hashlib').sha256(b'test').hexdigest()}
        else:
            item.type = tarfile.SYMTYPE if kind == 'symlink' else tarfile.LNKTYPE
            item.linkname = target
            row = {'path': 'file', 'mode': item.mode, 'kind': 'symlink', 'target': target}
        with tarfile.open(archive, 'w:gz') as stream:
            stream.addfile(item, io.BytesIO(b'test') if kind == 'file' else None)
        inventory.write_text(json.dumps([row]))
        receipt = {'approved_for_execution': True, 'runtime_sha256': mod.digest(archive), 'inventory_sha256': mod.digest(inventory),
                   'exact_restore_root': str(self.root), 'external_symlinks': {}}
        return archive, inventory, receipt

    def test_restores_exact_files(self):
        mod.restore(*self.bundle())
        self.assertEqual((self.root / 'file').read_bytes(), b'test')

    def test_traversal_absolute_and_foreign_members_rejected_before_write(self):
        for name in ('closure/../file', '/closure/file', 'other/file'):
            with self.subTest(name=name):
                with self.assertRaises(ValueError):
                    mod.restore(*self.bundle(name=name))
                self.assertFalse(self.root.exists())

    def test_escape_symlink_requires_exact_review_allowance(self):
        bundle = self.bundle(kind='symlink', target='/usr/lib/fixture')
        with self.assertRaises(ValueError):
            mod.restore(*bundle)
        self.assertFalse(self.root.exists())
        bundle[2]['external_symlinks'] = {'file': '/usr/lib/fixture'}
        mod.restore(*bundle)
        self.assertTrue((self.root / 'file').is_symlink())

    def test_hardlink_rejected(self):
        with self.assertRaises(ValueError):
            mod.restore(*self.bundle(kind='hardlink', target='../../escape'))
        self.assertFalse(self.root.exists())

    def test_restore_without_approval_is_rejected(self):
        archive, inventory, receipt = self.bundle()
        receipt['approved_for_execution'] = False
        with self.assertRaises(ValueError):
            mod.restore(archive, inventory, receipt)
        self.assertFalse(self.root.exists())

    def test_wrong_digest_rejected_before_write(self):
        archive, inventory, receipt = self.bundle()
        receipt['runtime_sha256'] = '0' * 64
        with self.assertRaises(ValueError):
            mod.restore(archive, inventory, receipt)
        self.assertFalse(self.root.exists())

    def test_missing_receipt_is_not_approval(self):
        with patch.object(mod, 'HERE', self.base):
            self.assertIsNone(mod.receipt())
            (self.base / 'hosted.review.json').write_text('{"approved_for_execution":false}')
            with self.assertRaises(ValueError):
                mod.receipt()


if __name__ == '__main__':
    unittest.main()
