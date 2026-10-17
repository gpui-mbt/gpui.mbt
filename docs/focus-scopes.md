# Bounded live focus scopes

`element.FocusScopeSession` is an additive, UI-thread-confined controller around
immutable `ElementTree`. One integrating owner keeps one session per window.
The controller knows no window IDs, native capture, IME, or accessibility
transport. Existing `ElementTree` methods and traversal contracts are unchanged.

## Identities and observations

- Copies of a session share authoritative `Ref`-backed state. Copies of a modal
  handle close/revoke together. No physical/reference equality is used.
- `FocusScopeHandle` identifies one open modal lifetime, independent of its
  current `FocusOwner`. Tab can acquire focus hundreds of times without making
  the lifetime handle stale. Session and scope identities use the existing
  checked focus identity allocator; exhaustion never wraps.
- `target()` captures an opaque session identity plus checked revision. Supply a
  current target to every mutation or synchronous input/action admission. A
  foreign target or an older revision is rejected before user callbacks.
- `snapshot()` returns a detached immutable observation. Calling `with_focus`,
  `clear_focus`, `without_subtree`, or traversal on it cannot mutate the session.
  Importing a replacement is an explicit separate operation.
- Accepted focus, open/close, removal, replacement, bounds refresh, and dismissal
  release transitions advance revision. Pure dispatch, wheel resolution, and
  traversal that keeps the exact acquisition preserve it. A target is not a
  one-shot action token. Checking a token and later using a snapshot is not
  asynchronous admission; dispatch through the live session synchronously.

## Open and traversal

`open_scope(target, root, cancel_interactions, initial?, fallback?)` returns a
handle. The stack is bounded to 32 frames. A new root may descend from an outer
scope or be a disjoint overlay sibling. It cannot equal or contain any outer
root, which would enlarge the modal boundary.

An explicit initial target must be live, focusable, and within the new root.
An explicit fallback must be live and focusable in the boundary that will resume,
and outside the new root. Invalid input fails atomically. Without an initial
target, opening selects the first in-scope existing tab stop, then the scope root
if it is focusable; otherwise it fails without moving to background focus.
The previous exact owner and the optional fallback acquisition are captured
separately from the new modal identity.

Only the top frame admits focus and input. `focus_next` / `focus_prev` filter
eligible stops in the original full tree, retaining signed lexicographic group
prefixes, stable preorder ties, non-stop anchors, wrap, and same-destination
acquisition preservation. They never rebuild a temporary subtree. Groups remain
ordering metadata. The host's existing Tab/Shift+Tab command calls these methods;
`dispatch_input_with` does not interpret Tab, modifiers, repeats, or default
keyboard actions.

## Destructive close and restoration

`close_scope` is deliberately a **remove-and-close** operation, not a visibility
flag. Closing any live frame removes its root and all logical child suffix roots
from the authoritative input tree, including disjoint sibling overlays, and
revokes every handle in that suffix. Closed dialogs cannot remain globally
tabbable or interactive. Restoration occurs once, after all removal, using the
outermost closed frame. No destroyed child is temporarily restored.

Restore order:

1. The saved exact `FocusOwner`, if still live, focusable, in the same tree
   lineage, and admissible in the resumed scope.
2. The captured explicit fallback owner, with the same checks.
3. The resumed scope's first tab stop, then its focusable root.
4. With no scope, a surviving global tab stop; otherwise clear focus.

A stale revision cannot overwrite a caller's newer focus. If the owner chooses
to close with a fresh revision after deliberately changing focus, that is a new,
explicit close request with the above restoration contract. No continuity is
inferred from reused numeric IDs.

`remove_subtree` is administrative tree maintenance and may remove background
restore targets. Removing a scope root or any ancestor unwinds the earliest
affected frame and its logical child suffix, including overlay siblings. Removing
only the focused child keeps its scope and chooses the first remaining stop/root
or clears focus. Removing a saved restore/fallback target alone leaves the active
scope intact. Ordinary removal preserves a surviving current owner.

`refresh_layout` delegates to the existing same-topology, non-scroll bounds-only
refresh. Exact owners and scopes survive, but old admission targets do not.
`replace_tree` clears focus and revokes all scopes and prior targets, even if the
caller supplies the same numeric IDs or an old snapshot. It is not reconciliation.
`close` is terminal across all session copies and leaves an empty readable
snapshot. Input and mutations then fail with `ClosedSession`.

## Routing and semantic admission

Pointer move/press/release, scroll, keys, and committed text all use the original
hit-test/focused route, then apply scope admission. Background hits yield an
empty successful route, never background callbacks. Admitted capture/bubble
routes start/end at the scope root: an ancestor outside the modal does not see
the event. Wheel resolution uses this truncated route, so a background scroll
ancestor cannot receive deltas merely because the modal is its descendant.
Wheel resolution still returns offsets; the owner installs them in its normal
render flow. Existing half-open bounds, clipping, and axis policies are retained.

`request_focus` and `dispatch_target_with` reject outside targets.
`dispatch_target_with` adds scope admission to an already validated semantic
Invoke/focus handler. The owner must still use `AccessibilityModel`'s NodeId,
action, enabled/loading, and relevant owner checks. It is not a replacement
semantic model, an external AX transport fence, or a general action executor.
The owner must not bypass this gate by delivering directly to a stale controller.

## Interaction boundary hook

Opening, destructive close/removal, replacement, and terminal close require a
synchronous `cancel_interactions` callback. It receives a `FocusScopeBoundary`
receipt with kind, previous/next scope roots, and removed roots. For `Removed`,
roots describe actual disjoint subtree removals; a nested root already removed
with its ancestor need not appear again. For `Replaced` and `Closed`, the list
contains revoked modal roots, and every old input binding is invalidated even if
the list is empty. Those operations require whole-owner cancellation. This
receipt is an integration obligation, not proof that arbitrary controllers reset.

All structural/focus/identity/revision validation and staging finishes before the
hook. The hook sees the old authoritative snapshot. It must, before returning
`Ok(())`:

- cancel every invalidated Button pointer/key press with `cancel_press`,
- cancel pending and active `DragSession` state, including copies,
- release or quarantine native pointer capture and queued old-owner delivery,
- handle any owned text session using its explicit observed commit/cancel/end
  contract, never an unconditional generic composition cancellation.

There is no native pointer-capture API in this slice. If capture cannot be safely
released/quarantined, return `InteractionBoundaryRejected`; do not acknowledge a
successful switch. Integrating owners should gate events through this session
before calling controllers and scope-filter drag bindings: an already active
drag can process moves without fresh hit testing. An empty route does not reset
an existing controller. If an out-of-scope release cannot be delivered to its
original owner, the host must explicitly cancel that gesture rather than feed
the rejected event to the controller or leave a captured gesture live. The
fixture proves rejected moves do not advance a drag, empty outside releases
trigger explicit host cancellation, and later inside releases cannot revive
activation/drop. It does not claim automatic pointer-capture or pointer-leave
handling.

The callback is a non-raising `Result` function. On callback `Err`, the session
publishes nothing. On any nested mutation or admission attempt during dispatch
or a boundary hook, the nested call returns `ReentrantMutation` and poisons the
outer operation even if its caller ignores that error. The outer operation also
returns `ReentrantMutation` and does not publish. Snapshot reads remain allowed.
User callback effects outside the session cannot be rolled back; an owner must
reconcile those effects before retrying. Consumed identity numbers are not reused.
A runtime abort/panic is not a recoverable transactional exception.

Pass the actual dismissal key to `close_scope(..., dismissal_key=key)`. Matching
presses, including repeats, and the trailing release are swallowed before any
background delivery. The release retires that key's guard and advances revision.
Multiple keys can be guarded; unrelated keys continue normally. Guards survive
replacement until an observed release. This does not synthesize releases or
purport to fence native keyboard transports.

## Verification boundary

`element/focus_scope_test.mbt` and `focus_scope_wbtest.mbt` cover public contracts,
identity/revision exhaustion, atomicity, scope routing, lifetime/restoration,
removal, refresh, and detached observations. The executable
`controls/button/focus_scope_test.mbt` fixture uses the real Button and DragSession
models for cancellation, scoped delivery, dismissal guard, and simulated capture
rejection; its host state is explicit.

Focused debug/release tests target JS, native, Wasm, and WasmGC. Source negative
controls must execute and fail before restoration; test claims and raw logs are
recorded with the candidate evidence. These are portable source/model contracts.
Actual Dialog rendering, native input/capture, external AX, IME integration, and
assistive-technology operation are **NOT_RUN**. GP-03 semantic/backend work and
anchor/layout geometry remain separate slices.
