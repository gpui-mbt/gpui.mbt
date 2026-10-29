#!/usr/bin/env python3
"""Review-gated hosted restore scaffold. No native launch or automatic approval."""
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import tarfile

HERE = Path(__file__).resolve().parent
IMAGE = 'debian:13@sha256:4c25275446ca371766b8b093c696782eabce06263fccacb8d5d813b3dc44b308'
FIELDS = {'engine', 'component', 'mozc_build_result', 'candidate_manifest'}


def require(condition, reason):
    if not condition:
        raise ValueError(reason)


def digest(path):
    value = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(block)
    return value.hexdigest()


def receipt():
    """Fixed repository receipt only; missing approval is NOT_RUN, never inferred."""
    path = HERE / 'hosted.review.json'
    if not path.exists():
        return None
    data = json.loads(path.read_text())
    require(data.get('schema_version') == 1 and data.get('approved_for_execution') is True,
            'receipt is not explicitly approved')
    require(data.get('container_image') == IMAGE, 'unexpected container')
    for key in ('runtime_sha256', 'inventory_sha256', 'recipe_sha256'):
        require(re.fullmatch('[0-9a-f]{64}', data.get(key, '')), 'missing digest: ' + key)
    for key in ('candidate_source_sha', 'candidate_source_tree', 'artifact_head_sha'):
        require(re.fullmatch('[0-9a-f]{40}', data.get(key, '')), 'missing source identity: ' + key)
    require(data['candidate_source_sha'] == data['artifact_head_sha'], 'artifact/source mismatch')
    for key in ('artifact_id', 'artifact_run_id'):
        require(type(data.get(key)) is int and data[key] > 0, 'missing artifact identity')
    require(set(data.get('expected', {})) == FIELDS, 'exact four review pins required')
    require(all(re.fullmatch('[0-9a-f]{64}', val) for val in data['expected'].values()), 'invalid review pins')
    require(type(data.get('external_symlinks')) is dict, 'explicit external link allowlist required')
    return data


def relative(name):
    p = PurePosixPath(name)
    require(not p.is_absolute() and '..' not in p.parts and str(p) == name and name != '.',
            'non-canonical archive path')
    return p


def create_owned_parent(approved):
    require(approved.get('approved_for_execution') is True, 'parent creation has no explicit approval')
    runner_temp = Path(os.environ['RUNNER_TEMP'])
    require(runner_temp.is_absolute() and runner_temp.resolve() == runner_temp and runner_temp.is_dir(),
            'canonical runner temp is required')
    root = Path(approved['exact_restore_root'])
    require(root == runner_temp/'gpui-ime-owned/closure', 'receipt does not identify the fixed owned-parent closure')
    parent = root.parent
    parent.mkdir(mode=0o700)  # Never adopt or modify an existing parent/symlink.
    info = parent.stat()
    require(info.st_uid == os.geteuid() and stat.S_IMODE(info.st_mode) == 0o700, 'new parent ownership/mode mismatch')
    return {'parent': str(parent), 'uid': info.st_uid, 'gid': info.st_gid,
            'mode': stat.S_IMODE(info.st_mode), 'effective_uid': os.geteuid(),
            'runner_temp_uid': runner_temp.stat().st_uid}


def restore(archive, inventory, approved):
    """Validate all bytes/paths before writing; no tar.extract or symlink traversal."""
    require(approved.get('approved_for_execution') is True, 'restore has no explicit approval')
    require(digest(archive) == approved['runtime_sha256'], 'runtime digest mismatch')
    require(digest(inventory) == approved['inventory_sha256'], 'inventory digest mismatch')
    root = Path(approved['exact_restore_root'])
    require(root.is_absolute() and root.resolve() == root and root != Path('/') and not root.exists(),
            'restore requires fresh canonical exact root')
    require(root.parent.is_dir() and root.parent.stat().st_uid == os.geteuid(), 'unowned restore parent')
    rows = json.loads(Path(inventory).read_text())
    by_name = {}
    for row in rows:
        name = str(relative(row['path']))
        require(name not in by_name, 'duplicate inventory path')
        require(type(row['mode']) is int and 0 <= row['mode'] <= 0o777, 'unsafe Unix mode')
        require(row['kind'] in ('file', 'directory', 'symlink'), 'special inventory node')
        by_name[name] = row
    with tarfile.open(archive, 'r:gz') as tar:
        members = {}
        for member in tar.getmembers():
            if member.name == 'closure':
                require(member.isdir(), 'invalid closure root')
                continue
            p = relative(member.name)
            require(p.parts[0] == 'closure' and len(p.parts) > 1, 'foreign archive member')
            name = str(PurePosixPath(*p.parts[1:]))
            require(name not in members and name in by_name, 'duplicate or unexpected member')
            row = by_name[name]
            require(member.mode == row['mode'], 'mode mismatch')
            for parent in PurePosixPath(name).parents:
                if str(parent) != '.':
                    require(by_name.get(str(parent), {}).get('kind') == 'directory', 'non-directory parent')
            if row['kind'] == 'file':
                require(member.isfile() and not member.islnk() and member.size == row['size'], 'invalid regular file')
                value = hashlib.sha256()
                with tar.extractfile(member) as stream:
                    for block in iter(lambda: stream.read(1024 * 1024), b''):
                        value.update(block)
                require(value.hexdigest() == row['sha256'], 'file digest mismatch')
            elif row['kind'] == 'directory':
                require(member.isdir(), 'directory mismatch')
            else:
                require(member.issym() and member.linkname == row['target'], 'link mismatch')
                target = Path(os.path.normpath(str(root / name / '..' / member.linkname))) if not Path(member.linkname).is_absolute() else Path(member.linkname)
                if root != target and root not in target.parents:
                    require(approved['external_symlinks'].get(name) == member.linkname,
                            'escaping link not explicitly reviewed')
            members[name] = member
        require(set(members) == set(by_name), 'incomplete archive')
        root.mkdir(mode=0o700)
        # Every parent is a real directory; links are created only after files.
        for name in sorted(members, key=lambda n: (len(PurePosixPath(n).parts), n)):
            if by_name[name]['kind'] == 'directory':
                (root / name).mkdir(mode=0o700)
        # Preserve archive order for regular-file reads: reordering by depth
        # repeatedly rewinds/decompresses large gzip archives.
        for name, member in members.items():
            row = by_name[name]
            if row['kind'] == 'file':
                path = root / name
                with tar.extractfile(member) as src, path.open('xb') as dst:
                    shutil.copyfileobj(src, dst)
                path.chmod(row['mode'])
        for name, row in by_name.items():
            if row['kind'] == 'symlink':
                (root / name).symlink_to(row['target'])
        for name in sorted(by_name, key=lambda n: len(PurePosixPath(n).parts), reverse=True):
            if by_name[name]['kind'] == 'directory':
                (root / name).chmod(by_name[name]['mode'])
    return root


if __name__ == '__main__':
    approved = receipt()
    print(json.dumps({'native_status': 'NOT_RUN', 'receipt_present': approved is not None,
                      'reason': 'Scaffold only; reviewed restore/constructor/launch orchestration is not enabled'}))
