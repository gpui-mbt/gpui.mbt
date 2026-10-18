# Bounded anchored attachments and deferred drawing

This is a MoonBit-native element lifecycle API, informed by the actual pinned
GPUI `anchor.rs` shape. It is not general CSS absolute positioning, arbitrary
Block layout, Rust source compatibility, or a full GPUI overlay/occlusion API.

## Explicit API

`Element::anchored_after(id, after_child, popup, anchor, mode, position, margin=0.0)`
returns `Result[Element, ElementError]`. The labeled `margin` argument is
optional and defaults to zero, preserving existing six-argument calls. Append
the returned element with `with_child`.
All eight perimeter `Anchor` values and both `AnchoredPositionMode` values,
`Local` and `Window`, are supported. Anchor, mode and position are required;
there is no implicit Rust-default fit mode or unspecified-position contract.
Fitting is always `SnapToWindow`, with zero client inset and no additional
offset. `margin=8.0`, for example, supplies one symmetric scalar margin. The
margin must be finite and nonnegative; negative values, NaN and infinities
return `GeometryFailure` during construction. Finite margins larger than the
viewport are allowed. There is no per-edge margin or `SwitchAnchor` surface.

`attachment.deferred()` returns a priority-zero attachment.
`attachment.deferred(priority=5)` supplies an optional labeled `Int32` priority.
The bounded range is 0 through 2147483647; negative values return
`InvalidDeferredPriority`. Higher values paint later, with structural attachment
order preserved for flat ties. Exactly two anchored deferred levels are
supported; nested ties use discovery order as described below. Repeated
wrapping, applying it to an ordinary element, and a third level are rejected. Leaving an
attachment undeferred keeps its popup in structural paint order. Priority is
chosen when wrapping; rebuild the declarative attachment for a different
priority instead of wrapping an already deferred attachment again.

The owning parent must contain exactly one fixed-size, nonflexing ordinary
child first, followed only by attachments that reference that child's ID. Use
a column `FlexTreeStyle`, start alignment/justification, no wrapping, zero gaps,
and zero border/padding. The reference child's main/cross dimensions must be
points and its grow/shrink must both be zero. Ordinary ancestors may use the
existing flex/grid lifecycle to position this parent. The popup may contain an
ordinary nonwrapping flex subtree with auto or authored dimensions, intrinsic
leaf metrics, padding, borders and min/max limits. Context-dependent percentage
sizes and grid popup content are outside this first measurement surface.

The attachment wrapper is a real, stable structural node, but is not painted,
focusable, tabbable, or pointer-enabled. Its one popup child decides its own
paint/input behavior. To model the source example's plain popup, set pointer
events to false on its noninteractive subtree. Interactive popup testing is a
separate semantic case; a background color alone does not disable the existing
core pointer-events default.

## Core-owned measurement and placement

The ordinary tree is laid out first with attachments excluded from allocation.
The core derives the attachment's static origin from the owning parent's live
left edge and the reference child's live bottom edge. Every attachment after
the same reference uses that origin. This is the constrained source-equivalent
single-child Block case; callers cannot provide a static origin or final popup
rectangle.

The real popup subtree is then measured through the existing core recursive
layout engine at that absolute origin, including its device-scale boundary.
The popup root is measured without parent flex shrink/grow. Intrinsic text
metrics and authored sizes are valid leaf inputs; final placement fixtures are
not. Absolute-origin measurement preserves the layout engine's independent
near/far-edge snapping. This feature adds no production layout-package APIs.

For `Local`, the requested point is relative to this actual attachment origin.
For `Window`, it is in logical window coordinates. Placement subtracts the
selected anchor fraction of the measured popup size. SnapToWindow processes
right, left, bottom, then top. A right or bottom crossing subtracts the raw
overflow plus the scalar margin. A left or top crossing sets that coordinate
to the margin. Conditions use the viewport edges, not an inset viewport:
near-edge and exact-edge noncrossings do not receive an automatic inset. The
later left/top correction wins for oversized popups and for opposite-edge
crossings introduced by a right/bottom margin correction. There is one pass,
with no subsequent recheck of the right/bottom edges. Consequently a margin
larger than the viewport can legitimately place a popup outside it; the
viewport mask still governs painting and hits. A finite margin that is not
used by an edge crossing has no placement effect.

Correction and placement arithmetic must remain finite. Overflow is reported
as `GeometryFailure` before a later edge correction could hide it or a partial
prepaint tree could be published. The desired-minus-static translation is rounded to logical
integer pixels with midpoint ties away from zero. Only then is the element
offset snapped to device pixels with ties toward zero. These are two distinct
stages: at scale 1.25, a logical translation of +1 becomes +0.8 logical units;
a single device rounding of +0.5 would produce a different result.

`RequestedLayout.layout` describes the ordinary in-flow tree. Prepaint joins
the separately measured popup subtrees into the full structural tree. Read
`prepainted.tree().node(attachment_id).bounds()` for genuine static attachment
bounds and the popup/descendant node bounds for final translated geometry.
Neither accessor accepts geometry or bypasses layout. Request-layout and the
published nodes retain structural order independently of deferred paint order;
there is no Rust-style per-node lifecycle callback surface.

Nested attachment parents and references are resolved from their real containing
popup's measured layout, never from the ordinary-only request or a caller-supplied
rectangle. Nested measurement excludes the nested attachment from its parent's
in-flow allocation. Prepaint performs the discovery rounds, retaining captured
logical offsets separately from device-snapped bounds. It adds each outer and
inner logical translation once, then applies the layout-boundary device snap
to the composed offset. Moving an ordinary ancestor changes final bounds while
preserving the authored Local positions. The qualified nested corpus uses
integer logical coordinates aligned at all exercised device scales; it does
not establish fractional nested rounding parity.

## Drawing, masks and input

`ElementTree.nodes()` always retains structural preorder. Dispatch ancestry,
tab order, focus ownership and drag identities use this same tree. A separate
stable traversal paints ordinary nodes first, then deferred groups in ascending
priority order. Each group includes its ordinary descendants and excludes every
nested deferred group. Groups have independent identity even at equal priority.
Flat ties retain structural attachment order. For nested groups, an ordinary
pass discovers outer groups structurally; each stable priority-sorted prepaint
round discovers the next round in its traversal order. The final paint pass
sorts all discovered groups globally, preserving discovery ties. Thus a child
may paint before its parent, and equal-priority children of reversed-priority
parents follow parent prepaint order rather than structural DFS. Priority comparison never subtracts,
so maximum and adjacent large `Int32` priorities cannot overflow the comparator.
Hit testing visits the exact reverse paint traversal, selecting the last
eligible overlapping node. This preserves the existing single-target core
input model; it does not adopt GPUI's multi-listener or occlusion behavior.

Anchored trees carry the logical viewport mask for the ordinary pass and each
attachment subtree. Scenes contain balanced `ClipPushCommand` /
`ClipPopCommand` entries with the root or attachment ID, alongside unchanged
quad bounds. A root clip may remain open around an attachment clip when its
structural parent is still active, or close before a later deferred pass.
Oversized quads remain oversized, but their effective paint and hit coverage is
clipped to the viewport. Core hit coverage remains half-open: left/top included,
right/bottom excluded. Interior-point agreement with GPUI does not claim
closed-edge or general native occlusion equivalence.

Scroll, uniform-list and container-query composition anywhere in an anchored
declarative tree is rejected before callbacks/factories run. Query-generated
attachments are also rejected. A deferred attachment may contain one further
deferred attachment level. Both levels must use the bounded parent/reference
shape; an undeferred outer or inner attachment cannot form a nested path.
There is no element-transform API, cached-view reuse, or ordinary-deferred
surface. Nontrivial nested ancestor masks are explicitly rejected when
reassembling exported node snapshots: nested scheduling supports only the
common full-viewport mask, with no implicit clip restoration or transform
composition. Reassembling exported anchored and scroll/list node snapshots is rejected too;
this surface does not silently drop an ancestor mask or support scroll escape.

## Identity, updates and rejection

IDs remain globally unique. Element/layout-item ID mismatches, missing/foreign
reference children, unsupported parent shapes and modified wrapper input/paint
metadata fail explicitly. Validation occurs before publishing a tree.

`with_layout_bounds` retains the old focus acquisition only for compatible
structural/input metadata, including attachment-reference identity, deferred
priority (including changes that leave paint order unchanged) and viewport
masks. An incompatible refresh is rejected without
changing the retained tree. Ordinary dynamic bounds and popup translation can
refresh when that contract remains satisfied.

Removing an attachment subtree leaves its ordinary reference and surviving
focus ownership intact. Removing the owning parent removes the reference and
all attachments as ordinary structural descendants. Removing only a reference
while an attachment remains is rejected atomically, preventing a dangling live
reference. Earlier immutable snapshots are unchanged. Exported node snapshots
retain the independent group identity and exact inherited priority through
copy operations. Grafting a node with different group or priority metadata
under a deferred parent is rejected, even when the visible paint order would
be unchanged. Bounds-only refresh compares both group identity and priority.

## Evidence and limits

The source baseline is GPUI revision
`5a5fbe79917971a4d52a96b6ddb04da198a5012e`, exercised by the real headless GPUI
`Element` lifecycle in the supplemental anchor diagnostic. Its retained first
run is [conformance run 38991697984](https://github.com/gpui-mbt/gpui-conformance/actions/runs/38991697984)
at suite revision `d44b141f36c6133986ccd19e4137bed52ebc0852`:
24 cases, 82 frames and five paired click probes. The font-free corpus uses
explicitly authored popup sizes and `NoopTextSystem`; it does not establish text
rendering, font shaping, visuals, native window behavior, or arbitrary Block
compositions. The example/video evidence and its 24-case profile are unchanged.

The retained actual run establishes static origin `[80, 145]` after a 120x65
ordinary child in a parent at `[80, 80]`; all three tied popups share it. At
scale 1.25, the child's actual height is approximately 64.8 and the static
origin is approximately `[40, 144.8]`. Positive/negative half translations then
produce approximately `[40.8, 145.6]` and `[39.2, 144]`. Core tests assert these
observations, all eight anchors, coordinate modes, edge clamps, oversized
masks, deferred order, pointer transparency, focus/tab/drag identity and explicit
negative controls. Core arithmetic uses Double and the Rust baseline uses f32;
small numerical representation differences are not broader geometry tolerance.

The separate scalar-margin oracle is actual GPUI
[run 39019813091](https://github.com/gpui-mbt/gpui-conformance/actions/runs/39019813091),
artifact `12096028446`, at suite CI merge
`11d18c9dd7322aa134733f3a4fa99973b9cef267` (tree
`1098d462cb250cc280a23dcf854772cd50ee7f4b`). Its original `raw.json` SHA-256 is
`1d19d7bb63f3415ef13e1aca483af83c40815f7c3669791a9d406cd82af5ae35`.
The focused core regressions retain all 88 authored cases and all 264 observed
frames: margins 0/8, configured scales 1/1.25, and each actual bootstrap frame
at scale 2. These cover crossed, near and exact edges, corners, oversized
popups, margin-induced opposite crossings, and Local positive/negative half
offsets. Observed expected bounds are assertions only, never layout inputs.
The f32-versus-Double allowance is less than 0.000016 logical pixels. Explicit
zero and omitted-margin tree/scene geometry are compared exactly. Additional
core tests cover all eight anchors, invalid margins, arithmetic failure,
fractional margins, finite margins larger than the viewport, clipped hits,
focus-preserving refresh and unsupported-composition rejection.

These core regressions do not replace separately source-bound paired candidate
execution or executed paired-control evidence. The Rust margin run has no
pointer probes and does not establish new browser/native-window, text,
popover, arbitrary nesting, priority or client-inset claims. Core hit/scene
checks remain tests of the MoonBit lifecycle's documented contract.


## Flat nonzero priority evidence

The separate actual Rust priority observation is
[run 39024859010](https://github.com/gpui-mbt/gpui-conformance/actions/runs/39024859010),
artifact `12098386453`, at suite CI merge
`7dcd55101572269950ecbc4b69b88c806575c3ad` (tree
`e9ccfbb217339438fff87c010cdc5292d15ef889`). Original `raw.json` SHA-256:
`5739ab910b7f3bd5dcfa22769d7e6f4af52469bf609b32e0bfe2684e2d6b4ecd`.
The focused core tests retain the paint-entry-to-box projection of all 16
cases and all 224 observed frames: ascending, descending, equal nonzero,
reversed equal, zero, priority update, removal and restoration, at configured
scales 1/1.25 and bootstrap scale 2. Expected box-order labels and bounds are
assertions copied from actual callbacks. Core observations come from genuine
request-layout/prepaint bounds and actual scene-command emission. They never
come from a synthetic callback traversal. Nonpainting flex helpers express
the authored child offsets without accepting final rectangles as layout inputs.

This is a source-derived correspondence from Rust paint-entry callbacks to
core emitted boxes, not a capture of Rust scene primitives or proof of
layout/prepaint/paint callback equality. Rust's ordinary, transparent,
occluding and propagation-stopping fixtures supply identical paint-order
projections but different input callback lists. Those richer input results do
not establish input parity with this core and are not reproduced by changing
its single-target route. Alpha-zero backgrounds remain emitted and do not
implicitly disable core pointer events; use `with_pointer_events(false)` for
that behavior. Separate tests cover stable whole-subtree order, maximum and
adjacent priorities, negative errors, exact default-zero compatibility,
immutable copies/removal, structural tab/focus/dispatch/drag identities, and
rejection of priority changes during bounds-only refresh.

These focused tests do not replace separately source-bound paired candidate
execution, wrong-behavior controls or independent final-source review. There
is no new browser/native-window, raster, text, cached-view, outside-click,
arbitrary ordinary-deferred qualification. The bounded two-level nested evidence
is recorded separately below.


## Bounded two-level nested evidence

The separate actual Rust oracle is
[run 39032334348](https://github.com/gpui-mbt/gpui-conformance/actions/runs/39032334348),
artifact `12100643370`, at CI merge
`554bfe0908102375cef15efdc0ea7c15541b2621` (tree
`62ada6494e6f6ec6d463a1425f6e7daa2dadbce2`). Its original `raw.json` SHA-256 is
`b4fd41463d8a12da803ef04ffa37750ee25864e23a0def8e21f9528b5799fe50`.
The core regressions retain all eight cases and all 56 observed frames,
including each scale-2 bootstrap, both base frames at configured scale 1 or
1.25, priority update, nested-child removal, restoration, and ancestor movement.
Removal retains the updated parent priority; restoration restores the original
priorities. No observed frame is discarded or fitted.

The comparison is the source-derived projection of Rust paint-entry callbacks
to actual core emitted boxes and prepainted bounds. The four families are
increasing priorities, child-lower priorities, all-equal priorities, and
reversed parent priorities with tied children. Reversed parents paint
B, A, B.nested, A.nested; child-lower cases paint the children before their
parents. Ordinary before/after sentinels remain in their groups. A's nested
root is `[80, 68, 40, 32]`; moving its ordinary ancestor by `[16, 12]` yields
`[96, 80, 40, 32]`. Expected observations are assertions, never layout inputs.

The tests also exercise real balanced full-viewport scene masks, structural
focus/tab/drag/dispatch ancestry, the core's existing topmost hit semantics,
metadata copies, immutable removal/restoration, dynamic reference geometry,
priority/group-sensitive bounds refresh, maximum priorities, malformed
snapshots, and explicit unsupported composition/depth rejection. These are
core contract checks. The Rust oracle has no pointer probes and does not
establish input, outside-click, arbitrary clipping, transform, fractional
nested rounding, cache, raster, text, browser/native-window, arbitrary
ordinary-deferred, deeper nesting, or full upstream popover parity.

These source regressions do not replace independently reviewed final source,
source-bound actual paired candidate execution, or executed wrong-behavior
controls. The external original conformance corpora are unchanged.
## Opt-in measured-leaf attachment owners

`Element::anchored_after_measured_leaf` is additive to `anchored_after` and
uses the same ID, reference ID, popup, anchor, coordinate mode, position, and
optional margin arguments. It supports one intrinsically measured leaf inside
a padded/bordered owner. The existing constructor keeps its zero-inset,
fixed-reference acceptance boundary.

The owner must be a start-aligned, start-justified, nonwrapping column with
zero gaps. Padding and border must be finite and nonnegative. The owner may
be auto-sized or fixed-sized; percentage owner dimensions are excluded. Its
first child must be an Auto/Auto leaf with zero grow/shrink, default minimum
and maximum limits, and no child container or contextual layout behavior.
All following children must be measured-leaf attachments referencing that
same first child. Mixing constructor modes on one owner is rejected.

The production request-layout phase lays out the ordinary tree, reads that
reference leaf's actual requested bounds, and uses its left/bottom as the
static attachment origin. It does not add authored decoration to an owner
coordinate, use the owner's outer bottom, or accept a final reference box from
the host. Existing recursive layout derives auto-owner sizes from the measured
leaf and decoration, and separately measures the popup subtree. The existing
prepaint path retains window fitting, nested cumulative offsets, device
snapping, viewport masks and deferred ordering. Wrapper input/focus rejection,
popup restrictions, and the two-attachment-level limit are unchanged.

Core `Element` has no semantic text tag or shaping engine. An application can
represent text using an intrinsic-size leaf, but supplying those metrics is a
separate responsibility. Rebuild/request layout when metric inputs, scale or
viewport change. This API neither shapes fonts nor provides general Block
static-position layout.

### Evidence and validation boundary

The source-bound Rust diagnostic at conformance PR71 head
`e60bbe60c8c6946e46a61483a90043be8bfb7ae6`, upstream
`5a5fbe79917971a4d52a96b6ddb04da198a5012e`, observed the static cursor at the
text child's bottom-left for two tested single-text-child Block owners. It
distinguished that cursor from the decorated owner's outer bottom. The
[original execution](https://github.com/gpui-mbt/gpui-conformance/actions/runs/39083515918)
used upstream NoopTextSystem synthetic metrics. It is not real-font evidence.

The added tests use independent synthetic intrinsic inputs and the genuine
core request-layout/prepaint/paint functions. Their expected attachment
positions come from live reference geometry, not copied Rust oracle boxes.
They exercise decoration, auto sizing, metric changes, fractional scales,
nested fitting, restoration and explicit rejection boundaries. They do not
establish a paired 42-attachment Rust comparison. Existing core fitting uses
Double, while the pinned Rust arithmetic uses f32; that distinction remains
unchanged. Fractional text line heights and all paired numerical discrepancies
must be reported honestly in a subsequent adapter comparison. No system-font,
screenshot or unchanged-full-example BrowserLab parity is claimed here.

### Preserving measured attachment layout phase

Measured-leaf attachments carry the reference's solved absolute left/bottom into
popup measurement before final edge snapping. Authored lengths and intrinsic
metrics have already undergone the existing device-scale quantization. This
preserves cumulative centering offsets across separately measured popup trees;
it does not reconstruct an offset from a snapped rectangle. The legacy
`anchored_after` mode keeps its existing origin behavior.

`FlexTreeLayout::bounds_before_edge_snap(id)` exposes that solved rectangle for
layout composition and diagnostics. Ordinary `root_bounds()`/`items()`, prepaint,
hit geometry and paint retain their existing snapped bounds. An unknown ID
returns `None`. The layout retains only rectangles which differ from their
published bounds, falling back to the published rectangle when they are equal.
This adds an array header per layout and O(k) ID/rectangle storage and lookup for
k changed rectangles, with O(n) worst-case storage and lookup including ordinary
identity search. No performance improvement is claimed.

Upstream raw-phase behavior is currently supported by source analysis and paired
final outputs; upstream intermediate raw origins have not yet been instrumented.
This change does not establish real-font parity or alter the Double metric
quantization contract.
