///|
/// The portable composition transport is deliberately much smaller than the
/// private editor session. These limits are UTF-16 code units; the native side
/// revalidates them and also bounds the copied UTF-8 sidecar.
const COMPOSITION_MAX_PREEDIT_UNITS : Int32 = 16_384

///|
const COMPOSITION_MAX_COMMIT_UNITS : Int32 = 65_536

///|
const COMPOSITION_MAX_TEXT_BYTES : Int32 = 262_144

///|
extern "C" fn native_set_text_composition(
  host : Int32,
  window : Int32,
  enabled : Int32,
) -> Int32 = "gpui_windows_set_text_composition"

///|
extern "C" fn native_set_text_composition_caret(
  host : Int32,
  window : Int32,
  x : Double,
  y : Double,
  width : Double,
  height : Double,
) -> Int32 = "gpui_windows_set_text_composition_caret"

///|
extern "C" fn native_finish_text_composition(
  host : Int32,
  window : Int32,
  commit : Int32,
) -> Int32 = "gpui_windows_finish_text_composition"

///|
extern "C" fn native_composition_text_size(host : Int32) -> Int32 = "gpui_windows_composition_text_size"

///|
#borrow(output)
extern "C" fn native_composition_text_copy(
  host : Int32,
  output : Bytes,
  capacity : Int32,
) -> Int32 = "gpui_windows_composition_text_copy"

///|
fn composition_rect_valid(
  caret : @primitives.Rect,
  operation : String,
) -> Result[Unit, @diagnostics.FrameworkError] {
  let x = caret.left()
  let y = caret.top()
  let width = caret.size().width()
  let height = caret.size().height()
  for value in [x, y, width, height] {
    if value.is_nan() || value.is_inf() || value < -8192.0 || value > 8192.0 {
      return Err(backend_error(3, operation))
    }
  }
  if width <= 0.0 || height <= 0.0 {
    return Err(backend_error(3, operation))
  }
  let pixel_width = width.to_int()
  let pixel_height = height.to_int()
  if pixel_width.to_double() != width ||
    pixel_height.to_double() != height ||
    pixel_width <= 0 ||
    pixel_height <= 0 ||
    pixel_width > 8192 ||
    pixel_height > 8192 {
    return Err(backend_error(3, operation))
  }
  Ok(())
}

///|
/// Enable or disable the opt-in Windows IMM32 composition client for one
/// window. Enabling arms a composition-only session; it does not advertise the
/// portable `TextInput` capability and does not change the private field
/// session. Disabling cancels an active preview and disarms the session.
pub fn Host::set_text_composition(
  self : Host,
  window : @platform.WindowId,
  enabled : Bool,
) -> Result[Unit, @diagnostics.FrameworkError] {
  let operation = "set_text_composition"
  let native_window = match session_window_token(window, operation) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  outcome(
    native_set_text_composition(
      self.token,
      native_window,
      if enabled {
        1
      } else {
        0
      },
    ),
    operation,
  )
}

///|
/// Publish the logical client caret rectangle used to place the IME
/// composition and candidate windows. The native side converts it with the
/// window DPI and treats placement as best-effort; a failed placement does not
/// break an active composition.
pub fn Host::set_text_composition_caret(
  self : Host,
  window : @platform.WindowId,
  caret : @primitives.Rect,
) -> Result[Unit, @diagnostics.FrameworkError] {
  let operation = "set_text_composition_caret"
  let native_window = match session_window_token(window, operation) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  match composition_rect_valid(caret, operation) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  outcome(
    native_set_text_composition_caret(
      self.token,
      native_window,
      caret.left(),
      caret.top(),
      caret.size().width(),
      caret.size().height(),
    ),
    operation,
  )
}

///|
/// Finish the current composition transaction. `commit=true` publishes the
/// current marked text as one `Commit`; `commit=false` publishes `Cancel`.
/// When no composition is active, no event is published.
pub fn Host::finish_text_composition(
  self : Host,
  window : @platform.WindowId,
  commit : Bool,
) -> Result[Unit, @diagnostics.FrameworkError] {
  let operation = "finish_text_composition"
  let native_window = match session_window_token(window, operation) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  outcome(
    native_finish_text_composition(
      self.token,
      native_window,
      if commit {
        1
      } else {
        0
      },
    ),
    operation,
  )
}

///|
/// Copy and decode the UTF-8 sidecar attached to the composition event most
/// recently popped by `next_event` / `dispatch`. The owner thread must read it
/// before the next pop.
fn read_composition_text(
  host : Host,
  operation : String,
) -> Result[String, @diagnostics.FrameworkError] {
  let size = native_composition_text_size(host.token)
  if size < 0 {
    return Err(backend_error(-size, operation))
  }
  if size > COMPOSITION_MAX_TEXT_BYTES {
    return Err(backend_error(8, operation))
  }
  let output = Bytes::makei(size, _ => (0).to_byte())
  let copied = native_composition_text_copy(host.token, output, size)
  if copied < 0 {
    return Err(backend_error(-copied, operation))
  }
  if copied != size {
    return Err(backend_error(11, operation))
  }
  for byte in output {
    if byte == (0).to_byte() {
      return Err(backend_error(3, operation))
    }
  }
  try @utf8.decode(output) catch {
    _ => Err(backend_error(11, operation))
  } noraise {
    text => Ok(text)
  }
}

///|
/// Decode one kind-17 composition frame. The native side stores UTF-16 units in
/// field 5 and the preedit cursor in field 4. `TextDocument` revalidates the
/// UTF-16 length and rejects a cursor inside a surrogate pair.
fn decode_composition_event(
  code : Int32,
  units_value : Double,
  cursor_value : Double,
  text : String,
  operation : String,
) -> Result[@platform.EventKind, @diagnostics.FrameworkError] {
  if !session_exact_i32(units_value) || units_value < 0.0 {
    return Err(backend_error(3, operation))
  }
  let units = units_value.to_int()
  let document = match @text.TextDocument::new(text) {
    Ok(value) => value
    Err(_) => return Err(backend_error(3, operation))
  }
  if document.utf16_length() != units {
    return Err(backend_error(3, operation))
  }
  match code {
    0 => {
      if units != 0 || cursor_value != 0.0 {
        return Err(backend_error(3, operation))
      }
      Ok(@platform.Composition(@primitives.Start))
    }
    1 => {
      if units > COMPOSITION_MAX_PREEDIT_UNITS {
        return Err(backend_error(8, operation))
      }
      if !session_exact_i32(cursor_value) || cursor_value < 0.0 {
        return Err(backend_error(3, operation))
      }
      let cursor = cursor_value.to_int()
      if cursor > units {
        return Err(backend_error(3, operation))
      }
      if units == 0 {
        if cursor != 0 {
          return Err(backend_error(3, operation))
        }
        return Ok(@platform.Composition(@primitives.Cancel))
      }
      let selection = match @text.TextSelection::new(cursor, cursor) {
        Ok(value) => value
        Err(_) => return Err(backend_error(3, operation))
      }
      match document.with_selection(selection) {
        Err(_) => Err(backend_error(3, operation))
        Ok(_) =>
          Ok(
            @platform.Composition(
              @primitives.Update(text~, cursor_utf16=cursor),
            ),
          )
      }
    }
    2 => {
      if units > COMPOSITION_MAX_COMMIT_UNITS {
        return Err(backend_error(8, operation))
      }
      if cursor_value != 0.0 {
        return Err(backend_error(3, operation))
      }
      Ok(@platform.Composition(@primitives.Commit(text~)))
    }
    3 => {
      if units != 0 || cursor_value != 0.0 {
        return Err(backend_error(3, operation))
      }
      Ok(@platform.Composition(@primitives.Cancel))
    }
    _ => Err(backend_error(2, operation))
  }
}

///|
/// Decode a kind-17 event after the native reader has popped it. The text
/// sidecar must still describe that exact event.
fn decode_composition_buffer(
  host : Host,
  data : FixedArray[Double],
  operation : String,
) -> Result[@platform.EventKind, @diagnostics.FrameworkError] {
  let text = match read_composition_text(host, operation) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  decode_composition_event(data[8].to_int(), data[5], data[4], text, operation)
}
