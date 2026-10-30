#!/usr/bin/env python3
"""Check a *non-executable* image-bound recovery recipe for independent review.

No archive extraction, image load, restore, bind, or native launch is performed.
A matching candidate remains unapproved; changing this file or the receipt
requires a separate final-HEAD review and an actual execution binding.
"""
import hashlib
import json
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
DESKTOP = HERE.parent.parent
sys.path.insert(0, str(HERE))
import host_image_gate as gate

CHANGED = {
    'tests/test_hosted_restore.py',
    'wayland-ime/recovery/hosted_restore.py',
}
CANDIDATE_RECEIPT_SHA256 = '87b8332d2c3502cb8d7aca4cf9477c2365373576712eb38dff42328c6ca2a7cb'
SCOPE = ('Unapproved immutable-host candidate; same runtime closure, new IaC '
         'source pins; no native execution or qualification.')


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def verify(receipt_raw, recipe_raw, old_receipt_raw, old_recipe_raw, image_raw,
           read_source):
    receipt = gate.json_bytes(receipt_raw)
    recipe = gate.json_bytes(recipe_raw)
    old_receipt = gate.json_bytes(old_receipt_raw)
    old_recipe = gate.json_bytes(old_recipe_raw)
    image = gate.json_bytes(image_raw)
    gate.require(sha(receipt_raw) == CANDIDATE_RECEIPT_SHA256,
                 'candidate receipt differs from fixed review bytes')
    gate.require(receipt.get('schema_version') == 1 and
                 receipt.get('approved_for_execution') is False and
                 receipt.get('native_status') == 'NOT_RUN', 'candidate must remain unapproved')
    for key, raw in (('candidate_recipe_sha256', recipe_raw),
                     ('historical_receipt_sha256', old_receipt_raw),
                     ('historical_recipe_sha256', old_recipe_raw),
                     ('image_candidate_sha256', image_raw)):
        gate.require(receipt.get(key) == sha(raw), 'candidate digest mismatch: ' + key)
    gate.require(old_receipt.get('approved_for_execution') is True and
                 image.get('approved_for_execution') is False, 'historical/candidate approval mismatch')
    gate.require(old_receipt.get('recipe_sha256') == sha(old_recipe_raw), 'historical recipe mismatch')
    for key in ('image_id', 'image_tar_sha256', 'runtime_sha256',
                'candidate_source_sha', 'candidate_source_tree'):
        gate.require(receipt.get(key) == image.get(key), 'image/runtime binding mismatch: ' + key)
    gate.require(recipe.get('image_id') == image['image_id'] and
                 recipe.get('image_tar_sha256') == image['image_tar_sha256'], 'recipe image mismatch')
    gate.require(recipe.get('native_qualified') is False, 'candidate must remain unqualified')
    expected = dict(old_recipe)
    expected['scope'] = SCOPE
    expected['image_id'] = image['image_id']
    expected['image_tar_sha256'] = image['image_tar_sha256']
    old_sources = old_recipe.get('source_files')
    new_sources = recipe.get('source_files')
    gate.require(isinstance(old_sources, dict) and isinstance(new_sources, dict) and
                 set(old_sources) == set(new_sources) and CHANGED <= set(old_sources),
                 'source closure changed')
    expected_sources = dict(old_sources)
    for name in CHANGED:
        expected_sources[name] = new_sources[name]
        gate.require(new_sources[name] != old_sources[name], 'expected source change absent: ' + name)
    expected['source_files'] = expected_sources
    gate.require(expected == recipe, 'unexpected recipe changes')
    for name, expected_hash in new_sources.items():
        path = Path(name)
        gate.require(not path.is_absolute() and '..' not in path.parts and str(path) == name,
                     'unsafe source path')
        gate.require(sha(read_source(name)) == expected_hash, 'source pin mismatch: ' + name)
    return {'status': 'review-candidate-pins-match', 'native_status': 'NOT_RUN',
            'approved_for_execution': False, 'sources_checked': len(new_sources),
            'candidate_recipe_sha256': sha(recipe_raw), 'image_id': image['image_id'],
            'candidate_source_sha': image['candidate_source_sha']}


def main():
    files = [HERE / 'image.review.candidate.json', HERE / 'image.recipe.candidate.json',
             HERE / 'hosted.review.json', HERE / 'hosted.recipe.lock.json',
             HERE / 'host-image.candidate.json']
    def read_regular(path, maximum):
        with gate.open_regular(path, maximum) as stream:
            return stream.read()

    def read_source(name):
        path = DESKTOP / name
        # Reject source symlinks, including intermediate components.
        gate.require(path.resolve(strict=True) == path, 'source path is not canonical: ' + name)
        return read_regular(path, 16 * 1024 * 1024)

    raw = [read_regular(p, 2 * 1024 * 1024) for p in files]
    result = verify(*raw, read_source)
    print(json.dumps(result, sort_keys=True))


if __name__ == '__main__':
    main()
