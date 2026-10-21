# Opt-in authored root boxes and physical viewports

The existing `layout_flex_tree`, `Element::root(...).request_layout(...)`, and
explicit-device-scale variants continue to give the root a definite viewport
size. Their legacy snapping behavior is unchanged.

Use `layout_flex_root_box` or `layout_flex_root_box_with_device_scale` when an
origin-zero authored flex root must be at least as large as its padding and
border on each axis. This is a root border-box minimum, not intrinsic content
sizing. Child flex layout uses that authored box. `root_bounds()` can exceed
the offered size, and `overflow()` reports this even for an empty root.
Scaled layout quantizes authored insets before computing the minimum and then
snaps absolute edges, using the existing positive-border minimum-pixel rule.

For the element lifecycle, use `request_layout_root_box` or
`request_layout_root_box_with_device_scale`. These accept an ordinary
`Element::root`, but explicitly select the new sizing policy. The original
physical viewport is retained independently from root geometry:

- Root/background paint and child layout use the authored root box.
- `Prepainted::viewport_bounds()` and snapshot viewport use the original offered
  logical rectangle, without expanding it to the root or snapping it away from
  window metrics.
- Hit testing, drag eligibility and wheel targeting are additionally bounded
  by the physical viewport, including left/top and excluding right/bottom.
- Scroll containers retain their own authored local scrollport dimensions.
- A standalone `paint()` scene remains viewport-less. Physical clipping is a
  snapshot/raster/render-boundary contract, not destructive paint normalization.
- Focus operations preserve the physical viewport. `with_layout_bounds` accepts
  same-topology root-box frames only when the physical viewports match, and
  rejects mixing legacy and root-box paths. Scroll relayout remains unsupported.
- Outside-pointer listeners retain their existing geometry-based semantics.

The initial lifecycle path supports ordinary flex trees and ordinary scrolling.
Grid/mixed, container-query, anchored, deferred and uniform-list compositions
return `UnsupportedRootBoxComposition`; they never silently select legacy sizing.

Portable/headless tests are not evidence of physical desktop rendering, native
input, or universal CSS/GPUI equivalence.
