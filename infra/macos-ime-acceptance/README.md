# Exact-source Apple Silicon Kotoeri acceptance — test-only

This harness is stacked on the **current active product slice** [PR #89](https://github.com/gpui-mbt/gpui.mbt/pull/89), pinned at its inspected starting commit `451ead8fce495a4ad471b577b06c3442d8165011`. It does **not** revive or merge [PR #40](https://github.com/gpui-mbt/gpui.mbt/pull/40) or modify [PR #45](https://github.com/gpui-mbt/gpui.mbt/pull/45). PR #45's 2026-10-07 failure remains FAIL: Return (keycode 36, dispatch 9) reached the GPView and AppKit `handleEvent:` returned true, but neither `insertText:` nor `unmarkText` committed the text in the existing 200-iteration bound. The old app subsequently exited abnormally, even though an abort receipt reported source restoration and session closure. That is **not** qualification evidence for this code revision.

Only the strict finite IME/screenshot validator is ported from #40. The monolithic pinned actrun/quality profile, unrelated proof/mutation/perf pipeline, historical executable/tested-source patch, and owned host activation wrapper are deliberately **not** copied. The profile now measures the actual arm64 macOS/Xcode/SDK/clang identities and requires a new, externally located evidence directory.

## 1. Portable/static contracts

From a clean branch checkout:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -p 'test_macos_ime_acceptance_contract.py' -v
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -p 'test_*.py'
python3 scripts/check_contracts.py
bash -n infra/macos-ime-acceptance/run.sh
```

These commands do not prove real macOS IME behavior. The additional tests verify that no recorded success can be fabricated by supplying a key receipt without Return callbacks, no Escape cancellation, a missing/old accepted blur frame, an unapplied revision/ACK, changed binary/source identities, or incomplete abort/source-restoration receipts. The historical timeout fixture is expected to be a **negative** control.

## 2. Native Apple Silicon acceptance

Requires an **unlocked, logged-in foreground** Apple Silicon/arm64 desktop, macOS 14+, compatible Xcode CLI tools, current MoonBit CLI, a Japanese Kotoeri RomajiTyping.Japanese source enabled in AppKit, Metal, ScreenCaptureKit permission for the capture helper, and an exclusively owned test window. A hosted macOS build runner without a GUI is insufficient.

Use a clean checkout of this test PR, with its original #89 base as an ancestor. Pass a **fresh path outside the checkout** (the command creates it):

```sh
bash infra/macos-ime-acceptance/run.sh /private/tmp/gpui-kotoeri-<new-unique-run>
```

The script:
1. Verifies arm64/Darwin, a clean worktree, and ancestry from `451ead8`.
2. Runs `script/test_macos.sh --text-field` to test macOS provider/model/ownership contracts and build a fresh test-hook `GpuiTextField.app` in the external run directory.
3. Runs the original finite `nihongo → Space → Return → Escape` app-local CGEvent/NSEvent sequence, with **one Return** and the unchanged **200-iteration** operation cap.
4. Captures three app-PID-bound ScreenCaptureKit images (initial, preedit, blurred final). Retains each PNG and capture geometry; checks accepted frame identities, source/tree/binary hashes, monotonically increasing frame revisions, text ROI pixel differences, all 11 key dispatch receipts, batch ownership, callback counters, and actual presenter ACKs.
5. Verifies app-window `NSTextInputContext.selectedKeyboardInputSource` restoration, explicit `GPUI_MACOS_IME_ABORTED` on error, and normal exit code **0** on a complete run.

Test-hook-only `GPUI_FIELD_MACOS_IME_DISPATCH_TRACE=1` logs `GPUI_MACOS_IME_TRACE` without dumping committed or preedit text. Events include AppKit `handleEvent:` begin/result and fallback, `setMarkedText:`, `insertText:`, `unmarkText`, `doCommandBySelector:`, `firstRectForCharacterRange:`, session fence, pending batch creation, FIFO delivery, revision ACK, and source restoration. Native trace records contain bounded identities/counters and monotonic uptime. `timeline.ndjson` stores runner-monotonic receipt times so an observed timeout can report elapsed real time in addition to iteration count.

Retained paths under the external directory include `build-and-contracts.log`, `acceptance/summary.json`, `acceptance/app.stdout.log`, `acceptance/timeline.ndjson`, `acceptance/initial-window.png`, `acceptance/composition-window.png`, `acceptance/final-window.png`, `acceptance/screenshots-index.json`, and app/host compiler fingerprints. On failure, available partial artifacts and `cleanup` are preserved; do **not** upgrade a source-level or partial input result to Product Green.

## 3. Return root-cause isolation (diagnostic-only)

A second fresh run can isolate whether waiting for the **composition ScreenCaptureKit image** influences Return delivery. Run the normal native provider/model/build stage once, then invoke the already built test-hook app with the same source/keyboard sequence, this time bypassing **only** that composition-image wait:

```sh
GPUI_FIELD_MACOS_IME_DISPATCH_TRACE=1 PYTHONDONTWRITEBYTECODE=1 \
python3 infra/macos-ime-acceptance/ime-acceptance.py \
  --repo . \
  --profile /private/tmp/gpui-kotoeri-<run>/profile \
  --app /private/tmp/gpui-kotoeri-<run>/checks/text-field/build/macos/GpuiTextField.app \
  --output /private/tmp/gpui-kotoeri-<run>/diagnostic-immediate-preview \
  --timeout 120 --diagnostic-immediate-preview
```

`--diagnostic-immediate-preview` intentionally **cannot return GREEN**. It retains the unchanged Return count, current app/code, real Kotoeri routing, and 200-iteration limit, but skips the composition screenshot so the original three-frame acceptance is **UNRUN**. It may finish all native callbacks, or still time out; either way it is not a substitute for the normal run. Do not inject `insertText("日本語")`, increase timeout/iteration count, or claim a successful conversion from a keyDown/keyUp receipt.

For offline inspection of **either** kind of failed log:

```sh
python3 infra/macos-ime-acceptance/diagnostics.py /path/to/acceptance/app.stdout.log
```

Compare `route_begin`, `route_result.handled`, `fallback_invoked`, `callback_marked`, `callback_insert`/`callback_unmark`, `batch_enqueued`, `batch_delivered`, `batch_acknowledged`, and `key_up_done` in order. A handled Return **without** a commit/unmark observation identifies the failing interface boundary but **not** the root cause. If both capture and immediate-preview attempts fail, investigate AppKit input-context lifetime and event-pump behavior; if only capture-based execution fails, investigate capture/command checkpoint blocking first. A matched `NSTextView` control remains an optional **separate** follow-up, not a passing reference substituted for GPView.

## 4. Separate acceptance gates

| Gate | Pass requirement |
| --- | --- |
| Initial frame | Focused app-owned, accepted initial text with retained PNG |
| Composition frame | Actual Kotoeri marked-text update with bound accepted PNG |
| Return commit | One `insertText:`/`unmarkText`-resolved commit, correct `Hello 日本語`, 11 ordered native key receipts |
| Escape cancel | At least one genuine cancellation callback; composition cleared |
| Final blur presentation | An accepted blurred frame **newer than the last ACKed batch**, with retained and validated pixel differences |
| Input source restored | Exact app-context input-source restoration or verified abort restoration receipt |
| Normal cleanup | App exits 0, process reaped; `SIGABRT`/`-6` is **FAIL** even if source restoration was acknowledged |

The summary reports each gate as `PASS`, `FAIL`, or `UNRUN`. It is only fully green if the strict independent artifact validator agrees, the source tree before and after is unchanged, diagnostic trace integrity holds, all required screenshots/pixel-ROI differences are present, and the app exited normally. Current automated CI can check **source/contracts/build only**; macOS Kotoeri / native pixels / cleanup remain **UNRUN** until measured on a logged-in Apple Silicon desktop.

Historical evidence: [#45 result](https://github.com/gpui-mbt/gpui.mbt/blob/ba9648dfb11408289cd1c945df7c377a7878a65e/infra/macos-desktop/evidence/pr40-e2e-20261007/RESULT.md), [Return diagnostics](https://github.com/gpui-mbt/gpui.mbt/blob/ba9648dfb11408289cd1c945df7c377a7878a65e/infra/macos-desktop/evidence/pr40-e2e-20261007/return-diagnostics.json).

## 5. Consolidation of #106 and #107 (2026-10-18)

**Canonical implementation: Draft #107. Draft #106 is superseded.** There is
one collector, host adapter and native instrumentation include, under
`infra/macos-ime-acceptance` and `tests/native/macos_ime_trace.inc`. No second
`infra/macos-desktop` collector is added. The #89 base and immutable #45 FAIL
archive remain unchanged. Live qualification is **UNRUN**.

| Area | #106 at `467303c` | #107 at `8d1868d` | Consolidated #107 |
| --- | --- | --- | --- |
| Collector | Strict historical PNG/ROI/source/binary validator | Same strict evidence, monotonic line receipt timeline | Keep #107 collector and independent artifact revalidation |
| Host | Current identity, macOS 26 minimum | Current identity, Apple Silicon/macOS 14+ | Keep measured #107 OS/Xcode/SDK/clang profile |
| Native trace | Inline opt-in diagnostic probes | Separate test-only bounded trace include; reserved Return/ACK slots | One bounded include; add callback enqueue kind, key entry, frame hash/revision, session close and restoration result/fallback probes |
| Offline diagnostics | Independent gate report | Legacy #45 log interpretation, Return timeout and latency, callback order | Keep #107 diagnostics and import independent gate-report capability |
| Evidence judgment | Return/commit/ACK/blur/restore/cleanup/pixel gates, weak cross-event matching | Strict artifact validator; runtime chronology check | Bind Return 9 and Escape 11 to window/host/session, callback, batch delivery and matching revision ACK; re-read raw trace during retained validation |
| Negative tests | 10 trace/receipt tests | 18 contract tests including historical 200-iteration failure | Both capabilities covered; add foreign ACK/session, suppressed callback, stale frame hash, missing trace and diagnostic-only rejection |
| CI | Dedicated Python checks and test-hook app build | General contracts and macOS build | Dedicated workflow runs focused tests and `script/test_macos.sh --text-field`; existing general CI retained |

The dedicated workflow `.github/workflows/macos-ime-contracts.yml` executes
portable contracts and builds/tests the exact native TextField test-hook path.
It explicitly reports live Kotoeri/pixels/cleanup **UNRUN**. A hosted build
success does not change Draft status or establish IME support.

`acceptance/gates.json` retains independent `appkit_return_route`,
`return_commit`, `revision_ack`, `escape_cancel`, `final_blur_frame`,
`input_source_restoration`, `normal_cleanup`, `window_pixel_frames`, and
`trace_integrity` results. `summary.json` includes those results, while
`validate_summary` re-reads the raw trace and retained pixels rather than trusting
cached gate statuses. An abort restoration witness cannot pass normal cleanup;
truncated/missing native evidence cannot qualify acceptance. Diagnostic preview
runs label successful native witnesses `DIAGNOSTIC_ONLY` and never qualify.

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -p 'test_macos_ime*.py' -v
python3 infra/macos-ime-acceptance/trace_contract.py --summary /path/to/acceptance/summary.json
```

The offline trace command evaluates native witnesses and capture metadata;
full acceptance additionally requires `validate_summary` to revalidate the
current source/host/binary and actual retained ScreenCaptureKit PNG bytes/ROI.
