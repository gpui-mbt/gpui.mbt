# Hosted IME recovery scaffold (not enabled)

No hosted recipe or approval receipt is shipped, so the proposed workflow fails
closed with `NOT_RUN`. The workflow and orchestrator are proposals requiring
independent final review before publication/execution. Once a reviewed receipt is
explicitly added, the orchestrator downloads and verifies artifacts, restores the
closure, binds the hosted deployment, and calls the existing native harness.
The standalone restore module itself never launches native processes.

A future independently reviewed stage must supply the fixed
`hosted.review.json` and `hosted.recipe.lock.json`, identify the exact preparation
run/artifact/head and SHA-256 digests, review all four build pins, and validate the
download against those identities before calling the restore function. The
receipt also needs `repository`, `review_artifact_id`,
`review_artifact_digest` and `runtime_artifact_digest` (GitHub API archive
digests, including the sha256 prefix), and `prepare_result_sha256`. These
are distinct from the inner runtime tar SHA. Metadata is checked against the
public repository, successful run, exact source head and both artifact IDs before
download and again before restore. No digest is promoted into an approval
automatically. Candidate
source remains the preparation checkout; the independently reviewed IaC checkout
may have a newer commit. The constructor checks the candidate SHA/tree, exact
restored paths, declared container identity, source/tool pins and runtime closure.
The container identity environment variable is a binding check, not remote
attestation; the workflow must itself pin that image.

Restore validates every archive member before creating the fresh exact root.
Files and directories precede symlinks. External symlink targets require an exact
reviewed allowlist and are never rewritten. Hardlinks are currently rejected;
support, if required by an observed archive, needs separate bounded validation.
No unreviewed closure is automatically approved.

## Historical recipe compatibility

The original `recipe.lock.json` is intentionally unchanged. It pins the original
constructor bytes, so historical recovery requires its original matching source
checkout. The modified hosted-aware constructor in this branch is **not**
compatible with that historical source hash. Legacy selection remains the
default and fails closed on a source mismatch; do not update old pins to make it
pass. The hosted recipe must separately pin the final reviewed constructor and
hosted verifier.

The unit tests use synthetic artifacts and mock the existing source/runtime
verifier. Their passing result is neither real IME E2E nor permission to execute.

The workflow uses only the ephemeral read-only GitHub Actions token to retrieve
public artifact metadata/downloads; no user secrets are required. The native
child environment excludes that token. A qualified-partial harness result stays
qualified-partial and exits 2, rather than becoming a green full acceptance.
Input traces, frames and cleanup proofs are validated by the existing harness;
its output and logs are always uploaded through one evidence-directory path.
