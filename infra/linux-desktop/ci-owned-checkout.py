#!/usr/bin/env python3
"""Clone exact clean CI IaC bytes into a fresh owned checkout; never launch native."""
import argparse
import json
import os
from pathlib import Path
import subprocess


def git(repo, *arguments):
    return subprocess.check_output(['git', '-C', str(repo), *arguments], text=True, timeout=60).strip()


def identity(repo):
    if git(repo, 'status', '--porcelain'):
        raise ValueError('owned checkout requires clean committed source')
    return {'sha': git(repo, 'rev-parse', 'HEAD'), 'tree': git(repo, 'rev-parse', 'HEAD^{tree}')}


def clone(source, runner_temp):
    source, runner_temp = Path(source), Path(runner_temp)
    if (not source.is_absolute() or source.resolve() != source or
            not runner_temp.is_absolute() or runner_temp.resolve() != runner_temp or
            not runner_temp.is_dir()):
        raise ValueError('source and runner temp must be direct canonical directories')
    destination = runner_temp/'gpui-ime-iac'
    if destination.exists() or destination.is_symlink():
        raise ValueError('refusing existing owned checkout')
    source_git = source/'.git'
    if source_git.is_symlink() or source_git.resolve() != source_git or not source_git.is_dir():
        raise ValueError('source .git must be a direct canonical directory')
    expected = identity(source)
    # file:// upload-pack checks .git rather than the worktree. Transport can
    # sanitize command-level config, so persist this one exact entry only in
    # the fresh task HOME established by the nonroot setup.
    home = runner_temp/'gpui-ime-home'
    if (Path(os.environ['HOME']) != home or home.resolve() != home or home.is_symlink()
            or not home.is_dir() or home.stat().st_uid != os.geteuid()
            or home.stat().st_mode & 0o777 != 0o700):
        raise ValueError('expected private owned CI HOME')
    config = home/'.gitconfig'
    if config.is_symlink() or (config.exists() and (not config.is_file() or config.stat().st_uid != os.geteuid())):
        raise ValueError('unsafe private Git configuration')
    subprocess.run(['git', 'config', '--file', str(config), '--add', 'safe.directory', str(source_git)],
                   check=True, timeout=30)
    subprocess.run(['git', 'clone', '--no-local', '--depth', '1', '--no-checkout',
                    source.as_uri(), str(destination)], check=True, timeout=120)
    destination.chmod(0o700)
    git(destination, 'checkout', '--detach', expected['sha'])
    git(destination, 'remote', 'remove', 'origin')  # No inherited remote/credential configuration.
    if identity(destination) != expected or identity(source) != expected:
        raise ValueError('source or cloned identity changed')
    if destination.stat().st_uid != os.geteuid():
        raise ValueError('new checkout is not current-user owned')
    return {'checkout': str(destination), 'uid': destination.stat().st_uid, **expected}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(clone(args.source, Path(os.environ['RUNNER_TEMP'])), sort_keys=True))


if __name__ == '__main__':
    main()
