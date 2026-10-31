import os
from pathlib import Path
import tempfile
import unittest

from private_mount_lease import LeaseError, MountLease


class PrivateMountLeaseTests(unittest.TestCase):
    def setUp(self):
        # The checkout path itself must be free of unsafe writable ancestors.
        self.tmp = tempfile.TemporaryDirectory(dir=os.getcwd(), prefix='.lease-test-')
        self.root = Path(self.tmp.name)
        self.source = self.root/'source'
        self.source.mkdir(mode=0o700)
        self.owner = os.getuid()

    def tearDown(self):
        self.tmp.cleanup()

    def test_valid_lease_and_close(self):
        with MountLease(str(self.root), 'source', self.owner) as lease:
            lease.revalidate()
        with self.assertRaisesRegex(LeaseError, 'closed'):
            lease.revalidate()
        lease.close()

    def test_replaced_directory_is_detected(self):
        with MountLease(str(self.root), 'source', self.owner) as lease:
            self.source.rename(self.root/'old')
            self.source.mkdir(mode=0o700)
            with self.assertRaisesRegex(LeaseError, 'replaced'):
                lease.revalidate()

    def test_replaced_parent_is_detected(self):
        (self.source/'leaf').mkdir(mode=0o700)
        with MountLease(str(self.root), 'source/leaf', self.owner) as lease:
            self.source.rename(self.root/'old')
            (self.source/'leaf').mkdir(parents=True, mode=0o700)
            with self.assertRaisesRegex(LeaseError, 'replaced'):
                lease.revalidate()

    def test_symlink_at_acquisition_and_revalidation_is_rejected(self):
        self.source.rename(self.root/'real')
        self.source.symlink_to(self.root/'real', target_is_directory=True)
        with self.assertRaisesRegex(LeaseError, 'without following'):
            MountLease(str(self.root), 'source', self.owner)
        self.source.unlink()
        self.source.mkdir(mode=0o700)
        with MountLease(str(self.root), 'source', self.owner) as lease:
            self.source.rmdir()
            self.source.symlink_to(self.root/'real', target_is_directory=True)
            with self.assertRaisesRegex(LeaseError, 'without following'):
                lease.revalidate()

    def test_symlink_ancestor_is_rejected(self):
        alias = self.root/'alias'
        alias.symlink_to(self.source, target_is_directory=True)
        with self.assertRaisesRegex(LeaseError, 'without following'):
            MountLease(str(alias), 'leaf', self.owner)

    def test_permissions_are_checked_again(self):
        with MountLease(str(self.root), 'source', self.owner) as lease:
            self.source.chmod(0o777)
            with self.assertRaisesRegex(LeaseError, 'unsafe mount source'):
                lease.revalidate()
        self.source.chmod(0o700)
        self.root.chmod(0o755)
        with self.assertRaisesRegex(LeaseError, 'private root'):
            MountLease(str(self.root), 'source', self.owner)
        self.root.chmod(0o700)

    def test_noncanonical_paths_and_wrong_owner_fail(self):
        for relative in ('../source', '/source', '.', 'source/../source', 'source//x'):
            with self.subTest(relative=relative), self.assertRaises(LeaseError):
                MountLease(str(self.root), relative, self.owner)
        with self.assertRaises(LeaseError):
            MountLease('//'+str(self.root).lstrip('/'), 'source', self.owner)
        with self.assertRaises(LeaseError):
            MountLease(str(self.root), 'source', 1001 if self.owner != 1001 else 1002)

    def test_unsafe_ancestor_and_descriptor_cleanup(self):
        os.chmod(self.source, 0o777)
        (self.source/'leaf').mkdir(mode=0o700)
        before = len(os.listdir('/proc/self/fd'))
        for _ in range(20):
            with self.assertRaises(LeaseError):
                MountLease(str(self.root), 'source/leaf', self.owner)
        self.assertEqual(len(os.listdir('/proc/self/fd')), before)
        os.chmod(self.source, 0o700)


if __name__ == '__main__':
    unittest.main()
