# Button paint palette

`controls/button` offers an immutable `ButtonPaintPalette` for callers that own
colors. `ButtonPaintPalette::new` requires ten labelled, validated
`primitives.Color` values:

- `normal_border`, `focused_border`, `disabled_border`
- `normal_fill`, `hovered_fill`, `pressed_fill`, `loading_fill`, `disabled_fill`
- `enabled_foreground`, `disabled_foreground`

Every supplied RGBA value is retained, including alpha. The opaque palette has
no setters, callbacks, theme resolution, or state. It is passed to
`button.paint_items_with_palette(item_id_base, palette)` and is not retained by
the Button. `ButtonPaintPalette::standard()` supplies the original opaque colors;
`button.paint_items(item_id_base)` delegates through that palette.

## Selection and compatibility

Border precedence is disabled, focused, normal. Fill precedence is disabled,
loading, pressed, hovered, normal. Foreground precedence is disabled, enabled.
Pointer and keyboard arming both count as pressed. State transitions and input
routing remain owned by Button and its caller; painting has no state effects.

The three items remain border quad, fill quad, and real text, with consecutive
IDs. The accepted base range is 1 through 18446744073709551612 inclusive. Focus
still gives a 2-pixel inset, otherwise 1 pixel; palette choice never changes
geometry. Text remains 16-pixel host-font text with the existing label bounds,
identity transforms, opacity 1, and no clip-chain reference. Color alpha and
item opacity are independent.

Validation retains the existing order: invalid base ID, invalid Button bounds,
then scene-construction failure. Empty labels and labels of 65536 UTF-16 code
units are accepted; longer labels fail through the existing scene validator.
There are no new error variants, scene/text APIs, or layout changes.

## Evidence boundary

Pre-change full-item JSON fixtures freeze original colors, IDs, ordering,
geometry, text, and metadata. Both default entry paths use those literals.
Sentinel fixtures cover every palette slot with distinct RGBA values, all 32
white-box state overlaps, pointer/Enter/Space arming, and minimum/fractional
bounds. Public input traces interleave painting with activation, cancellation,
focus, loading, disable, and resize transitions. These are portable model/scene
contracts; they do not establish OS rendering, native accessibility, IME,
browser display, or Yami theme integration.
