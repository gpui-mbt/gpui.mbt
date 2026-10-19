///|
extern "C" fn native_text_composition_mode(
  host : Int32,
  window : Int32,
  enabled : Int32,
) -> Int32 = "gpui_text_composition_mode"

///|
extern "C" fn native_text_composition_active(host : Int32) -> Int32 = "gpui_text_composition_active"

///|
extern "C" fn native_text_composition_caret(
  host : Int32,
  window : Int32,
  x : Int32,
  y : Int32,
  width : Int32,
  height : Int32,
) -> Int32 = "gpui_text_composition_caret"

///|
extern "C" fn native_text_composition_finish(
  host : Int32,
  window : Int32,
  commit : Int32,
) -> Int32 = "gpui_text_composition_finish"

///|
/// Opt in to bounded Wayland text-input-v1 composition. The application owns
/// committed text and selection. Mutually exclusive with full text sessions;
/// enabling disarms direct keyboard text. Disabled by default.
pub fn Host::set_text_composition(
  self : Host,
  window : @platform.WindowId,
  enabled : Bool,
) -> Result[Unit, @diagnostics.FrameworkError] {
  let operation = "set_text_composition"
  let window = match direct_window_token(window, operation) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  outcome(
    native_text_composition_mode(
      self.token,
      window,
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
/// Candidate caret in surface-logical integer coordinates, with positive
/// integer extent. Invalid geometry leaves the live composition unchanged.
pub fn Host::set_text_composition_caret(
  self : Host,
  window : @platform.WindowId,
  caret : @primitives.Rect,
) -> Result[Unit, @diagnostics.FrameworkError] {
  let operation = "set_text_composition_caret"
  let window = match direct_window_token(window, operation) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let (x, y, width, height) = match text_session_rect(caret, operation) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  outcome(
    native_text_composition_caret(self.token, window, x, y, width, height),
    operation,
  )
}

///|
/// Resolve the latest cached preedit exactly once and fence the native session.
/// Wayland v1 has no application-side commit request: commit=true publishes the
/// cached preview, not a newly chosen IME candidate. An empty preview is a no-op.
pub fn Host::finish_text_composition(
  self : Host,
  window : @platform.WindowId,
  commit : Bool,
) -> Result[Unit, @diagnostics.FrameworkError] {
  let operation = "finish_text_composition"
  let window = match direct_window_token(window, operation) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  outcome(
    native_text_composition_finish(
      self.token,
      window,
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
fn decode_wayland_composition(
  data : FixedArray[Double],
  bytes : Bytes,
  operation : String,
) -> Result[EditorEvent?, @diagnostics.FrameworkError] {
  let tag = data[0].to_int()
  if !exact_i32(data[10]) ||
    data[10] <= 0.0 ||
    data[11].is_nan() ||
    data[11].is_inf() ||
    data[11] < 1.0 ||
    data[11] > 4294967295.0 ||
    data[11].to_int64().to_double() != data[11] ||
    !exact_i32(data[12]) ||
    data[12] <= 0.0 ||
    !exact_i32(data[13]) ||
    data[13] < 0.0 ||
    !editor_zero_fields(data, 4, 10) ||
    !exact_i32(data[14]) ||
    data[14] < 0.0 ||
    data[14] > IME_MAX_BYTES.to_double() ||
    data[15] != 0.0 ||
    !editor_flag(data[16]) ||
    !exact_i32(data[17]) ||
    !editor_zero_fields(data, 18, EDITOR_EVENT_FIELDS) {
    return Err(editor_decode_error(operation, "invalid composition metadata"))
  }
  let length = data[14].to_int()
  if bytes.length() < length || (data[16] == 0.0 && data[17] != 0.0) {
    return Err(editor_decode_error(operation, "invalid composition payload"))
  }
  let composition = if tag == 26 || tag == 29 {
    if !editor_zero_fields(data, 14, EDITOR_EVENT_FIELDS) {
      return Err(
        editor_decode_error(operation, "composition lifecycle has text"),
      )
    }
    if tag == 26 {
      @primitives.Start
    } else {
      @primitives.Cancel
    }
  } else {
    let text = match editor_decode_string(bytes, 0, length, operation) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    if tag == 28 {
      if data[16] != 0.0 || data[17] != 0.0 {
        return Err(
          editor_decode_error(operation, "composition commit has cursor"),
        )
      }
      if text.length() > 65_536 {
        return Err(backend_error(8, operation))
      }
      @primitives.Commit(text~)
    } else {
      if text.length() > 16_384 {
        return Err(backend_error(8, operation))
      }
      let document = match @text.TextDocument::new(text) {
        Ok(value) => value
        Err(_) =>
          return Err(editor_decode_error(operation, "invalid composition text"))
      }
      let cursor_utf16 = if data[16] == 0.0 || data[17] < 0.0 {
        text.length()
      } else {
        match document.utf16_offset(data[17].to_int()) {
          Ok(value) => value
          Err(_) =>
            return Err(
              editor_decode_error(operation, "composition cursor splits UTF-8"),
            )
        }
      }
      if cursor_utf16 < 0 || cursor_utf16 > text.length() {
        return Err(
          editor_decode_error(operation, "composition cursor out of bounds"),
        )
      }
      @primitives.Update(text~, cursor_utf16~)
    }
  }
  Ok(Some(Platform(make_event(data, @platform.Composition(composition)))))
}

///|
#borrow(text)
extern "C" fn native_test_post_composition(
  host : Int32,
  window : Int32,
  kind : Int32,
  text : Bytes,
  length : Int32,
  cursor_utf16 : Int32,
) -> Int32 = "gpui_test_post_composition"

///|
/// Synthetic native transaction ingress, available only with GPUI_NATIVE_E2E=1.
/// This exercises the bounded transport, not a real input method or candidate UI.
pub fn Host::post_test_composition(
  self : Host,
  window : @platform.WindowId,
  event : @primitives.CompositionEvent,
) -> Result[Unit, @diagnostics.FrameworkError] {
  let operation = "post_test_composition"
  let window = match direct_window_token(window, operation) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let (kind, text, cursor) = match event {
    @primitives.Start => (0, "", -1)
    @primitives.Update(text~, cursor_utf16~) => {
      if text.length() > 16_384 {
        return Err(backend_error(8, operation))
      }
      if cursor_utf16 < 0 || cursor_utf16 > text.length() {
        return Err(backend_error(3, operation))
      }
      (1, text, cursor_utf16)
    }
    @primitives.Commit(text~) => {
      if text.length() > 65_536 {
        return Err(backend_error(8, operation))
      }
      (2, text, -1)
    }
    @primitives.Cancel => (3, "", -1)
  }
  let bytes = @utf8.encode(text)
  if bytes.length() > IME_MAX_BYTES {
    return Err(backend_error(8, operation))
  }
  outcome(
    native_test_post_composition(
      self.token,
      window,
      kind,
      bytes,
      bytes.length(),
      cursor,
    ),
    operation,
  )
}
