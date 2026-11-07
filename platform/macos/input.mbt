///|
pub fn Host::next_event(
  self : Host,
  timeout_ms~ : Int32 = 16,
) -> Result[@platform.Event?, @diagnostics.FrameworkError] {
  match self.check() {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  match status(call(6, 0, timeout_ms.to_double(), 0.0, b"", 0), "next_event") {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let tag = integer(1).to_int()
  if tag == 0 {
    return Ok(None)
  }
  let bits = integer(4).to_int()
  let modifiers = @primitives.Modifiers::new(
    shift=(bits & 1) != 0,
    control=(bits & 2) != 0,
    alt=(bits & 4) != 0,
    meta=(bits & 8) != 0,
  )
  let kind = match tag {
    1 => @platform.Created
    2 => @platform.Resized(width=number(3), height=number(4))
    3 => @platform.Moved(x=number(1), y=number(2))
    4 => @platform.ScaleChanged
    5 => @platform.FocusChanged(true)
    6 => @platform.FocusChanged(false)
    7 | 8 | 9 | 18 => {
      let position = match @primitives.Point::new(number(1), number(2)) {
        Ok(value) => value
        Err(_) => return Err(error(@diagnostics.InvalidInput, "next_event"))
      }
      let button = match integer(5).to_int() {
        1 => @primitives.Secondary
        2 => @primitives.Middle
        3 => @primitives.Back
        4 => @primitives.Forward
        _ => @primitives.Primary
      }
      @platform.Input(
        match tag {
          8 => @primitives.PointerButtonPressed(position~, button~, modifiers~)
          9 => @primitives.PointerButtonReleased(position~, button~, modifiers~)
          18 => {
            let click_count = integer(6).to_int()
            // A malformed repeat count degrades to an ordinary press instead of
            // failing the pump: the frame is already dequeued.
            if click_count < 2 {
              @primitives.PointerButtonPressed(position~, button~, modifiers~)
            } else {
              @primitives.PointerButtonMultiClick(
                position~,
                button~,
                modifiers~,
                click_count~,
              )
            }
          }
          _ => @primitives.PointerMoved(position~)
        },
      )
    }
    10 | 11 => {
      let text = match read_text() {
        Ok(text) => text
        Err(error) => return Err(error)
      }
      let key = key_from_code(integer(5).to_int(), text)
      @platform.Input(
        if tag == 10 {
          @primitives.KeyPressed(key~, modifiers~, repeat=integer(6) != 0)
        } else {
          @primitives.KeyReleased(key~, modifiers~)
        },
      )
    }
    16 =>
      match
        decode_scroll_event(
          number(1),
          number(2),
          number(3),
          number(4),
          modifiers,
        ) {
        Ok(kind) => kind
        Err(error) => return Err(error)
      }
    17 => {
      let text = match read_text() {
        Ok(text) => text
        Err(error) => return Err(error)
      }
      match decode_composition_event(integer(5).to_int(), text, number(3)) {
        Ok(kind) => kind
        Err(error) => return Err(error)
      }
    }
    // A composition record for an armed text session. The ordinary event pump
    // must not discard it: it is parked in the host's text queue so that
    // `next_text_input` can deliver it in order.
    20 => {
      let text = match read_text() {
        Ok(text) => text
        Err(error) => return Err(error)
      }
      let kind = match
        decode_composition(integer(5).to_int(), text, number(3), "next_event") {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      match self.park_text_record(kind, number(4).to_int64()) {
        Ok(_) => @platform.Wake
        Err(error) => return Err(error)
      }
    }
    12 => @platform.CloseRequested
    13 => @platform.Destroyed
    14 => @platform.Wake
    15 => @platform.ExitRequested
    _ => return Err(error(@diagnostics.NativeFailure, "next_event"))
  }
  Ok(
    Some({
      window: @platform.WindowId::new(integer(2)),
      sequence: integer(3),
      scale: number(0),
      kind,
    }),
  )
}

///|
/// Park one composition record that the ordinary event pump read while a text
/// session is armed. The record keeps its place in the text stream; the pump
/// reports a wake so the application can call `next_text_input`.
fn Host::park_text_record(
  self : Host,
  kind : @primitives.CompositionEvent,
  sequence : Int64,
) -> Result[Unit, @diagnostics.FrameworkError] {
  let owner = self.text.val
  if !owner.armed {
    return Err(error(@diagnostics.StaleHandle, "next_event"))
  }
  let event = match kind {
    @primitives.Start => return Ok(())
    @primitives.Update(text~, cursor_utf16~) =>
      @text_host.Preedit(text~, cursor=cursor_utf16)
    @primitives.Commit(text~) => @text_host.Commit(text~)
    @primitives.Cancel => @text_host.Cancel
  }
  owner.queue.emit_at(sequence, event)
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
/// Decode one native composition frame. The preedit and commit bounds are in
/// UTF-16 code units, matching AppKit's ranges and MoonBit's string length.
fn decode_composition(
  code : Int32,
  text : String,
  cursor : Double,
  operation : String,
) -> Result[@primitives.CompositionEvent, @diagnostics.FrameworkError] {
  match code {
    0 => Ok(@primitives.Start)
    1 => {
      if text.length() > 16_384 {
        return Err(error(@diagnostics.ResourceExhausted, operation))
      }
      if cursor.is_nan() ||
        cursor.is_inf() ||
        cursor < 0.0 ||
        cursor > text.length().to_double() ||
        cursor.to_int().to_double() != cursor {
        return Err(error(@diagnostics.InvalidInput, operation))
      }
      Ok(@primitives.Update(text~, cursor_utf16=cursor.to_int()))
    }
    2 =>
      if text.length() > 65_536 {
        Err(error(@diagnostics.ResourceExhausted, operation))
      } else {
        Ok(@primitives.Commit(text~))
      }
    3 => Ok(@primitives.Cancel)
    _ => Err(error(@diagnostics.NativeFailure, operation))
  }
}

///|
/// Decode one native composition frame into a platform event.
fn decode_composition_event(
  code : Int32,
  text : String,
  cursor : Double,
) -> Result[@platform.EventKind, @diagnostics.FrameworkError] {
  match decode_composition(code, text, cursor, "next_event") {
    Err(failure) => Err(failure)
    Ok(value) => Ok(@platform.Composition(value))
  }
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
