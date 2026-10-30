#!/usr/bin/env python3
"""Fail-closed inspection of an unstarted candidate, never an execution approval.

A matching Docker inspect record is a snapshot only. Callers must independently
validate their plan's provenance, source path ownership, the live container and
native caller identity; the fixture here performs none of those operations.
"""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import host_image_gate as gate

HERE = Path(__file__).resolve().parent
RECEIPT_SHA256 = '86bdf6aa0380a907463c9952e0a49e3f31e93a9f01d6ba49e32fca6386233f63'
REVIEW_SHA256 = '87b8332d2c3502cb8d7aca4cf9477c2365373576712eb38dff42328c6ca2a7cb'


def require(condition, reason):
    if not condition:
        raise ValueError(reason)


def path(value):
    require(isinstance(value, str) and value != '/' and PurePosixPath(value).is_absolute()
            and str(PurePosixPath(value)) == value and '..' not in PurePosixPath(value).parts
            and not any(c in value for c in '\0\n\r,'), 'invalid mount path')
    return PurePosixPath(value)


def validate_receipt(receipt, review_raw):
    require(hashlib.sha256(review_raw).hexdigest() == REVIEW_SHA256,
            'candidate review digest mismatch')
    review = gate.json_bytes(review_raw)
    require(type(receipt) is dict and set(receipt) == {
        'approved_for_execution', 'candidate_review_sha256', 'image_id',
        'native_status', 'plan', 'schema_version', 'scope'}, 'invalid receipt fields')
    require(type(receipt['schema_version']) is int and receipt['schema_version'] == 1
            and receipt['approved_for_execution'] is False
            and receipt['native_status'] == 'NOT_RUN' and review['approved_for_execution'] is False
            and receipt['candidate_review_sha256'] == REVIEW_SHA256
            and receipt['image_id'] == review['image_id'], 'candidate identity or status mismatch')
    require(receipt['plan'] is not None, 'candidate execution plan is incomplete')
    return receipt['plan']


def check(inspections, receipt, review_raw):
    plan = validate_receipt(receipt, review_raw)
    require(type(plan) is dict and set(plan) == {'container_id', 'user', 'entrypoint', 'cmd', 'env', 'mounts', 'network'},
            'incomplete execution plan')
    require(isinstance(plan['container_id'], str) and re.fullmatch(r'[0-9a-f]{64}', plan['container_id']),
            'invalid container ID')
    # The old workflow's root setup and runuser process have different identities.
    # This is only the container configuration user, not a native caller UID check.
    require(isinstance(plan['user'], str) and plan['user'], 'container user unspecified')
    require(all(type(plan[k]) is list and plan[k] and all(isinstance(x, str) and x and '\0' not in x
                for x in plan[k]) for k in ('entrypoint', 'cmd')), 'command unspecified')
    require(type(plan['env']) is dict and all(isinstance(k, str) and re.fullmatch(r'[A-Z_][A-Z0-9_]*', k)
                and isinstance(v, str) and '\0' not in v for k, v in plan['env'].items()), 'invalid environment')
    # No credential or proxy pass-through is assumed. Network metadata needs a
    # separately designed and reviewed phase; exact values are never printed.
    require(set(plan['env']) <= {'PATH', 'HOME', 'LANG', 'LC_ALL', 'TZ', 'RUNNER_TEMP',
                                  'GITHUB_WORKSPACE', 'PYTHONDONTWRITEBYTECODE', 'GPUI_CONTAINER_IMAGE'},
            'unreviewed environment variable')
    require(plan['network'] == 'none', 'networked plan not supported')
    mounts = plan['mounts']
    require(type(mounts) is list and mounts, 'mount plan unspecified')
    entries = set()
    for item in mounts:
        require(type(item) is dict and set(item) == {'source', 'destination', 'writable'}
                and type(item['writable']) is bool, 'invalid mount plan')
        path(item['source']); path(item['destination'])
        entries.add((item['source'], item['destination'], item['writable']))
    require(len(entries) == len(mounts), 'duplicate planned mount')
    for column in (0, 1):
        paths = [path(e[column]) for e in entries]
        require(len(set(paths)) == len(paths) and all(a not in b.parents and b not in a.parents
                for i, a in enumerate(paths) for b in paths[i+1:]), 'overlapping mounts')
    require(type(inspections) is list and len(inspections) == 1 and type(inspections[0]) is dict,
            'invalid Docker inspection')
    obj = inspections[0]
    state, config, host = obj.get('State') or {}, obj.get('Config') or {}, obj.get('HostConfig') or {}
    require(obj.get('Id') == plan['container_id'] and obj.get('Image') == receipt['image_id']
            and state.get('Status') == 'created'
            and state.get('Running') is False and state.get('Pid') == 0, 'image or state mismatch')
    require(config.get('User') == plan['user'] and config.get('Entrypoint') == plan['entrypoint']
            and config.get('Cmd') == plan['cmd'], 'container user or command mismatch')
    env = config.get('Env') or []
    require(type(env) is list and all(isinstance(v, str) and '=' in v for v in env), 'invalid inspected environment')
    keys = [v.split('=', 1)[0] for v in env]
    require(len(keys) == len(set(keys)) and dict(v.split('=', 1) for v in env) == plan['env'],
            'container environment mismatch')
    require({'NetworkMode', 'ReadonlyRootfs', 'Privileged', 'CapDrop', 'CapAdd', 'SecurityOpt',
             'PidMode', 'IpcMode', 'UTSMode', 'Devices', 'DeviceRequests', 'VolumesFrom', 'Tmpfs'} <= set(host)
            and 'Volumes' in config, 'incomplete container inspection')
    require(host.get('NetworkMode') == 'none' and host.get('ReadonlyRootfs') is True
            and host.get('Privileged') is False and host.get('CapDrop') == ['ALL']
            and host.get('CapAdd') in (None, []) and host.get('SecurityOpt') == ['no-new-privileges']
            and host.get('PidMode') in (None, '') and host.get('IpcMode') in (None, '', 'private', 'none')
            and host.get('UTSMode') in (None, '') and not host.get('Devices')
            and not host.get('DeviceRequests') and not host.get('VolumesFrom')
            and not host.get('Tmpfs') and not config.get('Volumes'), 'unsafe isolation')
    observed = obj.get('Mounts') or []
    require(type(observed) is list and len(observed) == len(entries), 'unexpected mount count')
    seen = set()
    for m in observed:
        require(type(m) is dict and m.get('Type') == 'bind' and m.get('Propagation') in ('private', 'rprivate')
                and type(m.get('RW')) is bool, 'unsafe mount')
        key = (m.get('Source'), m.get('Destination'), m['RW'])
        require(key in entries and key not in seen, 'unplanned mount')
        seen.add(key)
    require(seen == entries, 'missing mount')
    return {'status': 'unstarted-inspection-matches-plan', 'native_status': 'NOT_RUN',
            'approved_for_execution': False, 'image_id': receipt['image_id']}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inspect-json', required=True, type=Path)
    args = parser.parse_args()
    receipt = gate.json_bytes(gate.read_checked(HERE/'execution-container.candidate.json', RECEIPT_SHA256))
    review = gate.read_checked(HERE/'image.review.candidate.json', REVIEW_SHA256)
    with gate.open_regular(args.inspect_json, 1024 * 1024) as stream:
        inspections = gate.json_bytes(stream.read())
    print(json.dumps(check(inspections, receipt, review), sort_keys=True))


if __name__ == '__main__':
    main()
