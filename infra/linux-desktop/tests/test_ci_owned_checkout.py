import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

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
