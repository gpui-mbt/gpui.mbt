# Bounded grid and container queries

This opt-in portable layout slice supports the layout primitives used by pinned
GPUI's `grid_layout.rs`. It does not yet claim runtime conformance with that
example; independent pinned-GPUI observations and the paired diagnostic suite
are separate evidence. No renderer, text measurement, paint-order, or backend
behavior is added here.

## Explicit grid

`GridTreeStyle::new(columns, rows)` requires positive counts with at most 4096
cells. The division-based cap check runs before multiplication or allocation.
Every track is a zero-minimum equal-fraction track. For each physical axis:

```
track_extent = max(0, content_extent - all_gaps) / track_count
```

Physical horizontal/vertical gaps, padding and border are supported. Track
allocation never grows to accommodate an item's content or authored size.

`GridItem::new(id, width, height)` has physical dimensions, independent of
`FlexItem.main` and `FlexItem.cross`. Auto fills its assigned grid area; points
retain their authored size; percentages resolve against that area's size,
including any internal gaps of a span. Fixed dimensions may overflow. The
upstream example's 224-pixel table of contents can therefore extend beyond its
one assigned row.

Items are auto-placed in sparse row-major order, checking the complete occupied
rectangle for multi-row/multi-column spans. Placement never revisits earlier
holes. `with_span(columns, rows)` sets an automatic span. `full_columns()` means
definite column lines 1 through -1 and moves to a suitable full-width row after
a partial row. Results and painting remain in declaration preorder.

The subset intentionally omits implicit tracks, dense flow, RTL, general line
placement, unequal fractions, intrinsic/minmax tracks, grid margins, and
arbitrary alignment. A span that cannot fit returns `InvalidSpan` or
`PlacementExhausted`; it does not allocate an implicit row. Invalid counts,
duplicate IDs, non-finite arithmetic, geometric overflow and unrepresentable
bounds return explicit errors.

Overflow comparisons use the existing bounded binary64 tolerance from flex
layout, so reconstructed far edges do not turn exact-fit fractional tracks into
overflow. Meaningful excess from fixed-size items remains overflow.

## Mixed trees

Use `Element::grid_root` for a viewport grid root, `Element::grid_item` for an
item whose parent is a grid, and `with_grid_children_style` for grid children
inside a flex-allocated element. A grid item can use `with_children_style` for
its own flex children. The child-layout style builders replace one another;
other builders preserve all grid/query metadata.

`MixedTreeItem` and `MixedTreeStyle` distinguish parent allocation from the
layout of descendants. A flex item under a grid, or a grid item under a flex
container, returns `MismatchedItem`. Flex containers may contain definite-size
grid containers. If recursive auto measurement reaches a grid it returns
`UnsupportedIntrinsicGrid` rather than guessing an intrinsic track size.

Pure-flex trees retain their existing layout and prepaint path. The mixed path
retains raw logical positions through recursive layout. Device-scale layout
snaps authored lengths before resolution and final absolute near/far edges
after resolution. It never snaps each local grid rectangle and then adds its
parent origin. `layout_mixed_tree_at` exposes this same bounded dispatch for
headless callers; optional `root_size` is an authored size and is snapped before
resolving descendants.

## Query lifecycle

`with_container_query(callback)` turns a childless element into a request-layout
measurement leaf. Its flex/grid allocation is determined solely by its declared
item and its parent. `container_query_root(id, callback)` is the full-viewport
root form. Static children on a query are rejected.

No callback runs during `request_layout`, including device-scale requests. During
prepaint, each encountered callback receives its actual assigned `Size`, not the
window viewport. Its returned `Element::root` or `Element::grid_root` is laid out
independently against that definite size, then attached at the query's actual
origin. Each generated root lays out at zero and rounds its own absolute edges
before its separately snapped query origin is added. This independent-root
boundary matters at negative midpoint coordinates; ordinary descendants within
each mixed tree still round their final absolute edges together. Nested queries
retain cumulative origins, depth and preorder.
Overflow at the translated query boundary uses the same bounded binary64
tolerance as layout, while keeping the assigned and generated pixel bounds
unchanged. Exact-fit translation residue is ignored; genuinely oversized roots
still report overflow.

Generated roots fill the offered size by default. The bounded
`with_query_root_size(Size)` override supplies explicit physical dimensions for
a generated root, including a tiny or overflowing root. It does not change the
query's outer allocation. The authored override snaps before descendant sizing
on device-scale requests. Ordinary top-level requests and non-root descendants
reject this metadata; it is not a general root-sizing API.

A query-bearing `RequestedLayout` has a one-shot prepaint lease. It is consumed
before the first callback. Repeated or reentrant prepaint returns
`AlreadyPrepainted`, and failure also consumes the request. A fresh request may
reuse the same declarative Element. Plain flex and query-free grid requests keep
repeatable prepaint. This is a MoonBit per-request contract, not a promise of
Rust object-reuse equivalence.

All static IDs are reserved before callbacks, and each complete generated
subtree is validated and reserved before nested callbacks. Duplicate numeric
IDs, invalid returned roots, invalid child roots, invalid preorder, and cumulative
depth beyond 64 are rejected before any live `ElementTree` or scene is exposed.
Callback side effects cannot be rolled back. Earlier successful results remain
immutable.

Queries cannot have a scroll ancestor or generated scroll descendant. A
query-bearing tree cannot contain a uniform list in this first slice. Grid
scroll containers are unsupported. Grid/query content in uniform-row factories
is rejected before prototype measurement. Ordinary pure-flex scroll/list paths
remain unchanged; query-free grids below ordinary flex scroll containers, and
unrelated ordinary scroll siblings of queries, remain supported.

Grid gaps hit their container. Fixed overflow remains hittable when no scroll
clip intervenes. Existing `with_layout_bounds` same-topology, same-viewport,
non-scroll and focus-lineage constraints remain unchanged. A newly resized tree
cannot adopt an old tree's focus owner.

## Focused checks

`layout/grid_wbtest.mbt` covers generic track counts, asymmetric physical gaps and
insets, percentages, sparse holes and whole-span occupancy, full columns, fixed
overflow, zero-min tracks, numeric guards, and absolute-edge snapping.
Exact-fit fractional far-edge residue and genuine fixed overflow are checked on
both axes, including an ordinary negative-origin absolute-snapping control.

`element/grid_query_wbtest.mbt` covers deferred and nested callbacks, allocated
size and nonzero origin, tiny/huge independent roots, root-size snapping,
independent-root negative-midpoint rounding on both axes at device scales 1,
1.25 and 2, positive-origin controls and nested translated roots,
both-axis exact-fit translation residue and genuine oversized-root controls,
reentrant/failure/repeat leases, global ID and cumulative-depth guards, invalid
roots, unsupported combinations, builder chains, scroll siblings, hit testing,
immutable results, and focus/bounds-refresh constraints. These assertions are
intended to reject eager-callback, viewport-input, dense-placement,
content-grown-track, local-rounding, missing-origin, missing-ID, and depth-reset
regressions. Independent engine mutation runs and actual Rust pairing must be
reported separately.
