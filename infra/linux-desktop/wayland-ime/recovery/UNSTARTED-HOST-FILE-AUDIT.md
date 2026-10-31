# Unstarted image host-file comparison

This bounded, diagnostic check compares the immutable candidate image's files
for all `host_executables` and host-located `build_tools` in the pinned,
unapproved candidate recipe. It includes `/usr/bin/convert` and three build
helpers beyond the earlier three-executable image-build comparison. The
workflow verifies the fixed image artifact metadata and source run, while the
script verifies the full candidate recipe and source pin chain, image tar and
image configuration ID. It loads that image, creates but never starts an
isolated container, uses `docker cp -L` to read each target, and reinspects the
same container before removing it. Each output row includes the path, expected
and observed SHA-256 and match. The checker fails if any row differs.

`docker cp -L` follows symlinks in the container filesystem, matching the
existing `Path.read_bytes()` host executable hash semantics. Docker's local
daemon, the source checkout and its image store are trusted. This inspection
has a per-copy size and time bound and rejects multiple members, links or paths
in the output tar. It does not inspect shared libraries, live bind mounts,
kernel/ABI, actual UID/GID, transient modifications or any later container.
A byte match is not approval and does not prove runtime restore, bind, live IME
or candidate-table acceptance. Results explicitly retain `native_status:
NOT_RUN` and `approved_for_execution: false`; an interruption is incomplete.

The downloaded image is a different environment from the 2026-10-30 failed
run. Its `/usr/bin/convert` byte result cannot retrospectively establish that
old run's actual bytes. The pinned runtime app source remains
`825d99d499bf02bdf1d232827261043b38a6cdeb`, not current Shared Settings.
