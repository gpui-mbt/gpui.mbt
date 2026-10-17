# Bounded enhanced paint

Enhanced paint extends the existing `Scene` → `PaintCommand` → `SceneItem` →
`SceneSnapshot` pipeline. It does not introduce a second scene or element tree.
The v1 envelope is extensible; the legacy v1 renderer subset is narrower.
Existing Quad, Text and TextRun canonical bytes, clip numbering, order, byte
`Color`, and native 19/23/25-double records are unchanged.

## Construction and validation

- `primitives.FloatColor` stores finite, unpremultiplied Double RGBA channels in
  [0,1], retaining authored precision (including green 0.5). It is separate from
  byte sRGB `Color`. These source values inhabit the pinned shader's linear RGB
  domain; they are not automatically decoded from sRGB bytes.
- `LinearGradient` has exactly two FloatColor stops, a finite raw angle, finite
  raw stop positions, and `Srgb` or `Oklab` interpolation. Positions remain
  unsorted, unclamped and potentially equal. There is no multi-stop/pattern API.
- `PaintFill` is `FloatSolid` or `Gradient`.
- `PaintShape` is a rounded quad or a strictly convex filled polygon, either
  winding, with 3–64 distinct non-collinear vertices. Polygon points are copied
  on ingress/egress, and bounds are computed rather than supplied. Coordinates
  lie in [-1e9,1e9]; quads have positive dimensions and radius in
  [0,min(width,height)/2]. Self-intersections, concavity, duplicate/collinear
  vertices and nonfinite values are rejected, not repaired.
- `PaintCommand::paint` and `SceneItem::paint` validate shape, fill and opacity.
  Scene validation and both snapshot freeze paths recheck the same invariants,
  including public enum construction. Existing legacy validation is unchanged.
  Polygons cannot expose their owned mutable arrays through command/item copies.

`SceneSnapshot::legacy_v1_subset()` is fallible. It returns the same snapshot
for Quad/Text/TextRun-only frames, and `UnsupportedPaint` for any enhanced item.
Native presenters and packers invoke it before allocation or frame submission;
there is no skipped-paint, solid-color substitution or partial frame fallback.

## Numerical contract and backend boundary

The numerical model follows pinned GPUI WGSL at upstream
`5a5fbe79917971a4d52a96b6ddb04da198a5012e`, including source angle offset,
remainder, literal PI, aspect adjustment, directional projection, working-space
conversion and straight-alpha interpolation. `sample_shader_linear` explicitly
returns shader-linear RGB, not display-encoded channels. Srgb interpolation
encodes source linear endpoints, mixes them, then decodes the result; Oklab
converts linear endpoints to Lab, mixes, and converts back. Alpha is independently
interpolated without premultiplication. This implementation uses Double rather
than shader f32 and clamps final RGB into the bounded FloatColor gamut.

Equal stops have an explicit deterministic policy: use the start color at and
before the normalized stop position, and the end color after it. This matches the
qualified 161-pixel software WebGL2 observation (81 red then 80 blue), but is not
a statement about GPU NaN/Inf/clamp semantics or other backends. No universal
shader behavior is inferred from that screenshot.

Polygon gradient normalization uses actual tight bounds after rectangular
clipping, not the nominal layout allocation or merely its bounding-box
intersection. Quads retain their original gradient bounds. Coverage is binary:
rounded/path edge antialiasing remains an explicit presentation boundary.

## Binding real elements

`ElementPaintBinding::new(id, resolver)` receives the current prepainted node's
actual `Rect`; its resolver returns `(PaintShape, PaintFill, opacity)` or an
error. `Prepainted::paint_with_paints` and `ElementTree::to_scene_with_paints`
replace only bound node backgrounds through the existing traversal, deferred
order and clip stack. They do not change hit testing or lifecycle geometry.
Missing/duplicate binding IDs are rejected before any resolver is invoked, and
any invalid resolved paint prevents returning a scene. Resolver callbacks should
be pure; arbitrary callback side effects cannot be rolled back.

## Bounded reference presentation

- `sample_paint(id, point)` selects an enhanced item, resolves transform, clips,
  shape coverage, gradient basis and opacity, and returns an optional FloatColor.
  Duplicate selected IDs produce `AmbiguousPaint`; legacy duplicate IDs remain
  permitted. Outside/clipped samples are `None`, not transparent replacements.
- `rasterize_webgl2_linear(bounds,width,height,background)` processes one
  canonical snapshot in order, composites float values, and only then converts
  to straight RGBA8. It explicitly models the observed final-canvas software
  WebGL2 raw-linear byte route. It applies no display transfer function and makes
  no physical-GPU, WebGPU, native Vulkan or Metal equivalence claim.
- `rasterize_item_tile_webgl2_linear(index)` returns the item's clipped-tight
  physical tile at snapshot scale. `rasterize_paint_run_webgl2_linear(start,count)`
  does the same for an exact contiguous canonical item range. Tile RGBA arrays
  are copied on egress. Empty geometry returns `None`; text is an explicit
  `UnsupportedPaint` error, never silently omitted.
- Runs preserve interleaving: a presentation leaf may upload/source-over a tile
  at identity transform, full opacity and without extra clipping, then handle the
  next legacy text record in its original position. It must not reorder paints
  across text, reapply opacity or recompute gradient/geometry in JavaScript.
- Independent RGBA8 tiles quantize alpha before subsequent composition. To test
  exact alpha bytes, include the existing opaque background item and translucent
  paints in the same contiguous core run (or use whole-snapshot rasterization).
  Do not claim float-compositing equivalence across separately quantized tiles.
- Raster helpers reject text and non-axis-aligned or singular transforms.
  Canonical snapshots still accept finite affine transforms. Limits are 2048 per
  dimension, 1,048,576 pixels, and 64,000,000 item-pixel evaluations, checked before
  byte allocation. Physical tile edges must fit signed 32-bit coordinates.

No native enhanced rendering, glyph equivalence, antialiasing equivalence,
physical-GPU/backend parity or universal color conformance is established here.
The unchanged upstream oracle, synthetic policy diagnostics and candidate remain
separate evidence categories.
