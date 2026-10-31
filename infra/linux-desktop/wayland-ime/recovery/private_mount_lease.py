"""Hold and recheck a private host mount-source directory without following symlinks.

This Linux host-side primitive does not create or start a container and does
not authorize execution. A descriptor lease detects ordinary path substitution
at explicit revalidation points; Docker still consumes a pathname, so this is
not an atomic binding against a concurrent trusted-owner/daemon adversary.
"""
import os
from pathlib import PurePosixPath
import stat


class LeaseError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise LeaseError(message)


def components(value, *, absolute):
    require(isinstance(value, str) and value and '\0' not in value, 'invalid path')
    path = PurePosixPath(value)
    require(path.is_absolute() == absolute and str(path) == value and not value.startswith('//')
            and '..' not in path.parts,
            'noncanonical path')
    parts = path.parts[1:] if absolute else path.parts
    require(parts and all(part not in ('', '.', '..') for part in parts), 'empty path')
    return list(parts)


def directory_open(name, parent_fd=None):
    flags = os.O_PATH | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC
    try:
        return os.open(name, flags, dir_fd=parent_fd)
    except OSError as error:
        raise LeaseError('cannot open directory without following symlinks') from error


def validate_directory(fd, owner, phase):
    value = os.fstat(fd)
    require(stat.S_ISDIR(value.st_mode), 'path component is not a directory')
    require(type(owner) is int and 1000 <= owner <= 60000, 'invalid owner')
    if phase == 'ancestor':
        require(value.st_uid in (0, owner) and not value.st_mode & 0o022,
                'unsafe ancestor owner or write permissions')
    elif phase == 'root':
        require(value.st_uid == owner and stat.S_IMODE(value.st_mode) == 0o700,
                'private root must be owner-only and owned by the designated UID')
    else:
        require(value.st_uid == owner and not value.st_mode & 0o022,
                'unsafe mount source owner or write permissions')
    return (value.st_dev, value.st_ino)


class MountLease:
    """A non-serializable lease over a directory below an owner-only root."""
    def __init__(self, root, relative, owner):
        root_parts = components(root, absolute=True)
        self._parts = root_parts + components(relative, absolute=False)
        self._root_index = len(root_parts)
        self._owner = owner
        self._fds = []
        self._identities = []
        self._closed = False
        try:
            self._fds, self._identities = self._walk()
        except BaseException:
            self.close()
            raise

    def __copy__(self):
        raise TypeError('mount leases cannot be copied')

    def __deepcopy__(self, memo):
        raise TypeError('mount leases cannot be copied')

    def __reduce__(self):
        raise TypeError('mount leases cannot be serialized')

    def __reduce_ex__(self, protocol):
        raise TypeError('mount leases cannot be serialized')

    def __getstate__(self):
        raise TypeError('mount leases cannot be serialized')

    def _walk(self):
        fds, identities = [], []
        try:
            fd = directory_open('/')
            fds.append(fd)
            identities.append(validate_directory(fd, self._owner, 'ancestor'))
            for index, name in enumerate(self._parts, start=1):
                fd = directory_open(name, fds[-1])
                fds.append(fd)
                phase = 'ancestor' if index < self._root_index else ('root' if index == self._root_index else 'source')
                identities.append(validate_directory(fd, self._owner, phase))
            return fds, identities
        except BaseException:
            for fd in fds:
                os.close(fd)
            raise

    def revalidate(self):
        require(not self._closed, 'lease is closed')
        # Recheck both the retained objects and the current pathname from /.
        for index, fd in enumerate(self._fds):
            phase = 'ancestor' if index < self._root_index else ('root' if index == self._root_index else 'source')
            require(validate_directory(fd, self._owner, phase) == self._identities[index],
                    'retained directory identity changed')
        fresh, identities = self._walk()
        try:
            require(identities == self._identities, 'mount source or ancestor was replaced')
        finally:
            for fd in fresh:
                os.close(fd)

    def close(self):
        if not self._closed:
            for fd in self._fds:
                os.close(fd)
            self._fds = []
            self._closed = True

    def __enter__(self):
        require(not self._closed, 'lease is closed')
        return self

    def __exit__(self, *_):
        self.close()
