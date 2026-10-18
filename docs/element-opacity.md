# Element opacity

`Element::with_opacity(Double)` and `ElementNode::with_opacity(Double)` accept
finite values in `[0, 1]` and return `InvalidOpacity` otherwise. The default is
one. The `opacity()` getter returns the local scalar, not accumulated opacity.

Ordinary descendants multiply their local scalar by their parent's accumulated
scalar. Background color alpha and enhanced paint-fill alpha remain intrinsic;
the inherited scalar multiplies existing binding opacity once at scene emission.
There is no intermediate RGBA8 alpha conversion. This is per-primitive opacity,
not an isolated group/offscreen compositing operation. Two overlapping children
therefore composite independently.

Opacity does not alter layout, scroll clips, hit testing, pointer routing or
focus. Zero-opacity elements remain in the tree and emit transparent primitives.
Immutable frame repainting does not accumulate the previous frame's opacity.

## Deferred scope

Each deferred attachment group begins a new inherited-opacity scope, including
nested groups that paint before their structural parents. Its own local opacity
still applies to its ordinary descendants. Ancestor opacity outside that group
does not carry into deferred painting.

This follows pinned upstream GPUI commit
`5a5fbe79917971a4d52a96b6ddb04da198a5012e`:

- `crates/gpui/src/window.rs`, blob `33fa14bfea6ebad50743d6d4014955d1055ef772`,
  lines 4226–4242: save the previous scalar, multiply by local opacity, paint,
  and restore it.
- `crates/gpui/src/elements/div.rs`, blob
  `5d3b03b057bcac09f987a4587598a08a06872361`, line 2544: the opacity scope wraps
  both style painting and child painting.
- `window.rs` lines 1031–1045 and 4518–4543: deferred state does not capture
  element opacity. Lines 3953–3982 paint deferred elements later under their
  captured content mask and rem size, outside ordinary ancestor paint scopes.
- `crates/gpui/src/elements/deferred.rs`, blob
  `ddf324a6b26b861ca0e7ef1c2ede3d648abe82a2`, schedules the child during prepaint.

The source tests are contract checks, not a claim of an executed upstream oracle
or a full port of the asset-dependent upstream opacity example.

## Scene compatibility

Unit effective opacity preserves existing `QuadCommand` output byte-for-byte.
Nonunit background opacity uses the additive public `OpacityQuadCommand`
variant, retaining its original byte color and legacy geometry, including zero
extents and coordinates outside enhanced paint's bounded geometry. Its kind is
still `Quad`. `PaintCommand::opacity()` reports the scalar;
`PaintCommand::with_opacity()` multiplies it and leaves clip commands unchanged.

`Scene::snapshot_v1` lowers both quad variants into the existing `QuadItem`
shape, with scalar opacity separate from color alpha. No snapshot schema change
or renderer transport variant is required. Command snapshots of the new variant
add an `opacity` field; legacy unit command snapshots are unchanged.

External code exhaustively matching the public `PaintCommand` enum must handle
the new variant. Existing constructors and old variants are unchanged, but this
additive enum case is a source-compatibility consideration. All in-repository
direct enum consumers were audited against main `fa7120e`; rasterizers and host
renderers consume the unchanged `SceneItem` representation.

## Validation

Tests exercise real Element → request_layout → prepaint → scene flows, including
nested ordinary scopes, sibling restoration, intrinsic/binding alpha, zero
opacity input/focus behavior, scroll clipping, generated query descendants and
deferred scope reset. White-box tests cover nested deferred priority order and
the malformed scalar boundary. Scene tests preserve zero/large legacy geometry.

The editing environment has no active MoonBit compiler. Source preparation and
review do not mean compilation, formatting or test execution passed. Run the
repository's normal MoonBit formatting/interface generation and all-target test
workflows before merging.
