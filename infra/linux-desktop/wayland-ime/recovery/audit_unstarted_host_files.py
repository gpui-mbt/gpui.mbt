#!/usr/bin/env python3
"""Audit fixed host-file bytes from an unstarted image; never launch native input.

This is diagnostic evidence, not an approval, runtime bind, or proof of the
later running container. Docker's local daemon and this checkout are trusted.
"""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import resource
import subprocess
import tarfile
import tempfile

import check_candidate_recipe as recipe_check
import host_image_gate as gate
import host_image_inspect as inspect

HERE = Path(__file__).resolve().parent
DESKTOP = HERE.parent.parent
MAX_FILE = 64 * 1024 * 1024
MAX_TAR = MAX_FILE + 1024 * 1024


def expected_host_files(recipe):
    # Paths and hashes come from the already checked fixed candidate recipe.
    files = dict(recipe['host_executables'])
    for tool in recipe['build_tools'].values():
        if tool.get('location') == 'host':
            path, value = tool['path'], tool['sha256']
            gate.require(path not in files or files[path] == value, 'conflicting host file hashes')
            files[path] = value
    gate.require(files, 'empty host file list')
    for name, value in files.items():
        path = PurePosixPath(name)
        gate.require(path.is_absolute() and str(path) == name and '..' not in path.parts
                     and ':' not in name and re.fullmatch(r'[0-9a-f]{64}', value), 'invalid host file pin')
    return files


def digest_single_tar(stream):
    """Docker cp -L resolves a final symlink; reject every other archive shape."""
    stream.seek(0)
    with tarfile.open(fileobj=stream, mode='r:') as archive:
        members = archive.getmembers()
        gate.require(len(members) == 1, 'copy did not contain exactly one member')
        member = members[0]
        gate.require(member.isfile() and member.name not in ('', '.', '..') and
                     '/' not in member.name and 0 <= member.size <= MAX_FILE,
                     'unsafe copied file')
        content = archive.extractfile(member)
        gate.require(content is not None, 'missing copied file content')
        digest = hashlib.sha256()
        while True:
            chunk = content.read(1024 * 1024)
            if not chunk:
                break
            digest.update(chunk)
        return digest.hexdigest()


def copy_digest(container, path):
    # Limit Docker's output file, including malformed or unexpectedly large tar.
    def limit_output():
        resource.setrlimit(resource.RLIMIT_FSIZE, (MAX_TAR, MAX_TAR))
    with tempfile.TemporaryFile() as stream:
        result = subprocess.run(['docker', 'cp', '-L', container + ':' + path, '-'],
                                stdout=stream, stderr=subprocess.PIPE, timeout=30,
                                preexec_fn=limit_output, check=False)
        gate.require(result.returncode == 0, 'docker copy failed: ' + path)
        gate.require(stream.tell() <= MAX_TAR, 'docker copy exceeds limit')
        return digest_single_tar(stream)


def audit(image, candidate, recipe):
    image_id = candidate['image_id']
    gate.require(candidate['approved_for_execution'] is False and
                 re.fullmatch(r'sha256:[0-9a-f]{64}', image_id), 'invalid candidate')
    gate.check_image(image, candidate['image_tar_sha256'], image_id)
    expected = expected_host_files(recipe)
    container = None
    try:
        image.seek(0)
        inspect.run_docker(['load'], stdin=image)
        image.seek(0)
        gate.require(gate.stream_digest(image) == candidate['image_tar_sha256'], 'image changed during load')
        gate.require(inspect.run_docker(['image', 'inspect', '--format', '{{.Id}}', image_id]) == image_id,
                     'loaded image identity mismatch')
        container = inspect.run_docker(['create', '--network=none', '--read-only', '--cap-drop=ALL',
            '--security-opt=no-new-privileges', '--user=65534:65534', '--entrypoint=/bin/false', image_id])
        gate.require(re.fullmatch(r'[0-9a-f]{64}', container), 'invalid created container ID')
        inspect.check_container(gate.json_bytes(inspect.run_docker(['inspect', container])), image_id)
        records = []
        for path, wanted in sorted(expected.items()):
            actual = copy_digest(container, path)
            records.append({'path': path, 'expected_sha256': wanted, 'actual_sha256': actual,
                            'match': actual == wanted})
        inspect.check_container(gate.json_bytes(inspect.run_docker(['inspect', container])), image_id)
        return {'status': 'matched' if all(r['match'] for r in records) else 'mismatch',
                'image_id': image_id, 'image_tar_sha256': candidate['image_tar_sha256'],
                'host_files': records, 'native_status': 'NOT_RUN', 'approved_for_execution': False}
    finally:
        if container and re.fullmatch(r'[0-9a-f]{64}', container):
            inspect.run_docker(['rm', '-v', container])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--image', required=True, type=Path)
    args = parser.parse_args()
    paths = ['image.review.candidate.json', 'image.recipe.candidate.json', 'hosted.review.json',
             'hosted.recipe.lock.json', 'host-image.candidate.json']
    def read(path, limit):
        with gate.open_regular(path, limit) as stream:
            return stream.read()
    receipt, recipe_raw, old, old_recipe, candidate_raw = [read(HERE / p, 2 * 1024 * 1024) for p in paths]
    def source(name):
        path = DESKTOP / name
        gate.require(path.resolve(strict=True) == path, 'source path is not canonical: ' + name)
        return read(path, 16 * 1024 * 1024)
    recipe_check.verify(receipt, recipe_raw, old, old_recipe, candidate_raw, source)
    with gate.open_regular(args.image, gate.MAX_ARCHIVE) as image:
        result = audit(image, gate.json_bytes(candidate_raw), gate.json_bytes(recipe_raw))
    print(json.dumps(result, sort_keys=True))
    return 0 if result['status'] == 'matched' else 1


if __name__ == '__main__':
    raise SystemExit(main())
