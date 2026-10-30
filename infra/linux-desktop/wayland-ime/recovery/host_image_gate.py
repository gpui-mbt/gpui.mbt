#!/usr/bin/env python3
"""Prepare-only identity checks for an unapproved host image and old runtime.

This does not load an image, restore an archive, create a container or execute
native input. It cannot approve execution, including when every check passes.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import stat
import tarfile

HERE = Path(__file__).resolve().parent
CANDIDATE_SHA256 = '94a6cbf048fa05706388b2f07d3c778ffdbf03d06876eacb32aedf494de8b9d3'
HISTORICAL_RECEIPT_SHA256 = '23455b31939b0ef6323bce4a0a22df691e38ab667974b87c397c508951b30045'
MAX_ARCHIVE = 4 * 1024**3


def require(condition, message):
    if not condition:
        raise ValueError(message)


def no_duplicates(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, 'duplicate JSON key')
        result[key] = value
    return result


def json_bytes(raw):
    return json.loads(raw, object_pairs_hook=no_duplicates)


def open_regular(path, maximum):
    # No symlink final component, special files, or unbounded input.
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    try:
        st = os.fstat(fd)
        require(stat.S_ISREG(st.st_mode) and st.st_size <= maximum, 'unsafe input file')
        return os.fdopen(fd, 'rb')
    except BaseException:
        os.close(fd)
        raise


def stream_digest(stream):
    value = hashlib.sha256()
    for block in iter(lambda: stream.read(1024 * 1024), b''):
        value.update(block)
    return value.hexdigest()


def read_checked(path, expected, maximum=1024 * 1024):
    with open_regular(path, maximum) as stream:
        raw = stream.read()
    require(hashlib.sha256(raw).hexdigest() == expected, 'input digest mismatch: ' + Path(path).name)
    return raw


def check_image(stream, expected_hash, expected_id):
    require(stream_digest(stream) == expected_hash, 'image tar digest mismatch')
    stream.seek(0)
    with tarfile.open(fileobj=stream, mode='r:') as archive:
        members = archive.getmembers()
        require(len(members) <= 10000, 'too many image members')
        names = [item.name for item in members]
        require(len(names) == len(set(names)), 'duplicate image member')
        for item in members:
            path = PurePosixPath(item.name)
            require(not path.is_absolute() and '..' not in path.parts and (item.isdir() or item.isfile()), 'unsafe image member')
        manifest = archive.getmember('manifest.json')
        require(manifest.isfile() and manifest.size <= 65536, 'invalid image manifest')
        data = json_bytes(archive.extractfile(manifest).read())
        require(isinstance(data, list) and len(data) == 1 and isinstance(data[0], dict), 'unexpected image count')
        config_name = data[0].get('Config')
        require(isinstance(config_name, str) and config_name in names, 'missing image config')
        config = archive.getmember(config_name)
        require(config.isfile() and config.size <= 1048576, 'invalid image config')
        config_hash = hashlib.sha256(archive.extractfile(config).read()).hexdigest()
        require(expected_id == 'sha256:' + config_hash, 'image config identity mismatch')


def check_inputs(candidate, old, recipe_raw, image, runtime, inventory, prepared):
    require(candidate.get('schema_version') == 1 and candidate.get('approved_for_execution') is False,
            'candidate must remain explicitly unapproved')
    require(old.get('approved_for_execution') is True, 'historical runtime review missing')
    for new_key, old_key in (
        ('runtime_artifact_run_id', 'artifact_run_id'), ('runtime_artifact_id', 'artifact_id'),
        ('runtime_artifact_digest', 'runtime_artifact_digest'), ('review_artifact_id', 'review_artifact_id'),
        ('review_artifact_digest', 'review_artifact_digest'), ('runtime_sha256', 'runtime_sha256'),
        ('inventory_sha256', 'inventory_sha256'), ('prepare_result_sha256', 'prepare_result_sha256'),
        ('candidate_source_sha', 'candidate_source_sha'), ('candidate_source_tree', 'candidate_source_tree'),
        ('historical_hosted_recipe_sha256', 'recipe_sha256')):
        require(new_key in candidate and old_key in old and candidate[new_key] == old[old_key],
                'historical binding mismatch: ' + new_key)
    require(hashlib.sha256(recipe_raw).hexdigest() == candidate['historical_hosted_recipe_sha256'], 'historical recipe mismatch')
    require(hashlib.sha256(inventory).hexdigest() == candidate['inventory_sha256'], 'inventory digest mismatch')
    require(hashlib.sha256(prepared).hexdigest() == candidate['prepare_result_sha256'], 'prepare result digest mismatch')
    preparation = json_bytes(prepared)
    require(preparation.get('preparation_status') == 'PREPARED' and preparation.get('native_status') == 'NOT_RUN', 'invalid preparation state')
    require(preparation.get('source') == {'sha': candidate['candidate_source_sha'], 'tree': candidate['candidate_source_tree']}, 'runtime source mismatch')
    require(preparation.get('runtime_archive', {}).get('sha256') == candidate['runtime_sha256'] and preparation.get('inventory_sha256') == candidate['inventory_sha256'], 'preparation closure mismatch')
    require(stream_digest(runtime) == candidate['runtime_sha256'], 'runtime archive digest mismatch')
    check_image(image, candidate['image_tar_sha256'], candidate['image_id'])
    return {'status': 'identity-matched-unapproved', 'native_status': 'NOT_RUN', 'approved_for_execution': False,
            'image_id': candidate['image_id'], 'image_tar_sha256': candidate['image_tar_sha256'],
            'runtime_sha256': candidate['runtime_sha256'], 'candidate_source_sha': candidate['candidate_source_sha']}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--image', type=Path, required=True)
    parser.add_argument('--runtime', type=Path, required=True)
    parser.add_argument('--inventory', type=Path, required=True)
    parser.add_argument('--prepared', type=Path, required=True)
    args = parser.parse_args()
    candidate = json_bytes(read_checked(HERE/'host-image.candidate.json', CANDIDATE_SHA256))
    # The historical receipt is not approval for the new image. It only binds
    # the existing runtime identities and separately reviewed recipe.
    old = json_bytes(read_checked(HERE/'hosted.review.json', HISTORICAL_RECEIPT_SHA256))
    recipe = read_checked(HERE/'hosted.recipe.lock.json', candidate['historical_hosted_recipe_sha256'])
    inventory = read_checked(args.inventory, candidate['inventory_sha256'], 256 * 1024 * 1024)
    prepared = read_checked(args.prepared, candidate['prepare_result_sha256'])
    with open_regular(args.image, MAX_ARCHIVE) as image, open_regular(args.runtime, MAX_ARCHIVE) as runtime:
        print(json.dumps(check_inputs(candidate, old, recipe, image, runtime, inventory, prepared), sort_keys=True))


if __name__ == '__main__':
    main()
