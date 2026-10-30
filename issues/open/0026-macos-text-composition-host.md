# 0026: macOS text composition host

Status: bounded implementation / real IME qualification open
Updated: 2026-10-30

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
- `platform/macos.Host` implements the public `text_host.TextInputHost` over an
  epoch-tagged ordered queue; see [text host contract](../../docs/text-host-contract.md).

## Evidence

- [Native E2E](../../tests/native/macos_e2e.m) covers start/update/commit/cancel,
  a printable key through `interpretKeyEvents`, Enter commit without a duplicate
  application key, and Escape cancel without a duplicate Escape.
- [macOS guide](../../docs/macos-native.md) and
  [status](../../docs/status.md) record the bounded scope.
- The Yami-kumo native TextField sample recorded Kotoeri preedit, commit
  (`日本語`), committed document and candidate visibility as PASS on
  2026-10-21 using synthetic HID posting. See the
  [proof description](https://github.com/f4ah6o/Yami-kumo/blob/4405de81b231967388feddde08958d0786b03639/tests/native-ui/README.md#text-field-ime-proof).
  The checked-in description does not identify that run's app source SHA,
  binary digest, dependency lock, or evidence artifact digest, so it is a
  historical observation, not an exact-source acceptance of current HEAD or
  the shared TextField/Dialog flow. Its current driver identifies candidate
  visibility from window metadata and a small-floating-window heuristic; it
  does not verify candidate rows, selection, or dismissal.

## Open

- Exact-source Apple Silicon Kotoeri qualification of the shared consumer's
  edit, validation, Dialog confirm/cancel and focus-restoration flow remains
  NOT_RUN. The native E2E's opt-in `GPUI_MACOS_REAL_IME=1` path cannot make
  its process the active application in the headless harness; the separate
  Yami observation above does not change that result.
- Candidate-window placement across multiple displays and Retina scales.
- Reconversion, attributed replacement ranges, clause styling, and a full
  editor/selection/undo contract. These remain application or later-packet work.
- Windows/Linux/X11 composition clients are separate from this macOS increment.
  Windows and Wayland have since gained opt-in routes with their own qualification
  requirements. Handoffs:
  [Windows 0027](0027-windows-ime-composition-handoff.md) and
  [Wayland 0028](0028-wayland-ime-composition-handoff.md). X11/XIM remains out of scope.

## Constraints

- Do not add application-specific concepts to the composition value.
- Keep composition disabled by default and preserve the previous key path when
  it is disabled.
- Keep live input-method observations, synthetic callbacks, candidate
  placement, physical input and exact-source consumer acceptance separate.
