# Portable composition session contract (GP-01A)

`f4ah6o/gpui/text_session` is a **headless, composition-only** live-owner seam
around the existing `controls/text_field.TextField`. It adds no OS input route,
no shaping/segmentation engine, and no `platform.Backend` capability. It is a
bounded part of GP-01-SESSION, not completion of GP-01 or GP-02-L/W/M-IME.
Japanese IME transport, candidate placement, native fences/ACKs and browser
behavior still need separate exact-host evidence.

## Ownership and explicit lifecycle

`TextSession::new(window, root_id, field)` accepts an already validated,
noncomposing field, a positive `WindowId`, and a nonzero diagnostic root ID.
It owns one window/root/field binding. All access, including readable snapshots
and receipt comparisons, must be confined to one UI thread. There is no locking,
cross-thread contract, serialization format, or process-global token registry.

Copying a `TextSession` handle shares the private live state and mutation guard.
`SessionSnapshot` and its `TextField` are immutable readable values. Editing a
detached field value does not update the owner; no API installs a branch as an
ordinary delivery. `rebind` is a deliberate replacement with fresh incarnations,
not a way to claim an old branch is the current session.

Private mutable-cell incarnations distinguish the owner, window, root and field.
Routing IDs, identical text, field revision and identical numeric session values
in different owners confer no authority. The cells are never publicly exposed.
Their identity comparison uses observable reference aliasing: set the left
private marker, read the right marker, restore the left marker. There is no
callback or suspension in this short probe, and every marker is false between
probes. This avoids `physical_equal`: the pinned MoonBit
`moonbitlang/core/builtin/intrinsics.mbt` documentation says that intrinsic is
only for performance optimizations, must not determine program semantics, and
may differ across backends/optimization settings. It states no mutable-reference
exception. Tests exercise aliasing and restoration in debug and release builds.

The caller must explicitly report lifecycle changes:

- `rebind(window, root_id, field)` replaces the binding. All three binding
  incarnations change even when IDs, text and field revisions are identical.
  A composing current field or a pending end request rejects direct replacement.
- `rearm()` refocuses a resolved field and advances the binding session. It
  rejects an active composition or pending end request.
- `close()` terminally revokes the shared owner, including every copied handle
  and pending token. Repeated close through any copied handle succeeds without
  changing the visible snapshot. All other mutations and ingress still reject
  the closed owner. The final field remains readable for diagnostics. Closing
  does not imply that an OS commit or cancel was observed.

There is no automatic observation of `ElementTree`, focus changes, native window
replacement or destruction. A host must coordinate these calls with its own
queue/fence protocol before claiming lifecycle safety.

## Targets, counters and ingress

Capture `session.target()` once when a host batch enters the adapter. Retain that
exact opaque `SessionTarget` with every operation in the batch. Do not recapture
or retag already queued input after a publication. Public numeric target
accessors are diagnostic; there is no arbitrary-number target constructor.

This bounded seam permits one outstanding snapshot at a time. Multiple target
captures before publication refer to the same next delivery. After one succeeds,
the others are replay/stale; the host must explicitly resynchronize or recapture
**new** input. This is not a pipelined host queue or an automatic rebase policy.
The native adapter owns correspondence with its own event serials and epochs.

Counters are checked `UInt64` values, never wrapping:

| Counter | Exact meaning |
| --- | --- |
| `session_id` | Starts at 1. Advances on `rearm`, `rebind`, and successful end completion. It identifies a binding session, not each preedit callback or each composition within a batch. |
| `published_revision` | Starts at 0. Advances once per successful batch, end request, end completion, rearm or rebind. An accepted no-op empty preview still consumes one protocol publication. |
| `committed_document_revision` | Starts at 0. Advances once per successful batch/completion if any staged committed `TextDocument` changes, including its directional selection, even if later operations restore the original value. A rebind/replacement always advances it because the committed binding changes. Preview-only/cancel-only updates, focus-only changes and end requests do not advance it. |
| `delivery_watermark` | Starts at 0. Advances exactly once to the captured next sequence on successful batch/end completion. Requests, rearm and rebind do not consume or reset it. |
| `TextField::revision()` | The existing whole-field revision; it may advance several times inside one batch. It is neither of the session revision counters. |

`close()` is terminal revocation without advancing these counters, so exhaustion
cannot prevent revocation. Other exhausted transitions reject atomically.
Committed-document exhaustion can be detected after preparation; no publication
or receipt occurs. Session, revision and sequence accessors must not be truncated
when adapting a smaller native ABI.

Targets bind all private incarnations, window/root/field routing values, session,
published revision and the next delivery sequence. Closed, foreign, stale or
replayed deliveries reject **before measurement or admission callbacks**. Session
and binding checks precede replay; replay precedes revision. These errors describe
why that delivery cannot be accepted, not a universal ordering of host events.
An unfocused batch, empty batch, or commit without an active composition also
rejects. A rejected delivery consumes no watermark and returns no receipt.

## Bounds-only preparation

`prepare_bounds(target, bounds)` makes an immutable field proposal bound to the
exact current owner, session and publication. It neither publishes nor consumes
an observation. It delegates to `TextField::with_bounds`, which preserves an
active preview and the original document, selection, measurement and history
used if that preview is canceled. Invalid bounds, a pending end, an unfocused
field, foreign/stale target or a reentrant call is rejected without changing
the owner.

`publish_bounds(proposal)` installs that still-current field on the same owner.
A second publication, any intervening publication or a foreign owner rejects
the proposal. A real field resize advances the field's own revision; it does
not change the session revision, committed-document revision, session identity
or delivery watermark. A text target captured before the bounds-only update
remains valid for the same owner and next delivery: the caller must retain the
original host epoch and sequence rather than retag the observation. A target
consumed by another delivery remains a replay as usual. This exception applies
only to bounds-only updates with unchanged content and binding; it does not
authorize old pointer coordinates or general reconciliation.

The candidate is a preparation primitive, not a cross-owner commit. The
session does not atomically publish a native host rectangle, scene, runtime
action, or focus scope with it. An integrator must first supply a transaction
that can prepare and commit those owners without partial publication; calling
`publish_bounds` alone does not establish that guarantee. It also does not
remeasure the current preview or its rollback snapshot for a scale, font or
shaping change. Those cases need a separate remeasurement contract. Host input
cutoff, pending end, retained observations and stale-target fences remain the
integrator's responsibility.

## Existing field semantics, preserved

`apply_batch(target, operations, measure, admit)` stages immutable `TextField`
values and ordered `SessionOutcome`s and publishes once. It delegates directly to:

- `update_composition` for UTF-16 directional selections
- `update_composition_utf8` for strict UTF-8 directional byte endpoints
- `commit_composition` for final text over the original selected range
- `cancel_composition` for restoration of the exact original field state

The first successful **nonempty** preview opens a composition. A later empty
preview restores the original display and hides the marked range while retaining
the transaction. An initial empty preview opens nothing. Repeated previews replace
the original selected range, not the preceding preview range. Commit creates the
existing one-step original-to-final undo entry. Cancellation restores the original
directional selection and history; same-text commit retains TextField's existing
history semantics.

Commit-only insertion is explicitly unsupported (`NoComposition`). The adapter
never synthesizes a preview and never substitutes `replace_selection`, whose
caret-snapping behavior differs. Ordinary keyboard editing, clipboard changes,
undo/redo and general external-edit reconciliation are outside batch operations;
immutable result fields retain the existing public editing/history APIs.

UTF-16 remains the value-model offset unit. UTF-8 anchor/head are converted
independently against the exact preedit. Negative/out-of-range offsets,
scalar-interior UTF-8 offsets, split surrogates, malformed UTF-16, forbidden input,
unsupported layouts and endpoints not reported as exact cursor stops reject via
the existing field API. Scalar boundaries do not prove grapheme/bidi capability.

## Requests versus observed endings

`request_end(target, Blur | ExternalReplacement)` records intent and returns an
opaque `PendingEnd`. It advances the published revision and preserves the entire
field, preview, committed document, geometry, history and delivery watermark.
The old target becomes stale. Normal input and direct rebind/rearm are blocked
while the request is pending; `pending.target()` is the completion target.

The host observes what actually happened, then uses one of:

- `complete_blur(pending, Committed(text) | Cancelled, measure, admit)`
- `complete_replacement(pending, observed, window, root_id, field, measure, admit)`

The observed commit/cancel is applied first. Only then may blur call
`with_focus(false)`, or replacement install an already validated noncomposing
field. The receipt returns two ordered outcomes: `Committed`/`Cancelled` with the
resolved old field, then `Blurred`/`Rebound` with the final field. Thus external
replacement cannot hide an OS commit by reporting only a cancellation or only the
new value. The caller must dispatch both outcomes in order when reconciling its
application state. A `Cancelled` observation with no active composition confirms
that there is nothing to resolve; it can finish an ordinary noncomposing blur.
A committed observation with no composition remains unsupported.

Pending tokens have private completion identity and exact target. Wrong-owner,
wrong-reason, stale, forged or repeated completion rejects. Every failure leaves
the pending request resolvable and the model unchanged. There is no timeout or
implicit cancellation. The host can retry the same observed result after fixing
preparation, or explicitly close the owner as part of a separately fenced teardown.

An observed OS commit remains an OS fact even when model admission fails. The
caller must retain that observation, withhold the acceptance ACK, and explicitly
resynchronize the host/model. It must not reinterpret failure as cancellation or
continue by retagging later queued events. This package does not undo OS actions,
drain native event queues, choose a native barrier, or decide recovery policy.

## Atomicity and provider rules

All live mutations share one reentrancy guard. A provider that attempts any
mutation through this owner or a copied handle receives `Reentrant` and poisons
the outer transaction, even if it ignores the nested error. A poisoned measurement
also prevents the subsequent admission callback. A private publication-incarnation
check runs before publication. Readable snapshots remain the previously published
state throughout preparation.

The operations array is copied before provider invocation. Returned receipt
outcome arrays are copied on access. A provider cannot rewrite later operations
in the accepted batch by mutating the caller's array.

Failure at any operation preserves the published field, selection, composition,
undo/redo, measurement/caret geometry, scroll offset, all revisions and delivery
watermark. In particular, a valid first preview followed by an invalid second
operation does not publish the first preview. End resolution and subsequent
blur/rebind have the same all-or-nothing model rule.

This atomicity applies only to the model. Measurement and admission callbacks
must be preparation-only and must return errors rather than throwing, aborting,
suspending, publishing host geometry, acknowledging input, or committing OS side
effects. Their own allocations or external effects cannot be rolled back here.
A process abort is outside the recoverable callback contract.

## Host acceptance seam and evidence

Only successful publication returns `BatchReceipt`. `acknowledges(target)` checks
the exact original accepted target, including private identities. It does not
send an OS ACK. A host integration should follow:

1. Capture target at batch ingress; preserve event order.
2. Prepare/admit the complete batch and accept its model receipt.
3. Send the host's exact ACK for that original batch identity.
4. Publish deferred geometry from the accepted snapshot under the host's fence.

`fixtures_test.mbt` exercises acceptance → exact ACK → deferred geometry and
no-ACK/no-geometry on failure without AppKit or other native transport. It is an
ordering seam compatible with the bounded [PR89 synchronization plan](https://github.com/gpui-mbt/gpui.mbt/blob/451ead8fce495a4ad471b577b06c3442d8165011/examples/macos_text_field/owner.mbt#L627-L781),
not a claim that PR89, AppKit or any real OS is wired to this new package. Native
Busy/queue-quiet checks and cancel/rearm fences belong to that host integration.

Focused commands, using the pinned toolchain:

```sh
moon fmt text_session --check
moon check text_session --target all --deny-warn
moon info text_session --target all
for target in js native wasm wasm-gc; do
  moon test text_session --target "$target" --deny-warn
  moon test text_session --target "$target" --release --deny-warn
done
```

The package includes executable public rejection counterexamples, white-box
counter-exhaustion/incarnation tests and host-order fixtures. Independent scoped
production-source mutations additionally check that owner/binding/revision/replay,
atomicity, reentrancy, original input capture, pending identity and exact receipt
checks are detected. These controls are not a new global mutation gate.

All four compiler-target results are **headless model evidence**. Native here is
a Linux process without a display. macOS, Windows, Linux GUI/IME, Web DOM and
assistive-technology acceptance remain **NOT_RUN** by this package's local tests.
The existing contracts CI discovers this portable package via its all-package
format/check/test commands; exact-head CI and independent review remain release
and merge gates. No backend/manifests/workflows outside this package are changed.
