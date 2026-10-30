# New host image: proposed recovery binding, not execution approval

## Evidence and boundary

The host image candidate produced by [run 41074635858](https://github.com/gpui-mbt/gpui.mbt/actions/runs/41074635858)
is a new environment; no prior native run establishes the equivalence of its
library bytes or configuration to the old host. Its build used Debian's signed
2026-10-27 snapshot and checked the two fixed InRelease hashes. Historical
expiry is disabled only for those dated repositories; this is a frozen test
profile, not a security-update channel. The image ID is
`sha256:5b73c045b4652bae33ed9d37229bf3d261ab1a5b33e124e55ad279a97c133645`.
Artifact `12987002222` has GitHub ZIP digest
`sha256:4e06934ee0fa482712802a1e94b14728b4988c1cb8d2804cac9e5973bf34986f`.
The image tar SHA and its image-config binding must be independently checked
before use. An image content digest is not a publisher signature.

The saved image fixes its own files, including installed binaries, libraries,
fonts and configuration. It does not fix the host kernel, container runtime,
mount contents, external archive, actual device input, GPU/driver behavior or
application revision. The previously reviewed runtime archive is separately
identified by run `40438828021`, artifact `12704943291`, ZIP digest
`sha256:214cc925cc05372bffa0619b9d6a33a18deb0f42598e54a37bc658652a56f9f6`,
and app source `825d99d499bf02bdf1d232827261043b38a6cdeb`. The image was
prepared without restoring that archive or running its application.

## Proposed binding and review gates

1. Preserve the historical receipt and recipe. Add a distinct candidate receipt
   for the new image; record the image run, artifact ID, ZIP digest, tar SHA,
   image ID, Dockerfile and source HEAD, signed snapshot metadata, separately
   reviewed runtime archive identities, and the exact IaC and app source SHAs.
   Set `approved_for_execution` to false until a named independent review has
   examined the complete final receipt, source and artifact identities. Do not
   copy the old receipt's approval to this image.
2. On the Actions runner, validate the fixed artifact's GitHub run, HEAD, ID,
   ZIP digest and expiry, then download it and verify the tar SHA. Load only
   that tar into a fresh local Docker daemon; verify the resulting immutable
   image ID against the receipt. A string environment variable alone does not
   prove which image is running. Pin the image by ID for container creation and
   record the observed ID; fail before native execution on any mismatch.
3. Independently validate and restore the existing fixed runtime archive and
   inventory with the existing per-member hash, ownership, path and symlink
   checks. Recreate the exact nonroot account and private owned roots required
   by the existing recovery code. Any bind mounts must be limited to explicit
   fresh evidence, source and runtime roots; record their identities and modes.
   The image must not silently substitute another app, profile or archive.
4. Adapt the existing orchestrator for the new image identity without weakening
   any historical source pin or receipt. Keep GitHub metadata revalidation and
   remove credentials from the native child environment. Review whether the
   current container path, task-owner and `GPUI_CONTAINER_IMAGE` checks can be
   reused or require a separate typed image receipt; preserve fail-closed
   behavior for an unknown image, stale source, changed files or partial restore.
5. Before any native launch, independently review the final workflow, image
   artifact identities, the new receipt, library/configuration provenance and
   unchanged runtime archive. Run focused adversarial tests for image/tar/receipt
   mismatches, an unreviewed receipt, mount or UID drift and failed restore.
   A new final-HEAD gpt-6.1-sol/xhigh review and required CI remain separate from
   the earlier source-pin or snapshot reviews.
6. Run the existing native scenario only after that review. Retain the exact
   image ID and tar digest, runtime archive digest, IaC/harness HEAD, app source
   SHA, binary SHA, dependency locks, kernel/OS architecture, command, result,
   run URL and artifact digests. The current candidate-table gate remains false
   until independently correlated lookup, visible rows, selection and dismissal
   evidence is implemented. A partial transport result is not full acceptance.

This proposal makes no change to the active receipt, native execution workflow,
candidate-table gate or user-facing capability claim. No app or IME was run by
the image preparation job. The image audit and its tar digest are pending until
their separate read-only workflow completes.
