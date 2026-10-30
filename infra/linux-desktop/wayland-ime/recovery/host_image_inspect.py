#!/usr/bin/env python3
"""Verify an unstarted container from the unapproved fixed host image.

This prepare-only check never starts a container, restores a runtime, binds a
deployment, or authorizes execution. Docker's local daemon is trusted for its
image and container inspection; this is not remote attestation.
"""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys

import host_image_gate as identity

HERE = Path(__file__).resolve().parent
DOCKER = ['docker', '--host=unix:///var/run/docker.sock']


def docker_env():
    env = os.environ.copy()
    # Do not let a saved context redirect inspection to a different daemon.
    for key in ('DOCKER_HOST', 'DOCKER_CONTEXT', 'DOCKER_TLS', 'DOCKER_TLS_VERIFY', 'DOCKER_CERT_PATH'):
        env.pop(key, None)
    return env


def run_docker(arguments, *, stdin=None):
    return subprocess.run(DOCKER + arguments, stdin=stdin, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, check=True, timeout=600,
                          env=docker_env()).stdout.decode('utf-8').strip()


def check_container(data, image_id):
    identity.require(isinstance(data, list) and len(data) == 1 and isinstance(data[0], dict),
                     'unexpected container inspection')
    obj = data[0]
    identity.require(obj.get('Image') == image_id, 'container image mismatch')
    state = obj.get('State') or {}
    identity.require(state.get('Status') == 'created' and state.get('Running') is False
                     and state.get('Pid') == 0, 'container has run or is running')
    config = obj.get('Config') or {}
    host = obj.get('HostConfig') or {}
    identity.require(config.get('User') == '65534:65534' and config.get('Entrypoint') == ['/bin/false'],
                     'container user or inert entrypoint mismatch')
    identity.require(host.get('NetworkMode') == 'none' and host.get('ReadonlyRootfs') is True
                     and host.get('Privileged') is False, 'unsafe container isolation')
    identity.require(host.get('CapDrop') == ['ALL'] and 'no-new-privileges' in (host.get('SecurityOpt') or []),
                     'missing container restrictions')
    identity.require(not config.get('Volumes') and not host.get('Binds')
                     and not obj.get('Mounts') and not host.get('Devices'),
                     'unexpected mount or device')


def inspect_image(image_path):
    candidate = identity.json_bytes(identity.read_checked(HERE / 'host-image.candidate.json',
                                                          identity.CANDIDATE_SHA256))
    identity.require(candidate.get('approved_for_execution') is False, 'candidate must stay unapproved')
    image_id = candidate['image_id']
    identity.require(re.fullmatch(r'sha256:[0-9a-f]{64}', image_id) is not None, 'invalid image ID')
    container_id = None
    try:
        with identity.open_regular(image_path, identity.MAX_ARCHIVE) as image:
            identity.check_image(image, candidate['image_tar_sha256'], image_id)
            image.seek(0)
            # Feed Docker the same verified descriptor, not a reopened path.
            run_docker(['load'], stdin=image)
            image.seek(0)
            identity.require(identity.stream_digest(image) == candidate['image_tar_sha256'],
                             'image changed during load')
        actual = run_docker(['image', 'inspect', '--format', '{{.Id}}', image_id])
        identity.require(actual == image_id, 'loaded image identity mismatch')
        container_id = run_docker(['create', '--network=none', '--read-only', '--cap-drop=ALL',
                                   '--security-opt=no-new-privileges', '--user=65534:65534',
                                   '--entrypoint=/bin/false', image_id])
        identity.require(re.fullmatch(r'[0-9a-f]{64}', container_id) is not None,
                         'invalid created container ID')
        check_container(identity.json_bytes(run_docker(['inspect', container_id])), image_id)
        return {'status': 'unstarted-image-identity-matched', 'image_id': image_id,
                'image_tar_sha256': candidate['image_tar_sha256'],
                'native_status': 'NOT_RUN', 'approved_for_execution': False}
    finally:
        if container_id and re.fullmatch(r'[0-9a-f]{64}', container_id):
            # Remove only the container this invocation created, without start.
            run_docker(['rm', '-v', container_id])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--image', type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(inspect_image(args.image), sort_keys=True))


if __name__ == '__main__':
    sys.exit(main())
