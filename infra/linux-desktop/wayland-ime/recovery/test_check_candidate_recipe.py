import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
spec = importlib.util.spec_from_file_location('check_candidate_recipe', HERE / 'check_candidate_recipe.py')
check = importlib.util.module_from_spec(spec)
spec.loader.exec_module(check)


def data(value):
    return (json.dumps(value, sort_keys=True, indent=2) + '\n').encode()


class CandidateRecipeTests(unittest.TestCase):
    def setUp(self):
        self.receipt = json.loads((HERE / 'image.review.candidate.json').read_bytes())
        self.recipe = json.loads((HERE / 'image.recipe.candidate.json').read_bytes())
        self.old_receipt = json.loads((HERE / 'hosted.review.json').read_bytes())
        self.old_recipe = json.loads((HERE / 'hosted.recipe.lock.json').read_bytes())
        self.image = json.loads((HERE / 'host-image.candidate.json').read_bytes())
        self.sources = {name: (check.DESKTOP / name).read_bytes() for name in self.recipe['source_files']}

    def verify(self, *, reroll_receipt=False):
        recipe = data(self.recipe)
        old_receipt = data(self.old_receipt)
        old_recipe = data(self.old_recipe)
        image = data(self.image) if reroll_receipt else (HERE / 'host-image.candidate.json').read_bytes()
        receipt = copy.deepcopy(self.receipt)
        if reroll_receipt:
            receipt.update(candidate_recipe_sha256=check.sha(recipe),
                           historical_receipt_sha256=check.sha(old_receipt),
                           historical_recipe_sha256=check.sha(old_recipe),
                           image_candidate_sha256=check.sha(image))
        raw = data(receipt)
        with patch.object(check, 'CANDIDATE_RECEIPT_SHA256', check.sha(raw)):
            return check.verify(raw, recipe, old_receipt, old_recipe, image, self.sources.__getitem__)

    def test_real_candidate_binds_all_pins_without_authorizing(self):
        result = self.verify()
        self.assertEqual(result['sources_checked'], 44)
        self.assertFalse(result['approved_for_execution'])
        self.assertEqual(result['native_status'], 'NOT_RUN')

    def test_receipt_approval_does_not_become_execution(self):
        self.receipt['approved_for_execution'] = True
        with self.assertRaisesRegex(ValueError, 'unapproved'):
            self.verify()

    def test_source_drift_fails_even_with_matching_receipt(self):
        self.sources['wayland-ime/gpui_probe.py'] += b'\n'
        with self.assertRaisesRegex(ValueError, 'source pin mismatch'):
            self.verify()

    def test_unreviewed_pin_and_image_changes_rejected(self):
        self.recipe['source_files']['wayland-ime/gpui_probe.py'] = '0' * 64
        with self.assertRaisesRegex(ValueError, 'unexpected recipe changes'):
            self.verify(reroll_receipt=True)

    def test_candidate_image_cannot_be_replaced(self):
        self.image['image_id'] = 'sha256:' + '0' * 64
        with self.assertRaisesRegex(ValueError, 'image/runtime binding mismatch'):
            self.verify(reroll_receipt=True)

    def test_historical_receipt_is_not_inherited_as_new_approval(self):
        self.old_receipt['approved_for_execution'] = False
        with self.assertRaisesRegex(ValueError, 'approval mismatch'):
            self.verify(reroll_receipt=True)

    def test_unapproved_source_set_cannot_add_or_drop_paths(self):
        del self.recipe['source_files']['wayland-ime/gpui_probe.py']
        with self.assertRaisesRegex(ValueError, 'source closure changed'):
            self.verify(reroll_receipt=True)

    def test_duplicate_json_keys_are_rejected(self):
        with self.assertRaisesRegex(ValueError, 'duplicate JSON key'):
            check.verify(b'{"schema_version":1,"schema_version":1}', b'{}', b'{}', b'{}', b'{}', lambda _: b'')

    def test_fixed_receipt_rejects_even_valid_json_edits(self):
        raw = data(dict(self.receipt, purpose='silently changed'))
        with self.assertRaisesRegex(ValueError, 'fixed review bytes'):
            check.verify(raw, data(self.recipe), data(self.old_receipt),
                         data(self.old_recipe), (HERE / 'host-image.candidate.json').read_bytes(),
                         self.sources.__getitem__)


if __name__ == '__main__':
    unittest.main()
