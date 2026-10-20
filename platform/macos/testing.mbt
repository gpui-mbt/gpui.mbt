///|
pub extend Host with @testing.FrameReadback::{copy_frame, frame_metrics}

///|
/// Post a test-only left click to this host-owned window through AppKit's
/// normal event route. Requires GPUI_NATIVE_E2E=1 and a test-hooks dylib.
pub fn Host::post_test_click(
  self : Host,
  window : @platform.WindowId,
  point : @primitives.Point,
) -> Result[Unit, @diagnostics.FrameworkError] {
  match self.check() {
    Err(failure) => return Err(failure)
    Ok(_) => ()
  }
  status(
    test_post_click(window.value(), point.x(), point.y()),
    "post_test_click",
  )
}

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
/// Post one synthetic key-down/key-up pair to the owned NSWindow.
/// Character keys must be one printable ASCII character and use ANSI positions.
/// Requires GPUI_NATIVE_E2E=1 and a test-hooks dylib.
pub fn Host::post_test_key(
  self : Host,
  window : @platform.WindowId,
  key : @primitives.Key,
  modifiers : @primitives.Modifiers,
) -> Result[Unit, @diagnostics.FrameworkError] {
  match self.check() {
    Err(failure) => return Err(failure)
    Ok(_) => ()
  }
  let (key_code, text) = match test_key_code(key) {
    Ok(value) => value
    Err(failure) => return Err(failure)
  }
  let bytes = @utf8.encode(text)
  status(
    test_post_key(
      window.value(),
      key_code,
      test_modifier_bits(modifiers),
      bytes,
      bytes.length(),
    ),
    "post_test_key",
  )
}

///|
/// Post one key-down/key-up pair with an explicit ANSI key code and characters.
/// The live input method processes the record exactly as it processes a physical
/// key; only AppKit's hardware event source is replaced. Requires
/// `GPUI_NATIVE_E2E=1` and a test-hooks dylib.
pub fn Host::post_test_key_code(
  self : Host,
  window : @platform.WindowId,
  key_code : Int32,
  characters : String,
  modifiers : @primitives.Modifiers,
) -> Result[Unit, @diagnostics.FrameworkError] {
  match self.check() {
    Err(failure) => return Err(failure)
    Ok(_) => ()
  }
  if key_code < 0 || key_code > 127 || characters.length() > 256 {
    return Err(error(@diagnostics.InvalidInput, "post_test_key_code"))
  }
  let bytes = @utf8.encode(characters)
  status(
    test_post_key(
      window.value(),
      key_code,
      test_modifier_bits(modifiers),
      bytes,
      bytes.length(),
    ),
    "post_test_key_code",
  )
}

///|
/// The logical caret rectangle in screen coordinates that the AppKit text
/// client currently reports to the input method. The native side falls back to
/// a one-by-eighteen logical rectangle when no caret was published. Requires
/// `GPUI_NATIVE_E2E=1`.
pub fn Host::text_caret_screen(
  self : Host,
  window : @platform.WindowId,
) -> Result[@primitives.Rect, @diagnostics.FrameworkError] {
  match self.check() {
    Err(failure) => return Err(failure)
    Ok(_) => ()
  }
  let output : FixedArray[Double] = FixedArray::make(4, 0.0)
  match
    status(
      native_text_caret_screen(window.value(), output),
      "text_caret_screen",
    ) {
    Err(failure) => Err(failure)
    Ok(_) => {
      for value in output {
        if value.is_nan() || value.is_inf() {
          return Err(error(@diagnostics.ConversionFailed, "text_caret_screen"))
        }
      }
      match @primitives.Rect::new(output[0], output[1], output[2], output[3]) {
        Err(_) => Err(error(@diagnostics.ConversionFailed, "text_caret_screen"))
        Ok(rect) => Ok(rect)
      }
    }
  }
}

///|
/// Post one composition frame through the same `NSTextInputClient` callbacks
/// AppKit uses. Requires GPUI_NATIVE_E2E=1, a test-hooks dylib, and an enabled
/// composition client.
pub fn Host::post_test_composition(
  self : Host,
  window : @platform.WindowId,
  event : @primitives.CompositionEvent,
) -> Result[Unit, @diagnostics.FrameworkError] {
  match self.check() {
    Err(failure) => return Err(failure)
    Ok(_) => ()
  }
  let (kind, cursor, text) = match event {
    @primitives.Start => (0, 0, "")
    @primitives.Update(text~, cursor_utf16~) => (1, cursor_utf16, text)
    @primitives.Commit(text~) => (2, 0, text)
    @primitives.Cancel => (3, 0, "")
  }
  let bytes = @utf8.encode(text)
  if bytes.length() > 65_536 {
    return Err(error(@diagnostics.ResourceExhausted, "post_test_composition"))
  }
  status(
    test_post_composition(window.value(), kind, cursor, bytes, bytes.length()),
    "post_test_composition",
  )
}

///|
/// Post an Escape key down/up pair to this host-owned window through AppKit's
/// normal event route. Requires GPUI_NATIVE_E2E=1 and a test-hooks dylib.
pub fn Host::post_test_escape(
  self : Host,
  window : @platform.WindowId,
) -> Result[Unit, @diagnostics.FrameworkError] {
  match self.check() {
    Err(failure) => return Err(failure)
    Ok(_) => ()
  }
  status(test_post_escape(window.value()), "post_test_escape")
}

///|
pub impl @testing.FrameReadback for Host with fn frame_metrics(
  self,
  window : @platform.WindowId,
) -> Result[(Int32, Int32, Double), @diagnostics.FrameworkError] {
  match self.check() {
    Err(failure) => return Err(failure)
    Ok(_) => ()
  }
  let metrics : FixedArray[Double] = FixedArray::make(3, 0.0)
  match status(frame_metrics(window.value(), metrics), "frame_metrics") {
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
        Err(error(@diagnostics.ConversionFailed, "frame_metrics"))
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
  match self.check() {
    Err(failure) => return Err(failure)
    Ok(_) => ()
  }
  status(frame_copy(window.value(), output, output.length()), "copy_frame")
}
