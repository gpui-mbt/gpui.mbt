# Bounded anchored attachments and deferred drawing

This is a MoonBit-native element lifecycle API, informed by the actual pinned
GPUI `anchor.rs` shape. It is not general CSS absolute positioning, arbitrary
Block layout, Rust source compatibility, or a full GPUI overlay/occlusion API.

## Explicit API

`Element::anchored_after(id, after_child, popup, anchor, mode, position)` returns
`Result[Element, ElementError]`. Append the returned element with `with_child`.
All eight perimeter `Anchor` values and both `AnchoredPositionMode` values,
`Local` and `Window`, are supported. Anchor, mode and position are required;
there is no implicit Rust-default fit mode or unspecified-position contract.
Fitting is always `SnapToWindow`, with zero client inset, zero margins and no
additional offset. There is no `SwitchAnchor` surface.

`attachment.deferred()` returns a priority-zero attachment. Repeated wrapping
and applying it to an ordinary element are rejected. Higher priorities and
nested deferred draws are not supported. Leaving an attachment undeferred
keeps its popup in structural paint order.

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
right, left, bottom, then top, so an oversized popup aligns to the window's
left/top edges. The desired-minus-static translation is rounded to logical
integer pixels with midpoint ties away from zero. Only then is the element
offset snapped to device pixels with ties toward zero. These are two distinct
stages: at scale 1.25, a logical translation of +1 becomes +0.8 logical units;
a single device rounding of +0.5 would produce a different result.

`RequestedLayout.layout` describes the ordinary in-flow tree. Prepaint joins
the separately measured popup subtrees into the full structural tree. Read
`prepainted.tree().node(attachment_id).bounds()` for genuine static attachment
bounds and the popup/descendant node bounds for final translated geometry.
Neither accessor accepts geometry or bypasses layout.

## Drawing, masks and input

`ElementTree.nodes()` always retains structural preorder. Dispatch ancestry,
tab order, focus ownership and drag identities use this same tree. A separate
stable traversal paints ordinary nodes first and flat priority-zero deferred
subtrees afterward; hit testing visits the exact reverse paint traversal.
Deferred siblings retain their structural order, making the last overlapping
interactive popup the hit target.

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
attachments are also rejected. An attachment cannot contain another attachment.
Reassembling exported anchored and scroll/list node snapshots is rejected too;
this surface does not silently drop an ancestor mask or support scroll escape.

## Identity, updates and rejection

IDs remain globally unique. Element/layout-item ID mismatches, missing/foreign
reference children, unsupported parent shapes and modified wrapper input/paint
metadata fail explicitly. Validation occurs before publishing a tree.

`with_layout_bounds` retains the old focus acquisition only for compatible
structural/input metadata, including attachment-reference identity, deferred
classification and viewport masks. An incompatible refresh is rejected without
changing the retained tree. Ordinary dynamic bounds and popup translation can
refresh when that contract remains satisfied.

Removing an attachment subtree leaves its ordinary reference and surviving
focus ownership intact. Removing the owning parent removes the reference and
all attachments as ordinary structural descendants. Removing only a reference
while an attachment remains is rejected atomically, preventing a dangling live
reference. Earlier immutable snapshots are unchanged.

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

Local validation is the element package on the JS target with warnings denied.
Other compiler targets and aggregate repository checks require CI; a focused
JS pass is not an all-target or native conformance claim.
