///|
/// Immutable text-transport state shared by every copy of a host handle. Each
/// accepted operation replaces the whole value, so a host copy never observes
/// two different sessions.
priv struct TextHostState {
  next_epoch : UInt64
  next_synthetic_sequence : Int64
  active : TextHostSession?
}

///|
/// One live native text session. AppKit owns the marked text, so the transport
/// keeps only the epoch, window and focus-reporting flag; the application's
/// `TextSession` remains the single committed-document authority.
priv struct TextHostSession {
  epoch : UInt64
  window : @platform.WindowId
  /// Whether this session observed key focus at least once. A session that
  /// never held focus cannot report a loss.
  had_focus : Bool
  focus_reported : Bool
}

///|
fn TextHostState::empty() -> TextHostState {
  { next_epoch: 1UL, next_synthetic_sequence: -1L, active: None, }
}

///|
/// Private transport seam. The AppKit implementation and the whitebox fixture
/// provide the same five operations, so epoch/order/focus behavior stays
/// headless-testable without a native window.
priv trait TextRoute {
  fn enable(Self, @platform.WindowId, Bool, String) -> Result[
    Unit,
    @diagnostics.FrameworkError,
  ]
  fn set_caret(Self, @platform.WindowId, @primitives.Rect, String) -> Result[
    Unit,
    @diagnostics.FrameworkError,
  ]
  fn finish(Self, @platform.WindowId, Bool, String) -> Result[
    Unit,
    @diagnostics.FrameworkError,
  ]
  fn take(Self, @platform.WindowId, Int32, String) -> Result[
    (@primitives.CompositionEvent?, Int64),
    @diagnostics.FrameworkError,
  ]
  fn is_key(Self, @platform.WindowId, String) -> Result[
    Bool,
    @diagnostics.FrameworkError,
  ]
}

///|
/// AppKit transport. Every operation runs on the UI owner thread; the native
/// shim returns `WrongThread` otherwise.
priv struct NativeTextRoute {
  host : Host
}

///|
fn NativeTextRoute::new(host : Host) -> NativeTextRoute {
  { host, }
}

///|
impl TextRoute for NativeTextRoute with fn enable(
  self,
  window,
  enabled,
  operation,
) {
  match self.host.check() {
    Err(failure) => return Err(failure)
    Ok(_) => ()
  }
  composition_enable(window, enabled, operation)
}

///|
impl TextRoute for NativeTextRoute with fn set_caret(
  self,
  window,
  caret,
  operation,
) {
  match self.host.check() {
    Err(failure) => return Err(failure)
    Ok(_) => ()
  }
  composition_caret(window, caret, operation)
}

///|
impl TextRoute for NativeTextRoute with fn finish(
  self,
  window,
  commit,
  operation,
) {
  match self.host.check() {
    Err(failure) => return Err(failure)
    Ok(_) => ()
  }
  composition_finish(window, commit, operation)
}

///|
impl TextRoute for NativeTextRoute with fn take(
  self,
  window,
  timeout_ms,
  operation,
) {
  match self.host.check() {
    Err(failure) => return Err(failure)
    Ok(_) => ()
  }
  let code = call(22, window.value(), timeout_ms.to_double(), 0.0, b"", 0)
  if code != 0 {
    match status(code, operation) {
      Err(failure) => return Err(failure)
      Ok(_) => return Ok((None, 0L))
    }
  }
  let kind = integer(1).to_int()
  if kind == 0 {
    return Ok((None, 0L))
  }
  let sequence = integer(3)
  let text = match read_text() {
    Err(failure) => return Err(failure)
    Ok(value) => value
  }
  match decode_composition(integer(5).to_int(), text, number(3), operation) {
    Err(failure) => Err(failure)
    Ok(value) => Ok((Some(value), sequence))
  }
}

///|
impl TextRoute for NativeTextRoute with fn is_key(self, window, operation) {
  match self.host.check() {
    Err(failure) => return Err(failure)
    Ok(_) => ()
  }
  let code = call(23, window.value(), 0.0, 0.0, b"", 0)
  if code != 0 {
    match status(code, operation) {
      Err(failure) => return Err(failure)
      Ok(_) => return Ok(false)
    }
  }
  Ok(integer(10) != 0L)
}

///|
/// Start one session. The epoch is host-issued, strictly increasing and never
/// reused, including after a failed native enable.
fn[R : TextRoute] begin_text_route(
  state : TextHostState,
  route : R,
  window : @platform.WindowId,
  root : UInt64,
) -> Result[(TextHostState, UInt64), @diagnostics.FrameworkError] {
  if window.value() <= 0L || root == 0UL {
    return Err(error(@diagnostics.InvalidInput, "begin_text_input"))
  }
  match state.active {
    Some(_) => return Err(error(@diagnostics.Busy, "begin_text_input"))
    None => ()
  }
  if state.next_epoch == 0xFFFF_FFFF_FFFF_FFFFUL {
    return Err(error(@diagnostics.ResourceExhausted, "begin_text_input"))
  }
  let epoch = state.next_epoch
  match route.enable(window, true, "begin_text_input") {
    Err(failure) => Err(failure)
    Ok(_) =>
      Ok(
        (
          {
            ..state,
            next_epoch: epoch + 1UL,
            active: Some({
              epoch,
              window,
              had_focus: false,
              focus_reported: false,
            }),
          },
          epoch,
        ),
      )
  }
}

///|
/// Return the active session for an exact epoch, or a typed stale failure.
fn text_route_session(
  state : TextHostState,
  epoch : UInt64,
  operation : String,
) -> Result[TextHostSession, @diagnostics.FrameworkError] {
  match state.active {
    Some(current) =>
      if current.epoch == epoch {
        Ok(current)
      } else {
        Err(error(@diagnostics.StaleHandle, operation))
      }
    None => Err(error(@diagnostics.StaleHandle, operation))
  }
}

///|
/// Hand the owner caret to the native transport after the epoch check. A
/// rejected caret leaves the live session and its epoch unchanged.
fn[R : TextRoute] update_text_route(
  state : TextHostState,
  route : R,
  epoch : UInt64,
  value : @text_host.TextInputState,
) -> Result[TextHostState, @diagnostics.FrameworkError] {
  let active = match text_route_session(state, epoch, "update_text_input") {
    Err(failure) => return Err(failure)
    Ok(value) => value
  }
  match route.set_caret(active.window, value.caret(), "update_text_input") {
    Err(failure) => Err(failure)
    Ok(_) => Ok(state)
  }
}

///|
/// Cancel the active composition. The session stays live and the returned
/// epoch remains the only valid value for later calls.
fn[R : TextRoute] cancel_text_route(
  state : TextHostState,
  route : R,
  epoch : UInt64,
) -> Result[TextHostState, @diagnostics.FrameworkError] {
  let active = match text_route_session(state, epoch, "cancel_text_input") {
    Err(failure) => return Err(failure)
    Ok(value) => value
  }
  match route.finish(active.window, false, "cancel_text_input") {
    Err(failure) => Err(failure)
    Ok(_) => Ok(state)
  }
}

///|
/// Discard composition frames left behind by a disabled client. Only frames for
/// this window are removed; other queued events keep their order.
fn[R : TextRoute] drain_text_frames(
  route : R,
  window : @platform.WindowId,
) -> Unit {
  let mut drained = 0
  let mut done = false
  while !done && drained < 64 {
    let continues = match route.take(window, 0, "end_text_input") {
      Ok((Some(_), _)) => {
        drained += 1
        true
      }
      _ => false
    }
    if !continues {
      done = true
    }
  }
}

///|
/// Disable the native client and revoke the epoch. Repeated or stale epochs are
/// rejected before any native call.
fn[R : TextRoute] end_text_route(
  state : TextHostState,
  route : R,
  epoch : UInt64,
) -> Result[TextHostState, @diagnostics.FrameworkError] {
  let active = match text_route_session(state, epoch, "end_text_input") {
    Err(failure) => return Err(failure)
    Ok(value) => value
  }
  let next = { ..state, active: None, }
  match route.enable(active.window, false, "end_text_input") {
    Err(failure) => Err(failure)
    Ok(_) => {
      drain_text_frames(route, active.window)
      Ok(next)
    }
  }
}

///|
/// Deliver one ordered observation. Composition start frames carry no
/// observation and are skipped. Frames are delivered even when the window is
/// not key; a lost key window is reported once as `FocusLost` with a negative
/// synthetic sequence that cannot collide with the per-window native sequence
/// numbers, and only after this session observed key focus at least once.
fn[R : TextRoute] next_text_route(
  state : TextHostState,
  route : R,
  timeout_ms : Int32,
) -> Result[
  (TextHostState, @text_host.TextInputEvent?),
  @diagnostics.FrameworkError,
] {
  if timeout_ms < 0 || timeout_ms > 250 {
    return Err(error(@diagnostics.InvalidInput, "next_text_input"))
  }
  let active = match state.active {
    Some(value) => value
    None => return Ok((state, None))
  }
  let key = match route.is_key(active.window, "next_text_input") {
    Err(failure) => return Err(failure)
    Ok(value) => value
  }
  let mut current = if key {
    {
      ..state,
      active: Some({ ..active, had_focus: true, focus_reported: false, }),
    }
  } else {
    state
  }
  let mut remaining = 16
  while remaining > 0 {
    remaining -= 1
    let wait = if remaining == 15 { timeout_ms } else { 0 }
    let (kind, sequence) = match
      route.take(active.window, wait, "next_text_input") {
      Err(failure) => return Err(failure)
      Ok((None, _)) => {
        let observed = match current.active {
          Some(session) =>
            if !key && session.had_focus && !session.focus_reported {
              let sequence = current.next_synthetic_sequence
              let event = @text_host.TextInputEvent::new(
                session.window,
                sequence,
                session.epoch,
                @text_host.FocusLost,
              )
              current = {
                ..current,
                next_synthetic_sequence: sequence - 1L,
                active: Some({ ..session, focus_reported: true, }),
              }
              Some(event)
            } else {
              None
            }
          None => None
        }
        return Ok((current, observed))
      }
      Ok((Some(value), sequence)) => (value, sequence)
    }
    let observed = match kind {
      @primitives.Start => None
      @primitives.Update(text~, cursor_utf16~) =>
        Some(@text_host.Preedit(text~, cursor=cursor_utf16))
      @primitives.Commit(text~) => Some(@text_host.Commit(text~))
      @primitives.Cancel => Some(@text_host.Cancel)
    }
    match observed {
      Some(kind) =>
        return Ok(
          (
            current,
            Some(
              @text_host.TextInputEvent::new(
                active.window,
                sequence,
                active.epoch,
                kind,
              ),
            ),
          ),
        )
      None => ()
    }
  }
  Ok((current, None))
}

///|
pub extend Host with @text_host.TextInputHost::{
  begin_text_input,
  update_text_input,
  cancel_text_input,
  end_text_input,
  next_text_input,
}

///|
/// Optional AppKit transport for native text sessions. The general
/// `@platform.Backend` interface is unchanged; a host without this route keeps
/// returning `UnsupportedCapability` from its backend.
pub impl @text_host.TextInputHost for Host with fn begin_text_input(
  self,
  window,
  root,
) {
  match self.check() {
    Err(failure) => return Err(failure)
    Ok(_) => ()
  }
  match
    begin_text_route(self.text.val, NativeTextRoute::new(self), window, root) {
    Err(failure) => Err(failure)
    Ok((state, epoch)) => {
      self.text.val = state
      Ok(epoch)
    }
  }
}

///|
pub impl @text_host.TextInputHost for Host with fn update_text_input(
  self,
  epoch,
  value,
) {
  match self.check() {
    Err(failure) => return Err(failure)
    Ok(_) => ()
  }
  match
    update_text_route(self.text.val, NativeTextRoute::new(self), epoch, value) {
    Err(failure) => Err(failure)
    Ok(state) => {
      self.text.val = state
      Ok(epoch)
    }
  }
}

///|
pub impl @text_host.TextInputHost for Host with fn cancel_text_input(
  self,
  epoch,
) {
  match self.check() {
    Err(failure) => return Err(failure)
    Ok(_) => ()
  }
  match cancel_text_route(self.text.val, NativeTextRoute::new(self), epoch) {
    Err(failure) => Err(failure)
    Ok(state) => {
      self.text.val = state
      Ok(epoch)
    }
  }
}

///|
pub impl @text_host.TextInputHost for Host with fn end_text_input(self, epoch) {
  match self.check() {
    Err(failure) => return Err(failure)
    Ok(_) => ()
  }
  match end_text_route(self.text.val, NativeTextRoute::new(self), epoch) {
    Err(failure) => Err(failure)
    Ok(state) => {
      self.text.val = state
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
    Err(failure) => return Err(failure)
    Ok(_) => ()
  }
  match next_text_route(self.text.val, NativeTextRoute::new(self), timeout_ms) {
    Err(failure) => Err(failure)
    Ok((state, event)) => {
      self.text.val = state
      Ok(event)
    }
  }
}
