#!/usr/bin/env python3
"""Set up one fresh nonroot IME CI account; never adopt users or shared paths."""
import argparse
import grp
import json
import os
from pathlib import Path
import pwd
import stat
import subprocess

USER = 'gpui-ime-ci'
TEMP = Path('/__w/_temp')
SOURCE = Path('/__w/gpui.mbt/gpui.mbt')
IMAGE = 'debian:13@sha256:4c25275446ca371766b8b093c696782eabce06263fccacb8d5d813b3dc44b308'


def require(value, message):
    if not value:
        raise ValueError(message)


def inspect(path):
    require(path.is_absolute() and path.resolve() == path and not path.is_symlink(),
            'noncanonical or symlinked CI path')
    info = path.stat()
    require(stat.S_ISDIR(info.st_mode), 'CI path is not a directory')
    return {'uid': info.st_uid, 'gid': info.st_gid, 'mode': stat.S_IMODE(info.st_mode)}


def validate(runner_temp, source, temp_info, source_info):
    require(runner_temp == TEMP and source == SOURCE, 'unexpected CI paths')
    uid, gid = temp_info['uid'], temp_info['gid']
    require(1000 <= uid <= 60000 and 1000 <= gid <= 60000, 'expected bounded nonroot runner UID/GID')
    require((source_info['uid'], source_info['gid']) == (uid, gid), 'checkout/temp identity mismatch')
    require(temp_info['mode'] & 0o700 == 0o700 and not temp_info['mode'] & 0o022,
            'runner temp permissions are unsafe')
    require(not source_info['mode'] & 0o022, 'checkout is group/world writable')
    return uid, gid


def absent(lookup, key):
    try:
        lookup(key)
    except KeyError:
        return
    raise ValueError('refusing existing CI account/group identity')


def plan(runner_temp, source):
    uid, gid = validate(runner_temp, source, inspect(runner_temp), inspect(source))
    for lookup, key in ((pwd.getpwnam, USER), (pwd.getpwuid, uid),
                        (grp.getgrnam, USER), (grp.getgrgid, gid)):
        absent(lookup, key)
    paths = [runner_temp/'gpui-ime-home', runner_temp/'gpui-ime-execution',
             runner_temp/'gpui-ime-iac', runner_temp/'gpui-ime-owned']
    require(all(not path.exists() and not path.is_symlink() for path in paths), 'refusing existing private CI paths')
    return {'user': USER, 'uid': uid, 'gid': gid, 'home': str(paths[0]),
            'evidence': str(paths[1]), 'source': str(source), 'runner_temp': str(runner_temp)}


def setup():
    require(os.getuid() == 0 and os.geteuid() == 0, 'account setup requires root')
    require(os.environ.get('GPUI_CONTAINER_IMAGE') == IMAGE, 'unexpected container image')
    record = plan(Path(os.environ['RUNNER_TEMP']), Path(os.environ['GITHUB_WORKSPACE']))
    subprocess.run(['groupadd', '--gid', str(record['gid']), USER], check=True, timeout=30)
    subprocess.run(['useradd', '--uid', str(record['uid']), '--gid', str(record['gid']),
                    '--home-dir', record['home'], '--no-create-home', '--no-log-init',
                    '--shell', '/usr/sbin/nologin', USER], check=True, timeout=30)
    for name in ('home', 'evidence'):
        path = Path(record[name])
        path.mkdir(mode=0o700)  # Only these fresh task-owned paths are chowned.
        os.chown(path, record['uid'], record['gid'])
    (Path(record['evidence'])/'nonroot-setup.json').write_text(json.dumps(record, indent=2)+'\n')
    return record


def validate_process(uid, gid):
    require((os.getuid(), os.geteuid(), os.getgid(), os.getegid()) == (uid, uid, gid, gid),
            'real/effective CI identity mismatch')
    require(set(os.getgroups()) <= {gid}, 'unexpected supplementary groups')


def check(downloads=False):
    require(os.environ.get('GPUI_CONTAINER_IMAGE') == IMAGE, 'unexpected container image')
    runner_temp, source = Path(os.environ['RUNNER_TEMP']), Path(os.environ['GITHUB_WORKSPACE'])
    uid, gid = validate(runner_temp, source, inspect(runner_temp), inspect(source))
    validate_process(uid, gid)
    if downloads:
        for relative in ('gpui-ime-download-runtime/runtime-closure.tar.gz',
                         'gpui-ime-download-review/prepare-result.json',
                         'gpui-ime-download-review/closure-inventory.json'):
            path = runner_temp/relative
            require(path.resolve() == path and not path.is_symlink() and path.is_file() and os.access(path, os.R_OK),
                    'download is not directly readable by nonroot')
    account = pwd.getpwnam(USER)
    home = runner_temp/'gpui-ime-home'
    require(account.pw_uid == uid and account.pw_gid == gid and account.pw_dir == str(home),
            'CI account differs')
    require(Path(os.environ['HOME']) == home and inspect(home) == {'uid': uid, 'gid': gid, 'mode': 0o700},
            'CI home differs')
    output = os.environ.get('GITHUB_OUTPUT')
    if output:
        path = Path(output)
        require(path.is_absolute() and path.resolve() == path and not path.is_symlink() and path.is_file(),
                'invalid Actions output file')
        require(path.stat().st_uid == uid and os.access(path, os.W_OK), 'Actions output is not owned/writable')
    return {'uid': uid, 'euid': os.geteuid(), 'gid': gid, 'egid': os.getegid(),
            'groups': os.getgroups(), 'home': str(home), 'github_output_writable': bool(output)}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('phase', choices=('setup', 'check'))
    parser.add_argument('--downloads', action='store_true')
    args = parser.parse_args()
    print(json.dumps(setup() if args.phase == 'setup' else check(args.downloads), sort_keys=True))
