# Device-scale layout boundaries

`layout_flex` and `layout_flex_tree` continue to return raw logical geometry.
Call `layout_flex_tree_with_device_scale` or
`Element::request_layout_with_device_scale` when the caller needs the bounded
GPUI layout-boundary behavior at a known device scale.

The opt-in path keeps the stages distinct:

1. Absolute authored flex lengths are rounded to the nearest device pixel,
   with exact half-pixel ties toward zero. Percentage dimensions remain ratios.
2. Measured intrinsic sizes are ceiled to device pixels. Nonzero border strokes
   remain at least one device pixel wide.
3. Flex resolves in logical coordinates using those pre-rounded style values.
   The root viewport is not rounded before layout.
4. After layout, each box's absolute near and far edges are rounded separately.
   Nested nodes use their raw, unrounded ancestor origins for this step.

The returned values are still logical coordinates. This API does not snap text
caret positions, glyph origins, quads, or other paint primitives; those have
separate GPUI boundaries. It also does not change the raw `layout_flex` result
or claim general CSS, native-window, GPU, text, or raster compatibility.

`layout/device_grid_wbtest.mbt` covers authored half ties, measured-size ceiling,
negative origins, nonzero borders, and nested absolute-edge rounding. The
Linux headless flex-wrap corpus records the TestWindow scale with each
device-grid fixture and compares the resulting logical bounds at the existing
0.0001-pixel numeric tolerance. The tolerance is unchanged.
