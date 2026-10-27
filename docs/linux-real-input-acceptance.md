# Linux real-input acceptance boundary

This acceptance lane is separate from layout, headless text geometry and
renderer-only smoke tests. Passing those tests does not establish input E2E.
The runnable catalog is `infra/linux-desktop/fixtures/cases` version 2.

## Direct keyboard route

The existing harness sends real XTest events to an authenticated, isolated Xvfb
server. Weston 14's X11 backend translates those events into actual
`wl_keyboard`/pointer events for the native GPUI application. This is nested
Wayland input, **not** physical evdev/libinput input and not XWayland.
The harness refuses to use the caller's desktop as an input fallback.

Seven supported cases cover typing/Shift, Ctrl+A replacement, directional
selection and deletion, standalone modifiers, undo/redo, redo invalidation,
and focus loss/reentry. Retain `events.jsonl`, raw `app.log` (Wayland delivery),
compositor logs, initial/checkpoint/final PNGs and exact build/runtime manifests.
The read-only observer publishes model state only after accepted presentation;
the runner independently binds it to the completed compositor frame.

The basic six-key case additionally requires the unchanged reviewed full-frame
RGBA golden plus Latin OCR. The other semantic cases require exact model states,
completed frame bindings and nonblank actual captures. Their captures are
**evidence**, not a full per-pixel correctness oracle for every glyph, caret or
selection color. No new capture is automatically promoted to a golden.

Held-repeat is NOT_RUN in the reusable catalog because its adaptive policy
oracle is pending; historical release/focus-loss proof is not a current pass.

## IME is a separate experimental lane

`GPUI_FIELD_WAYLAND_IME=1` selects the existing experimental single-window,
text-input-v1 owner. It requires Weston 14 **desktop-shell**, the synchronous
IBus Wayland adapter and Mozc. The direct-keyboard catalog uses kiosk-shell and
does not activate or qualify this lane. Its IME entry is therefore NOT_RUN,
not proof that all Linux IME implementation is absent.

See `ubuntu-ime.md` and
`../infra/linux-desktop/wayland-ime/GPUI-README.md`. The exact-current IME
acceptance requires real kana preedit, conversion, one commit, cancellation,
atomic undo/redo, blur/refocus, held shortcuts, native protocol/Gio traces and
actual panel show/hide pixels. A newly recovered runtime must be built and
qualified using `wayland-ime/recovery/README.md`; historical partial evidence
cannot qualify a new binary or runtime.

Candidate-table contents/highlight, text-input-v3, other compositors, XWayland,
IME repeat, surrounding deletion, reconversion and arbitrary styling remain
outside the bounded qualified claims. Japanese initial text, paste and mock
callback tests do not establish real IME conversion.

## Current local execution limit

On 2026-10-27 the task's cloud command executor rejected AF_UNIX socket creation
with EPERM, before compositor launch. Native input here is NOT_RUN. No sandbox,
system setting or user desktop was changed to work around that restriction.
The dedicated hosted acceptance job is the reproducible permitted execution
route; each job result must independently retain its evidence and report
PASS/FAIL/NOT_RUN. A green wrapper with missing artifacts is not an E2E pass.
