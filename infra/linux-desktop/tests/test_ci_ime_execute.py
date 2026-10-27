import json
import tempfile
from unittest.mock import patch
import importlib.util
from pathlib import Path
import unittest

HERE = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('ci_ime_execute', HERE/'ci-ime-execute.py')
ci = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ci)


class ExecutionGateTests(unittest.TestCase):
    def fixtures(self):
        approved = {'artifact_run_id': 12, 'artifact_head_sha': 'a'*40, 'review_artifact_id': 13,
                    'artifact_id': 14, 'review_artifact_digest': 'sha256:'+'b'*64,
                    'runtime_artifact_digest': 'sha256:'+'c'*64}
        run = {'id': 12, 'head_sha': 'a'*40, 'repository': {'full_name': ci.REPOSITORY, 'private': False},
               'status': 'completed', 'conclusion': 'success'}
        def artifact(id_, prefix, digest):
            return {'id': id_, 'expired': False, 'digest': digest, 'name': prefix+'a'*40,
                    'workflow_run': {'id': 12, 'head_sha': 'a'*40}}
        return approved, run, artifact(13, 'linux-ime-review-', approved['review_artifact_digest']), artifact(14, 'linux-ime-runtime-', approved['runtime_artifact_digest'])

    def test_exact_public_successful_artifacts_are_accepted(self):
        ci.verify_metadata(*self.fixtures())

    def test_run_head_repository_or_success_drift_rejected(self):
        for key, value in [('id', 99), ('head_sha', 'f'*40), ('conclusion', 'failure'),
                           ('repository', {'full_name': 'other/repo', 'private': False}),
                           ('repository', {'full_name': ci.REPOSITORY, 'private': True})]:
            values = self.fixtures()
            values[1][key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                ci.verify_metadata(*values)

    def test_artifact_digest_id_expiry_name_or_run_drift_rejected(self):
        for index in (2, 3):
            for key, value in [('id', 99), ('digest', 'sha256:'+'d'*64), ('expired', True),
                               ('name', 'other-artifact'), ('workflow_run', {'id': 99, 'head_sha': 'a'*40})]:
                values = self.fixtures()
                values[index][key] = value
                with self.subTest(index=index, key=key), self.assertRaises(ValueError):
                    ci.verify_metadata(*values)

    def test_missing_receipt_records_not_run_without_api_or_native(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary)/'evidence'
            with patch.object(ci.gate, 'receipt', return_value=None), patch.object(ci, 'api', side_effect=AssertionError('no API')), patch.object(ci.subprocess, 'run', side_effect=AssertionError('no launch')), patch('sys.argv', ['ci-ime-execute.py', 'metadata', '--evidence', str(output)]):
                self.assertEqual(ci.main(), 1)
            self.assertEqual(json.loads((output/'execution-status.json').read_text())['native_status'], 'NOT_RUN')

    def test_native_invocation_matches_diagnostic_and_locked_python_contract(self):
        root, binding = Path('/owned/closure'), Path('/owned/evidence/binding')
        with patch.dict('os.environ', {'GH_TOKEN': 'must-not-inherit', 'PYTHONPATH': '/foreign/modules'}):
            command, env, output = ci.native_invocation(root, binding, binding/'overlay.json')
        self.assertEqual(command[command.index('--diagnostic-log')+1], binding/(output.name+'.launcher.log'))
        self.assertEqual(env['PYTHONPATH'], str(root/'profile/prefix/usr/lib/python3/dist-packages'))
        self.assertEqual(env['GI_TYPELIB_PATH'], str(root/'profile/prefix/usr/lib/x86_64-linux-gnu/girepository-1.0'))
        self.assertTrue(env['LD_LIBRARY_PATH'].startswith(str(root/'profile/prefix/usr/lib/x86_64-linux-gnu')))
        self.assertNotIn('GH_TOKEN', env)
        self.assertIn('--held-shortcuts', command)

    def test_workflow_uses_scoped_permissions_and_single_paths(self):
        workflow = (HERE.parents[1]/'.github/workflows/linux-ime-execute.yml').read_text()
        self.assertIn('contents: read', workflow)
        self.assertIn('actions: read', workflow)
        self.assertNotIn('write', workflow)
        self.assertEqual(workflow.count('path: ${{ runner.temp }}'), 3)
        self.assertNotIn('path: |', workflow)
        self.assertIn('artifact-ids: ${{ steps.receipt.outputs.artifact_id }}', workflow)
        self.assertIn('d3f86a106a0bac45b974a628896c90dbdf5c8093', workflow)


class ExecuteOrchestrationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.review, self.runtime, self.evidence = [self.base/name for name in ('review', 'runtime', 'evidence')]
        for path in (self.review, self.runtime, self.evidence):
            path.mkdir()
        self.root = self.base/'closure'
        prepared = {'preparation_status': 'PREPARED', 'native_status': 'NOT_RUN',
                    'source': {'sha': 'a'*40, 'tree': 'b'*40},
                    'exact_restore_root': str(self.root), 'container_image': ci.gate.IMAGE,
                    'runtime_archive': {'sha256': 'c'*64}, 'inventory_sha256': 'd'*64}
        ci.save(self.review/'prepare-result.json', prepared)
        self.approved = {'prepare_result_sha256': ci.gate.digest(self.review/'prepare-result.json'),
                         'candidate_source_sha': 'a'*40, 'candidate_source_tree': 'b'*40,
                         'exact_restore_root': str(self.root), 'runtime_sha256': 'c'*64,
                         'inventory_sha256': 'd'*64,
                         'expected': {name: 'e'*64 for name in ci.gate.FIELDS}}
        self.calls = []

    def invoke(self, result, code):
        def fake_run(command, **kwargs):
            self.calls.append((command, kwargs))
            if '--run-native' in command:
                output = Path(command[command.index('--output')+1])
                output.mkdir(parents=True)
                if result is not None:
                    ci.save(output/'result.json', result)
                return ci.subprocess.CompletedProcess(command, code)
            return ci.subprocess.CompletedProcess(command, 0)
        with patch.object(ci.gate, 'restore', return_value=self.root), patch.object(ci.subprocess, 'run', side_effect=fake_run), patch.dict('os.environ', GH_TOKEN='secret-fixture'):
            return ci.execute(self.approved, self.review, self.runtime, self.evidence)

    def test_full_pass_requires_flags_and_scrubs_every_child_token(self):
        result = {'status': 'passed', 'native_executed': True,
                  'full_suite_verified': True, 'gpui_ime_verified': True}
        self.assertEqual(self.invoke(result, 0), 0)
        summary = json.loads((self.evidence/'execution-status.json').read_text())
        self.assertEqual(summary['native_status'], 'passed')
        self.assertEqual(len(self.calls), 3)
        for command, kwargs in self.calls:
            self.assertNotIn('GH_TOKEN', kwargs['env'])
            self.assertEqual(kwargs['timeout'], 180)
        self.assertIn('--recipe-variant', self.calls[0][0])
        self.assertIn('--held-shortcuts', self.calls[2][0])

    def test_partial_remains_non_green(self):
        self.assertEqual(self.invoke({'status': 'qualified-partial', 'native_executed': True,
                                     'full_suite_verified': False, 'gpui_ime_verified': False}, 2), 2)
        summary = json.loads((self.evidence/'execution-status.json').read_text())
        self.assertEqual(summary['native_status'], 'qualified-partial')
        self.assertEqual(summary['harness_returncode'], 2)

    def test_native_error_rejected_and_not_recorded_passed(self):
        with self.assertRaisesRegex(ValueError, 'harness failed'):
            self.invoke({'status': 'error', 'native_executed': True}, 1)
        self.assertEqual(json.loads((self.evidence/'execution-status.json').read_text())['native_status'], 'INCOMPLETE')

    def test_missing_native_result_rejected(self):
        with self.assertRaises(FileNotFoundError):
            self.invoke(None, 0)
        self.assertEqual(json.loads((self.evidence/'execution-status.json').read_text())['native_status'], 'INCOMPLETE')

    def test_missing_full_suite_flags_rejected(self):
        with self.assertRaisesRegex(ValueError, 'qualification flags'):
            self.invoke({'status': 'passed', 'native_executed': True}, 0)

    def test_missing_native_execution_flag_rejected(self):
        with self.assertRaisesRegex(ValueError, 'execution proof'):
            self.invoke({'status': 'passed', 'full_suite_verified': True, 'gpui_ime_verified': True}, 0)


if __name__ == '__main__':
    unittest.main()
