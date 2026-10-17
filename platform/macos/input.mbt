///|
pub fn Host::next_event(
  self : Host,
  timeout_ms~ : Int32 = 16,
) -> Result[@platform.Event?, @diagnostics.FrameworkError] {
  if timeout_ms < 0 || timeout_ms > 250 {
    return Err(error(@diagnostics.InvalidInput, "next_event"))
  }
  match self.check() {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  match status(call(6, 0, timeout_ms.to_double(), 0.0, b"", 0), "next_event") {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  decode_platform_event()
}

///|
/// Decodes AppKit scroll-wheel values without imposing a cross-platform unit
/// conversion. Precise deltas are points; non-precise deltas are lines/rows.
fn decode_scroll_event(
  x : Double,
  y : Double,
  delta_x : Double,
  delta_y : Double,
  modifiers : @primitives.Modifiers,
) -> Result[@platform.EventKind, @diagnostics.FrameworkError] {
  let position = match @primitives.Point::new(x, y) {
    Ok(value) => value
    Err(_) => return Err(error(@diagnostics.InvalidInput, "next_event"))
  }
  let delta = match @primitives.Point::new(delta_x, delta_y) {
    Ok(value) => value
    Err(_) => return Err(error(@diagnostics.InvalidInput, "next_event"))
  }
  Ok(@platform.Input(@primitives.Scroll(position~, delta~, modifiers~)))
}

///|
fn key_from_code(code : Int32, text : String) -> @primitives.Key {
  match code {
    36 | 76 => @primitives.Enter
    53 => @primitives.Escape
    51 => @primitives.Backspace
    117 => @primitives.Delete
    48 => @primitives.Tab
    49 => @primitives.Space
    123 => @primitives.ArrowLeft
    124 => @primitives.ArrowRight
    125 => @primitives.ArrowDown
    126 => @primitives.ArrowUp
    115 => @primitives.Home
    119 => @primitives.End
    116 => @primitives.PageUp
    121 => @primitives.PageDown
    _ => @primitives.Character(text)
  }
}
