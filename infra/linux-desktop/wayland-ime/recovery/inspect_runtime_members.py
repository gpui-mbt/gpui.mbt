#!/usr/bin/env python3
"""Read-only per-member audit; never restore or authorize the new image."""
import argparse
import json
from pathlib import Path
import tarfile

import host_image_gate as identity
import hosted_restore as restore

HERE = Path(__file__).resolve().parent


def inspect(image_path, archive_path, inventory_path, prepared_path):
    candidate = identity.json_bytes(identity.read_checked(HERE / 'host-image.candidate.json',
                                                          identity.CANDIDATE_SHA256))
    historical = identity.json_bytes(identity.read_checked(HERE / 'hosted.review.json',
                                                           identity.HISTORICAL_RECEIPT_SHA256))
    recipe = identity.read_checked(HERE / 'hosted.recipe.lock.json', candidate['historical_hosted_recipe_sha256'])
    inventory = identity.read_checked(inventory_path, candidate['inventory_sha256'], 256 * 1024 * 1024)
    prepared = identity.read_checked(prepared_path, candidate['prepare_result_sha256'])
    with identity.open_regular(image_path, identity.MAX_ARCHIVE) as image, \
         identity.open_regular(archive_path, identity.MAX_ARCHIVE) as archive:
        # This validates the unapproved new candidate against separately
        # reviewed historical archive identities. It grants no restore right.
        identity.check_inputs(candidate, historical, recipe, image, archive, inventory, prepared)
        by_name = restore.parse_inventory(identity.json_bytes(inventory))
        root = Path(historical['exact_restore_root'])
        restore.require(root.is_absolute() and root != Path('/'), 'invalid reviewed root')
        archive.seek(0)
        with tarfile.open(fileobj=archive, mode='r:gz') as tar:
            members = restore.validate_members(tar, by_name, root, historical)
    return {'status': 'members-validated-unapproved', 'members': len(members),
            'runtime_sha256': candidate['runtime_sha256'], 'candidate_source_sha': candidate['candidate_source_sha'],
            'image_id': candidate['image_id'], 'native_status': 'NOT_RUN', 'approved_for_execution': False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('image', 'archive', 'inventory', 'prepared'):
        parser.add_argument('--' + name, required=True, type=Path)
    args = parser.parse_args()
    print(json.dumps(inspect(args.image, args.archive, args.inventory, args.prepared), sort_keys=True))


if __name__ == '__main__':
    main()
