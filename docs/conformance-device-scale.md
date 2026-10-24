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
