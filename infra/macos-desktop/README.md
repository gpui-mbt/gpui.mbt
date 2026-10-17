# Apple Silicon Kotoeri acceptance — test-only stacked PR for #89

Active implementation: https://github.com/gpui-mbt/gpui.mbt/pull/89 at
`451ead8fce495a4ad471b577b06c3442d8165011` (base revision).
Historical implementation: https://github.com/gpui-mbt/gpui.mbt/pull/40.
Historical failure archive: https://github.com/gpui-mbt/gpui.mbt/pull/45.
**#45 remains FAIL.** No historical screenshot or tested-source.diff is reused.

This restores the #40 finite 3-frame ScreenCaptureKit collector and strict source,
binary, session, batch/ACK, callback and pixel validators. Unlike the old full
actrun stack, `profile.py` is only a host-identity adapter; no pinned
toolchain, mutation/proof pipeline or historical data has been imported.
`platform/macos/native.m` adds diagnostic probes only when built with
`GPUI_TESTING` *and* run with `GPUI_MACOS_IME_TRACE=1`. They do not
log text content and do not change the normal product runtime.

## 1. Static contracts — no GUI required

    python3 -m py_compile infra/macos-desktop/ime-acceptance.py infra/macos-desktop/profile.py infra/macos-desktop/trace_contract.py
    python3 -m unittest discover -s infra/macos-desktop/tests -p 'test_*.py'
    bash -n infra/macos-desktop/run.sh

These checks cannot qualify live IME.

## 2. Live Kotoeri — real logged-in Apple Silicon

Requires macOS 26+, unlocked interactive desktop with active key window,
Kotoeri Romaji Japanese/Hiragana mode, Xcode CLI tools, MoonBit and
Screen Recording permission for ScreenCaptureKit. On a clean checkout of the
test-only PR HEAD, supply a **new absolute directory outside the checkout**:

    ./infra/macos-desktop/run.sh --output-root /private/tmp/gpui-kotoeri-new-run --expected-head "$(git rev-parse HEAD)"

The entrypoint performs isolated native model/provider tests, compiles a fresh
`--test-hooks` app, runs the old strict live collector against the *current*
source, and writes `acceptance/summary.json`, `acceptance/gates.json`,
`app.stdout.log`, 3 own-window screenshots, screenshot index, native
callback trace, toolchain identity, source commit/tree/patch, library and
binary SHA-256 and cleanup receipts.

Independent gate statuses: `appkit_return_route`, `return_commit`,
`revision_ack`, `escape_cancel`, `final_blur_frame`,
`input_source_restoration`, `normal_cleanup`, `window_pixel_frames`.
A missing native stage is `UNRUN`, an observed failure is `FAIL`.
An acknowledged abort may prove source restoration but is **not** normal
cleanup. Product PASS requires both collector/validator success and every gate
PASS. A source-hash mismatch fails closed.

## 3. Comparison A — diagnostic, never acceptance

    ./infra/macos-desktop/run.sh --output-root /private/tmp/gpui-kotoeri-preview-run --diagnostic-preview-first

The collector immediately replies `preview` to composition-ready rather
than waiting for a screenshot. Only that blocking collector wait changes.
The same key generator, single Return, callback/ACK logic and finite bounds
remain. It always exits nonzero with `DIAGNOSTIC_ONLY` and no E2E PASS,
even if Return then commits. Use separate fresh output directories for the
ordinary strict run and this comparison, at the same source revision.

## 4. Diagnosing historical Return failure

Trace sequence + monotonic time distinguish keyDown/keyUp, actual
`NSTextInputContext.handleEvent` and `interpretKeyEvents` fallback,
`NSTextInputClient` insert/setMarked/unmark entry, callback enqueue,
native batch/owner revision ACK, frame presentation, input-source restore
and session end. Return `handleEvent=true` means event consumed, *not*
commit succeeded. PR #45 logged Return dispatch but no commit/unmark
callback, an idle ACK state, 200 iterations and abnormal SIGABRT cleanup.
These observations remain failures. This harness does not claim their cause
is identified or fixed.

Control B (an unchanged `NSTextView` under the identical CGEvent-backed
producer and input source) is a **recommended follow-up experiment, not yet
implemented or executed**. Never substitute direct synthetic insertText,
repeated Return or arbitrary extended timeouts to force a PASS.

## 5. Limitations

GitHub-hosted macOS can compile this test-hook binary but does **not**
offer this run's qualified logged-in Japanese desktop. Its native Kotoeri,
pixels and cleanup are `UNRUN`. The mini host adapter records the actual
Xcode/compiler/SDK/OS fingerprint but does not claim to pin and reproduce the
full original #40 actrun machine image. GitHub CI build PASS is separate
from live acceptance PASS.
