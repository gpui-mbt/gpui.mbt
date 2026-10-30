import importlib.util
import io
import json
import os
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

    def test_nested_regular_files_are_read_in_archive_order(self):
        archive, inventory = self.base/'ordered.tar.gz', self.base/'ordered.json'
        names = ['deep/nested/first', 'root-file', 'deep/last']
        rows = [{'path': name, 'mode': 0o755, 'kind': 'directory'}
                for name in ('deep', 'deep/nested')]
        content = b'order-fixture'
        with tarfile.open(archive, 'w:gz') as stream:
            # Files may precede directory headers; validation still checks all
            # declared parents, and restoration creates directories first.
            for name in names:
                item = tarfile.TarInfo('closure/'+name)
                item.mode, item.size = 0o644, len(content)
                stream.addfile(item, io.BytesIO(content))
                rows.append({'path': name, 'mode': item.mode, 'kind': 'file',
                             'size': len(content),
                             'sha256': __import__('hashlib').sha256(content).hexdigest()})
            for name in ('deep/nested', 'deep'):
                item = tarfile.TarInfo('closure/'+name)
                item.type, item.mode = tarfile.DIRTYPE, 0o755
                stream.addfile(item)
        inventory.write_text(json.dumps(rows))
        approved = {'approved_for_execution': True, 'runtime_sha256': mod.digest(archive),
                    'inventory_sha256': mod.digest(inventory),
                    'exact_restore_root': str(self.root), 'external_symlinks': {}}
        order = []
        original = tarfile.TarFile.extractfile
        def tracked(instance, member):
            order.append(member.name)
            return original(instance, member)
        with patch.object(tarfile.TarFile, 'extractfile', tracked):
            mod.restore(archive, inventory, approved)
        self.assertEqual(order, ['closure/'+name for name in names] * 2)
        for name in names:
            self.assertEqual((self.root/name).read_bytes(), content)

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

    def test_fresh_private_parent_and_existing_parent_rejection(self):
        approved = {'approved_for_execution': True,
                    'exact_restore_root': str(self.base/'gpui-ime-owned/closure')}
        with patch.dict(os.environ, RUNNER_TEMP=str(self.base)):
            record = mod.create_owned_parent(approved)
            self.assertEqual(record['uid'], os.geteuid())
            self.assertEqual(record['mode'], 0o700)
            with self.assertRaises(FileExistsError):
                mod.create_owned_parent(approved)

    def test_foreign_receipt_root_and_symlink_parent_rejected(self):
        approved = {'approved_for_execution': True, 'exact_restore_root': str(self.base/'old-closure')}
        with patch.dict(os.environ, RUNNER_TEMP=str(self.base)):
            with self.assertRaises(ValueError):
                mod.create_owned_parent(approved)
            approved['exact_restore_root'] = str(self.base/'gpui-ime-owned/closure')
            (self.base/'gpui-ime-owned').symlink_to(self.base/'missing', target_is_directory=True)
            with self.assertRaises(FileExistsError):
                mod.create_owned_parent(approved)

    def test_restore_without_approval_is_rejected(self):
        archive, inventory, receipt = self.bundle()
        receipt['approved_for_execution'] = False
        with self.assertRaises(ValueError):
            mod.restore(archive, inventory, receipt)
        self.assertFalse(self.root.exists())

    def test_read_only_member_validation_does_not_authorize_restore(self):
        archive, inventory, receipt = self.bundle()
        receipt['approved_for_execution'] = False
        rows = mod.read_inventory(archive, inventory, receipt)
        with tarfile.open(archive, 'r:gz') as tar:
            self.assertEqual(set(mod.validate_members(tar, rows, self.root, receipt)), {'file'})
        self.assertFalse(self.root.exists())
        with self.assertRaises(ValueError):
            mod.restore(archive, inventory, receipt)
        self.assertFalse(self.root.exists())

    def test_read_only_member_validation_rejects_mismatched_file_content(self):
        archive, inventory, receipt = self.bundle()
        rows = json.loads(inventory.read_text())
        rows[0]['sha256'] = '0' * 64
        inventory.write_text(json.dumps(rows))
        receipt['inventory_sha256'] = mod.digest(inventory)
        by_name = mod.read_inventory(archive, inventory, receipt)
        with tarfile.open(archive, 'r:gz') as tar, self.assertRaises(ValueError):
            mod.validate_members(tar, by_name, self.root, receipt)
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
