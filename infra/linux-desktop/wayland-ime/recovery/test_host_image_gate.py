import hashlib
import io
import json
from pathlib import Path
import tarfile
import tempfile
import unittest

import host_image_gate as gate


def sha(data):
    return hashlib.sha256(data).hexdigest()


def image_bytes(extra=None):
    config = b'{"architecture":"amd64"}'
    manifest = json.dumps([{'Config': 'config.json', 'Layers': []}]).encode()
    result = io.BytesIO()
    with tarfile.open(fileobj=result, mode='w') as tar:
        for name, data in [('manifest.json', manifest), ('config.json', config)] + (extra or []):
            item = tarfile.TarInfo(name)
            item.size = len(data)
            tar.addfile(item, io.BytesIO(data))
    return result.getvalue(), 'sha256:' + sha(config)


class ImageGateTests(unittest.TestCase):
    def setUp(self):
        self.image, image_id = image_bytes()
        self.runtime, self.inventory, self.recipe = b'runtime', b'inventory', b'recipe'
        self.candidate = {
            'schema_version': 1, 'approved_for_execution': False,
            'image_tar_sha256': sha(self.image), 'image_id': image_id,
            'runtime_artifact_run_id': 1, 'runtime_artifact_id': 2, 'runtime_artifact_digest': 'zip1',
            'review_artifact_id': 3, 'review_artifact_digest': 'zip2',
            'runtime_sha256': sha(self.runtime), 'inventory_sha256': sha(self.inventory),
            'candidate_source_sha': 'a'*40, 'candidate_source_tree': 'b'*40,
            'historical_hosted_recipe_sha256': sha(self.recipe),
        }
        prep = {'preparation_status': 'PREPARED', 'native_status': 'NOT_RUN',
                'source': {'sha': 'a'*40, 'tree': 'b'*40},
                'runtime_archive': {'sha256': sha(self.runtime)}, 'inventory_sha256': sha(self.inventory)}
        self.prepared = json.dumps(prep).encode()
        self.candidate['prepare_result_sha256'] = sha(self.prepared)
        self.old = {'approved_for_execution': True, 'artifact_run_id': 1, 'artifact_id': 2,
                    'runtime_artifact_digest': 'zip1', 'review_artifact_id': 3, 'review_artifact_digest': 'zip2',
                    'runtime_sha256': sha(self.runtime), 'inventory_sha256': sha(self.inventory),
                    'prepare_result_sha256': sha(self.prepared), 'candidate_source_sha': 'a'*40,
                    'candidate_source_tree': 'b'*40, 'recipe_sha256': sha(self.recipe)}

    def check(self):
        return gate.check_inputs(self.candidate, self.old, self.recipe, io.BytesIO(self.image),
                                 io.BytesIO(self.runtime), self.inventory, self.prepared)

    def test_valid_candidate_is_never_execution_approval(self):
        result = self.check()
        self.assertEqual(result['status'], 'identity-matched-unapproved')
        self.assertIs(result['approved_for_execution'], False)
        self.assertEqual(result['native_status'], 'NOT_RUN')

    def test_committed_candidate_and_historical_receipt_are_exactly_pinned(self):
        candidate = gate.json_bytes(gate.read_checked(gate.HERE/'host-image.candidate.json', gate.CANDIDATE_SHA256))
        old = gate.json_bytes(gate.read_checked(gate.HERE/'hosted.review.json', gate.HISTORICAL_RECEIPT_SHA256))
        self.assertIs(candidate['approved_for_execution'], False)
        self.assertEqual(candidate['historical_hosted_recipe_sha256'], old['recipe_sha256'])
        gate.read_checked(gate.HERE/'hosted.recipe.lock.json', candidate['historical_hosted_recipe_sha256'])

    def test_approval_or_changed_old_binding_is_rejected(self):
        self.candidate['approved_for_execution'] = True
        with self.assertRaisesRegex(ValueError, 'unapproved'): self.check()
        self.candidate['approved_for_execution'] = False
        self.old['artifact_id'] = 99
        with self.assertRaisesRegex(ValueError, 'historical binding'): self.check()

    def test_each_archive_and_metadata_digest_is_checked(self):
        for name in ('runtime', 'inventory', 'prepared', 'recipe', 'image'):
            with self.subTest(name=name):
                previous = getattr(self, name)
                setattr(self, name, previous + b'x')
                with self.assertRaises(ValueError): self.check()
                setattr(self, name, previous)

    def test_unsafe_image_member_and_config_mismatch_are_rejected(self):
        raw, image_id = image_bytes([('../escape', b'x')])
        with self.assertRaisesRegex(ValueError, 'unsafe image member'):
            gate.check_image(io.BytesIO(raw), sha(raw), image_id)
        with self.assertRaisesRegex(ValueError, 'config identity mismatch'):
            gate.check_image(io.BytesIO(self.image), sha(self.image), 'sha256:'+'0'*64)

    def test_duplicate_json_and_symlink_input_are_rejected(self):
        with self.assertRaisesRegex(ValueError, 'duplicate JSON'):
            gate.json_bytes(b'{"id":1,"id":2}')
        with tempfile.TemporaryDirectory() as temp:
            target, link = Path(temp)/'target', Path(temp)/'link'
            target.write_bytes(b'input')
            link.symlink_to(target)
            with self.assertRaises(OSError): gate.open_regular(link, 100)


if __name__ == '__main__':
    unittest.main()
