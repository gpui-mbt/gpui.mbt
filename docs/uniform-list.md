# Bounded genuine-core uniform lists

`element.UniformList` is a vertical, top-to-bottom virtual element integrated
with the ordinary request-layout, prepaint, scene and input pipeline. Its
viewport participates in the parent's real flex layout. Its complete content
extent is independent of the number of materialized rows. There are no spacer
nodes, hidden all-item trees, browser geometry calculations or supplied row
heights.

## Authoring and lifecycle

Construct a `UniformList` with a parent-facing `layout.FlexItem`, nonnegative
item count, checked `UniformListIdSpace`, and range factory. Convert it with
`into_element()` and add it to an ordinary root. Viewport main/cross dimensions
must be definite point or percentage dimensions; indefinite auto/infer viewport
sizing is not supported. Ordinary parent flex allocation remains authoritative.

The factory receives a core-created half-open `UniformListRange`. `start()` and
`end()` select ascending indexes. Return exactly one row per index. Obtain its
root ID with `range.id(index, 0)` and descendant IDs with further local slots.
Row roots must have auto main/cross dimensions, zero growth, and no min/max
constraints. The core controls their no-shrink measurement and fits their width
to the allocated viewport. Rows can contain ordinary nested flex children,
authored padding/borders and intrinsic leaf metrics. Row-root height comes from
actual recursive layout, including authored insets. Percentage row dimensions,
row-owned scrolling, and virtual lists inside rows are rejected.

For each nonempty list, request-layout calls the factory for `[0,1)` and measures
that prototype using the real recursive layout engine. Prepaint repeats that
prototype measurement, computes full content height and a checked visible range,
and calls the factory for that range. Prototypes never enter the live tree.
Visible row subtrees are genuinely laid out, validated for uniform outer height,
and attached to the real list node in preorder. The two prototype calls and the
visible call are the only factory calls. Empty lists call no factory, have no
prototype and retain no live rows.

Factories must return stable content within a lifecycle invocation. Capture
changed metrics/model data in a new render. The materialization/storage bound is
two prototypes plus visible rows and their bounded ordinary subtrees, plus the
ordinary tree. A million-item list does not allocate a million-ID registry.
Existing recursive layout and materialized-tree validation costs still apply;
this is not a claim that all validation is linear.

After prepaint, `tree.uniform_list(id)` returns immutable `UniformListLayout`:

- `id()`, `item_count()`, `bounds()`
- `measured_item_size()`, absent only for an empty list
- `content_size()`, the complete virtual extent
- `visible_range()`, `offset()`, `max_offset()`

`tree.scroll_viewport(id)` reports the same bounds and Y position/limit, with
X zero. `Prepainted::paint()` uses the existing scene's actual clip push/pop
commands and paint order. Hit testing uses actual live node bounds and every
ancestor's half-open scroll mask. Partial rows cannot receive input outside a
list clip; right/bottom edges are excluded. Ordinary siblings and scroll
ancestors measure the list viewport, never its virtual content. Ancestor
translation is resolved before visible-row expansion, and the list offset is
applied exactly once.

## Scrolling and numerical scope

Pass a retained positive logical Y offset with `with_scroll_offset(y)`. Positive
Y moves content upward. Prepaint reclamps it against count, measured height and
allocated viewport changes without changing owner state or older trees.
`tree.scroll_wheel(position, dx, dy)` returns fresh updates; save the returned
Y and render again. The list uses nonzero `dy` even when `abs(dx)` is larger;
only when Y is zero does X become a vertical fallback. Ordinary two-axis scroll
ancestors retain dominant-axis selection independently. There is no residual
wheel redistribution, native capture or new overlapping-hitbox model.

Offsets/deltas must be finite. Finite extreme wheel inputs saturate at a limit.
Complete extent, row placement and namespace arithmetic are checked. Limits
reuse the core's two-decimal scroll-limit rounding. Visible indexes use Double
floor/ceil clamped to the full count in floating point before integer conversion.
The factory boundary rechecks the range before invoking user code. Device-scale
layout uses the existing recursive layout boundary. Zero-area viewports retain
half-open no-hit behavior; their range follows the same checked formula, and a
nonempty list may invoke an empty visible-range factory. Fractional/tiny/extreme
geometry and zero viewports are bounded candidate contracts, not a claim of
unexecuted upstream numerical equivalence. In particular, fractional virtual-row
translation is retained in logical coordinates after row layout; it is not an
assertion of GPUI's device-snapped element-offset behavior. The retained semantic
corpus uses integer offsets and 1x operational scale.

## Stable row clicks

`UniformListClickSession::new(list_id)` owns a shared one-shot pending press.
Call `reconcile(tree)` after **every successful fresh frame**, even with no
input, then `dispatch(tree, event)` for actual portable pointer events. Dispatch
also reconciles. `Pressed(index, id)` and `Clicked(index, id)` identify the
stable row root using the actual tree route, not pointer Y or its current
visible slot. Apply application effects only for `Clicked`.

A still-materialized row may keep its pending primary press while scrolling,
and release at that row's new bounds can click. If an intervening frame omits
the row, removes it by count change, removes the list, changes its namespace, or
disables its pointer eligibility, the pending press is cancelled. Reappearance
or numeric-ID reuse does not restore it. Release on another row or outside its
clip consumes the press without a click. No-down and duplicate releases do not
click. Session copies share consumption; nonprimary input does not admit a
primary press. Explicitly `cancel()` when replacing the logical list/model or
changing what descendant slots mean, even if numeric IDs remain equal.

This surface does not replace Button, DragGesture, DragSession or focus
ownership. Fresh `ElementTree::new` lineages remain fresh. The existing
same-topology `with_layout_bounds` operation still rejects scrolling trees.

## Validation and atomicity

For count N and stride S, reserve N×S IDs beginning at `first_id`; slot zero is
the root. Validate the complete reserved span arithmetically against list IDs,
ordinary ancestors/siblings and other list spans before factories run. Each
materialized row must use only its own slots, with no duplicates. Validation
never enumerates offscreen IDs. UInt64 overflow, invalid counts/slots/ranges,
wrong cardinality/root IDs, unsupported shapes, excessive combined tree depth,
zero measured height, nonuniform visible heights, layout failures and geometry
overflow return explicit errors. The list's own children/style are core-owned;
adding ordinary children, child-container style or generic scroll offset to a
converted list fails rather than being ignored.

A rejected lifecycle result cannot mutate older immutable trees, retained
owner offsets, focus tokens or click-session state. User factory side effects
(such as appending a trace) cannot be rolled back. A caller must reconcile only
successfully published frames, not failed attempted renders.

## Evidence boundary

The behavior reference for this new surface is genuine GPUI
`5a5fbe79917971a4d52a96b6ddb04da198a5012e`, specifically its
`crates/gpui/src/elements/uniform_list.rs`. The older repository-wide reference
is not interchangeable for uniform-list precision arithmetic.

The independent actual TestPlatform diagnostic at public source
`37cf7d18ec141993c1953c8e10e37006340b0c12`, signed CI source
`0e9b32f2e8d69c18262ba23d86b101c6e92b43b6`, tree
`93cc9ec841a66c0b6cc88597db540ba9cc25d0d3`, run `38968060005`, original artifact
`12075667392` is the qualified supplemental baseline. It retains nine bootstrap
2x frames and then explicitly switches to actual 1x. Its raw schema-2 evidence
covers 9 cases, 102 operation snapshots and 85 frames: two actual prototypes,
26→31 measurement, complete extent/clamps, million-item laziness, vertical wheel
fallback/mixed deltas, half-open masks and stable-row click lifetime.

These headless font-free observations are separate from browser raster/font
qualification. This implementation and its unit tests do not alone establish
an exact paired runtime/browser acceptance. The separate candidate adapters
must compile this exact core source and compare original raw outputs. No
variable-height/flipped lists, scrollbar UI, selection/navigation, generic
reconciliation, text-element expansion or broad scroll-to strategy is claimed.

## Local acceptance checks

The focused source snapshot passes 311 tests on each of JS, wasm, wasm-gc and
native, with warnings denied: 263 unchanged element/layout tests, 12 unchanged
Button tests, 29 new public-API uniform-list tests and 7 new white-box safety
tests. These include actual-call-count million/Int-max laziness, authored
padding, full-size allocation, metric/viewport/count reclamping, scene/hit masks,
click lifetime, ID boundaries/collisions, factory errors, nonuniform/unsupported
rows, combined depth, nonfinite/overflow inputs, and prior focus/drag contracts.
Formatting, generated interface and whitespace checks also pass. This is a
small-module local matrix; it does not assert full-repository CI, platform-host
compilation, browser acceptance or an executed mutant result.
