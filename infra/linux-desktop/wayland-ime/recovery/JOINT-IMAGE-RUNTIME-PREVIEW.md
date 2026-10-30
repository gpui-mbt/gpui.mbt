# Joint immutable-image and runtime preview

This prepare-only step combines the earlier unstarted image inspection (#171),
read-only runtime member audit (#174) and candidate recipe pin check (#179) in
one invocation. It first checks the fixed unapproved candidate receipt, its
candidate and historical recipes, the 44 IaC source files, image identity and
runtime/prepare identities. It then loads the verified image through the same
open descriptor, rehashes it, creates an inert and isolated container by exact
image ID, and inspects that container. While that *same unstarted container*
exists, it validates every runtime archive member through the already-open
runtime descriptor, then rehashes the runtime and re-inspects the container.
Finally it removes the created container, including on member-validation error.

The result is always `native_status: NOT_RUN` and
`approved_for_execution: false`. The preview never starts a container, mounts
or extracts the runtime, binds a deployment, or runs an app or IME. The test
container has `/bin/false` as entrypoint and no mounts; it is deliberately not
the future execution container. Docker's local daemon and the isolated runner
are trusted. Pre/post hashing through an open descriptor detects ordinary file
changes but is not an atomic immutable snapshot against a concurrent writer
that can mutate and restore bytes between reads. This check does not prove the
identity or restrictions of a later container, kernel, ABI, mount contents or
any native acceptance.

The workflow checks the fixed artifact IDs, names, SHA-256 service digests,
expiry, run IDs, heads and successful source-run status before downloading.
The runtime is separately pinned to app source
`825d99d499bf02bdf1d232827261043b38a6cdeb`. It is not a binary built from the
IaC or Shared Settings HEAD. Artifact API digests and local tar hashes have
different scopes. Candidate-table proof remains independent and incomplete.

A future execution step still needs a separately reviewed execution receipt,
the actual running-container identity and mount/UID checks, strict restore and
bind, all wrapper/source pins and their same-HEAD independent review. The
unapproved candidate receipt is fixed by its digest and cannot be promoted by
editing `approved_for_execution`. Historical approval is evidence for the old
runtime, not permission for the new image. This preview does not authorize that
future step.
