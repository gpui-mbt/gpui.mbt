# GP-01B — native text host seam

Status: open — macOS route implemented. `@macos.Host` implements
`text_host.TextInputHost` and the portable `text_adapter/` consumes it into
`text_session`/`TextField`; Ubuntu, Windows and X11 still return
`UnsupportedCapability`. Synthetic AppKit evidence exists; real Japanese IME,
real window-focus acquisition and candidate placement remain `NOT_RUN`.

Priority: P1
Decision date: 2026-10-19
Parent: [M3 coordination](20261019-m3-textfield-dialog-coordination.md)
Depends on: GP-01A (`text_session/`, merged)
Unblocks: GP-02-L/W/M, Yami YK-06, native Dialog work

## 1. Problem

`text_session/` supplies the portable live composition transaction, but it has no
transport edge: `platform.Backend` intentionally knows only windows, frames and
general input, and no host or example imports `text_session`. A native TextField
therefore cannot move an OS preedit/commit/cancel observation into the existing
`TextField`/`TextSession` model through a public API.

## 2. Scope

Add an optional `text_host/` package:

- `TextInputHost` with `begin_text_input`, `update_text_input`,
  `cancel_text_input`, `end_text_input`, `next_text_input`.
- `TextInputState` with the committed `TextDocument`, logical caret rectangle,
  and an optional display-only `TextPreedit`.
- `TextInputEvent` with `window`, `sequence`, `epoch`, and `TextInputEventKind`
  (`Preedit`, `Commit`, `Cancel`, `Geometry`, `FocusLost`).
- `Capability::TextInputGeometry` in `platform`. `TextInput` already exists.

The `Backend` trait does not change. A host that does not implement
`TextInputHost` continues to return `UnsupportedCapability` for text routes.

## 3. Non-goals

- No second text value model, history, focus model or shaping engine.
- No native implementation in this packet itself. The macOS route landed
  separately as GP-02-M (`platform/macos/text_host.mbt` + `text_adapter/`).
- No `controls/dialog` package.
- No claim that a headless fixture proves Japanese IME or candidate placement.

## 4. Verification

- `moon test --package f4ah6o/gpui/text_host --target all --deny-warn` (headless
  transport fixture).
- `moon test --package f4ah6o/gpui/text_adapter --target all --deny-warn`
  (fake-host adapter fixture).
- `moon test --package f4ah6o/gpui/platform/macos --target native --deny-warn`
  (epoch/order/focus state machine with a private transport fake).
- `moon check --target all --deny-warn`.
- `python3 scripts/check_contracts.py` (new package edges and required manifest).
- `./script/test_macos.sh` — builds the test-hooks dylib and prints
  `GPUI_MACOS_TEXT_HOST {...}` from the synthetic AppKit route; real Kotoeri and
  real window focus stay `NOT_RUN`.
- Existing `text_session`, `controls/text_field` and `element` tests stay green.

## 5. Acceptance

- [x] The new package is reachable from a non-test adapter without importing a
      native host package (`text_adapter/` imports only `text_host`).
- [x] Epoch, sequence and window are preserved in every event; a stale epoch is
      rejected by the host contract. A synthesized `FocusLost` uses a documented
      negative sequence that cannot collide with native per-window sequences.
- [x] `Capability::TextInputGeometry` is independent of `TextInput` and is not
      advertised by hosts that cannot report reliable geometry (macOS advertises
      `TextInput` only).
- [x] The transport fixture proves ordered delivery and end/cancel ownership,
      not OS behavior; the native E2E adds synthetic AppKit callbacks only.
