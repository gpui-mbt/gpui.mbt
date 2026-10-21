# Native text host contract (GP-01B)

Status: additive contract in `text_host/`, implemented by `platform/macos` over
the AppKit `NSTextInputClient` client. Other hosts do not implement it yet. A
host that provides the trait still needs an exact-source runtime profile before
it can claim text or IME support.

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

`TextHostQueue` is the shared state for hosts whose native route exposes one
ordered editor stream instead of a separate text queue. It owns the host-issued
epoch, observation sequence, pending text observations, bounded parked platform
events and a sticky unsupported-record failure. A host adapter maps its native
records into `emit`/`park` and exposes `take_text`/`take_parked`; it remains
responsible for begin/update/cancel/end against its own session. Parking is
bounded and a full queue reports failure instead of dropping a record.

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

## macOS route

`platform/macos.Host` implements the trait over the existing AppKit composition
client. The host advertises `Capability::TextInput` only when the loaded library
exports the session and record operations. It does not advertise
`TextInputGeometry`: AppKit reports the caret to the client but keeps the
candidate window position inside the input method.

- `begin_text_input` enables the client, makes the content view the first
  responder, issues a fresh epoch, and rejects a second begin with `Busy`. The
  client is window-scoped: the portable `root` stays the owner's routing identity
  and this transport does not subdivide a window by root.
- While a session is armed, composition records go to the host's ordered
  text-input queue instead of `platform.EventKind::Composition`. Key and pointer
  events keep using the ordinary `next_event` queue, so an owner pumps both.
  The older `set_text_composition` operation is rejected with `Busy` while a
  session is armed.
- `update_text_input` installs the logical caret rectangle. The committed
  document and the owner preedit are validated but not written back: the
  `NSTextInputClient` route never queries the document, and republishing marked
  text would inject a synthetic composition into the input method.
- `cancel_text_input` discards the marked text without publishing a redundant
  `Cancel`, invalidates the old epoch and returns the replacement. Records from
  the replaced epoch are dropped before they can reach the owner.
- `end_text_input` disables the client and drops the window's queued records;
  window destruction and host stop do the same. Window focus loss publishes
  `FocusLost` after the native `Cancel`.
- `next_text_input` returns `Ok(None)` on timeout and never consumes ordinary
  platform events.
- Test hooks expose an explicit ANSI key code with characters and the current
  caret rectangle in screen coordinates. Both require `GPUI_NATIVE_E2E=1` and a
  test-hooks library. The key hook replaces only AppKit's hardware event source:
  the live input method still processes the key. Neither hook synthesizes a
  composition or proves a real input method by itself.

## Windows route (bounded)

`windows.TextHostRoute` adapts the existing default-off IMM32 session. `Marked`
becomes `Preedit` (a missing cursor becomes -1), `Inserted` with an empty
replacement range becomes `Commit`, `Cancelled` becomes `Cancel`, and
composition start/end produce no observation. A replacement insert cannot be
represented by the insertion-only portable vocabulary, so the route fails with
`UnsupportedCapability` and does not flatten it into an insertion.

`begin_text_input` defers the native session until the first `update`, because
IMM32 begin needs the document, caret and owner generation; the portable `root`
provides `owner_generation`. `next_text_input` parks ordinary platform records
for `next_platform_event`, so an application can pump both without losing
input. A window focus loss emits `FocusLost` once. The route is opt-in:
`Host::require_capability(TextInput)` stays unadvertised until an exact-source
IME run qualifies it.

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

## Evidence boundary

The transport fixture and headless tests establish the type contract, epoch
ownership and ordered delivery. The macOS route adds a host implementation and
native E2E coverage that drives the real `NSTextInputClient` callbacks through
the test hook. Neither establishes composition from physical keystrokes,
candidate placement, screen-reader behavior, or a platform support tier.
Each OS route needs its own exact-source profile:

- Linux/Wayland: text-input-v1 + IBus/Mozc profile, including candidate panel.
- Windows: IMM32 route, with real IME and UIA recorded separately.
- macOS: `NSTextInputClient` route on Apple Silicon, with `platform/macos.Host`
  implementing `TextInputHost` over an epoch-tagged, ordered queue. The host,
  epochs, caret update, cancel replacement and `FocusLost` are implemented. A
  live Kotoeri run through the Yami-kumo native sample on 2026-10-21 recorded
  preedit, commit (`日本語`), committed-document and candidate-visibility
  `PASS`; it posted synthetic HID events rather than physical keystrokes, so
  candidate anchoring, physical-keyboard entry and accessibility remain
  `NOT_RUN`. The TextField AX observation is a separate bounded service.

Unavailable profiles remain `NOT_RUN`. Build-only or synthetic-event results do
not become `PASS`.
