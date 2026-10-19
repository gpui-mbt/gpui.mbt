///|
/// Enable or disable the AppKit text-composition client for one window.
/// Enabling makes the owned content view the first responder; disabling
/// cancels any marked text before the host stops publishing composition.
pub fn Host::set_text_composition(
  self : Host,
  window : @platform.WindowId,
  enabled : Bool,
) -> Result[Unit, @diagnostics.FrameworkError] {
  match self.check() {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  if window.value() <= 0L {
    return Err(error(@diagnostics.InvalidInput, "set_text_composition"))
  }
  status(
    call(19, window.value(), if enabled { 1.0 } else { 0.0 }, 0.0, b"", 0),
    "set_text_composition",
  )
}

///|
/// Publish the logical caret rectangle used to place the candidate window.
/// The native side revalidates finite bounds and a positive bounded size.
pub fn Host::set_text_composition_caret(
  self : Host,
  window : @platform.WindowId,
  caret : @primitives.Rect,
) -> Result[Unit, @diagnostics.FrameworkError] {
  match self.check() {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  if window.value() <= 0L {
    return Err(error(@diagnostics.InvalidInput, "set_text_composition_caret"))
  }
  let width = caret.size().width()
  let height = caret.size().height()
  let x = caret.left()
  let y = caret.top()
  for value in [x, y, width, height] {
    if value.is_nan() || value.is_inf() || value < -8192.0 || value > 8192.0 {
      return Err(error(@diagnostics.InvalidInput, "set_text_composition_caret"))
    }
  }
  if width <= 0.0 || height <= 0.0 {
    return Err(error(@diagnostics.InvalidInput, "set_text_composition_caret"))
  }
  let pixel_width = width.to_int()
  let pixel_height = height.to_int()
  if pixel_width.to_double() != width ||
    pixel_height.to_double() != height ||
    pixel_width <= 0 ||
    pixel_height <= 0 ||
    pixel_width > 8192 ||
    pixel_height > 8192 {
    return Err(error(@diagnostics.InvalidInput, "set_text_composition_caret"))
  }
  let bytes = Bytes::makei(8, index => {
    if index < 4 {
      ((pixel_width >> (index * 8)) & 0xff).to_byte()
    } else {
      ((pixel_height >> ((index - 4) * 8)) & 0xff).to_byte()
    }
  })
  status(
    call(20, window.value(), x, y, bytes, bytes.length()),
    "set_text_composition_caret",
  )
}

///|
/// Finish the current composition. Committing publishes the marked text as a
/// normal `Commit`; cancelling discards it. No event is published when the
/// window has no active composition.
pub fn Host::finish_text_composition(
  self : Host,
  window : @platform.WindowId,
  commit : Bool,
) -> Result[Unit, @diagnostics.FrameworkError] {
  match self.check() {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  if window.value() <= 0L {
    return Err(error(@diagnostics.InvalidInput, "finish_text_composition"))
  }
  status(
    call(21, window.value(), if commit { 1.0 } else { 0.0 }, 0.0, b"", 0),
    "finish_text_composition",
  )
}
