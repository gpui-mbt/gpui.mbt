# GP-01B — native text host seam

Status: open — macOS implementation shipped and consumed. `platform/macos.Host`
implements `TextInputHost` with an epoch-tagged ordered queue, and the Yami
native adapter (`f4ah6o/yami_kumo_native/ui`) imports `text_host` and applies
observations through `Mounted::text_input`. Linux and Windows keep their
host-local editor sessions. No real IME profile is claimed.

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
- No Linux or Windows native implementation in this packet.
- No `controls/dialog` package.
- No claim that a headless fixture proves Japanese IME or candidate placement.

## 4. Verification

- `moon test text_host --target all --deny-warn` (headless transport fixture).
- `moon check --target all --deny-warn`.
- `moon test platform/macos --target native` (record decoding and epoch bounds).
- `script/test_macos.sh` (real `NSTextInputClient` callbacks through the test hook).
- `python3 scripts/check_contracts.py` (new package edge and required manifest).
- Existing `text_session`, `controls/text_field` and `element` tests stay green.

## 5. Acceptance

- [x] The new package is reachable from a non-test adapter without importing a
      native host package. (Yami `native/ui` imports `text_host` and exposes
      `Mounted::text_input`; no host package import is involved.)
- [x] Epoch, sequence and window are preserved in every event; a stale epoch is
      rejected by the host contract.
- [x] `Capability::TextInputGeometry` is independent of `TextInput` and is not
      advertised by hosts that cannot report reliable geometry.
- [x] The transport fixture proves ordered delivery and end/cancel ownership,
      not OS behavior. The macOS E2E proves the same ordering through AppKit
      callbacks; synthetic composition is not an IME pass.

## 6. 2026-10-30 — cross-kind order and unresolved end boundary

The Ubuntu legacy two-poll route can absorb a text record while polling for a
platform record and return the latter first. A draft candidate adds a separate
opt-in single-poll ordered route without changing the legacy API. Its scope is
the order of records copied from the Ubuntu editor stream; it does not establish
that an IME has stopped producing records. A host end boundary that preserves
already-observed commits before revocation, the adapter's pending `TextSession`
resolution, and live IME evidence remain open. macOS and Windows are not
covered by the candidate's ordering guarantee. Yami's concrete focus-loss
failure and reproduction are tracked in
[Yami PR #83](https://github.com/f4ah6o/Yami-kumo/pull/83).

The Ubuntu host has an earlier boundary too: `keyboard_leave` calls
`ime_invalidate`, which advances the native epoch before the editor queue is
read. `ime_queued_stale` then discards a previously accepted unread commit;
neither ordered nor legacy portable polling can recover a record already
discarded there. This does not imply that callbacks received after invalidation
are valid. See [0028](0028-wayland-ime-composition-handoff.md) for the native
fixture and lifecycle work needed to distinguish accepted old-owner records
from genuinely stale callbacks. Coordinate its host end-boundary contract with
the adapter's pending `TextSession` resolution; a one-time empty poll is not a
completion signal.
