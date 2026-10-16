# Bounded element scroll viewports

`Element::with_scroll_offset(Point)` integrates two-axis scrolling into the
portable request-layout → prepaint → scene pipeline. The caller owns a finite
content offset: positive X/Y moves descendants left/up. Pass the retained
offset back when rendering the element again. No browser DOM scrolling or
JavaScript geometry emulation is involved.

After prepaint, `tree.scroll_viewport(id)` returns an immutable
`ScrollViewport` with `id()`, `bounds()`, `offset()`, and `max_offset()`.
Offsets are clamped to the current layout on both axes. Non-scroll elements
and unknown IDs return `None`.

`tree.scroll_wheel(position, delta_x, delta_y)` returns a fresh array of
viewport updates in target-to-root order. Its pixel-delta convention matches
the existing portable `InputEvent::Scroll` browser path: positive deltas
increase content offsets. Keep each returned `id()`/`offset()` pair in caller
state, then render/prepaint again. Reading updates does not mutate the live
tree, its geometry, or its focus owner. All eligible scroll ancestors receive
the **same** delta and clamp independently. This is not residual-delta
consumption. A diagonal event uses its dominant axis; equal magnitudes choose
Y. Non-finite deltas reject the entire update, even outside any hit target.
Finite extreme deltas saturate safely at the corresponding limit.

## Geometry and clipping

- Limits use the union of each viewport's laid-out **direct** children, plus
  its padding, minus its own size. Overflowing grandchildren do not enlarge
  an ancestor's limit. Gaps between direct children are included in the union.
- Empty child lists use the viewport size as their content-size fallback,
  before adding padding. Limits are nonnegative and rounded to two decimals.
- Device-scale layout uses the same snapped padding as the existing layout
  contract. The accumulated ancestor scroll translation is snapped once when
  applied to a node's bounds, with midpoint ties toward zero. Accumulation and
  caller-retained offsets remain raw, so nested fractional offsets are not
  rounded independently. Raw logical layout keeps raw padding and offsets.
- Each viewport's own bounds/background remain at its parent-translated
  position. Descendants receive the additional negative content offset.
  Nested offsets compose; leaving a subtree restores the sibling's transform.
- The scene paints the viewport background, pushes its descendant clip,
  paints children in existing preorder, and pops before the next sibling.
  Nested clips remain balanced, including empty scroll elements and forests.
- Hit testing requires the node's half-open bounds and every scroll ancestor's
  half-open clip. Zero-area masks receive no hits. A pointer-disabled viewport
  still clips descendants but receives no wheel update.
- Translation, content-union, or accumulated-offset geometry that cannot be
  represented safely returns `ElementError::GeometryFailure`.

`ElementTree::new` still starts a fresh focus lineage. Existing immutable
focus operations and subtree removal keep their previous ownership rules.
Scroll metadata is private and immutable, and returned node/update arrays
cannot mutate a tree's owned arrays.

## Explicit scope

This is the small two-axis core surface needed by the nested `scrollable.rs`
example. It does not implement a full GPUI scrolling replacement:

- Masks use the viewport rectangle. GPUI's visible-border-aware inset masks
  are not modeled; the example's two scroll viewports have no visible borders.
- Wheel routing uses eligible ancestors of the selected pointer target.
  GPUI's set-of-hitboxes routing and occlusion among unrelated overlapping
  scroll hitboxes are not represented by this contract.
- There is no one-axis overflow mode, axis fallback, concurrent diagonal
  movement, gesture locking, precise/line delta conversion, inertia,
  scrollbar painting, scroll anchoring, or automatic reveal/focus scrolling.
- The existing element scene surface still emits background quads and clips.
  This change does not add text, border, or native-window rendering primitives.

## Evidence and provenance

The engine behavior reference remains the repository compatibility pin,
`zed-industries/zed@d9afb21688e04f89d9e94d96d33eb530aef90886`. The separate browser
execution harness uses `5a5fbe79917971a4d52a96b6ddb04da198a5012e`. The bounded behavior
was independently implemented in MoonBit after inspecting the following scoped
sources; correspondence checks confirmed the relevant production code is
byte-identical at both revisions:

- `crates/gpui/examples/scrollable.rs`, blob
  `c81795618875aecf06e06043bd1709c48630b58f`, selects nested two-axis viewports.
- `crates/gpui/src/elements/div.rs` supplies direct-child content measurement,
  padded/rounded limits, clamping, and dominant-axis same-delta wheel behavior.
- `crates/gpui/src/window.rs` supplies `with_content_mask`,
  `with_element_offset`, `layout_bounds`, `pixel_snap_point`, and
  `should_handle_scroll` context.
- `crates/gpui/src/style.rs::overflow_mask` identifies the visible-border mask
  limitation.

The inspected package declares Apache-2.0 in `crates/gpui/Cargo.toml` and its
`LICENSE-APACHE` resolves to the repository's Apache license. No upstream code,
test bodies, fixtures, or assets were copied into these core files. This
separate browser execution pin does not replace the repository-wide engine
compatibility pin.

`element/scroll_viewport_test.mbt` and `scroll_viewport_wbtest.mbt` are original,
source-derived contract tests. The initial unchanged-main run failed to
compile because the viewport API was absent. An intermediate API-scaffold
probe compiled but failed geometry/clip/wheel assertions before lifecycle
integration. That probe was a source adaptation, not an unchanged-main run.
Mutation checks that suppress translation or hit clipping fail the relevant
regressions. These are local test results, **not** an executed Rust browser
oracle, native-window comparison, GPU-pixel comparison, or a claim of general
GPUI equivalence.

Run the bounded suite with:

```sh
moon test element layout scene primitives --target js --deny-warn
```
