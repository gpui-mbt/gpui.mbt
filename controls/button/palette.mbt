///|
/// Immutable paint-only colors. Button state, geometry, and text validation are
/// independent of the palette; supplied Color alpha values are preserved.
pub struct ButtonPaintPalette {
  priv normal_border : @primitives.Color
  priv focused_border : @primitives.Color
  priv disabled_border : @primitives.Color
  priv normal_fill : @primitives.Color
  priv hovered_fill : @primitives.Color
  priv pressed_fill : @primitives.Color
  priv loading_fill : @primitives.Color
  priv disabled_fill : @primitives.Color
  priv enabled_foreground : @primitives.Color
  priv disabled_foreground : @primitives.Color
}

///|
/// Supply every role using already-validated colors. Selection precedence is
/// disabled > focused > normal for borders, disabled > loading > pressed >
/// hovered > normal for fills, and disabled > enabled for foregrounds.
pub fn ButtonPaintPalette::new(
  normal_border~ : @primitives.Color,
  focused_border~ : @primitives.Color,
  disabled_border~ : @primitives.Color,
  normal_fill~ : @primitives.Color,
  hovered_fill~ : @primitives.Color,
  pressed_fill~ : @primitives.Color,
  loading_fill~ : @primitives.Color,
  disabled_fill~ : @primitives.Color,
  enabled_foreground~ : @primitives.Color,
  disabled_foreground~ : @primitives.Color,
) -> ButtonPaintPalette {
  {
    normal_border,
    focused_border,
    disabled_border,
    normal_fill,
    hovered_fill,
    pressed_fill,
    loading_fill,
    disabled_fill,
    enabled_foreground,
    disabled_foreground,
  }
}

///|
/// The original Button colors, with opaque alpha, for backwards-compatible paint.
pub fn ButtonPaintPalette::standard() -> ButtonPaintPalette {
  ButtonPaintPalette::new(
    normal_border=button_paint_color(102, 126, 150),
    focused_border=button_paint_color(98, 170, 255),
    disabled_border=button_paint_color(100, 106, 114),
    normal_fill=button_paint_color(42, 71, 101),
    hovered_fill=button_paint_color(48, 91, 137),
    pressed_fill=button_paint_color(35, 77, 119),
    loading_fill=button_paint_color(55, 70, 88),
    disabled_fill=button_paint_color(47, 52, 60),
    enabled_foreground=button_paint_color(242, 246, 250),
    disabled_foreground=button_paint_color(166, 171, 178),
  )
}
