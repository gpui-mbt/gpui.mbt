///|
/// One portable text-input route over the existing Windows IMM32 session.
///
/// The host-local `begin_text_session`/`update_text_session`/
/// `next_editor_event` API remains authoritative. This adapter owns only the
/// portable epoch, the ordered translation of editor records, and the platform
/// records it parks while the application pumps both queues.
pub struct TextHostRoute {
  priv host : Host
  priv queue : @text_host.TextHostQueue
  priv mut native_epoch : Int32
  priv mut owner : Int32
  priv mut window : @platform.WindowId?
  priv mut started : Bool
}

///|
fn text_host_route_error(
  code : @diagnostics.ErrorCode,
  operation : String,
) -> @diagnostics.FrameworkError {
  @diagnostics.FrameworkError::new(
    code,
    operation,
    subsystem="windows-text-host",
  )
}

///|
pub fn TextHostRoute::new(host : Host) -> TextHostRoute {
  {
    host,
    queue: @text_host.TextHostQueue::new(),
    native_epoch: 0,
    owner: 0,
    window: None,
    started: false,
  }
}

///|
/// Drain one ordinary platform record, absorbing text records into the portable
/// queue. Use this instead of `Host::next_event` while the route is active.
pub fn TextHostRoute::next_platform_event(
  self : TextHostRoute,
  timeout_ms~ : Int32 = 16,
) -> Result[@platform.Event?, @diagnostics.FrameworkError] {
  match self.queue.take_parked() {
    Some(event) => return Ok(Some(event))
    None => ()
  }
  while true {
    let event = match self.host.next_editor_event(timeout_ms~) {
      Err(error) => return Err(error)
      Ok(value) => value
    }
    let event = match event {
      None => return Ok(None)
      Some(value) => value
    }
    match event {
      Platform(value) => return Ok(Some(value))
      TextSession(target, value) =>
        match self.absorb(target, value) {
          Err(error) => return Err(error)
          Ok(_) => ()
        }
    }
  } nobreak {
    Ok(None)
  }
}

///|
/// Portable translation of one editor record. The portable vocabulary is
/// insertion-only, so a replacement insert is reported as unsupported instead
/// of being flattened into a plain insertion.
priv enum TextTranslation {
  Emit(@text_host.TextInputEventKind)
  Unsupported
  Skip
}

///|
fn translate_editor_event(event : TextSessionEvent) -> TextTranslation {
  match event {
    CompositionStarted(..) | CompositionEnded => Skip
    Marked(text~, cursor_utf16~, ..) =>
      Emit(@text_host.Preedit(text~, cursor=cursor_utf16.unwrap_or(-1)))
    Inserted(text~, replacement_range~) =>
      if replacement_range.start() == replacement_range.end() {
        Emit(@text_host.Commit(text~))
      } else {
        Unsupported
      }
    Cancelled => Emit(@text_host.Cancel)
  }
}

///|
fn TextHostRoute::absorb(
  self : TextHostRoute,
  target : TextSessionTarget,
  event : TextSessionEvent,
) -> Result[Unit, @diagnostics.FrameworkError] {
  if !self.started || target.epoch != self.native_epoch {
    return Ok(())
  }
  match translate_editor_event(event) {
    Skip => Ok(())
    Unsupported => {
      self.queue.fail(@diagnostics.UnsupportedCapability)
      Err(
        text_host_route_error(
          @diagnostics.UnsupportedCapability,
          "next_text_input",
        ),
      )
    }
    Emit(kind) =>
      match self.queue.emit(kind) {
        Err(error) => Err(error)
        Ok(_) => Ok(())
      }
  }
}

///|
pub impl @text_host.TextInputHost for TextHostRoute with fn begin_text_input(
  self,
  window,
  root,
) {
  if root == 0UL || root > 2147483647UL || self.queue.is_active() {
    return Err(
      text_host_route_error(@diagnostics.InvalidInput, "begin_text_input"),
    )
  }
  let epoch = match self.queue.begin(window) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  self.owner = root.to_int()
  self.window = Some(window)
  self.native_epoch = 0
  self.started = false
  Ok(epoch)
}

///|
pub impl @text_host.TextInputHost for TextHostRoute with fn update_text_input(
  self,
  epoch,
  state,
) {
  let epoch = match self.queue.update(epoch, state) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  if !self.started {
    self.native_epoch = match
      self.host.begin_text_session(
        self.window.unwrap(),
        self.owner,
        state.document(),
        state.caret(),
      ) {
      Err(error) => return Err(error)
      Ok(value) => value
    }
    self.started = true
  } else {
    self.native_epoch = match
      self.host.update_text_session(
        self.window.unwrap(),
        self.native_epoch,
        self.owner,
        state.document(),
        state.caret(),
        external_edit=false,
      ) {
      Err(error) => return Err(error)
      Ok(value) => value
    }
  }
  Ok(epoch)
}

///|
pub impl @text_host.TextInputHost for TextHostRoute with fn cancel_text_input(
  self,
  epoch,
) {
  let replacement = match self.queue.cancel(epoch) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  if self.started {
    self.native_epoch = match
      self.host.cancel_text_session(
        self.window.unwrap(),
        self.native_epoch,
        self.owner,
      ) {
      Err(error) => return Err(error)
      Ok(value) => value
    }
  }
  Ok(replacement)
}

///|
pub impl @text_host.TextInputHost for TextHostRoute with fn end_text_input(
  self,
  epoch,
) {
  if self.started {
    match
      self.host.end_text_session(
        self.window.unwrap(),
        self.native_epoch,
        self.owner,
      ) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
    self.started = false
  }
  self.queue.end(epoch)
}

///|
pub impl @text_host.TextInputHost for TextHostRoute with fn next_text_input(
  self,
  timeout_ms?,
) {
  let timeout = match timeout_ms {
    Some(value) => value
    None => 16
  }
  match self.queue.failure() {
    Some(code) => return Err(text_host_route_error(code, "next_text_input"))
    None => ()
  }
  match self.queue.take_text() {
    Some(event) => return Ok(Some(event))
    None => ()
  }
  while true {
    let event = match self.host.next_editor_event(timeout_ms=timeout) {
      Err(error) => return Err(error)
      Ok(value) => value
    }
    let event = match event {
      None => return Ok(None)
      Some(value) => value
    }
    match event {
      TextSession(target, value) => {
        match self.absorb(target, value) {
          Err(error) => return Err(error)
          Ok(_) => ()
        }
        match self.queue.take_text() {
          Some(text) => return Ok(Some(text))
          None => ()
        }
      }
      Platform(value) => {
        if !self.queue.park(value) {
          self.queue.fail(@diagnostics.ResourceExhausted)
          return Err(
            text_host_route_error(
              @diagnostics.ResourceExhausted,
              "next_text_input",
            ),
          )
        }
        match value.kind() {
          @platform.FocusChanged(false) => {
            match self.queue.emit(@text_host.FocusLost) {
              Err(error) => return Err(error)
              Ok(_) => ()
            }
            return Ok(self.queue.take_text())
          }
          _ => ()
        }
      }
    }
  } nobreak {
    Ok(None)
  }
}

///|
/// Revoke all portable state without an epoch check. Hosts call this when the
/// owned window is destroyed or the host stops.
pub fn TextHostRoute::reset(self : TextHostRoute) -> Unit {
  self.queue.reset()
  self.started = false
  self.native_epoch = 0
  self.owner = 0
  self.window = None
}

///|
pub extend TextHostRoute with @text_host.TextInputHost::{
  begin_text_input,
  cancel_text_input,
  end_text_input,
  next_text_input,
  update_text_input,
}
