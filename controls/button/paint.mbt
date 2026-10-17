///|
/// Errors from assembling a button's bounded scene items.
pub(all) enum ButtonPaintError {
  InvalidItemId
  InvalidBounds
  SceneFailure(@scene.SnapshotError)
} derive(Eq)

///|
pub extend ButtonPaintError with Eq::{not_equal, equal}

///|
fn button_paint_rect(
  x : Double,
  y : Double,
  width : Double,
  height : Double,
) -> Result[@primitives.Rect, ButtonPaintError] {
  match @primitives.Rect::new(x, y, width, height) {
    Ok(value) => Ok(value)
    Err(_) => Err(InvalidBounds)
  }
}

///|
fn button_paint_quad(
  id : UInt64,
  bounds : @primitives.Rect,
  color : @primitives.Color,
) -> Result[@scene.SceneItem, ButtonPaintError] {
  match
    @scene.SceneItem::quad(
      id,
      bounds,
      color,
      @scene.AffineTransform::identity(),
      1.0,
      None,
    ) {
    Ok(value) => Ok(value)
    Err(error) => Err(SceneFailure(error))
  }
}

///|
fn button_paint_color(r : Int32, g : Int32, b : Int32) -> @primitives.Color {
  @primitives.Color::rgba(r, g, b, 255).unwrap()
}

///|
/// Emit a compact frame contribution: border, fill and a real host-font text
/// item. The owner reserves three adjacent item IDs and merges the copied items
/// into its SceneSnapshot. This carries no native accessibility semantics.
pub fn Button::paint_items(
  self : Button,
  item_id_base : UInt64,
) -> Result[Array[@scene.SceneItem], ButtonPaintError] {
  self.paint_items_with_palette(item_id_base, ButtonPaintPalette::standard())
}

///|
/// Paint using caller-supplied colors without changing state, item IDs/order,
/// geometry, or label validation. The palette is not retained by the Button.
pub fn Button::paint_items_with_palette(
  self : Button,
  item_id_base : UInt64,
  palette : ButtonPaintPalette,
) -> Result[Array[@scene.SceneItem], ButtonPaintError] {
  let maximum_base : UInt64 = 18446744073709551612
  if item_id_base == 0UL || item_id_base > maximum_base {
    return Err(InvalidItemId)
  }
  if !button_bounds_valid(self.bounds) {
    return Err(InvalidBounds)
  }
  let border = if !self.enabled {
    palette.disabled_border
  } else if self.focused {
    palette.focused_border
  } else {
    palette.normal_border
  }
  let fill = if !self.enabled {
    palette.disabled_fill
  } else if self.loading {
    palette.loading_fill
  } else if self.is_pressed() {
    palette.pressed_fill
  } else if self.hovered {
    palette.hovered_fill
  } else {
    palette.normal_fill
  }
  let foreground = if !self.enabled {
    palette.disabled_foreground
  } else {
    palette.enabled_foreground
  }
  let bounds = self.bounds
  let border_item = match button_paint_quad(item_id_base, bounds, border) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let inset = if self.focused { 2.0 } else { 1.0 }
  let fill_bounds = match
    button_paint_rect(
      bounds.left() + inset,
      bounds.top() + inset,
      bounds.size().width() - inset * 2.0,
      bounds.size().height() - inset * 2.0,
    ) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let fill_item = match
    button_paint_quad(item_id_base + 1UL, fill_bounds, fill) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let text_bounds = match
    button_paint_rect(
      fill_bounds.left() + 8.0,
      fill_bounds.top() + 2.0,
      fill_bounds.size().width() - 16.0,
      fill_bounds.size().height() - 4.0,
    ) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let label_item = match
    @scene.SceneItem::text(
      item_id_base + 2UL,
      text_bounds,
      self.label,
      16.0,
      foreground,
      @scene.AffineTransform::identity(),
      1.0,
      None,
    ) {
    Ok(value) => value
    Err(error) => return Err(SceneFailure(error))
  }
  Ok([border_item, fill_item, label_item])
}
