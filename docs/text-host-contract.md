# Native text host contract (GP-01B)

Status: additive contract in `text_host/`. The macOS AppKit host implements it
and a portable `text_adapter/` consumes it; Ubuntu, Windows and X11 keep
returning `UnsupportedCapability`. A host that provides the trait still needs an
exact-source runtime profile before it can claim text or IME support. The macOS
route has synthetic `NSTextInputClient` evidence only; real Kotoeri/IME stays
`NOT_RUN`.

## Why this package exists

`text_session/` owns the portable live composition transaction: window/root/field
generations, preview/commit/cancel ordering, revisions and observed-end
resolution. It intentionally has no OS transport. `platform.Backend` owns
windows, frames and general input, and must remain usable by hosts that provide
no text input at all.

`text_host/` is the optional transport seam between those two boundaries. A host
implements `TextInputHost`; an application adapter feeds the ordered observations
into `TextSession` and keeps the existing `TextField` as the value model. The
package does not duplicate `TextSession`, `TextField`, shaping, or accessibility.

## Host obligations

`TextInputHost` is separate from `platform.Backend`. Implementing it is opt-in;
`Backend` implementations keep their current methods and error behavior.

- `begin_text_input(window, root)` starts one session for an owned window/root
  and returns a positive epoch.
- `update_text_input(epoch, state)` replaces the owner state and returns the
  current epoch. A replacement may advance the epoch. The state carries the
  committed `TextDocument`, the logical caret rectangle, and an optional
  display-only preedit.
- `cancel_text_input(epoch)` cancels the active composition and returns the
  replacement epoch. It does not commit the preedit. The returned value is the
  only valid epoch for later calls; a host is not required to increment it.
- `end_text_input(epoch)` revokes the session. Repeated or stale epochs are
  rejected by the host.
- `next_text_input(timeout_ms?)` drains one ordered observation. A timeout is
  `Ok(None)`, not an error.

An epoch is host-issued and never reused across sessions. Numeric values are
diagnostic; callers must retain the exact value returned by the host. A host
must reject a stale window, root, epoch, sequence, or replacement before it
publishes a document or acknowledges a commit.

## Event values

`TextInputEvent` carries `window`, `sequence`, `epoch` and `kind` so an adapter
can reject a record from a replaced target before it reaches the model. `kind` is
one of:

- `Preedit(text~, cursor~)` - display-only composition preview. `cursor` is a
  UTF-16 code-unit offset in the preview, or a negative value when hidden.
- `Commit(text~)` - the host observed a committed insertion. This is an OS fact;
  the adapter must not rewrite it to `Cancel` when model admission fails.
- `Cancel` - the host observed cancellation.
- `Geometry(caret~, candidate~?)` - logical caret and optional candidate-window
  rectangle in surface-logical coordinates. Do not multiply by output scale.
- `FocusLost` - the host lost the keyboard-focus target; the adapter requests an
  explicit end rather than treating it as a commit.

## Capability and failure behavior

- `Capability::TextInput` is advertised only when the host can begin, update,
  cancel and end a real session and deliver committed text.
- `Capability::TextInputGeometry` is advertised only when the host reports
  reliable caret and candidate geometry. It is independent of `TextInput`.
- A host without the required route returns `UnsupportedCapability`. It must not
  map an unavailable route to an empty successful event, and an application must
  not substitute a read-only `Text` for an editable field.
- `Busy`, `StaleHandle` and `WindowUnavailable` are typed failures. A caller may
  retry the same operation after the host state settles; it must not retag a
  stale event as a new session.

## Mapping from a platform event kind

A host that already publishes native composition values as a platform event
kind (for example AppKit `NSTextInputClient` start/update/commit/cancel) still
implements `TextInputHost`; the event kind alone is not the trait. The adapter
maps one observation stream as follows:

- composition start: no `TextInputEvent`; the session epoch already identifies
  the transaction.
- preedit update: `Preedit(text~, cursor~)` with the UTF-16 cursor.
- commit: `Commit(text~)` carrying the host-observed insertion.
- cancel: `Cancel`.
- window focus loss: `FocusLost`, followed by an explicit `end_text_input`.

`begin_text_input`, `update_text_input`, `cancel_text_input` and
`end_text_input` remain host methods because they carry owner state, caret
geometry and epoch replacement. Do not flatten them into a stateless event.

## Relationship to text_session

The intended adapter order is:

1. `begin_text_input` returns an epoch.
2. `update_text_input` publishes the committed document and optional preedit.
3. `next_text_input` returns ordered observations.
4. The adapter applies `Preedit`/`Commit`/`Cancel` through the existing
   `TextSession` operations and measurement/admission callbacks.
5. `end_text_input` revokes the transport after the observed end is resolved.

`TextSession` remains the authority for revisions, ownership and atomic field
transactions. `text_host` does not add a second history, a second focus model,
or a second text value model. UTF-16 remains the offset unit of
`TextDocument`, `TextSelection` and the existing field API.

## macOS route (GP-02-M)

`platform/macos.Host` implements `TextInputHost`. Two additive native
operations keep the transport single-owner:

- op 22 takes the first queued composition frame for one window token (wait is
  0-250 ms) and leaves every other queued event in order. With an active
  session, composition frames therefore no longer appear on `next_event`; that
  is the single-owner rule, and applications that never call the text API are
  unaffected.
- op 23 reports the AppKit key state for the window; `text_host` derives
  `FocusLost` from it. A test-only op 24 forces the key state under
  `GPUI_TESTING` + `GPUI_NATIVE_E2E=1`; it never changes the real window state.

Boundary rules:

- one live session per host; a second `begin_text_input` is `Busy`.
- epochs start at 1, increase monotonically and are never reused, including
  after a failed native enable. Every other epoch is `StaleHandle`.
- `update_text_input` publishes the committed document boundary and the painted
  caret; the caret is rounded outward to integer logical pixels for AppKit.
  The committed document is not retained by the host: `text_session` stays the
  only document authority.
- `FocusLost` is reported at most once, only after the session observed key
  focus, and carries a negative synthetic sequence that cannot collide with the
  native per-window sequence.
- `end_text_input` disables the client and drains at most 64 leftover
  composition frames for that window, so a revoked transport leaves no
  stragglers.
- `Capability::TextInput` is advertised; `Capability::TextInputGeometry` is not,
  because AppKit places the candidate window from the supplied caret rectangle
  and no candidate geometry is reported back to the portable layer.

Run the synthetic proof with `./script/test_macos.sh`; it prints
`GPUI_MACOS_TEXT_HOST {...}` after preedit, commit, cancel, stale-epoch and
forced focus-loss cases. Real keyboard focus acquisition, candidate placement
and Japanese IME remain `NOT_RUN`.

## Portable adapter (`text_adapter/`)

`text_adapter` is the application-facing glue between one `TextInputHost` and
one live `TextSession`:

- `start_host_text(session, host, caret)` begins the transport and publishes
  the current committed document and caret; a rejected handoff ends it again.
- `receive_host_text(session, host, binding, measure, admit)` validates the
  event window and epoch before the document, maps `Preedit` to a checked
  `Preview`, applies `Commit`/`Cancel` through `TextSession::apply_batch`,
  republishes the committed document and painted caret, returns `FocusLost`
  after ending the transport, and treats `Geometry` as a caret update.
- `end_host_text(session, host, binding)` revokes the binding; callers re-arm
  with a fresh start after the next real focus.

The adapter owns no document, history or focus model. It maps host failures and
session rejections into distinct error variants so a caller cannot retag one as
the other. `platform/macos_app.MacosTextFieldHost` wraps the adapter for
one-call app integration: it creates the CoreText-backed field and session,
starts the transport, applies pumped observations to its stored field, and
reports a focus-loss or ended state. The host remains a caller-supplied value,
so the helper is testable with a fixture transport.

`text_adapter.apply_host_text_event` separates fetching an observation from
applying it, so a host can re-bind the portable session to the current field
before a preview starts. `examples/macos_command_palette --text-host` uses that
split: it opens the palette, applies synthetic preedit/commit/cancel frames,
install the resulting field through `CommandPalette::install_field`, and checks
that the committed query filters the list and that cancel preserves it. This is
transport evidence, not real IME qualification (`real_ime: NOT_RUN`). The
sample's interactive ASCII key path is unchanged.

Wiring composition into the live loop was attempted and reverted: with the text
client enabled, the sample's palette loop observes the synthetic commit frame
but no preview frame, so the adapter rejects the commit with
`session_no_composition`. The host keeps only the newest composition frame, and
the loop's event pump drains the generic queue between frames. A live
composition path needs a dedicated frame pump (or a host-side composition
queue) before it can be claimed.

## Evidence boundary

This package has a transport fixture and headless tests only. They establish
the type contract, epoch ownership and ordered delivery; they do not establish a
native window, Japanese composition, candidate placement, screen-reader
behavior, or a platform support tier. Each OS route needs its own exact-source
profile:

- Linux/Wayland: text-input-v1 + IBus/Mozc profile, including candidate panel.
- Windows: IMM32 route, with real IME and UIA recorded separately.
- macOS: the NSTextInputClient route is implemented and synthetic start/update/
  commit/cancel/focus-loss cases run in `./script/test_macos.sh`. The focus case
  forces the key state through the test hook because the automation context
  cannot take real keyboard focus. Real Kotoeri composition, candidate
  placement, and window-activation focus remain `NOT_RUN`.

Unavailable profiles remain `NOT_RUN`. Build-only or synthetic-event results do
not become `PASS`.
