import importlib.util
from pathlib import Path
from contextlib import ExitStack
import tempfile
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('ci_nonroot', HERE/'ci-nonroot.py')
ci = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ci)


class NonrootTests(unittest.TestCase):
    def valid(self, **values):
        return dict(uid=1001, gid=1001, mode=0o755, **values)

    def test_observed_nonroot_identity_and_exact_paths(self):
        row = self.valid()
        self.assertEqual(ci.validate(ci.TEMP, ci.SOURCE, row, row), (1001, 1001))
        for uid, gid in ((0, 1001), (1001, 0), (65534, 65534)):
            with self.assertRaises(ValueError):
                ci.validate(ci.TEMP, ci.SOURCE, {'uid': uid, 'gid': gid, 'mode': 0o755}, row)
        for temp, source in ((Path('/tmp'), ci.SOURCE), (ci.TEMP, Path('/foreign/repo'))):
            with self.assertRaises(ValueError):
                ci.validate(temp, source, row, row)

    def test_source_identity_and_permission_mismatch_rejected(self):
        row = self.valid()
        for bad in ({'uid': 1002, 'gid': 1001, 'mode': 0o755},
                    {'uid': 1001, 'gid': 1002, 'mode': 0o755},
                    {'uid': 1001, 'gid': 1001, 'mode': 0o777}):
            with self.assertRaises(ValueError):
                ci.validate(ci.TEMP, ci.SOURCE, row, bad)

    def test_existing_user_or_group_is_never_adopted(self):
        with self.assertRaises(ValueError):
            ci.absent(lambda key: object(), 1001)
        def missing(key):
            raise KeyError(key)
        ci.absent(missing, 1001)

    def test_symlink_and_noncanonical_directory_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root/'alias').symlink_to(root, target_is_directory=True)
            with self.assertRaises(ValueError):
                ci.inspect(root/'alias')
            with self.assertRaises(ValueError):
                ci.inspect(root/'alias/../alias')

    def test_real_effective_ids_and_groups_must_match(self):
        with patch.object(ci.os, 'getuid', return_value=1001), patch.object(ci.os, 'geteuid', return_value=1001), patch.object(ci.os, 'getgid', return_value=1001), patch.object(ci.os, 'getegid', return_value=1001), patch.object(ci.os, 'getgroups', return_value=[1001]):
            ci.validate_process(1001, 1001)
            with patch.object(ci.os, 'geteuid', return_value=0), self.assertRaises(ValueError):
                ci.validate_process(1001, 1001)
            with patch.object(ci.os, 'getuid', return_value=0), self.assertRaises(ValueError):
                ci.validate_process(1001, 1001)
            with patch.object(ci.os, 'getegid', return_value=0), self.assertRaises(ValueError):
                ci.validate_process(1001, 1001)
            with patch.object(ci.os, 'getgroups', return_value=[1001, 0]), self.assertRaises(ValueError):
                ci.validate_process(1001, 1001)

    def test_setup_chowns_only_new_private_home_and_evidence(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            record = {'uid': 1001, 'gid': 1001, 'home': str(root/'home'), 'evidence': str(root/'evidence')}
            with patch.object(ci, 'plan', return_value=record), patch.dict(ci.os.environ, RUNNER_TEMP=str(ci.TEMP), GITHUB_WORKSPACE=str(ci.SOURCE), GPUI_CONTAINER_IMAGE=ci.IMAGE), patch.object(ci.os, 'getuid', return_value=0), patch.object(ci.os, 'geteuid', return_value=0), patch.object(ci.subprocess, 'run') as run, patch.object(ci.os, 'chown') as chown:
                ci.setup()
            self.assertEqual(run.call_count, 2)
            self.assertEqual([call.args[0] for call in chown.call_args_list], [root/'home', root/'evidence'])
            self.assertEqual((root/'home').stat().st_mode & 0o777, 0o700)

    def test_all_account_collisions_and_nonfresh_home_fail_before_mutation(self):
        lookups = [(ci.pwd, 'getpwnam'), (ci.pwd, 'getpwuid'),
                   (ci.grp, 'getgrnam'), (ci.grp, 'getgrgid')]
        for collision in range(5):
            with self.subTest(collision=collision), ExitStack() as stack:
                stack.enter_context(patch.object(ci.os, 'getuid', return_value=0))
                stack.enter_context(patch.object(ci.os, 'geteuid', return_value=0))
                stack.enter_context(patch.dict(ci.os.environ, RUNNER_TEMP=str(ci.TEMP),
                                               GITHUB_WORKSPACE=str(ci.SOURCE), GPUI_CONTAINER_IMAGE=ci.IMAGE))
                stack.enter_context(patch.object(ci, 'inspect', return_value=self.valid()))
                for index, (module, name) in enumerate(lookups):
                    stack.enter_context(patch.object(module, name, **(
                        {'return_value': object()} if index == collision else {'side_effect': KeyError('missing')})))
                stack.enter_context(patch.object(Path, 'exists', lambda path: collision == 4 and path.name == 'gpui-ime-home'))
                stack.enter_context(patch.object(Path, 'is_symlink', return_value=False))
                mutation = stack.enter_context(patch.object(ci.subprocess, 'run'))
                with self.assertRaises(ValueError):
                    ci.setup()
                mutation.assert_not_called()

    def test_wrong_image_fails_before_account_setup(self):
        with patch.object(ci.os, 'getuid', return_value=0), patch.object(ci.os, 'geteuid', return_value=0), patch.dict(ci.os.environ, GPUI_CONTAINER_IMAGE='foreign'), patch.object(ci.subprocess, 'run') as mutation:
            with self.assertRaises(ValueError):
                ci.setup()
            mutation.assert_not_called()

    def test_workflow_uses_runuser_for_all_execution_phases(self):
        workflow = (HERE.parents[1]/'.github/workflows/linux-ime-execute.yml').read_text()
        self.assertIn('python3 infra/linux-desktop/ci-nonroot.py setup', workflow)
        self.assertIn('runuser -u gpui-ime-ci -- python3 infra/linux-desktop/ci-owned-checkout.py', workflow)
        for phase in ('metadata', 'execute'):
            self.assertIn('runuser -u gpui-ime-ci -- python3 "$RUNNER_TEMP/gpui-ime-iac/infra/linux-desktop/ci-ime-execute.py" '+phase, workflow)
        self.assertIn('ci-nonroot.py" check --downloads', workflow)
        self.assertNotIn('chown', workflow)
        self.assertNotIn('chmod', workflow)


if __name__ == '__main__':
    unittest.main()
