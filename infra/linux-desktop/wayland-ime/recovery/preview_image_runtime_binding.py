#!/usr/bin/env python3
"""Inspect one unstarted candidate-image container and the fixed runtime together.

Prepare-only: never starts a container, restores a runtime, creates a deployment
or executes native input. The candidate remains unapproved even after success.
Docker's local daemon is trusted; this is not proof about a later container.
"""
import argparse
from contextlib import ExitStack
import json
from pathlib import Path
import re
import tarfile

import check_candidate_recipe as recipe_check
import host_image_gate as gate
import host_image_inspect as inspect
import hosted_restore as restore

HERE = Path(__file__).resolve().parent
DESKTOP = HERE.parent.parent


def read_regular(path, maximum):
    with gate.open_regular(path, maximum) as stream:
        return stream.read()


def source_bytes(name):
    path = DESKTOP / name
    gate.require(path.resolve(strict=True) == path, 'source path is not canonical: ' + name)
    return read_regular(path, 16 * 1024 * 1024)


def validate_runtime(runtime, inventory, old_receipt, expected_sha):
    """Read every member through the same descriptor, then recheck its hash."""
    runtime.seek(0)
    rows = gate.json_bytes(inventory)
    by_name = restore.parse_inventory(rows)
    root = Path(old_receipt['exact_restore_root'])
    gate.require(root.is_absolute() and root != Path('/'), 'invalid reviewed root')
    with tarfile.open(fileobj=runtime, mode='r:gz') as archive:
        members = restore.validate_members(archive, by_name, root, old_receipt)
    runtime.seek(0)
    gate.require(gate.stream_digest(runtime) == expected_sha, 'runtime changed during member inspection')
    return len(members)


def preview(image, runtime, inventory, prepared, candidate, old_receipt, old_recipe):
    identity = gate.check_inputs(candidate, old_receipt, old_recipe,
                                 image, runtime, inventory, prepared)
    image_id = candidate['image_id']
    gate.require(re.fullmatch(r'sha256:[0-9a-f]{64}', image_id) is not None,
                 'invalid image ID')
    container_id = None
    try:
        image.seek(0)
        inspect.run_docker(['load'], stdin=image)
        image.seek(0)
        gate.require(gate.stream_digest(image) == candidate['image_tar_sha256'],
                     'image changed during load')
        actual = inspect.run_docker(['image', 'inspect', '--format', '{{.Id}}', image_id])
        gate.require(actual == image_id, 'loaded image identity mismatch')
        container_id = inspect.run_docker([
            'create', '--network=none', '--read-only', '--cap-drop=ALL',
            '--security-opt=no-new-privileges', '--user=65534:65534',
            '--entrypoint=/bin/false', image_id,
        ])
        gate.require(re.fullmatch(r'[0-9a-f]{64}', container_id) is not None,
                     'invalid created container ID')
        inspect.check_container(gate.json_bytes(inspect.run_docker(['inspect', container_id])), image_id)
        count = validate_runtime(runtime, inventory, old_receipt, candidate['runtime_sha256'])
        # Re-inspect the same container after the archive pass, before cleanup.
        inspect.check_container(gate.json_bytes(inspect.run_docker(['inspect', container_id])), image_id)
        return {'status': 'unstarted-image-and-runtime-members-match',
                'image_id': image_id, 'image_tar_sha256': candidate['image_tar_sha256'],
                'runtime_sha256': candidate['runtime_sha256'], 'members': count,
                'candidate_source_sha': identity['candidate_source_sha'],
                'native_status': 'NOT_RUN', 'approved_for_execution': False}
    finally:
        if container_id and re.fullmatch(r'[0-9a-f]{64}', container_id):
            inspect.run_docker(['rm', '-v', container_id])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--image', type=Path, required=True)
    parser.add_argument('--runtime', type=Path, required=True)
    parser.add_argument('--inventory', type=Path, required=True)
    parser.add_argument('--prepared', type=Path, required=True)
    args = parser.parse_args()
    fixed = [HERE / 'image.review.candidate.json', HERE / 'image.recipe.candidate.json',
             HERE / 'hosted.review.json', HERE / 'hosted.recipe.lock.json',
             HERE / 'host-image.candidate.json']
    receipt_raw, recipe_raw, old_raw, old_recipe, candidate_raw = [
        read_regular(path, 2 * 1024 * 1024) for path in fixed
    ]
    recipe_check.verify(receipt_raw, recipe_raw, old_raw, old_recipe, candidate_raw, source_bytes)
    candidate, old = gate.json_bytes(candidate_raw), gate.json_bytes(old_raw)
    inventory = read_regular(args.inventory, 256 * 1024 * 1024)
    prepared = read_regular(args.prepared, 2 * 1024 * 1024)
    with ExitStack() as stack:
        image = stack.enter_context(gate.open_regular(args.image, gate.MAX_ARCHIVE))
        runtime = stack.enter_context(gate.open_regular(args.runtime, gate.MAX_ARCHIVE))
        result = preview(image, runtime, inventory, prepared, candidate, old, old_recipe)
    print(json.dumps(result, sort_keys=True))


if __name__ == '__main__':
    main()
