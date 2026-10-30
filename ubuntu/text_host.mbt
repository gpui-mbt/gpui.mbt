///|
/// One portable text-input route over the existing Ubuntu text-input-v1
/// session.
///
/// The host-local `begin_text_session`/`update_text_session`/
/// `next_editor_event` API remains authoritative. This adapter owns the portable
/// epoch, the ordered translation of editor records, and the ordinary platform
/// records it parks while the application pumps both queues.
pub struct TextHostRoute {
  priv host : Host
  priv queue : @text_host.TextHostQueue
  priv mut native_epoch : Int32
  priv mut window : @platform.WindowId?
  priv mut started : Bool
  priv ordered : Bool
  priv shortcuts : ShortcutKeyTracker
}

///|
extern "C" fn native_terminal_retention_active(host : Int32) -> Int32 = "gpui_terminal_retention_active"

///|
fn TextHostRoute::require_legacy_mode(
  self : TextHostRoute,
  operation : String,
) -> Result[Unit, @diagnostics.FrameworkError] {
  let active = native_terminal_retention_active(self.host.token)
  if active < 0 {
    return Err(backend_error(-active, operation))
  }
  if active != 0 {
    return Err(
      ubuntu_text_host_error(@diagnostics.UnsupportedCapability, operation),
    )
  }
  Ok(())
}

///|
fn ubuntu_text_host_error(
  code : @diagnostics.ErrorCode,
  operation : String,
) -> @diagnostics.FrameworkError {
  @diagnostics.FrameworkError::new(
    code,
    operation,
    subsystem="ubuntu-text-host",
  )
}

///|
pub fn TextHostRoute::new(host : Host) -> TextHostRoute {
  {
    host,
    queue: @text_host.TextHostQueue::new(),
    native_epoch: 0,
    window: None,
    started: false,
    ordered: false,
    shortcuts: ShortcutKeyTracker::new(),
  }
}

///|
/// Internal constructor: ordered routes are exposed only through the separate
/// wrapper, which does not implement the legacy `TextInputHost` poll API.
fn TextHostRoute::new_ordered(host : Host) -> TextHostRoute {
  {
    host,
    queue: @text_host.TextHostQueue::new(),
    native_epoch: 0,
    window: None,
    started: false,
    ordered: true,
    shortcuts: ShortcutKeyTracker::new(),
  }
}

///|
/// A single record from Ubuntu's ordered editor ingress.
pub(all) enum OrderedTextEvent {
  Text(@text_host.TextInputEvent)
  Platform(@platform.Event)
}

///|
/// Opt-in ordered facade. It does not implement `TextInputHost`: the latter's
/// independent text poll cannot express this route's cross-kind ordering.
pub struct OrderedTextHostRoute {
  priv route : TextHostRoute
}

///|
pub fn OrderedTextHostRoute::new(host : Host) -> OrderedTextHostRoute {
  { route: TextHostRoute::new_ordered(host), }
}

///|
pub fn OrderedTextHostRoute::begin_text_input(
  self : OrderedTextHostRoute,
  window : @platform.WindowId,
  root : UInt64,
) -> Result[UInt64, @diagnostics.FrameworkError] {
  self.route.begin_text_input(window, root)
}

///|
pub fn OrderedTextHostRoute::update_text_input(
  self : OrderedTextHostRoute,
  epoch : UInt64,
  state : @text_host.TextInputState,
) -> Result[UInt64, @diagnostics.FrameworkError] {
  self.route.update_text_input(epoch, state)
}

///|
pub fn OrderedTextHostRoute::cancel_text_input(
  self : OrderedTextHostRoute,
  epoch : UInt64,
) -> Result[UInt64, @diagnostics.FrameworkError] {
  self.route.cancel_text_input(epoch)
}

///|
pub fn OrderedTextHostRoute::end_text_input(
  self : OrderedTextHostRoute,
  epoch : UInt64,
) -> Result[Unit, @diagnostics.FrameworkError] {
  self.route.end_text_input(epoch)
}

///|
/// End at an empty native editor queue after the owner has processed every
/// returned record. Busy is side-effect-free; successful end is not an IME
/// commit/cancel observation or proof that the input method is quiescent.
pub fn OrderedTextHostRoute::try_end_when_drained(
  self : OrderedTextHostRoute,
  epoch : UInt64,
) -> Result[Unit, @diagnostics.FrameworkError] {
  let route = self.route
  let operation = "try_end_when_drained"
  if !route.queue.is_active() || epoch != route.queue.epoch() {
    return Err(ubuntu_text_host_error(@diagnostics.StaleHandle, operation))
  }
  if !route.started {
    return Err(ubuntu_text_host_error(@diagnostics.InvalidInput, operation))
  }
  match route.queue.failure() {
    Some(code) => return Err(ubuntu_text_host_error(code, operation))
    None => ()
  }
  if route.queue.has_text() || route.queue.has_parked() {
    return Err(ubuntu_text_host_error(@diagnostics.Busy, operation))
  }
  match route.require_legacy_mode(operation) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  match
    route.host.end_text_session_when_drained(
      route.window.unwrap(),
      route.native_epoch,
    ) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  route.started = false
  match route.queue.end(epoch) {
    Err(error) => Err(error)
    Ok(_) => {
      route.shortcuts.held = 0
      Ok(())
    }
  }
}

///|
pub fn OrderedTextHostRoute::reset(self : OrderedTextHostRoute) -> Unit {
  self.route.reset()
}

///|
/// Drain one ordinary platform record, absorbing text records into the portable
/// queue. Use this instead of `Host::next_event` while the route is active.
pub fn TextHostRoute::next_platform_event(
  self : TextHostRoute,
  timeout_ms~ : Int32 = 16,
) -> Result[@platform.Event?, @diagnostics.FrameworkError] {
  if self.ordered {
    return Err(
      ubuntu_text_host_error(@diagnostics.InvalidInput, "next_platform_event"),
    )
  }
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
/// Portable translation of one editor record.
priv enum TextTranslation {
  Emit(@text_host.TextInputEventKind)
  Forward(@primitives.Key, Bool, @primitives.Modifiers)
  Unsupported
  Skip
}

///|
/// The bounded command keys are not text. Track only acquisitions so their
/// release survives a modifier being released before the character key.
priv struct ShortcutKeyTracker {
  mut held : Int32
}

///|
fn ShortcutKeyTracker::new() -> ShortcutKeyTracker {
  { held: 0, }
}

///|
fn shortcut_key(keysym : Int32) -> (Int32, @primitives.Key)? {
  match keysym {
    0x61 | 0x41 => Some((1, @primitives.Character("a")))
    0x63 | 0x43 => Some((2, @primitives.Character("c")))
    0x78 | 0x58 => Some((4, @primitives.Character("x")))
    0x76 | 0x56 => Some((8, @primitives.Character("v")))
    0x7a | 0x5a => Some((16, @primitives.Character("z")))
    0x79 | 0x59 => Some((32, @primitives.Character("y")))
    _ => None
  }
}

///|
fn ShortcutKeyTracker::translate(
  self : ShortcutKeyTracker,
  event : TextSessionEvent,
) -> TextTranslation {
  match event {
    ForwardedPressed(keysym~, modifiers~, ..) =>
      match shortcut_key(keysym) {
        Some((bit, key)) if modifiers.control() || modifiers.meta() => {
          self.held = self.held | bit
          Forward(key, true, modifiers)
        }
        _ => translate_editor_event(event)
      }
    ForwardedReleased(keysym~, modifiers~, ..) =>
      match shortcut_key(keysym) {
        Some((bit, key)) if (self.held & bit) != 0 => {
          self.held = self.held & (63 - bit)
          Forward(key, false, modifiers)
        }
        _ => translate_editor_event(event)
      }
    _ => translate_editor_event(event)
  }
}

///|
fn translate_editor_event(event : TextSessionEvent) -> TextTranslation {
  match event {
    Entered | Left => Skip
    Preedit(text~, cursor_utf16~, ..) =>
      Emit(@text_host.Preedit(text~, cursor=cursor_utf16.unwrap_or(-1)))
    Commit(text~, deletion~, ..) =>
      match deletion {
        Some(value) if value.length_bytes != 0 => Unsupported
        _ => Emit(@text_host.Commit(text~))
      }
    ForwardedPressed(key~, modifiers~, ..) =>
      match key {
        Some(value) => Forward(value, true, modifiers)
        None => Skip
      }
    ForwardedReleased(key~, modifiers~, ..) =>
      match key {
        Some(value) => Forward(value, false, modifiers)
        None => Skip
      }
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
  match self.shortcuts.translate(event) {
    Skip => Ok(())
    Unsupported => {
      self.queue.fail(@diagnostics.UnsupportedCapability)
      Err(
        ubuntu_text_host_error(
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
    Forward(key, pressed, modifiers) => {
      let scale = match self.host.window_metrics(target.window) {
        Err(error) => return Err(error)
        Ok((_, _, value)) => value
      }
      let kind = if pressed {
        @platform.Input(@primitives.KeyPressed(key~, repeat=false, modifiers~))
      } else {
        @platform.Input(@primitives.KeyReleased(key~, modifiers~))
      }
      let event = @platform.Event::new(
        target.window,
        target.sequence,
        scale,
        kind,
      )
      if !self.queue.park(event) {
        self.queue.fail(@diagnostics.ResourceExhausted)
        return Err(
          ubuntu_text_host_error(
            @diagnostics.ResourceExhausted,
            "next_text_input",
          ),
        )
      }
      Ok(())
    }
  }
}

///|
pub impl @text_host.TextInputHost for TextHostRoute with fn begin_text_input(
  self,
  window,
  root,
) {
  match self.require_legacy_mode("begin_text_input") {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  if root == 0UL || self.queue.is_active() {
    return Err(
      ubuntu_text_host_error(@diagnostics.InvalidInput, "begin_text_input"),
    )
  }
  let epoch = match self.queue.begin(window) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  self.window = Some(window)
  self.native_epoch = 0
  self.started = false
  self.shortcuts.held = 0
  Ok(epoch)
}

///|
pub impl @text_host.TextInputHost for TextHostRoute with fn update_text_input(
  self,
  epoch,
  state,
) {
  match self.require_legacy_mode("update_text_input") {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let epoch = match self.queue.update(epoch, state) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  if !self.started {
    self.native_epoch = match
      self.host.begin_text_session(
        self.window.unwrap(),
        state.document(),
        state.caret(),
      ) {
      Err(error) => return Err(error)
      Ok(value) => value
    }
    self.started = true
  } else {
    let previous = self.native_epoch
    let next = match
      self.host.update_text_session(
        self.window.unwrap(),
        self.native_epoch,
        state.document(),
        state.caret(),
        external_edit=false,
      ) {
      Err(error) => return Err(error)
      Ok(value) => value
    }
    if next != previous {
      self.queue.discard_text()
      self.shortcuts.held = 0
    }
    self.native_epoch = next
  }
  Ok(epoch)
}

///|
pub impl @text_host.TextInputHost for TextHostRoute with fn cancel_text_input(
  self,
  epoch,
) {
  match self.require_legacy_mode("cancel_text_input") {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let replacement = match self.queue.cancel(epoch) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  self.shortcuts.held = 0
  if self.started {
    self.native_epoch = match
      self.host.cancel_text_session(self.window.unwrap(), self.native_epoch) {
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
  match self.require_legacy_mode("end_text_input") {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  if self.started {
    match self.host.end_text_session(self.window.unwrap(), self.native_epoch) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
    self.started = false
  }
  match self.queue.end(epoch) {
    Err(error) => Err(error)
    Ok(_) => {
      self.shortcuts.held = 0
      Ok(())
    }
  }
}

///|
pub impl @text_host.TextInputHost for TextHostRoute with fn next_text_input(
  self,
  timeout_ms?,
) {
  if self.ordered {
    return Err(
      ubuntu_text_host_error(@diagnostics.InvalidInput, "next_text_input"),
    )
  }
  let timeout = match timeout_ms {
    Some(value) => value
    None => 16
  }
  match self.queue.failure() {
    Some(code) => return Err(ubuntu_text_host_error(code, "next_text_input"))
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
        if self.queue.has_text() {
          return Ok(self.queue.take_text())
        }
      }
      Platform(value) => {
        if !self.queue.park(value) {
          self.queue.fail(@diagnostics.ResourceExhausted)
          return Err(
            ubuntu_text_host_error(
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
/// Read text and ordinary platform records in the order copied from the Ubuntu
/// editor stream. This is an ingress ordering guarantee, not a host shutdown
/// or IME quiescence barrier.
pub fn OrderedTextHostRoute::next_ordered_event(
  self : OrderedTextHostRoute,
  timeout_ms~ : Int32 = 16,
) -> Result[OrderedTextEvent?, @diagnostics.FrameworkError] {
  let route = self.route
  next_ordered_event_from(
    route.queue,
    timeout_ms,
    fn(timeout) { route.host.next_editor_event(timeout_ms=timeout) },
    fn(target, event) { route.absorb(target, event) },
  )
}

///|
fn next_ordered_event_from(
  queue : @text_host.TextHostQueue,
  timeout_ms : Int32,
  read : (Int32) -> Result[EditorEvent?, @diagnostics.FrameworkError],
  absorb : (TextSessionTarget, TextSessionEvent) -> Result[
    Unit,
    @diagnostics.FrameworkError,
  ],
) -> Result[OrderedTextEvent?, @diagnostics.FrameworkError] {
  match queue.failure() {
    Some(code) => return Err(ubuntu_text_host_error(code, "next_ordered_event"))
    None => ()
  }
  while true {
    let event = match read(timeout_ms) {
      Err(error) => return Err(error)
      Ok(None) => return Ok(None)
      Ok(Some(event)) => event
    }
    match event {
      Platform(event) => return Ok(Some(Platform(event)))
      TextSession(target, value) => {
        match absorb(target, value) {
          Err(error) => return Err(error)
          Ok(_) => ()
        }
        match queue.take_text() {
          Some(text) => return Ok(Some(Text(text)))
          None => ()
        }
        match queue.take_parked() {
          Some(event) => return Ok(Some(Platform(event)))
          None => ()
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
  self.window = None
  self.shortcuts.held = 0
}

///|
pub extend TextHostRoute with @text_host.TextInputHost::{
  begin_text_input,
  cancel_text_input,
  end_text_input,
  next_text_input,
  update_text_input,
}
