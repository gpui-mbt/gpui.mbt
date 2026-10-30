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

### Ubuntu ordered ingress (opt-in)

The legacy Ubuntu `TextHostRoute::new` retains the two-poll API and its existing
behaviour. The separate `OrderedTextHostRoute::new` selects an exclusive
alternative: `next_ordered_event` returns each translated text or platform
record in the order read from the Ubuntu editor stream. The ordered facade
exposes begin/update/cancel/end and its single poll; it does not implement the
legacy `TextInputHost` trait with its separate text poll. Consumers must handle
both event variants. An empty result means no deliverable event was returned;
the poll may have consumed skipped or stale records. Forwarded keys retain
their position as platform records. Unsupported editing records remain errors
rather than silently becoming insertions.

This ordering applies to records returned by Ubuntu `Host::next_editor_event`.
It does not prove an IME has finished producing observations, make an empty
poll a quiescence barrier, or resolve a pending composition. The native host
preserves eligible preedit and commit records admitted before natural focus
loss ahead of that loss's `Left` record; explicit close and session replacement
still fence old-target text. Cancel and end can discard undelivered
observations. The owner must resolve the original binding and any pending end;
this API alone does not establish observed-commit preservation for every blur
or close. The remaining boundary and integration work are tracked in
[0028](../issues/open/0028-wayland-ime-composition-handoff.md) and
[GP-01B](../issues/open/20261019-gp-01b-text-host-contract.md). macOS and
Windows retain their existing contracts; this section adds no guarantee for
them.

### Ubuntu drained end (opt-in candidate)

`OrderedTextHostRoute::try_end_when_drained(epoch)` is an explicit, bounded
operation for an owner that intends to stop input. On the host owner thread it
checks the entire native editor queue and revokes the active native epoch in
the same call only when that queue is empty. If any native record is queued,
it returns `Busy` without changing the route, epoch, field, or queue. The owner
can read and resolve records through the ordered poll and retry. A mismatch or
an unavailable native session is an error; no implicit retry is performed.

The cut covers records already admitted to the native queue at the instant of
the successful call. It does not promise that the operating system has emitted
all possible callbacks or decided whether an active preedit should commit or
cancel. Nor does it acknowledge records already returned to the caller: the
caller must retain and apply each returned observation to its original owner
before attempting this operation. A successful cut is not `ObservedEnd::Cancelled`
and does not by itself authorize a composing `TextSession` to blur. If the
outcome is unknown, the adapter must keep it pending or report the limitation.
The caller must not use unrelated `Host` poll methods while the ordered route
owns the session. The legacy cancel/end behavior is unchanged.

### Explicit owner discard is not an OS observation

`TextSession::complete_blur_by_owner_discard` is a separate portable operation
for an application owner that has received an explicit user request to discard
an active preview. It reports `SessionOutcome::OwnerDiscarded`, not an
`ObservedEnd::Cancelled`. Before invoking it the owner must process all
accepted old-binding observations and establish the applicable host cutoff.
The method cannot verify a host cutoff, infer what an undispatched callback
would have done, or authorize discarding on a bare Tab or focus change.
Failure leaves the pending end and its field intact. On success the original
committed document, selection and undo/redo state survive the discard, and the
session advances before blur; old targets and pending tokens are rejected.
An owner must choose a user-visible fallback when it cannot establish the
cutoff or the user has not explicitly requested discard.

If no preview remains after processing the accepted prefix, the separate
`TextSession::complete_blur_if_uncomposed` operation completes the pending blur
without inventing any cancel observation. It rejects an active preview and
leaves the pending request intact. The same caller-owned host cutoff and
old-binding delivery obligations apply.

An observed direct insertion with no active preedit can be applied through
`TextSession::apply_batch` using `SessionOperation::Insert`. It uses the same
owner target, replay fence and atomic field transaction as composition
updates. `Insert` rejects an active composition; use the composition-only
`Commit` for that case. It must not be used to invent a preview or flatten an
unsupported replacement operation.

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

## Ubuntu route (bounded)

`ubuntu.TextHostRoute` maps forwarded Ctrl/Meta A, C, X, V, Z and Y keysyms
to platform command keys. A matching release is delivered for an acquired key
even if its modifier was released first; the acquisition is revoked when the
text session is canceled, ended or replaced. Unmodified character keysyms and
other modified characters do not become text or command keys through this
mapping. IME commits remain the source of inserted text. This bounded mapping
does not itself qualify a live IME or cross-queue event ordering.

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

### Experimental Ubuntu terminal retention

Ubuntu's `Host::enable_terminal_retention` selects a separate experimental
reader before any text or direct-keyboard session. The legacy readers then
return unsupported before dispatching callbacks. `dispatch_retained` pumps
callbacks only when the FIFO is
empty and never dequeues a record; Busy makes no progress.
`peek_retained_editor` leaves the native FIFO head owned by
the host; its opaque record acknowledges only the same window and sequence.
Native invalidation marks a stale record; it does not authorize delivery to a
new window or editor. The consumer must validate the captured session and its
own root/field binding generation. It may acknowledge a text record only after
its original `TextSession` and resulting shared-model actions are applied, or
after a suspended owner retaining that exact processing stage is handed off.
Nontext records need an explicit terminal policy. A native dequeue, a scene
failure, or an empty application buffer alone is not an acknowledgement.

An unresolved bounded composition preview is reported separately through
`terminal_preview_receipt`; it is not an OS commit or cancel. Its one-shot
handoff requires the original window and native epoch and only transfers the
preview obligation; it does not authenticate a consumer field or apply a
record. Stop rejects a pending FIFO or preview. Buffer exhaustion or a
terminal lifecycle error is not a completed shutdown: the caller must retain
and inspect the host and any removed owner state. `try_end_when_drained`
remains a native cutoff and can itself generate a lifecycle record which must
be read and acknowledged before stop.

This is not yet connected to `OrderedTextHostRoute` or Yami Shared Settings.
It does not provide a new OS composition after focus/epoch loss, a portable
cross-layer geometry transaction, or Linux live-IME acceptance. In particular,
keeping a snapshot across blur does not mean that a later OS callback for the
invalidated native session was received.

`RetainedOrderedRoute` is the experimental gpui-owned translation layer above
that FIFO. One route claims the host, and legacy text routes and composition or
direct-text modes cannot be started alongside it. The route uses its own
native session entrypoints; legacy raw session mutation is rejected while the
route is claimed. A binding captures the root,
window, native epoch, and, after Entered is acknowledged, seat and proxy
generation. A prepared receipt preserves native sequence separately from its
text-only portable ordinal. Preparing the same head does not advance the ordinal
or shortcut state; those advance only after the exact native ACK succeeds.
Foreign or stale targets, unmapped events, replacement, and position changes
remain explicit unhandled records. Cutoff retains the binding until its
lifecycle records are acknowledged and release succeeds.

The app-layer `OwnedTextRoute` retains the original opaque `TextSession`
binding above the Ubuntu native leaf. After
natural focus loss, the owner must process and ACK the admitted FIFO prefix and
the matching Left, then explicitly resolve blur in that same session. A Left is
not an observed cancel. `end_after_left` checks the resulting blur receipt,
current owner state, empty FIFO, and the old native window, epoch, seat and
proxy in the inactive state. `OwnedTextRoute::release` rechecks the resolution and native
window, and rechecks the old native identity after natural focus loss. The
caller is responsible for applying all generated actions to the original
shared model before requesting either operation. Explicit owner discard is
distinct from an OS-observed cancel. No old record is transferred to a new
owner or epoch. A disappeared window, unconfirmed identity, unresolved
composition, pending record, or failed check retains the binding and host.

This adapter does not yet implement cancel-to-new-epoch handoff or
transactional native geometry updates. The lower-level
`RetainedOrderedRoute` exposes only native cutoffs and relies on the caller to
resolve its editing owner. A route that cannot finish cutoff must be surfaced
as unresolved rather than force-released. The claim lasts until its host stops.
Yami integration and real IME operation are not verified.
