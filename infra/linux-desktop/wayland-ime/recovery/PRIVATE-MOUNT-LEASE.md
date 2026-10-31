# Private host mount-source lease: unintegrated primitive

A future reviewed execution wrapper needs to check the actual source paths it
will mount. The current unapproved container candidate checker only compares
path strings. `MountLease` is a Linux host-side building block which opens an
owner-only private directory and a selected source directory beneath it by
walking each component with `O_NOFOLLOW | O_DIRECTORY`. It checks the UID and
writability of every ancestor, private root and source component and retains
all file descriptors. `revalidate()` reopens the complete path and compares
device/inode identities, while rechecking ownership and modes on both the
retained and reopened directories. A changed path, replaced ancestor, symlink,
unsafe mode or closed lease is rejected. Closing releases the descriptors.

The private root must be mode 0700 and owned by the designated bounded nonroot
UID. All ancestors must be owned by root or that UID and not group/world
writable; components inside the private root must be owned by that UID and not
group/world writable. The strict ancestor policy rejects sticky `/tmp`; use a
fresh private directory under the reviewed runner path after verifying it.

This primitive is **not wired into the candidate checker or a running wrapper**.
A later reviewed wrapper must establish real source and mount requirements,
keep leases alive, revalidate at its defined transitions, inspect actual Docker
mounts and container identity, and separately validate data and real/effective
UID/GID. Docker consumes pathnames rather than these FDs, so revalidation cannot
remove a replacement race between inspection and Docker's open, or protect
against a same-UID owner, privileged host or daemon. Mount contents can change
without changing directory identity; content verification is a separate gate.
This is not an execution approval, restore, bind, native IME, library closure,
or claim that the proposed isolation is sufficient. Candidate `plan` remains
null, `approved_for_execution` remains false, and native is NOT_RUN.
