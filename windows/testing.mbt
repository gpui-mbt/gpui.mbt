///|
pub extend Host with @testing.FrameReadback::{copy_frame, frame_metrics}

///|
pub impl @testing.FrameReadback for Host with fn frame_metrics(
  self,
  window : @platform.WindowId,
) -> Result[(Int32, Int32, Double), @diagnostics.FrameworkError] {
  let metrics : FixedArray[Double] = FixedArray::make(3, 0.0)
  match
    outcome(
      native_frame_metrics(self.token, window.value().to_int(), metrics),
      "frame_metrics",
    ) {
    Err(failure) => Err(failure)
    Ok(_) => {
      let width = metrics[0].to_int()
      let height = metrics[1].to_int()
      if metrics[0].is_nan() ||
        metrics[0].is_inf() ||
        metrics[1].is_nan() ||
        metrics[1].is_inf() ||
        width.to_double() != metrics[0] ||
        height.to_double() != metrics[1] {
        Err(backend_error(11, "frame_metrics"))
      } else {
        Ok((width, height, metrics[2]))
      }
    }
  }
}

///|
pub impl @testing.FrameReadback for Host with fn copy_frame(
  self,
  window : @platform.WindowId,
  output : FixedArray[Byte],
) -> Result[Unit, @diagnostics.FrameworkError] {
  outcome(
    native_frame_copy(
      self.token,
      window.value().to_int(),
      output,
      output.length(),
    ),
    "copy_frame",
  )
}

///|
extern "C" fn native_test_post_key(
  host : Int32,
  window : Int32,
  kind : Int32,
  value : Int32,
  modifiers : Int32,
) -> Int32 = "gpui_windows_test_post_key"

///|
extern "C" fn native_test_post_click(
  host : Int32,
  window : Int32,
  x : Double,
  y : Double,
) -> Int32 = "gpui_windows_test_post_click"

///|
fn test_modifier_bits(modifiers : @primitives.Modifiers) -> Int32 {
  let mut bits = 0
  if modifiers.shift() {
    bits = bits | 1
  }
  if modifiers.control() {
    bits = bits | 2
  }
  if modifiers.alt() {
    bits = bits | 4
  }
  if modifiers.meta() {
    bits = bits | 8
  }
  bits
}

///|
/// Encode one key as (kind, value). Kind 0 is a special-key symbol using the
/// same values as the platform event decoder; kind 1 is a single printable
/// Unicode scalar.
fn test_key_encoding(
  key : @primitives.Key,
) -> Result[(Int32, Int32), @diagnostics.FrameworkError] {
  match key {
    @primitives.Character(value) => {
      let mut count = 0
      let mut scalar = 0
      for character in value.iter() {
        count += 1
        scalar = character.to_int()
      }
      if count == 1 &&
        scalar >= 0x20 &&
        scalar <= 0x10ffff &&
        scalar != 0x7f &&
        !(scalar >= 0xd800 && scalar <= 0xdfff) {
        Ok((1, scalar))
      } else {
        Err(backend_error(3, "post_test_key"))
      }
    }
    @primitives.Enter => Ok((0, 0xff0d))
    @primitives.Escape => Ok((0, 0xff1b))
    @primitives.Backspace => Ok((0, 0xff08))
    @primitives.Delete => Ok((0, 0xffff))
    @primitives.Tab => Ok((0, 0xff09))
    @primitives.Space => Ok((0, 0x20))
    @primitives.ArrowLeft => Ok((0, 0xff51))
    @primitives.ArrowUp => Ok((0, 0xff52))
    @primitives.ArrowRight => Ok((0, 0xff53))
    @primitives.ArrowDown => Ok((0, 0xff54))
    @primitives.Home => Ok((0, 0xff50))
    @primitives.End => Ok((0, 0xff57))
    @primitives.PageUp => Ok((0, 0xff55))
    @primitives.PageDown => Ok((0, 0xff56))
  }
}

///|
/// Enqueue one synthetic key-down event through the production decoder path.
/// Requires GPUI_NATIVE_E2E=1. This is an event-queue hook, not physical input.
pub fn Host::post_test_key(
  self : Host,
  window : @platform.WindowId,
  key : @primitives.Key,
  modifiers : @primitives.Modifiers,
) -> Result[Unit, @diagnostics.FrameworkError] {
  let (kind, value) = match test_key_encoding(key) {
    Err(failure) => return Err(failure)
    Ok(encoded) => encoded
  }
  outcome(
    native_test_post_key(
      self.token,
      window.value().to_int(),
      kind,
      value,
      test_modifier_bits(modifiers),
    ),
    "post_test_key",
  )
}

///|
/// Enqueue a synthetic move/down/up sequence for a logical client point.
/// Requires GPUI_NATIVE_E2E=1. This is an event-queue hook, not physical input.
pub fn Host::post_test_click(
  self : Host,
  window : @platform.WindowId,
  point : @primitives.Point,
) -> Result[Unit, @diagnostics.FrameworkError] {
  outcome(
    native_test_post_click(
      self.token,
      window.value().to_int(),
      point.x(),
      point.y(),
    ),
    "post_test_click",
  )
}
