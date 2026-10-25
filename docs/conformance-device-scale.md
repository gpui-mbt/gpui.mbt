# Device-scale layout boundaries

`layout_flex` and `layout_flex_tree` continue to return raw logical geometry.
Call `layout_flex_tree_with_device_scale` or
`Element::request_layout_with_device_scale` when the caller needs the bounded
GPUI layout-boundary behavior at a known device scale.

The opt-in path keeps the stages distinct:

1. Absolute authored flex lengths are rounded to the nearest device pixel,
   with exact half-pixel ties toward zero. The horizontal and vertical authored
   gaps are snapped independently. Percentage dimensions remain ratios.
2. Measured intrinsic sizes are ceiled to device pixels. Nonzero border strokes
   remain at least one device pixel wide.
3. Flex and mixed flex/grid trees resolve in device-pixel coordinates using
   those pre-rounded style values. Offered root extents and supplied root origins
   are scaled but not rounded before layout; an explicit authored mixed-root size
   is pre-rounded like other point dimensions. Percentage dimensions and flex
   bases remain ratios throughout preparation.
4. After layout, each box's absolute near and far device edges are rounded
   separately. Nested nodes use their raw, unrounded ancestor origins for this
   step. Origin and extent are divided by the scale only after edge subtraction.
   Pre-edge metadata is also converted back to logical coordinates.

Keeping the solve in device pixels avoids recurring logical fractions at scales
such as 1.5 from pushing exact half-pixel edges above their ties. No epsilon or
comparison-tolerance adjustment is used.

The returned values are still logical coordinates. This API does not snap text
caret positions, glyph origins, quads, or other paint primitives; those have
separate GPUI boundaries. It also does not change the raw `layout_flex` result
or claim general CSS, native-window, GPU, text, or raster compatibility.

`layout/device_grid_wbtest.mbt` covers authored half ties, measured-size ceiling,
negative origins, nonzero borders, and nested absolute-edge rounding. The
Linux headless flex-wrap corpus records the TestWindow scale with each
device-grid fixture and compares the resulting logical bounds at the existing
0.0001-pixel numeric tolerance. The tolerance is unchanged.

`layout/device_space_test.mbt` retains five measured half-edge profiles across
both axes and pure/mixed tree paths, including Auto/point controls, percentage
shrink, wrap and wrap-reverse. Full differential results belong to the separate
gpui-conformance corpus; these unit tests alone do not establish parity.

## Distributed spacing arithmetic

For fitting `space_between`, `space_around`, and `space_evenly` lines with
at least two children and zero grow/shrink on every child, the device-grid path
matches the pinned GPUI/Taffy single-precision placement order: compute f32
free space and alignment offsets, then accumulate from the physical content
origin in flow order (reversed for reverse directions). The origin participates
before each item offset, not after relative placement. Both pure and mixed
flex trees use this path for nowrap and each wrapped line.

This matters even for integer authored inputs. A 142-pixel row with left/right
padding 14/10, gap 6, child widths 12/20/49, and reverse `space_around` places
the middle child at device pixel 82: its f32 near edge is just above 81.5.
Double relative accumulation instead reaches exactly 81.5 and snaps to 81.
Forward flow can also differ at fractional device scales. No epsilon, changed
tie rule, or relaxed comparison tolerance is used.

This is not a conversion of the complete solver to f32. The raw logical APIs
remain Double. Flexible lines, singleton/exact-fit/overflow fallback cases,
non-distributed justification, and metrics or accumulated used extent above
2^24 device pixels keep the prior stable path. Cross-axis alignment and flex
negotiation arithmetic are unchanged. The bound prevents applying this
compatibility approximation to the raw engine's huge finite geometry contract.

Percent-basis lines retain the existing Double path: percent resolution and
far-edge snapping must remain consistent, rather than mixing f32 positions
with Double-derived percentage sizes. Full f32 percent resolution is outside
this bounded compatibility path.

The compatibility path additionally requires a zero absolute container origin
on its main axis, non-percentage main dimensions, exactly f32-representable
child sizes, and identical final device-grid far-edge snapping between f32
and Double addition. Lines failing these checks retain the existing Double
path. This avoids introducing translated/nested-origin or far-edge regressions;
it does not claim complete Taffy f32 layout compatibility.
