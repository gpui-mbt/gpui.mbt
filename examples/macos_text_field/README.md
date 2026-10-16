# macOS single-line text field

This native example connects the shared immutable `TextField` model to the
macOS CoreText/CoreGraphics text path and AppKit editor callbacks. It is a
bounded, experimental, single-line, left-to-right monochrome control. Selection,
horizontal scrolling, clipboard commands, undo/redo, revision fencing and frame
rollback use the same portable control state as the Linux example.

Ordinary committed text uses AppKit's resolved `insertText:` callback. The
per-window Japanese composition owner is disabled by default. Enable it for a
local run with:

```sh
GPUI_FIELD_MACOS_IME=1 GPUI_FIELD_MACOS_E2E_STATE=1 \
  ./script/build_and_run.sh --demo text-field
```

The IME session begins after the window receives native key focus. An
interactive opt-in run keeps the accepted field frame open while waiting for
that transition; the finite acceptance run uses a bounded wait and cleanup.

The synthetic-only observer writes one flushed `GPUI_FIELD_MACOS_STATE` JSON
line only after an accepted frame. It includes document/selection/focus and
composition state, the rounded caret rectangle, session epoch and commit
count, plus the source revision/tree and built executable SHA-256 injected by
the run script. `field_bounds` is in logical content-view coordinates with a
top-left origin, matching the scene viewport; the observer does not multiply
by backing scale. It cannot inject input or change the field. Keep the text
synthetic because the observer includes the complete document in stdout.

The opt-in owner applies one ordered native batch against its acknowledged
session and field revision, then acknowledges the new snapshot before the next
native dispatch. Duplicate/old batches, stale epochs, unsupported replacement
metadata and unsupported styles are rejected. Rejected edits restore the last
accepted field value and fence the native session; focus loss ends the session.
Empty preedit cancels and restores the original selection, while a later empty
commit remains a real deletion.

Use `./script/test_macos.sh --text-field --target-dir <fresh-external-directory>`
for the provider/owner tests and a test-hook app build.

## Live IME acceptance (not yet qualified for this slice)

The historical native actrun profile, including `infra/macos-desktop/profile.py`,
`infra/macos-desktop/actrun-feedback.py` and
`infra/macos-desktop/ime-acceptance.py`, is retained on
[the source PR #40](https://github.com/gpui-mbt/gpui.mbt/pull/40).
**Those files are deliberately excluded from this PR #89 branch.** Do not
execute the historical profile as though it tested this slice, and do not
report old screenshots, source hashes or a 6/7 partial run as a pass.

To qualify PR #89, restore/rebind the native acceptance harness to this exact
source revision in a separate test-only integration, rebuild the app from the
same revision on an unlocked Apple Silicon Mac, and record source/tree/binary
hashes, Kotoeri input callbacks, accepted frame revisions, and screenshots.
The assertions for Return commit, Escape cancellation, final blurred frame,
context source restoration and cleanup must remain strict; missing callbacks
or failed acceptance keep the native IME gate red.

The real IME step requires a logged-in desktop with the Japanese Kotoeri source
enabled. The test hook selects it only on this app window's NSTextInputContext
and restores that context's previous source after the run. If capture or input
validation fails, the runner sends `abort`; the app fences the editor, restores
the source and emits a `GPUI_MACOS_IME_ABORTED` cleanup receipt. Its retained
screenshots and strict JSON summary are runtime evidence;
source-level owner checks do not count as an IME pass. This bounded path does
not change the portable TextInput capability, the macOS support tier or
production release gates.

The acceptance app is launched by the runner as
`GpuiTextField.app/Contents/MacOS/GpuiTextField --ime-acceptance`. It prints an
accepted `initial-ready` checkpoint, waits for `begin`, then sends a deterministic
`nihongo` + Space conversion. It waits for the runner's screenshot at the
`composition-ready` checkpoint before Return commits `日本語`, then verifies an
Escape cancellation and blur fence. The runner sends `quit` after the final
accepted-frame screenshot. Checkpoints and the final record include the field
bounds; the initial checkpoint also carries native content origin/size and
window size so capture ROI can be mapped without guessing the titlebar offset.
The records bind window, host, session, FIFO batch, frame, source-tree and
executable identities.

Control, color-font, bidirectional, multiline and reconversion metadata are
typed failures. Emoji and other color-glyph fallback are not included in this
monochrome path.
