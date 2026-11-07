///|
/// One armed portable text session. The native side owns the epoch and the
/// ordered record stream; this state only fences operations from the owner.
/// The macOS client is window-scoped, so the portable root stays the owner's
/// routing identity and is not subdivided by this transport.
priv struct TextInputOwner {
  epoch : UInt64
  window : Int64
  armed : Bool
}

///|
fn text_input_owner() -> TextInputOwner {
  { epoch: 0UL, window: 0L, armed: false, }
}

///|
fn text_input_error(
  code : @diagnostics.ErrorCode,
  operation : String,
) -> @diagnostics.FrameworkError {
  @diagnostics.FrameworkError::new(
    code,
    operation,
    subsystem="platform",
    backend="macos-metal",
    message="portable text input",
  )
}

///|
fn text_input_epoch(
  value : Double,
) -> Result[UInt64, @diagnostics.FrameworkError] {
  if value.is_nan() || value.is_inf() || value < 1.0 || value > 2_147_483_647.0 {
    return Err(
      text_input_error(@diagnostics.ConversionFailed, "text_input_epoch"),
    )
  }
  Ok(value.to_int64().reinterpret_as_uint64())
}

///|
fn decode_text_input(
  payload : FixedArray[Byte],
  length : Int32,
) -> Result[String, @diagnostics.FrameworkError] {
  if length < 0 || length > 65_536 {
    return Err(
      text_input_error(@diagnostics.ResourceExhausted, "next_text_input"),
    )
  }
  let bytes = Bytes::makei(length, index => payload[index])
  try @utf8.decode(bytes) catch {
    _ => Err(text_input_error(@diagnostics.ConversionFailed, "next_text_input"))
  } noraise {
    text => Ok(text)
  }
}

///|
pub impl @text_host.TextInputHost for Host with fn begin_text_input(
  self,
  window,
  root,
) {
  match self.check() {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let owner = self.text.val
  ignore(root)
  if owner.armed {
    return Err(text_input_error(@diagnostics.Busy, "begin_text_input"))
  }
  let fields = FixedArray::make(1, 0.0)
  match
    status(
      text_session(1, window.value(), 0L, fields, b"", 0),
      "begin_text_input",
    ) {
    Err(error) => Err(error)
    Ok(_) => {
      let epoch = match text_input_epoch(fields[0]) {
        Err(error) => return Err(error)
        Ok(value) => value
      }
      self.text.val = { epoch, window: window.value(), armed: true, }
      Ok(epoch)
    }
  }
}

///|
/// The committed document is not sent to AppKit: the `NSTextInputClient` route
/// never queries the document and the marked text stays IME-owned. The owner's
/// preedit is validated as display data and not written back, so this route
/// cannot inject a synthetic composition into the input method.
pub impl @text_host.TextInputHost for Host with fn update_text_input(
  self,
  epoch,
  state,
) {
  match self.check() {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let owner = self.text.val
  if !owner.armed || epoch != owner.epoch {
    return Err(text_input_error(@diagnostics.StaleHandle, "update_text_input"))
  }
  match state.preedit() {
    None => ()
    Some(preedit) =>
      if preedit.text().length() > 16_384 {
        return Err(
          text_input_error(@diagnostics.ResourceExhausted, "update_text_input"),
        )
      } else {
        let length = preedit.text().length()
        let selection = preedit.selection()
        if selection.anchor() < 0 ||
          selection.head() < 0 ||
          selection.anchor() > length ||
          selection.head() > length {
          return Err(
            text_input_error(@diagnostics.InvalidInput, "update_text_input"),
          )
        }
      }
  }
  let caret = state.caret()
  let fields = FixedArray::make(4, 0.0)
  fields[0] = caret.left()
  fields[1] = caret.top()
  fields[2] = caret.size().width()
  fields[3] = caret.size().height()
  match
    status(
      text_session(
        2,
        owner.window,
        epoch.reinterpret_as_int64(),
        fields,
        b"",
        0,
      ),
      "update_text_input",
    ) {
    Err(error) => Err(error)
    Ok(_) => Ok(epoch)
  }
}

///|
pub impl @text_host.TextInputHost for Host with fn cancel_text_input(
  self,
  epoch,
) {
  match self.check() {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let owner = self.text.val
  if !owner.armed || epoch != owner.epoch {
    return Err(text_input_error(@diagnostics.StaleHandle, "cancel_text_input"))
  }
  let fields = FixedArray::make(1, 0.0)
  match
    status(
      text_session(
        3,
        owner.window,
        epoch.reinterpret_as_int64(),
        fields,
        b"",
        0,
      ),
      "cancel_text_input",
    ) {
    Err(error) => Err(error)
    Ok(_) => {
      let replacement = match text_input_epoch(fields[0]) {
        Err(error) => return Err(error)
        Ok(value) => value
      }
      self.text.val = { ..owner, epoch: replacement, }
      Ok(replacement)
    }
  }
}

///|
pub impl @text_host.TextInputHost for Host with fn end_text_input(self, epoch) {
  match self.check() {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let owner = self.text.val
  if !owner.armed || epoch != owner.epoch {
    return Err(text_input_error(@diagnostics.StaleHandle, "end_text_input"))
  }
  match
    status(
      text_session(
        4,
        owner.window,
        epoch.reinterpret_as_int64(),
        FixedArray::make(1, 0.0),
        b"",
        0,
      ),
      "end_text_input",
    ) {
    Err(error) => Err(error)
    Ok(_) => {
      self.text.val = text_input_owner()
      Ok(())
    }
  }
}

///|
pub impl @text_host.TextInputHost for Host with fn next_text_input(
  self,
  timeout_ms~ : Int32 = 16,
) {
  match self.check() {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let owner = self.text.val
  if !owner.armed {
    return Err(text_input_error(@diagnostics.StaleHandle, "next_text_input"))
  }
  let fields = FixedArray::make(6, 0.0)
  let payload = FixedArray::make(65_536, b'\x00')
  match
    status(
      text_next(
        owner.window,
        owner.epoch.reinterpret_as_int64(),
        timeout_ms,
        fields,
        payload,
        65_536,
      ),
      "next_text_input",
    ) {
    Err(error) => Err(error)
    Ok(_) =>
      if fields[0] != 1.0 {
        Ok(None)
      } else {
        let kind = fields[1].to_int()
        let sequence = fields[2].to_int64()
        let epoch = match text_input_epoch(fields[3]) {
          Err(error) => return Err(error)
          Ok(value) => value
        }
        if epoch != owner.epoch {
          return Ok(None)
        }
        let text = match decode_text_input(payload, fields[5].to_int()) {
          Err(error) => return Err(error)
          Ok(value) => value
        }
        let kind = match kind {
          1 => {
            let cursor = fields[4].to_int()
            @text_host.Preedit(text~, cursor~)
          }
          2 => @text_host.Commit(text~)
          3 => @text_host.Cancel
          5 => @text_host.FocusLost
          _ =>
            return Err(
              text_input_error(@diagnostics.ConversionFailed, "next_text_input"),
            )
        }
        Ok(
          Some(
            @text_host.TextInputEvent::new(
              @platform.WindowId::new(owner.window),
              sequence,
              epoch,
              kind,
            ),
          ),
        )
      }
  }
}

///|
pub extend Host with @text_host.TextInputHost::{
  begin_text_input,
  cancel_text_input,
  end_text_input,
  next_text_input,
  update_text_input,
}
