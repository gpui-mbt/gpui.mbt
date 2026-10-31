# Retained route terminal seal

This experimental API is based on PR #200 at
`53e42a5888167fd9203b27f6558deabaf5c54e4b`. A successful direct cutoff still
allows ordinary keys while the binding is held. Neither cutoff nor an empty
poll establishes safe host shutdown.

## Contract

`RetainedOrderedRoute::seal_destroyed(window, destroyed_native_sequence)`
returns an opaque `RetainedTerminalReceipt` only after these native facts have
been checked in one owner-thread call:

1. The route has no active binding. Cutoff and explicit binding release must
   already have succeeded; a partial begin failure does not qualify.
2. A successful native `destroy_window` recorded the exact window, its
   `Destroyed` sequence and its creation-attempt generation. A close request
   alone does not qualify.
3. The exact native FIFO `Destroyed` record was acknowledged. A foreign,
   duplicate or failed ACK cannot supply this evidence.
4. No window exists, the FIFO is empty and its sequence still equals that
   final record. The generation has not changed or exhausted. An intervening
   window creation attempt that reaches native allocation invalidates the old
   evidence, even if that allocation fails.
5. No direct binding, pressed physical key, key repeat, frame callback, XKB
   compose transaction, retained preview, queued IME payload or active/pending
   IME phase remains. A latched native error also prevents sealing.

On success, the host atomically enters `Quiescing` and records the terminal
seal. New window creation, retained callback dispatch and binding admission
are refused. `Host::stop` remains a separate operation with its existing
native ownership guards. A refused seal does not consume a record, clear an
owner, cancel composition, or change the host state.

The receipt exposes only `window()` and `native_sequence()`. It does not prove
consumer editing-owner reconciliation, action delivery, model reflection or
scene publication. The consumer must prove those stages before discarding its
local ledger or declaring its run complete. Native ACK remains an explicit
consumer operation with the same responsibilities as before this change.

## Validation scope

- `moon test ubuntu --target native --deny-warn --no-parallelize`: 100/100 PASS,
  using MoonBit `0.10.15+943464bfa` and matching core.
- `sh scripts/test_ubuntu_ingress.sh`: five native callback/queue programs
  PASS, including successful terminal stop, close-only refusal, exact ACK
  checks, reopen/failed-creation generations and refusal without mutation for
  unresolved native obligations.
- `python3 scripts/check_contracts.py`: PASS.
- The five native programs also PASS with
  `GPUI_TEST_CFLAGS='-fsanitize=address,undefined -fno-omit-frame-pointer -g'`
  and `ASAN_OPTIONS=detect_leaks=0`. LeakSanitizer was not verified: its first
  run failed because the sandbox could not read another task's `/proc` entry.

These fixtures do not establish live compositor or IBus/Mozc acceptance. The
inherited retained-direct XKB compose/shortcut admission issue reported on
PR #200 remains outside this change: Ctrl/Meta can reset compose before a
FIFO-full shortcut is refused. Shared Settings P1 completion, registry-only
consumer acceptance and merge readiness are not asserted.

## Explicit direct rearm

`begin_after_resolved_cutoff(window, root, released_portable_epoch,
retired_native_sequence)` supports the same-focus direct checkpoint and
close/reopen paths after the consumer has resolved the original owner, all
editing/model actions and the published scene through that exact native ACK
watermark. Ordinary `begin_direct` still requires its original strict
`NoPressObservedSinceFocus` history; no UNKNOWN entry is cleared or reclassified.

The native predecessor records a successful direct cutoff and explicit hold
release, native epoch after disabling, window creation generation, keyboard
focus generation, keyboard/keymap identity and seat. Rearm requires that same
provenance, exact last native ACK and FIFO tail, no unACKed record, no pressed
physical key, no compose/repeat/IME work, and no native error. Ordinary
post-cutoff Enter/Escape records are allowed only through this explicit
consumer-resolved ACK suffix. Successful rearm consumes the predecessor and
creates a fresh native and portable epoch. Every refusal occurs before any
native or portable ownership mutation, including Busy.

Native fixtures cover the full Enter/Escape suffix, retained UNKNOWN history,
one-shot predecessor use, unACKed/held-key/compose refusal, changed owner
generations and real keyboard leave/enter and keymap callbacks. Real focus loss
or keymap replacement invalidates this same-focus rearm; recovery remains
retained and requires a separate fresh-focus policy. This API does not broaden
that policy or establish live IBus/Mozc acceptance.
