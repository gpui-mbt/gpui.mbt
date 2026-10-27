#!/usr/bin/env python3
"""Bound Ubuntu CI dependency acquisition without changing package requirements.

Only the Azure Ubuntu mirror URI is replaced, by Canonical's primary archive.
Suites, components, Signed-By, package arguments and normal apt authentication
remain unchanged. Temporary source copies leave /etc/apt untouched.
"""
import argparse
from pathlib import Path
import re
import subprocess
import tempfile

PACKAGES = (
    'build-essential pkg-config libx11-dev libwayland-dev wayland-protocols '
    'libegl1-mesa-dev libgles2-mesa-dev libxkbcommon-dev libpango1.0-dev '
    'libfontconfig1-dev fontconfig fonts-dejavu-core fonts-dejavu-extra '
    'fonts-noto-cjk fonts-noto-color-emoji'
).split()
AZURE = re.compile(r'(https?://)azure\.archive\.ubuntu\.com(?=/|\s|$)')


def official_mirror(text):
    return AZURE.sub(r'\1archive.ubuntu.com', text)


def copied_sources(apt_root, destination):
    destination.mkdir(mode=0o755)
    parts = destination/'sources.list.d'
    parts.mkdir(mode=0o755)
    source = apt_root/'sources.list'
    (destination/'sources.list').write_text(official_mirror(source.read_text()) if source.exists() else '')
    original_parts = apt_root/'sources.list.d'
    if original_parts.is_dir():
        for source in sorted(original_parts.iterdir()):
            if source.suffix in ('.list', '.sources') and source.is_file():
                (parts/source.name).write_text(official_mirror(source.read_text()))


def commands(sources):
    options = ['-o', 'Acquire::http::Timeout=30', '-o', 'Acquire::https::Timeout=30',
               '-o', 'Acquire::Retries=1', '-o', 'APT::Update::Error-Mode=any',
               '-o', 'Dir::Etc::sourcelist='+str(sources/'sources.list'),
               '-o', 'Dir::Etc::sourceparts='+str(sources/'sources.list.d')]
    return [(['sudo', 'timeout', '--signal=TERM', '--kill-after=15s', '120s', 'apt-get', *options, 'update'], 120),
            (['sudo', 'timeout', '--signal=TERM', '--kill-after=15s', '420s', 'apt-get', *options, 'install', '-y', *PACKAGES], 420)]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='gpui-contract-apt-') as temporary:
        root = Path(temporary)
        root.chmod(0o755)  # apt's unprivileged reader needs access to source copies.
        sources = root/'apt'
        copied_sources(Path('/etc/apt'), sources)
        for command, timeout in commands(sources):
            print('Bounded dependency command:', ' '.join(command), 'deadline:', timeout, flush=True)
            # Root-owned GNU timeout terminates the apt process group, not just
            # the unprivileged sudo wrapper. Its grace period is also bounded.
            subprocess.run(command, check=True, timeout=timeout + 30)


if __name__ == '__main__':
    main()
