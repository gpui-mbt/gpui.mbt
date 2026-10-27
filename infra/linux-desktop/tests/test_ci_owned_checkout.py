import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('ci_owned_checkout', HERE/'ci-owned-checkout.py')
ci = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ci)


class OwnedCheckoutTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root/'source'
        self.runner = self.root/'runner'
        self.source.mkdir()
        self.runner.mkdir()
        self.home = self.runner/'gpui-ime-home'
        self.home.mkdir(mode=0o700)
        environment = patch.dict(os.environ, HOME=str(self.home), GIT_CONFIG_GLOBAL=str(self.home/'.gitconfig'))
        environment.start()
        self.addCleanup(environment.stop)
        subprocess.run(['git', 'init', '-q', str(self.source)], check=True)
        ci.git(self.source, 'config', 'user.name', 'Fixture')
        ci.git(self.source, 'config', 'user.email', 'fixture@example.invalid')
        (self.source/'source.txt').write_text('exact source')
        ci.git(self.source, 'add', 'source.txt')
        ci.git(self.source, 'commit', '-qm', 'fixture')
        ci.git(self.source, 'checkout', '--detach')

    def test_exact_owned_detached_clone_has_no_remote(self):
        expected = ci.identity(self.source)
        result = ci.clone(self.source, self.runner)
        checkout = Path(result['checkout'])
        self.assertEqual(ci.identity(checkout), expected)
        self.assertEqual(result['uid'], os.geteuid())
        self.assertEqual(checkout.stat().st_mode & 0o777, 0o700)
        self.assertEqual(ci.git(checkout, 'remote'), '')
        self.assertTrue((checkout/'.git').is_dir())
        self.assertEqual((checkout/'source.txt').read_text(), 'exact source')

    def test_dirty_source_and_existing_destination_rejected(self):
        (self.source/'source.txt').write_text('dirty')
        with self.assertRaises(ValueError):
            ci.clone(self.source, self.runner)
        self.assertFalse((self.runner/'gpui-ime-iac').exists())
        ci.git(self.source, 'checkout', '--', 'source.txt')
        (self.runner/'gpui-ime-iac').mkdir()
        with self.assertRaises(ValueError):
            ci.clone(self.source, self.runner)

    def test_symlink_destination_rejected(self):
        (self.runner/'gpui-ime-iac').symlink_to(self.root/'missing')
        with self.assertRaises(ValueError):
            ci.clone(self.source, self.runner)

    def test_file_transport_trust_is_exact_for_strict_git_directory(self):
        original = subprocess.run
        strict_env = dict(os.environ, GIT_TEST_ASSUME_DIFFERENT_OWNER='1')
        denied = original(['git', '-C', str(self.source/'.git'), 'rev-parse', 'HEAD'],
                          capture_output=True, text=True, env=strict_env, timeout=30)
        self.assertNotEqual(denied.returncode, 0)
        self.assertIn('dubious ownership', denied.stderr)
        accepted = original(['git', '-c', 'safe.directory='+str(self.source/'.git'),
                             '-C', str(self.source/'.git'), 'rev-parse', 'HEAD'],
                            capture_output=True, text=True, env=strict_env, timeout=30)
        self.assertEqual(accepted.returncode, 0)
        seen = []
        def strict_clone(command, **kwargs):
            if 'clone' in command:
                seen.append(command)
            return original(command, **kwargs)
        with patch.object(ci.subprocess, 'run', side_effect=strict_clone):
            result = ci.clone(self.source, self.runner)
        self.assertEqual(ci.identity(Path(result['checkout'])), ci.identity(self.source))
        trust = subprocess.check_output(['git', 'config', '--file', str(self.home/'.gitconfig'),
                                         '--get-all', 'safe.directory'], text=True).splitlines()
        self.assertEqual(trust, [str(self.source/'.git')])
        self.assertNotIn('*', trust)
        self.assertEqual(seen[0][:2], ['git', 'clone'])

    def test_indirect_git_directory_rejected_before_clone(self):
        original = self.source/'.git'
        elsewhere = self.root/'git-directory'
        original.rename(elsewhere)
        original.symlink_to(elsewhere, target_is_directory=True)
        with patch.object(ci.subprocess, 'run') as run:
            with self.assertRaisesRegex(ValueError, 'source .git'):
                ci.clone(self.source, self.runner)
            run.assert_not_called()

    def test_worktree_git_pointer_is_rejected(self):
        original = self.source/'.git'
        elsewhere = self.root/'git-directory'
        original.rename(elsewhere)
        original.write_text('gitdir: '+str(elsewhere)+'\n')
        with self.assertRaisesRegex(ValueError, 'source .git'):
            ci.clone(self.source, self.runner)

    def test_foreign_home_or_symlink_config_is_rejected(self):
        with patch.dict(os.environ, HOME=str(self.root/'foreign')):
            with self.assertRaisesRegex(ValueError, 'CI HOME'):
                ci.clone(self.source, self.runner)
        (self.home/'.gitconfig').symlink_to(self.root/'foreign-config')
        with self.assertRaisesRegex(ValueError, 'Git configuration'):
            ci.clone(self.source, self.runner)

    def test_workflow_both_phases_use_owned_checkout(self):
        workflow = (HERE.parents[1]/'.github/workflows/linux-ime-execute.yml').read_text()
        self.assertEqual(workflow.count('python3 "$RUNNER_TEMP/gpui-ime-iac/infra/linux-desktop/ci-ime-execute.py"'), 2)
        self.assertNotIn('chown', workflow)
        clone_step = workflow.split('name: Create exact fresh owned IaC checkout', 1)[1].split('- name:', 1)[0]
        self.assertIn('set -o pipefail', clone_step)
        self.assertIn('Create fresh nonroot CI account', workflow)
        self.assertNotIn('mkdir -p', clone_step)
        self.assertIn('| tee "$RUNNER_TEMP/gpui-ime-execution/owned-checkout.json"', clone_step)
        self.assertLess(workflow.index('Create exact fresh owned IaC checkout'), workflow.index('Verify fixed reviewed artifact metadata'))


if __name__ == '__main__':
    unittest.main()
