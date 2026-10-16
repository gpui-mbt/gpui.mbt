# Typed drag sessions

`@element.DragSession[T]` is an additive, bounded drag-and-drop channel. It does
not change `DragGesture`: that immutable API still has inclusive/configurable
thresholds, immediate zero-threshold begin, and release-coordinate activation.
The existing task-board keeps that API and its original behavior.

## API

- `DragSession[T]::new()` creates an independent idle session. Copying a handle
  shares the private cell, including cancellation and one-shot consumption.
- `DragSource::new(element_id, payload)` binds a current `T` value.
- `DropTarget::new(element_id, can_drop? : (T) -> Bool)` binds a current target;
  the optional predicate defaults to acceptance and must be pure/read-only.
- `session.dispatch(tree, event, current_sources, current_targets)` returns
  `Result[DragDispatchOutcome[T], DragDispatchError]`.
- `session.cancel()` returns whether pending/active state was cleared. Call it
  for model reset, destruction or invalidated source lifetime before ID reuse.
- `session.snapshot()` returns a detached `DragSnapshot[T]`: `Idle`,
  `Pending(source~, origin~)`, or `Active(source~, origin~, position~,
  cursor_offset~, payload~)`. There is no restoration API. `T` is retained
  shallowly; reference-valued payloads are not deep-copied or made immutable.

Outcomes are `Unchanged`, `Admitted`, `Activated`, `Moved`, `Cancelled`,
`Rejected(target_id)` and `Dropped(target_id, payload)`. Apply a returned drop to
application state once, after dispatch. Aliased session handles cannot generate
a second drop from another release. The returned value itself is not linear:
application code is responsible for not applying the same outcome twice.
`state_changed()` distinguishes unchanged input from a session transition;
`was_stopped()` is true only for activation and acceptance. These flags do not
schedule a window repaint or stop an independently dispatched application event.
The host integrates them into its own event/render loop.

## Transition rules

1. Only an idle Primary press admits a source on the current ElementTree bubble
   route. Sources require their own enabled, half-open pointer bounds and all
   ancestor scroll clips. Pending retains only source ID and press point.
2. Only a move at Euclidean distance **strictly greater than 2** activates. It
   resolves the admitted ID's current `T` and current bounds at that moment.
   `cursor_offset` is the exact finite activation position minus current source
   origin. It is separate from payload and any application preview geometry.
   Source pointer enablement/bounds do not re-admit or retarget pending ownership
   at activation; normal rerenders may change those bounds and payload.
3. Missing binding with a live pending node stays pending. Observed node removal
   without a stale binding cancels pending. Active state retains its value even
   after source removal. Numeric-ID reuse requires explicit lifecycle cancel;
   this is not an ABA-proof lifetime token. Fresh focus lineage on rerender is
   deliberately unrelated to drag ownership.
4. Active state remains active on return to the press point. Repeated Primary
   or Secondary presses while busy do not replace it. This single-admission
   policy is narrower than Rust's general repeated-down pending overwrite.
5. Every **successfully validated** release, regardless of button, clears the
   pending/active state. A release never activates. For active release, choose
   the first eligible typed target on the current target-to-root route, consume
   the state, then evaluate its predicate. Rejection is terminal, does not retry
   an ancestor, and does not stop propagation. Acceptance returns one `T`.
   An unregistered child permits a registered ancestor; no target also clears.
6. A predicate sees `Idle` through any alias. Nested `dispatch` returns
   `ReentrantDispatch`. Do not perform application mutations in predicates;
   effects belong after a returned `Dropped`. No fallible operation follows
   predicate execution. The predicate contract is documented, not a language
   effect-system purity check. Escape is not an implicit cancellation command.

## Errors and geometry

Each call structurally copies both binding arrays, then validates all entries,
including those off the pointer route. Duplicate IDs within each list fail with
`DuplicateSourceBinding(id)` / `DuplicateTargetBinding(id)`; absent tree IDs fail
with `UnknownSourceBinding(id)` / `UnknownTargetBinding(id)`. Source validation
precedes target validation, and each list scans in array order. The same live ID
may appear once in each list. Disabled, clipped and zero-area live nodes are
valid bindings even when they cannot receive pointer input.

Every `Err` preserves prior state, including pointer, payload and ownership
visible through aliases; it invokes no predicate and produces no drop. This
includes malformed releases: handle the error by fixing/retrying or explicitly
calling `cancel()`. Ignoring such an error can leave a preview/session active.

Finite endpoints can still produce an unrepresentable difference. Activation
returns `CursorOffsetOverflow(source_id)` if the exact cursor-offset subtraction
is non-finite, rather than clamping it. Threshold classification caps axis
distances safely above 2 before squaring, so extreme finite coordinates cannot
overflow its distance calculation. A later retry may activate successfully.
Computing a preview origin as `position - cursor_offset` also needs checked
geometry in application code; the API offers no infallible derived-point getter.

With S sources, T targets and N tree nodes, complete registry validation costs
`O((S+T)N + S² + T²)` time and `O(S+T)` structural copy space. Selection adds the
existing ElementTree routing/ancestor-clip work and scans bindings along that
route. This deliberately favors small registries without a new map dependency.

## Source and evidence boundary

The pinned Zed source is
[`5a5fbe79917971a4d52a96b6ddb04da198a5012e`](https://github.com/zed-industries/zed/tree/5a5fbe79917971a4d52a96b6ddb04da198a5012e).
Relevant production blocks:

- [`div.rs`](https://github.com/zed-industries/zed/blob/5a5fbe79917971a4d52a96b6ddb04da198a5012e/crates/gpui/src/elements/div.rs#L2941-L3012): pending press, strict 2px move activation and current hitbox offset.
- [`div.rs`](https://github.com/zed-industries/zed/blob/5a5fbe79917971a4d52a96b6ddb04da198a5012e/crates/gpui/src/elements/div.rs#L2903-L2933): take-before-predicate, terminal rejection and accepted-drop stop.
- [`div.rs`](https://github.com/zed-industries/zed/blob/5a5fbe79917971a4d52a96b6ddb04da198a5012e/crates/gpui/src/elements/div.rs#L3083-L3103) and [`window.rs`](https://github.com/zed-industries/zed/blob/5a5fbe79917971a4d52a96b6ddb04da198a5012e/crates/gpui/src/window.rs#L5966-L6021): release cleanup and broader global dispatch.
- [`drag_drop.rs`](https://github.com/zed-industries/zed/blob/5a5fbe79917971a4d52a96b6ddb04da198a5012e/crates/gpui/examples/drag_drop.rs): typed value versus separately constructed preview.

The audited unchanged example blob is
`8f038ef3308fee9b097e7289665c9fa47cd6945b` in that source and compatibility runtime
`d9afb21688e04f89d9e94d96d33eb530aef90886`. Its browser evidence covers bounded
visible example behavior. Dynamic bindings, predicates, aliasing, reentry and
numeric extremes here are separately labeled source/API tests, not behaviors
independently exposed by that example. Its preview padding cancels the internal
grip offset, so centered visible preview geometry does not measure that offset.

This implementation preserves ElementTree's existing topmost-target-plus-
ancestors routing. It does **not** implement Rust `Any` / `TypeId` heterogeneity,
global hovered-hitbox/occlusion rules, arbitrary callback reentrancy, full window
refresh scheduling, native input/capture, or multiple pending pointers. `T` is
one homogeneous compile-time channel; JavaScript adapters should forward input
and render state, leaving drag policy and typed payloads in MoonBit.

## Portable verification

Run the focused and compatibility suites:

```sh
moon check --target js --deny-warn element
moon test --target js --deny-warn primitives layout scene element examples/task_board
moon info element
```

Run retained isolated mutation/type controls in a fresh output directory:

```sh
python3 scripts/check_drag_session_controls.py --output /tmp/drag-session-controls
```

The script copies only the portable dependency closure. It first compiles every
mutant, then requires runtime assertion failures for inclusive threshold,
release activation, press-time payload freezing, predicate-before-consumption,
ancestor retry, double delivery, error-time mutation and offset clamping.
Separate negative compile controls reject foreign source/predicate types and
snapshot restoration. It retains commands, timestamps, sources and raw logs;
these are control results, not additional production or browser implementations.
