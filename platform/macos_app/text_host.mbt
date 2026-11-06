///|
/// Error from the reusable macOS text-host integration. Field, transport and
/// lifecycle failures stay distinct so a caller cannot retag one as another.
pub(all) enum MacosTextFieldHostError {
  Field(@text_field.TextFieldError)
  Adapter(@text_adapter.HostTextError)
  InvalidCaret
  Ended
}

///|
/// One editable `TextField` wired to the optional native text host. The helper
/// owns the portable session and the transport binding; the caller owns the
/// host, the input pump and the repaint policy. It does not own a window or a
/// renderer.
pub struct MacosTextFieldHost {
  priv adapter : MacosTextFieldAdapter
  priv session : @text_session.TextSession
  priv binding : @text_adapter.HostTextSession
  priv mut field : @text_field.TextField
  priv mut ended : Bool
}

///|
/// Create a focused field and start one host text session on it. The caller
/// supplies the host so the helper stays testable with a fixture transport.
pub fn[T : @text_host.TextInputHost] MacosTextFieldHost::start(
  id : UInt64,
  window : @platform.WindowId,
  root : UInt64,
  bounds : @primitives.Rect,
  font_size : Double,
  document : @text.TextDocument,
  host : T,
) -> Result[MacosTextFieldHost, MacosTextFieldHostError] {
  let adapter = match MacosTextFieldAdapter::new(font_size) {
    Err(error) => return Err(Field(error))
    Ok(value) => value
  }
  let measure = fn(candidate : @text.TextDocument) {
    adapter.measure(candidate)
  }
  let admit = fn(
    candidate : @text.TextDocument,
    measurement : @text_layout.TextMeasurement,
  ) {
    adapter.admit(candidate, measurement)
  }
  let field = match
    @text_field.TextField::new(id, bounds, font_size, document, measure, admit) {
    Err(error) => return Err(Field(error))
    Ok(value) => value
  }
  let field = match field.with_focus(true) {
    Err(error) => return Err(Field(error))
    Ok(value) => value
  }
  let caret = match field.caret_rect() {
    Err(_) => return Err(InvalidCaret)
    Ok(value) => value
  }
  let session = match @text_session.TextSession::new(window, root, field) {
    Err(error) => return Err(Adapter(@text_adapter.Session(error)))
    Ok(value) => value
  }
  let binding = match @text_adapter.start_host_text(session, host, caret) {
    Err(error) => return Err(Adapter(error))
    Ok(value) => value
  }
  Ok({ adapter, session, binding, field, ended: false, })
}

///|
/// The current field value. It is a copy; the helper updates its stored copy
/// after each accepted observation.
pub fn MacosTextFieldHost::field(
  self : MacosTextFieldHost,
) -> @text_field.TextField {
  self.field
}

///|
pub fn MacosTextFieldHost::session(
  self : MacosTextFieldHost,
) -> @text_session.TextSession {
  self.session
}

///|
pub fn MacosTextFieldHost::binding(
  self : MacosTextFieldHost,
) -> @text_adapter.HostTextSession {
  self.binding
}

///|
pub fn MacosTextFieldHost::adapter(
  self : MacosTextFieldHost,
) -> MacosTextFieldAdapter {
  self.adapter
}

///|
/// Whether the transport ended, either through `end` or an observed focus loss.
pub fn MacosTextFieldHost::is_ended(self : MacosTextFieldHost) -> Bool {
  self.ended
}

///|
/// Drain one host observation and apply it. `Applied` updates the stored field;
/// `FocusLost` ends the helper. A helper that already ended returns `Ended`.
pub fn[T : @text_host.TextInputHost] MacosTextFieldHost::pump(
  self : MacosTextFieldHost,
  host : T,
  timeout_ms~ : Int32 = 16,
) -> Result[@text_adapter.HostTextOutcome, MacosTextFieldHostError] {
  if self.ended {
    return Err(Ended)
  }
  let adapter = self.adapter
  let measure = fn(candidate : @text.TextDocument) {
    adapter.measure(candidate)
  }
  let admit = fn(
    candidate : @text.TextDocument,
    measurement : @text_layout.TextMeasurement,
  ) {
    adapter.admit(candidate, measurement)
  }
  match
    @text_adapter.receive_host_text(
      self.session,
      host,
      self.binding,
      measure,
      admit,
      timeout_ms~,
    ) {
    Err(error) => Err(Adapter(error))
    Ok(outcome) => {
      match outcome {
        @text_adapter.Applied(receipt) =>
          self.field = receipt.snapshot().field()
        @text_adapter.FocusLost => self.ended = true
        @text_adapter.Idle => ()
      }
      Ok(outcome)
    }
  }
}

///|
/// Revoke the transport. Calling it on an ended helper is a no-op.
pub fn[T : @text_host.TextInputHost] MacosTextFieldHost::end(
  self : MacosTextFieldHost,
  host : T,
) -> Result[Unit, MacosTextFieldHostError] {
  if self.ended {
    return Ok(())
  }
  match @text_adapter.end_host_text(self.session, host, self.binding) {
    Err(error) => Err(Adapter(error))
    Ok(_) => {
      self.ended = true
      Ok(())
    }
  }
}
