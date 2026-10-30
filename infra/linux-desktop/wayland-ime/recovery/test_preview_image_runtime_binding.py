import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import textwrap
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
spec = importlib.util.spec_from_file_location('preview_image_runtime_binding', HERE / 'preview_image_runtime_binding.py')
preview = importlib.util.module_from_spec(spec)
spec.loader.exec_module(preview)


def runtime_fixture(content=b'kept'):
    output = io.BytesIO()
    with tarfile.open(fileobj=output, mode='w:gz') as archive:
        item = tarfile.TarInfo('closure/value')
        item.size, item.mode = len(content), 0o644
        archive.addfile(item, io.BytesIO(content))
    data = output.getvalue()
    inventory = [{'path': 'value', 'kind': 'file', 'mode': 0o644,
                  'size': len(content), 'sha256': hashlib.sha256(content).hexdigest()}]
    return data, json.dumps(inventory).encode()


class PreviewTests(unittest.TestCase):
    def setUp(self):
        self.runtime, self.inventory = runtime_fixture()
        self.image = b'fixed-image-tar'
        self.image_id = 'sha256:' + 'b' * 64
        self.container = 'c' * 64
        self.candidate = {'image_id': self.image_id,
                          'image_tar_sha256': hashlib.sha256(self.image).hexdigest(),
                          'runtime_sha256': hashlib.sha256(self.runtime).hexdigest()}
        self.old = {'exact_restore_root': '/tmp/reviewed/closure', 'external_symlinks': {}}
        self.calls = []

    def docker(self, arguments, *, stdin=None):
        self.calls.append(list(arguments))
        if arguments == ['load']:
            self.assertIsNotNone(stdin)
            self.assertEqual(stdin.read(), self.image)
            return 'loaded'
        if arguments[:2] == ['image', 'inspect']:
            return self.image_id
        if arguments[0] == 'create':
            return self.container
        if arguments[0] == 'inspect':
            return json.dumps([{'Image': self.image_id,
                                'State': {'Status': 'created', 'Running': False, 'Pid': 0},
                                'Config': {'User': '65534:65534', 'Entrypoint': ['/bin/false']},
                                'HostConfig': {'NetworkMode': 'none', 'ReadonlyRootfs': True,
                                               'Privileged': False, 'CapDrop': ['ALL'],
                                               'SecurityOpt': ['no-new-privileges']},
                                'Mounts': []}])
        if arguments[0] == 'rm':
            return self.container
        raise AssertionError('unexpected Docker operation: ' + repr(arguments))

    def run_preview(self, runtime=None):
        with patch.object(preview.gate, 'check_inputs', return_value={'candidate_source_sha': 'a' * 40}), \
             patch.object(preview.inspect, 'run_docker', side_effect=self.docker):
            return preview.preview(io.BytesIO(self.image), io.BytesIO(self.runtime if runtime is None else runtime),
                                   self.inventory, b'prepared', self.candidate, self.old, b'old-recipe')

    def test_combined_preview_never_starts_or_approves(self):
        result = self.run_preview()
        self.assertEqual(result['members'], 1)
        self.assertFalse(result['approved_for_execution'])
        self.assertEqual(result['native_status'], 'NOT_RUN')
        self.assertEqual([call[0] for call in self.calls], ['load', 'image', 'create', 'inspect', 'inspect', 'rm'])
        self.assertFalse(any(call[0] in ('start', 'run', 'exec') for call in self.calls))

    def test_member_hash_failure_removes_unstarted_container(self):
        bad, _ = runtime_fixture(b'evil')
        self.candidate['runtime_sha256'] = hashlib.sha256(bad).hexdigest()
        with self.assertRaisesRegex(ValueError, 'file digest mismatch'):
            self.run_preview(runtime=bad)
        self.assertEqual(self.calls[-1], ['rm', '-v', self.container])
        self.assertFalse(any(call[0] in ('start', 'run', 'exec') for call in self.calls))

    def test_runtime_rehash_detects_changed_descriptor_bytes(self):
        with self.assertRaisesRegex(ValueError, 'runtime changed'):
            preview.validate_runtime(io.BytesIO(self.runtime), self.inventory, self.old, '0' * 64)

    def test_unapproved_input_failure_happens_before_docker(self):
        with patch.object(preview.gate, 'check_inputs', side_effect=ValueError('not unapproved')), \
             patch.object(preview.inspect, 'run_docker', side_effect=self.docker):
            with self.assertRaisesRegex(ValueError, 'not unapproved'):
                preview.preview(io.BytesIO(self.image), io.BytesIO(self.runtime), self.inventory,
                                b'prepared', self.candidate, self.old, b'old-recipe')
        self.assertEqual(self.calls, [])

    def test_changed_image_after_load_never_creates_container(self):
        self.candidate['image_tar_sha256'] = '0' * 64
        with self.assertRaisesRegex(ValueError, 'image changed'):
            self.run_preview()
        self.assertEqual(self.calls, [['load']])

    def test_inspection_failure_cleans_up_created_container(self):
        original = self.docker

        def unsafe_inspect(arguments, *, stdin=None):
            if arguments[0] == 'inspect':
                data = json.loads(original(arguments, stdin=stdin))
                data[0]['HostConfig']['NetworkMode'] = 'host'
                return json.dumps(data)
            return original(arguments, stdin=stdin)

        with patch.object(preview.gate, 'check_inputs', return_value={'candidate_source_sha': 'a' * 40}), \
             patch.object(preview.inspect, 'run_docker', side_effect=unsafe_inspect):
            with self.assertRaisesRegex(ValueError, 'unsafe container isolation'):
                preview.preview(io.BytesIO(self.image), io.BytesIO(self.runtime), self.inventory,
                                b'prepared', self.candidate, self.old, b'old-recipe')
        self.assertEqual(self.calls[-1], ['rm', '-v', self.container])

    def test_workflow_invocation_reaches_input_open_with_supported_flags(self):
        # Execute the actual workflow run block with absent inputs. It must get
        # past argparse and fail closed at the first missing input instead of
        # silently accepting tee's exit code or using an obsolete CLI flag.
        root = HERE.parents[3]
        workflow = (root / '.github/workflows/linux-ime-image-runtime-joint-preview.yml').read_text()
        step = workflow.split('      - name: Inspect the unstarted image container and all runtime members\n', 1)[1]
        script = step.split('        run: |\n', 1)[1].split('      - name:', 1)[0]
        with tempfile.TemporaryDirectory() as temp:
            env = dict(os.environ, RUNNER_TEMP=temp)
            result = subprocess.run(['bash', '-euo', 'pipefail', '-c', textwrap.dedent(script)],
                                    cwd=root, env=env, capture_output=True, text=True, check=False)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('closure-inventory.json', result.stderr)
            self.assertNotIn('unrecognized arguments', result.stderr)


if __name__ == '__main__':
    unittest.main()
