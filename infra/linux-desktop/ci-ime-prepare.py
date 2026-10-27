#!/usr/bin/env python3
"""Prepare reviewable IME build bytes, never launch compositor/input/IME processes."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tarfile

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
CONTAINER_IMAGE = 'debian:13@sha256:4c25275446ca371766b8b093c696782eabce06263fccacb8d5d813b3dc44b308'


def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(block)
    return value.hexdigest()


def write(path, value):
    path.write_text(json.dumps(value, sort_keys=True, indent=2) + '\n')


def disjoint_roots(repo, root, evidence):
    paths = [Path(p).absolute() for p in (repo, root, evidence)]
    if any(p.resolve() != p for p in paths):
        raise ValueError('symlinked or non-canonical roots are not accepted')
    for a in paths:
        for b in paths:
            if a != b and a in b.parents:
                raise ValueError('source, closure, and evidence roots must not overlap')
    if len(set(paths)) != 3:
        raise ValueError('roots must be distinct')
    if root.exists() or evidence.exists():
        raise ValueError('closure and evidence directories must be fresh')


def create_owned_parent(root):
    runner_temp = Path(os.environ['RUNNER_TEMP'])
    if (not runner_temp.is_absolute() or runner_temp.resolve() != runner_temp
            or not runner_temp.is_dir()
            or root != runner_temp / 'gpui-ime-owned/closure'):
        raise ValueError('owned parent requires the exact canonical CI closure path')
    parent = root.parent
    # mkdir without exist_ok rejects existing directories and dangling symlinks.
    parent.mkdir(mode=0o700)
    info = parent.stat()
    if info.st_uid != os.geteuid() or stat.S_IMODE(info.st_mode) != 0o700:
        raise ValueError('fresh parent ownership/mode mismatch')
    return {'parent': str(parent), 'uid': info.st_uid, 'gid': info.st_gid,
            'mode': stat.S_IMODE(info.st_mode), 'effective_uid': os.geteuid(),
            'runner_temp_uid': runner_temp.stat().st_uid}


def inventory(root):
    """No link following; retain exact Unix link text/modes and reject IPC nodes."""
    rows = []
    for path in sorted(root.rglob('*')):
        info = path.lstat()
        row = {'path': path.relative_to(root).as_posix(), 'mode': stat.S_IMODE(info.st_mode)}
        if stat.S_ISLNK(info.st_mode):
            row.update(kind='symlink', target=os.readlink(path))
        elif stat.S_ISDIR(info.st_mode):
            row.update(kind='directory')
        elif stat.S_ISREG(info.st_mode):
            row.update(kind='file', size=info.st_size, sha256=digest(path))
        else:
            raise ValueError('special file in prepare-only closure: ' + str(path))
        rows.append(row)
    return rows


def host_identities(field_build):
    """Capture bytes only, using the build manifest's actual tool resolution."""
    manifest = json.loads(field_build.read_text())
    tools = {}
    for role in ('cc', 'fc-list', 'pkg-config'):
        row = next(row for row in manifest['runtime']['files'] if row.get('role') == 'tool:' + role)
        resolved = Path(row['path']).resolve(strict=True)
        actual = digest(resolved)
        if actual != row['sha256']:
            raise RuntimeError('build tool changed after capture: ' + role)
        tools[role] = {'path': str(resolved), 'sha256': actual, 'location': 'host'}
    executables = {}
    for name in ('/usr/bin/convert', '/usr/bin/dbus-daemon', '/usr/bin/python3'):
        resolved = Path(name).resolve(strict=True)
        executables[name] = {'resolved_path': str(resolved), 'sha256': digest(resolved)}
    return {'approved_for_execution': False, 'host_executables': executables,
            'build_tools': tools, 'field_build_sha256': digest(field_build)}


def export_closure(root, output, source, stages):
    if os.environ.get('GPUI_CONTAINER_IMAGE') != CONTAINER_IMAGE:
        raise ValueError('exact reviewed container identity is required')
    if any(stage['returncode'] != 0 for stage in stages):
        raise ValueError('failed stages cannot produce a prepared closure')
    rows = inventory(root)
    write(output / 'closure-inventory.json', rows)
    tar_path = output / 'runtime-closure.tar.gz'
    # Relative members only, exact root recorded separately. No restoration here.
    with tarfile.open(tar_path, 'w:gz', dereference=False) as archive:
        archive.add(root, arcname='closure', recursive=True)
    if inventory(root) != rows:
        raise RuntimeError('closure changed during export; no readiness record')
    structure = {'member_type_counts': {}, 'hardlinks': [], 'root': None}
    with tarfile.open(tar_path, 'r:gz') as archive:
        for member in archive:
            kind = ('directory' if member.isdir() else 'symlink' if member.issym()
                    else 'hardlink' if member.islnk() else 'file' if member.isfile() else 'special')
            structure['member_type_counts'][kind] = structure['member_type_counts'].get(kind, 0) + 1
            if member.islnk():
                structure['hardlinks'].append({'name': member.name, 'target': member.linkname})
            if member.name == 'closure':
                structure['root'] = {'mode': member.mode, 'uid': member.uid, 'gid': member.gid}
    write(output / 'archive-structure.json', structure)

    metadata = {'schema_version': 1, 'preparation_status': 'PREPARED', 'native_status': 'NOT_RUN',
                'approved_for_execution': False, 'required_next_step': 'Independent pin review before any restore/execute stage',
                'exact_restore_root': str(root), 'source': source, 'stages': stages,
                'container_image': CONTAINER_IMAGE,
                'runtime_archive': {'name': tar_path.name, 'size': tar_path.stat().st_size, 'sha256': digest(tar_path)},
                'inventory_sha256': digest(output / 'closure-inventory.json'),
                'archive_structure_sha256': digest(output / 'archive-structure.json'),
                'scope': 'Build only. No sockets, compositor, OS input, IME conversion, or acceptance execution.',
                'external_dependencies': 'Host/container libraries remain external; host package inventory and exact image are recorded. Absolute symlinks are retained, not silently rebased.'}
    write(output / 'prepare-result.json', metadata)
    return metadata


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--evidence', type=Path, required=True)
    parser.add_argument('--create-owned-parent', action='store_true')
    args = parser.parse_args(argv)
    root, evidence = args.root.absolute(), args.evidence.absolute()
    disjoint_roots(REPO, root, evidence)
    ownership = create_owned_parent(root) if args.create_owned_parent else None
    root.mkdir(parents=True)
    evidence.mkdir(parents=True)
    if ownership is not None:
        write(evidence / 'parent-ownership.json', ownership)
    stages = []
    write(evidence / 'prepare-result.json', {'preparation_status': 'INCOMPLETE', 'native_status': 'NOT_RUN', 'approved_for_execution': False})
    def run(name, command, cwd=REPO):
        with (evidence / (name + '.log')).open('w') as stream:
            stream.write(repr(list(map(str, command))) + '\n'); stream.flush()
            result = subprocess.run(list(map(str, command)), cwd=cwd, stdout=stream, stderr=subprocess.STDOUT)
        stages.append({'stage': name, 'returncode': result.returncode})
        write(evidence / 'stages.json', stages)
        if result.returncode:
            raise RuntimeError(name + ' failed')
    try:
        source = {'sha': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=REPO, text=True).strip(),
                  'tree': subprocess.check_output(['git', 'rev-parse', 'HEAD^{tree}'], cwd=REPO, text=True).strip()}
        if subprocess.check_output(['git', 'status', '--porcelain'], cwd=REPO):
            raise RuntimeError('prepare requires a clean committed source checkout')
        run('host', ['sh', '-c', 'cat /etc/os-release; uname -a; dpkg-query -W; cc --version; python3 --version'])
        run('source-archive', ['git', 'archive', '--format=tar.gz', '-o', evidence / 'source.tar.gz', source['sha']])
        # A self-contained local shallow clone avoids an external worktree .git pointer.
        run('source-clone', ['git', 'clone', '--no-local', '--depth', '1', REPO.as_uri(), root / 'source'])
        run('source-checkout', ['git', 'checkout', '--detach', source['sha']], cwd=root / 'source')
        if subprocess.check_output(['git', 'rev-parse', 'HEAD^{tree}'], cwd=root / 'source', text=True).strip() != source['tree']:
            raise RuntimeError('cloned source tree mismatch')
        profile = root / 'profile'
        desktop = root / 'source/infra/linux-desktop'
        run('bootstrap', [sys.executable, desktop / 'gpui-desktop.py', '--root', profile, 'bootstrap'])
        # Keep the existing recovery contract: runtime prefix is profile/prefix.
        # Mozc rebuild copies this SDK into its own distinct build root.
        run('mozc-build', [sys.executable, desktop / 'mozc-prefix/rebuild.py', '--sdk-root', profile / 'prefix',
                           '--runtime-prefix', profile / 'prefix', '--build-root', root / 'mozc-build'])
        run('app-build', [sys.executable, desktop / 'gpui-desktop.py', '--root', profile, 'build',
                          '--repo', root / 'source', '--output-dir', root / 'app-build'])
        run('candidate', [sys.executable, desktop / 'candidate_bundle.py', 'prepare', '--profile-root', profile,
                         '--output', root / 'candidate'])
        for relative in ['profile/installed.json', 'profile/field-build.json', 'candidate/manifest.json', 'candidate/build-manifest.json',
                         'mozc-build/build-result.json', 'mozc-build/runtime-ldd.txt',
                         'mozc-build/artifacts/ibus-engine-mozc', 'mozc-build/artifacts/mozc.xml']:
            destination = evidence / 'review' / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(root / relative, destination)
        for relative in ['profile.lock.json', 'mozc-prefix/build.lock.json', 'wayland-ime/recovery/recipe.lock.json']:
            destination = evidence / 'review/locks' / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(desktop / relative, destination)
        write(evidence / 'host-executables.json', host_identities(profile / 'field-build.json'))
        result = export_closure(root, evidence, source, stages)
        result['pins_for_independent_review'] = {
            role: {'path': relative, 'sha256': digest(root / relative)}
            for role, relative in {
                'engine': 'mozc-build/artifacts/ibus-engine-mozc',
                'component': 'mozc-build/artifacts/mozc.xml',
                'build_result': 'mozc-build/build-result.json',
                'candidate_field_build': 'profile/field-build.json',
            }.items()
        }
        result['host_executables_sha256'] = digest(evidence / 'host-executables.json')
        result['host_inventory_sha256'] = digest(evidence / 'host.log')
        result['source_archive_sha256'] = digest(evidence / 'source.tar.gz')
        result['review_files'] = inventory(evidence / 'review')
        write(evidence / 'prepare-result.json', result)
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        write(evidence / 'prepare-result.json', {'preparation_status': 'FAIL', 'native_status': 'NOT_RUN',
              'approved_for_execution': False, 'error': str(error), 'stages': stages})
        # Preserve internal compilation diagnostics without pretending a closure passed.
        for name in ['mozc-build/build.log', 'mozc-build/runtime-ldd.txt']:
            if (root / name).is_file():
                shutil.copyfile(root / name, evidence / Path(name).name)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
