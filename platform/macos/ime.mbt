///|
/// Enable or disable the AppKit text-composition client for one window. Shared
/// by the public IME methods and the optional native text-host route.
fn composition_enable(
  window : @platform.WindowId,
  enabled : Bool,
  operation : String,
) -> Result[Unit, @diagnostics.FrameworkError] {
  if window.value() <= 0L {
    return Err(error(@diagnostics.InvalidInput, operation))
  }
  status(
    call(19, window.value(), if enabled { 1.0 } else { 0.0 }, 0.0, b"", 0),
    operation,
  )
}

///|
/// Publish the logical caret rectangle used to place the candidate window. The
/// native side revalidates finite bounds and a positive bounded size.
fn composition_caret(
  window : @platform.WindowId,
  caret : @primitives.Rect,
  operation : String,
) -> Result[Unit, @diagnostics.FrameworkError] {
  if window.value() <= 0L {
    return Err(error(@diagnostics.InvalidInput, operation))
  }
  // The native shim takes integer pixel extents. Round the logical rectangle
  // outward so a fractional painted caret never loses or clips a pixel.
  let left = caret.left().floor()
  let top = caret.top().floor()
  let right = caret.right().ceil()
  let bottom = caret.bottom().ceil()
  for value in [left, top, right, bottom] {
    if value.is_nan() || value.is_inf() || value < -8192.0 || value > 8192.0 {
      return Err(error(@diagnostics.InvalidInput, operation))
    }
  }
  let pixel_width = (right - left).to_int()
  let pixel_height = (bottom - top).to_int()
  if pixel_width <= 0 ||
    pixel_height <= 0 ||
    pixel_width > 8192 ||
    pixel_height > 8192 {
    return Err(error(@diagnostics.InvalidInput, operation))
  }
  let bytes = Bytes::makei(8, index => {
    if index < 4 {
      ((pixel_width >> (index * 8)) & 0xff).to_byte()
    } else {
      ((pixel_height >> ((index - 4) * 8)) & 0xff).to_byte()
    }
  })
  status(call(20, window.value(), left, top, bytes, bytes.length()), operation)
}

///|
/// Finish the current composition. Committing publishes the marked text as a
/// normal `Commit`; cancelling discards it. No event is published when the
/// window has no active composition.
fn composition_finish(
  window : @platform.WindowId,
  commit : Bool,
  operation : String,
) -> Result[Unit, @diagnostics.FrameworkError] {
  if window.value() <= 0L {
    return Err(error(@diagnostics.InvalidInput, operation))
  }
  status(
    call(21, window.value(), if commit { 1.0 } else { 0.0 }, 0.0, b"", 0),
    operation,
  )
}

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
  composition_enable(window, enabled, "set_text_composition")
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
  composition_caret(window, caret, "set_text_composition_caret")
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
  composition_finish(window, commit, "finish_text_composition")
}
