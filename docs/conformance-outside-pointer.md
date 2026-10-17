# Rendered outside-down capture (scoped portable contract)

`PointerOutsideFrame` is an opt-in snapshot of a validated `ElementTree` and
unique outside-down listener element IDs. Construction copies tree nodes and
registrations. Dispatch fixes the normal route and eligible outside listeners
before calling application code. A new render requires a new frame.

Any pointer button press outside an element's raw half-open bounds invokes its
outside listener in capture phase, even if another element is hit or no element
is hit. Inside-but-occluded positions remain inside. Releases, movement, scroll,
and keyboard events never invoke outside-down. Bounds are not clipped for this
predicate. Duplicate and unknown registration IDs are rejected.

The additive entry point delivers outside listeners in stable paint order,
then the unchanged hit-ancestry capture/bubble route. Stop and error terminate
later callbacks. This deliberately scoped ordering is NOT parity with GPUI's
complete interleaving of ordinary and outside window listeners. Existing
`ElementTree.dispatch_input_with` semantics remain unchanged. There is no
prompt suppression, mouse-up-out, synthesized click, or automatic popover state.
Applications register the parent listener only when the child is closed; a
callback changing state cannot add that listener to the same event.

## Actual-source basis

Oracle pin: zed-industries/zed `5a5fbe79917971a4d52a96b6ddb04da198a5012e`.

- `crates/gpui/src/elements/div.rs:258–275`: any-button capture, active-prompt
  suppression, and negation of raw hitbox bounds containment.
- `crates/gpui/src/geometry.rs:1468–1473`: left/top inclusive, right/bottom
  exclusive containment.
- `crates/gpui/src/elements/div.rs:2789–2794`: drain mouse-down listeners into
  window registration in stored order.
- `crates/gpui/src/window.rs:5468–5480`: append listeners during paint for the
  next frame.
- `crates/gpui/src/window.rs:5966–6003`: take rendered-frame listener registry,
  capture forward, bubble reverse, and restore registry. Stop skips later work.

Baseline core: `e13c99d387738369e13a26302e556732d78a3b88`, tree
`e269ce546db3e13d8f82b742c0d7b1ae2ca35ca7`. Legacy hit ancestry alone cannot
visit a child popover outside the hit route. Focused unit checks are not full
core validation or a substitute for actual paired oracle evidence.
