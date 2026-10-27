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
    expected = identity(source)
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
