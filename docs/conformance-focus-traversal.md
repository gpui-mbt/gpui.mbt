# Flat focus traversal and explicit input modality

This bounded portable element capability supports the focus-order and modality
parts of GPUI's `focus_visible.rs` example. Its current evidence is source
inspection and MoonBit core tests. Actual Rust/browser paired execution is
separate and pending; these tests do not establish browser or pixel parity.

## Public contract

`Element` and `ElementNode` both provide immutable `with_tab_index(Int)` and
`with_tab_stop(Bool)` builders, with `tab_index()` and `is_tab_stop()` queries.
The defaults are index `0` and stop `false`. Neither builder changes focusability.
Metadata survives existing builders, layout, device-scale prepaint, and scroll
translation. An index is a signed MoonBit `Int` (32 bits), rather than Rust's
platform-sized `isize`. Negative indices participate in ordering normally.

`ElementTree::focus_next()` and `focus_prev()` return
`Result[ElementTree, ElementError]`:

- Only live, focusable nodes marked as tab stops are destinations.
- Order is ascending signed index, with stable tree preorder breaking ties.
  Reverse traversal reverses both parts of this order.
- A focused non-stop retains its position as an ordering anchor. It is skipped
  as a destination, including when wrapping.
- Missing focus starts at the first stop for next and last stop for previous.
  Traversal wraps; an empty tree or a tree with no eligible stops is unchanged.
- An already-focused destination preserves its acquisition. This matters for a
  singleton stop and for identity exhaustion. Explicit `with_focus` retains its
  existing contract of allocating a new acquisition, even for the same ID.
- A changed destination uses the existing focus allocator and may return
  `FocusIdentityExhausted`. Traversal does not mutate prior snapshots or arrays.

The implementation makes two bounded scans and compares order keys directly,
without subtracting signed indices or sorting the owned node array. Existing
focus-owner lineage validation, removed-subtree handling, and restoration are
unchanged. A new `ElementTree`, including each `RequestedLayout::prepaint()`,
starts a fresh lineage. Equal numeric IDs never adopt tokens from an old tree.
For a fixed-layout example, retain the live input tree separately from newly
produced paint snapshots. General retained-tree reconciliation is outside scope.

`InputModality::{Mouse, Keyboard}` is a separate immutable value. Initialize it
to `Mouse` and apply `after_input(event)` before dispatching the event:

- `KeyPressed`, including repeats and modified keys, selects `Keyboard`.
- `PointerMoved` and `PointerButtonPressed`, with any button/modifiers and even
  outside a hit target, select `Mouse`.
- `KeyReleased`, `PointerButtonReleased`, `TextInput`, and `Scroll` retain the
  previous modality.

`dispatch_input` and `dispatch_input_with` remain pure routing operations. They
do not update modality, change focus, or interpret Tab/Shift-Tab. Hosts decide
which actions invoke traversal. GPUI's web adapter filters modifier-only DOM
keys before emitting KeyDown; an adapter must not invent a `KeyPressed` event
for a filtered modifier-only DOM event.

`ElementTree::is_focused(id)` queries exact focus; it is not a focus-within
query. `is_focus_visible(id, modality)` additionally requires `Keyboard`.
Callers apply ordinary focus styling first, then focus-visible overrides.
`InputModality::allows_hover()` is true only for `Mouse`, and must be combined
with hit testing. It describes uncaptured Mouse/Keyboard hover policy only.
Upstream captured hitboxes bypass keyboard hover suppression; pointer capture
is not represented by this API. Touch input, which is absent from the current
`InputEvent`, is not modeled or claimed.

## Evidence, commands, and reproducibility

The unchanged-main missing-API baseline was executed before product edits at
`89a11dd7d4cfc4acfa7b8efea52bbf88ac00ccbf`. Only an independently authored compile
probe was added. Its [literal source](evidence/focus-traversal/unchanged-main-api-probe.mbt.txt)
and [compiler output](evidence/focus-traversal/unchanged-main-api-probe.log) are
retained. `moon test element/focus_traversal_api_probe_test.mbt --target js
--deny-warn -j 2` exited `1` for unavailable `with_tab_index`, `focus_next`,
`focus_prev`, and `InputModality` APIs. No baseline app was adapted to emulate
those missing features. This is a compile-time capability gap, not an executed
behavioral mismatch. The identical probe passes after the additions; its
[result](evidence/focus-traversal/implemented-api-probe.log) is separate.

On Linux x86_64 with the recorded [MoonBit toolchain](evidence/focus-traversal/toolchain.txt):

- `moon test element --target all --deny-warn -j 2`: 95 pass per target on JS,
  native, wasm, and wasm-gc, including 15 new focused tests. See the
  [final element log](evidence/focus-traversal/element-final-all-targets.log).
- Portable regression command below: 537 pass each on JS/wasm/wasm-gc, 536 on
  native. Existing focus-owner, scroll, independent-axis gap, layout, controls,
  scene, text, capability and MCP tests are included. See the
  [regression log](evidence/focus-traversal/portable-regressions-all-targets.log).
- `moon check --target all --deny-warn -j 2`, `moon fmt --check`, generated
  element interface verification, and `python3 scripts/check_contracts.py` pass.
  The contract checker continues to report production release evidence pending.
- `python3 -m unittest discover -s tests -p 'test_*.py'`: 142 pass. See the
  [Python log](evidence/focus-traversal/python-regressions.log).

```sh
moon test primitives diagnostics core layout element scene text text_layout \
  controls/button controls/text_field controls/command_palette accessibility \
  capability mcp testing/core_model examples/task_board \
  --target all --deny-warn -j 2
```

The focused tests cover signed extremes, stable equal-index preorder, non-stop
anchors, defaults, no/one stops, both wrap directions, removal, copied arrays,
lineage and acquisition preservation/exhaustion, lifecycle and scroll metadata,
all existing key variants, all 16 modifier combinations, both repeat values,
all mouse buttons, each input transition, exact focus queries, uncaptured hover
policy, and unchanged route-only dispatch.

Four independent mutations were run in an isolated temporary source copy:
reversing signed index order causes five test failures; admitting non-stops
causes five; changing KeyPressed to Mouse causes two; reacquiring an already
focused traversal target causes two. Each mutant compiled and exited `2` with
failing assertions. Restoring the implementation passes all 95 tests. The
[mutation manifest](evidence/focus-traversal/negative-controls.json) records exact
replacements and individual logs. These are focused mutation controls, not a
full mutation score or an upstream oracle.

## Upstream source boundary

The compatibility pin remains
`zed-industries/zed@d9afb21688e04f89d9e94d96d33eb530aef90886`. The separate browser
harness uses `5a5fbe79917971a4d52a96b6ddb04da198a5012e`. Exact pinned source reads
confirm:

- `crates/gpui/examples/focus_visible.rs` is unchanged, blob
  `c5b3d5dfec3a189d088a621baff55eb55a121b6c`.
- `crates/gpui_web/src/events.rs` is unchanged, blob
  `9908b423470ba8f46379832a80a468ca5ccf0c7b`.
- `tab_stop.rs` production code before `#[cfg(test)]` is byte-identical. It
  orders index paths with insertion-order ties, retains non-stops as anchors,
  skips them as destinations, and wraps in either direction.
- Relevant `window.rs` portions are byte-identical: `Window::focus` returns
  early for the same focus handle, traversal delegates to tab stops, dispatch
  updates modality before callbacks, and uncaptured hover is suppressed during
  keyboard input. The broader file is not claimed identical.
- The `div.rs` ordinary-focus then focus-visible style refinement region is
  byte-identical. The broader file is not claimed identical.

Full file blobs and scoped SHA-256 comparisons are in the
[source manifest](evidence/focus-traversal/source-provenance.json). Both owning
GPUI and gpui_web packages declare Apache-2.0; the pinned Apache license text is
unchanged. Implementation and test scenarios are independently authored; no
upstream code, test bodies, fixtures, fonts, or image assets are copied here.
The new record in [upstream.json](upstream.json) preserves all earlier records.

## Limits

This adds flat traversal, separate input-state transitions, and style queries.
It does not add tab groups, keymaps/action dispatch, focus scrolling, native
accessibility, automatic host event integration, retained-tree reconciliation,
pointer capture, Touch, or full GPUI/CSS focus semantics. It does not change
layout algorithms, scroll behavior, or independent-axis gaps. No native-window,
physical-input, GPU-pixel, or browser comparison claim follows from this core
verification.
