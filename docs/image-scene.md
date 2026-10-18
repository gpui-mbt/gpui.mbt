# Bounded image scene references

This is an image-resource and element-binding prerequisite, not a complete image
subsystem or a full port of the upstream `opacity` example.

`ImageData` is immutable metadata naming encoded bytes by lowercase SHA-256. It
contains uniform prepared-frame dimensions and frame count. It does not contain
pixel bytes, decode images, fetch URLs, animate frames, or hold host handles.
Dimensions are 1..16,384, frame count is 1..256, and total prepared pixels are at
most 16,777,216. A host must verify the identity and dimensions against the actual
bytes, prepare the selected frame, and reject unsupported formats/features before
any presentation. Pixel alpha belongs to those decoded bytes and is independent
of item opacity. Frame indices outside the metadata range fail closed; this
bounded API does not implement upstream image-change frame-index clamping.

`SceneResource::new(id)` still constructs the old id-only placeholder and retains
its canonical JSON. `SceneResource::image(id, data)` constructs a resource-backed
reference. Image resource tables reject duplicate IDs, inconsistent metadata for
the same content identity, missing entries, and references to placeholders.
Existing legacy-only resource tables retain their prior behavior.

`ImageCommand` embeds its resource reference. `Scene::validate` checks every image
command and resource conflict before snapshot conversion; `snapshot_v1` collects
resources once in first-use order. `SceneSnapshot::new` validates image references,
frame indices, transforms, geometry, opacity and clip links before returning a
snapshot. Canonical image resources have fields `id`, `kind: "image"`,
`content_identity`, `pixel_width`, `pixel_height`, `frame_count`. Image items have
`kind: "image"`, `id`, `resource_id`, `frame_index`, `bounds`, `image_bounds`,
`transform`, `opacity`, `clip_chain_id`. Existing items keep their original bytes.

`bounds` is the complete fitted sprite, while `image_bounds` is its element crop.
An image renderer clips to image_bounds and the ancestor clip chain, then draws
the full sprite bounds. Core does not round/crop atlas texels or implement rounded
corners; image corner radii, sampling filters and native/GPU texture upload are
outside this subset. Hosts must explicitly reject unsupported image transforms
and prepared frames rather than omitting them.

`ElementImageBinding` resolves Contain/Cover/Fill from actual prepainted bounds and
replaces only that element's background. The existing deferred traversal applies
ancestor and local opacity once, with no alpha quantization, and preserves sibling
scope, clipping, hit testing and immutable repaint. Binding opacity is an
additional scalar; intrinsic pixel alpha is never baked into it. The image and
paint binding entry points are separate; mixed enhanced-paint/image binding in one
call is not supplied by this prerequisite.

The containment rule follows pinned Zed GPUI
`5a5fbe79917971a4d52a96b6ddb04da198a5012e`,
`crates/gpui/src/elements/img.rs` test
`explicit_aspect_ratio_is_not_overridden_by_intrinsic_ratio`: a 100×200 image in an
explicit 100×100 element, Contain, yields bounds `(25,0,50,100)`. Cover of the same
image yields `(0,-50,100,200)` with the square element retained as crop.
`crates/gpui/src/window.rs` `paint_image` is the source of the separate sprite,
image crop, content mask, frame identity and element-opacity responsibilities.

ImageItem, ImageCommand, Image PaintKind and image error variants are additive
public enum cases: exhaustive downstream matches need updating. Legacy native
presenters reject the whole image-bearing frame before native calls. Core enhanced
paint rasterizers return UnsupportedPaint for images because they do not have
decoded pixels. This makes unsupported rendering explicit rather than silently
skipping an image. Browser image presentation is a separate opt-in host capability.

Tests cover immutable resource/item arrays, resource collisions, missing resources,
prepared-frame selection, containment and cover crop, actual prepaint opacity,
sibling restoration, transparent hit behavior and ancestor clipping. These source
tests do not by themselves prove browser pixels or native image support.
