# Immutable-host recipe candidate: review only

The old hosted recipe still names the historical mutable Debian container and
continues to fail closed if its source pins do not match. It is not modified.
`image.recipe.candidate.json` copies that recipe, changes exactly the two
source hashes for the #174 read-only validation refactor, and records the new
image tar and config ID. The separately pinned
`image.review.candidate.json` is explicitly `approved_for_execution: false`
and `native_status: NOT_RUN`. No historical approval is transferred.

Run `python3 check_candidate_recipe.py` from this directory or the repository
root. It checks the candidate receipt's exact bytes, the historical receipt,
recipe and image-candidate digest chain, the image and runtime identities,
the complete 44-file source closure, and that only those two source hashes,
the candidate scope and image identities differ from the historical recipe.
A match is review preparation, not an execution approval or live test. The
checker has no archive/image input and does not load, extract, restore, bind,
create a container or execute an app. The read-only artifact checks and
unstarted image inspection remain separate steps in #170, #171 and #174.

The two source changes and their required independent review are:

| Path under `infra/linux-desktop` | Old SHA-256 | Candidate SHA-256 |
| --- | --- | --- |
| `tests/test_hosted_restore.py` | `3b6de7a1a803eaa6dd7c8886dd44facb84508fd8afce169540a3161e11b4b37a` | `a19e7de26623c1a88a86d644641b89d578c91c4d55d9380cdc3e5980f5a7abfe` |
| `wayland-ime/recovery/hosted_restore.py` | `d5387d50b1b5545f73898f12c16031c31ba04fc8fd8ab6745dba5317371647bd` | `663cd250cc522335055fb4e50db678bb2270cd01b1b9eca845480c3d6cd4b09c` |

The candidate receipt identifies source baseline #174
`e74e1c1ce0189288902628899b14baf317f36e1b`; the separately pinned app remains
`825d99d499bf02bdf1d232827261043b38a6cdeb`, not the checkout running the
checker. The immutable image is a new environment, not proof of old-run host
byte equivalence. `scope` and the new image fields distinguish this recipe from
the historical one. The pinned base revision is not the final head of this
change; final-HEAD CI and independent review must cover the checker, candidate
files, and any later execution wrapper.

Actual restore/bind/launch remains unimplemented for the candidate: the
existing executor accepts only the historical receipt and container. A later
change must bind the *actual execution container* and its restricted mounts to
the verified image ID, use a separately reviewed recipe and receipt, retain the
existing per-member restore checks, and pin the complete execution wrapper.
The current fixed candidate cannot be approved by flipping its flag: that
changes its pinned bytes and the checker rejects it. A fresh reviewed receipt
and pinned executable path are needed before any native run. Candidate table,
physical keyboard, kernel, ABI and new app acceptance remain separate.
