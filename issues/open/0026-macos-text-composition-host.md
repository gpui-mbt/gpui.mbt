# 0026: macOS text composition host

Status: bounded implementation / real IME qualification open
Updated: 2026-10-19

## Goal

Expose an opt-in, document-owner composition transport on the macOS native
host so applications can accept AppKit input-method text without adopting a
full editor. The host publishes `Start`, `Update`, `Commit`, and `Cancel`; the
application owns the document, selection, undo history, and rendering.

## Implemented

- `primitives.CompositionEvent` and `platform.EventKind::Composition`.
- `Host::set_text_composition`, `Host::set_text_composition_caret`, and
  `Host::finish_text_composition`.
- `GPView` conforms to `NSTextInputClient`. Non-Command key events route through
  `interpretKeyEvents` while composition is enabled; Command chords remain normal
  key events.
- Preedit and commit bounds, UTF-16 cursor validation, candidate-window caret
  geometry, and Enter/Escape resolution for marked text.
- `Host::post_test_composition` drives the same native callbacks in the opt-in
  native E2E.

## Evidence

- [Native E2E](../../tests/native/macos_e2e.m) covers start/update/commit/cancel,
  a printable key through `interpretKeyEvents`, Enter commit without a duplicate
  application key, and Escape cancel without a duplicate Escape.
- [macOS guide](../../docs/macos-native.md) and
  [status](../../docs/status.md) record the bounded scope.

## Open

- Real Japanese Kotoeri qualification. The opt-in `GPUI_MACOS_REAL_IME=1` path
  selects Kotoeri on the window input context, but the headless test harness
  cannot make its process the active application. The result is reported as
  NOT RUN, not a pass.
- Candidate-window placement across multiple displays and Retina scales.
- Reconversion, attributed replacement ranges, clause styling, and a full
  editor/selection/undo contract. These remain application or later-packet work.
- Windows/Linux/X11 composition clients. The event value is platform-neutral,
  but this increment implements only macOS.

## Constraints

- Do not add application-specific concepts to the composition value.
- Keep composition disabled by default and preserve the previous key path when
  it is disabled.
- Do not claim Japanese IME support until a real input-method run is recorded.
