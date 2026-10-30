# Execution container candidate: fail-closed preview

`execution-container.candidate.json` pins the unapproved image review and its
image ID. Its execution plan is deliberately `null`. `check_execution_container.py`
therefore rejects the actual candidate until a separately reviewed, complete plan
and a new pinned receipt are prepared. The script accepts Docker inspection JSON
only; it never creates or starts a container, extracts a runtime, binds a
closure, or authorizes native execution. A matching test fixture is not a live
container and always reports `native_status: NOT_RUN` and
`approved_for_execution: false`.

The proposed inspection checks a supplied full container ID, exact configured image, inert state, configured
container user/command, complete environment, exact bind sources, destinations,
write modes and propagation, and a restrictive isolation profile. It rejects
credentials and proxy variables through an environment allowlist and rejects
unexpected injected variables. The local Docker client is known to inject proxy
variables; a future wrapper must explicitly address that before this check can
pass. No proxy value is logged. The offline profile is an intentionally narrow
starting point for review, **not** evidence that the existing executor works
without network. The old executor separately calls GitHub's metadata API; a
future reviewed design must authenticate metadata before an offline phase or
specify and review another secure arrangement. Simply weakening the check is not
a proof of an equivalent execution environment.

The historical workflow starts as root, installs dependencies and creates a
fresh account, then runs as `gpui-ime-ci`. The candidate image and future actual
execution wrapper have not established an equivalent account or mount layout.
The configurable Docker `User` is not the UID/GID of the native process. The
old nonroot helper derives the latter from the owner of the runner temp and
checkout directories, checking both real/effective IDs and supplementary groups.
A future design must prove that identity in the actual task and re-establish the
required directory and metadata checks. No UID from a previous run is a pin.

Inspection alone cannot establish receipt authenticity, source directory
ownership, symlink/TOCTOU safety, daemon trust, the later container identity,
account setup, runtime restore, bind, app revision, or native operation. The
standalone CLI pins the checked-in incomplete receipt and review digest, so
editing the receipt is rejected. Its pure helper is usable with synthetic plans
for tests only; its caller must not treat arbitrary plan matching as authority.
The eventual wrapper must bind the fresh ID to the container it created; it cannot
be a static receipt pin. The actual container, runtime artifacts and wrapper require independently
reviewed same-revision pins and a separate explicit approval before execution.
