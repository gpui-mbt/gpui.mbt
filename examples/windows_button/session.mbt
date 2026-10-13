///|
/// Adapter between Win32 host events and the shared portable Button fixture.
/// It owns no HWND or GPU resources; the executable owns those lifetimes.
pub struct WindowsButtonSession {
  demo : @fixture.ButtonDemo
  accessibility : WindowsButtonAccessibilityBinding
  width : Double
  height : Double
  scale : Double
  presentable : Bool
  closed : Bool
  session_generation : UInt64
  session_generation_source : Ref[UInt64?]
  repeat_keydowns : Int32
  unmatched_key_releases : Int32
  unmatched_pointer_releases : Int32
}

///|
enum WindowsButtonSessionError {
  InvalidMetrics
  FixtureFailure
  AccessibilityFailure
  Suspended
  StaleSession
}

///|
fn windows_button_fixture_result(
  result : Result[@fixture.ButtonDemo, @fixture.ButtonDemoError],
) -> Result[@fixture.ButtonDemo, WindowsButtonSessionError] {
  match result {
    Ok(value) => Ok(value)
    Err(_) => Err(FixtureFailure)
  }
}

///|
fn windows_button_valid_scale(scale : Double) -> Bool {
  !scale.is_nan() && !scale.is_inf() && scale > 0.0
}

///|
const WINDOWS_BUTTON_SESSION_MAX_GENERATION : UInt64 = 0xffff_ffff_ffff_ffff

///|
/// Session-only transitions (such as a backing-scale update) can make an
/// older immutable host value stale without changing the semantic fixture.
/// Keep this separate from the fixture's live model fence and require both.
fn windows_button_session_is_current(session : WindowsButtonSession) -> Bool {
  session.session_generation_source.val == Some(session.session_generation) &&
  session.demo.is_current()
}

///|
/// Advance the host-session owner fence after returning a changed session.
/// Exhaustion invalidates the source instead of wrapping to an old value.
fn windows_button_session_advance(
  session : WindowsButtonSession,
) -> WindowsButtonSession {
  match session.session_generation_source.val {
    Some(current) if current == session.session_generation =>
      if current == WINDOWS_BUTTON_SESSION_MAX_GENERATION {
        session.session_generation_source.val = None
        session
      } else {
        let next = current + 1UL
        session.session_generation_source.val = Some(next)
        { ..session, session_generation: next, }
      }
    _ => session
  }
}

///|
fn WindowsButtonSession::new(
  width : Double,
  height : Double,
  scale : Double,
) -> Result[WindowsButtonSession, WindowsButtonSessionError] {
  if width.is_nan() ||
    width.is_inf() ||
    width <= 0.0 ||
    height.is_nan() ||
    height.is_inf() ||
    height <= 0.0 ||
    !windows_button_valid_scale(scale) {
    return Err(InvalidMetrics)
  }
  match @fixture.ButtonDemo::new(width, height) {
    Ok(demo) => {
      let accessibility = match
        windows_button_accessibility_new(demo.accessibility_snapshot(), true) {
        Ok(value) => value
        Err(_) => {
          demo.close()
          return Err(AccessibilityFailure)
        }
      }
      Ok({
        demo,
        accessibility,
        width,
        height,
        scale,
        presentable: true,
        closed: false,
        session_generation: 1UL,
        session_generation_source: Ref(Some(1UL)),
        repeat_keydowns: 0,
        unmatched_key_releases: 0,
        unmatched_pointer_releases: 0,
      })
    }
    Err(_) => Err(FixtureFailure)
  }
}

///|
fn WindowsButtonSession::demo(
  self : WindowsButtonSession,
) -> @fixture.ButtonDemo {
  self.demo
}

///|
fn WindowsButtonSession::is_presentable(self : WindowsButtonSession) -> Bool {
  self.presentable
}

///|
/// Return the current copied semantic tree. A suspended or closed window has
/// an empty unavailable tree; a stale fixture value is reported explicitly.
pub fn WindowsButtonSession::accessibility_snapshot(
  self : WindowsButtonSession,
) -> Result[WindowsButtonAccessibilitySnapshot, WindowsButtonAccessibilityError] {
  // A closed session keeps returning its empty terminal snapshot. For every
  // live-looking copy, consult the fixture's shared owner fence before even
  // consulting the copied binding: its cached source snapshot is not authority.
  if !self.closed && !windows_button_session_is_current(self) {
    return Err(StaleSnapshot)
  }
  windows_button_accessibility_snapshot(
    self.accessibility,
    self.demo.accessibility_snapshot(),
    self.presentable && !self.closed,
  )
}

///|
/// Resolve a copied sample token against the current fixture, then deliver the
/// accepted Invoke through the app-owned ButtonDemo dispatcher. Repeated
/// delivery is intentionally repeatable, like the shared fixture contract.
pub fn WindowsButtonSession::dispatch_accessibility_action(
  self : WindowsButtonSession,
  export_id : WindowsButtonAccessibilityId,
  action : @accessibility.AccessibilityAction,
) -> Result[WindowsButtonSession, WindowsButtonAccessibilityError] {
  if !self.closed && !windows_button_session_is_current(self) {
    return Err(StaleSnapshot)
  }
  let node_id = match
    windows_button_accessibility_resolve(
      self.accessibility,
      self.demo.accessibility_snapshot(),
      self.presentable && !self.closed,
      export_id,
    ) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  match
    self.demo.dispatch_accessibility_request(
      @accessibility.ActionRequest::new(node_id, action),
    ) {
    Err(error) => Err(ActionRejected(error))
    Ok(demo) => {
      let next = { ..self, demo, }
      match
        windows_button_accessibility_publish(
          next.accessibility,
          next.demo.accessibility_snapshot(),
          next.presentable,
        ) {
        Ok(_) => Ok(windows_button_session_advance(next))
        Err(error) => {
          windows_button_accessibility_close(
            next.accessibility,
            next.demo.accessibility_snapshot().revision(),
          )
          next.demo.close()
          Err(error)
        }
      }
    }
  }
}

///|
fn windows_button_session_reconcile_accessibility(
  session : WindowsButtonSession,
) -> WindowsButtonSession {
  // A stale immutable copy must never publish or revoke the shared binding.
  // The live session generation and fixture owner are the source of truth;
  // this copy's cached source snapshot is never sufficient authority.
  if !windows_button_session_is_current(session) {
    return session
  }
  if session.closed {
    return session.close()
  }
  match
    windows_button_accessibility_publish(
      session.accessibility,
      session.demo.accessibility_snapshot(),
      session.presentable,
    ) {
    Ok(_) => session
    Err(_) => {
      windows_button_accessibility_close(
        session.accessibility,
        session.demo.accessibility_snapshot().revision(),
      )
      session.demo.close()
      { ..session, presentable: false, closed: true, }
    }
  }
}

///|
/// Revoke copied IDs and the app-owned semantic model when the HWND lifetime
/// ends, including process exit paths without a final Destroyed event.
fn WindowsButtonSession::close(
  self : WindowsButtonSession,
) -> WindowsButtonSession {
  if !windows_button_session_is_current(self) {
    // Preserve a local terminal value for stale callers without closing the
    // shared accessibility binding or revoking the current fixture owner.
    return { ..self, presentable: false, closed: true, }
  }
  windows_button_accessibility_close(
    self.accessibility,
    self.demo.accessibility_snapshot().revision(),
  )
  self.demo.close()
  { ..self, presentable: false, closed: true, }
}

///|
/// Reconcile a pending draw with the HWND's current client metrics. Exact
/// matches are a no-op so a metrics poll cannot cancel an armed gesture.
fn WindowsButtonSession::sync_metrics(
  self : WindowsButtonSession,
  width : Double,
  height : Double,
  scale : Double,
) -> (WindowsButtonSession, Bool) {
  if self.closed || !windows_button_session_is_current(self) {
    return (self, false)
  }
  if width.is_nan() ||
    width.is_inf() ||
    width <= 0.0 ||
    height.is_nan() ||
    height.is_inf() ||
    height <= 0.0 ||
    !windows_button_valid_scale(scale) {
    let next = windows_button_session_reconcile_accessibility({
      ..self,
      demo: self.demo.blur(),
      width,
      height,
      scale,
      presentable: false,
    })
    return (windows_button_session_advance(next), false)
  }
  if self.presentable &&
    self.width == width &&
    self.height == height &&
    self.scale == scale {
    return (self, false)
  }
  if self.presentable && self.width == width && self.height == height {
    return (windows_button_session_advance({ ..self, scale, }), true)
  }
  match self.demo.resize(width, height) {
    Ok(demo) =>
      (
        windows_button_session_advance(
          windows_button_session_reconcile_accessibility({
            ..self,
            demo,
            width,
            height,
            scale,
            presentable: true,
          }),
        ),
        true,
      )
    Err(_) =>
      (
        windows_button_session_advance(
          windows_button_session_reconcile_accessibility({
            ..self,
            demo: self.demo.blur(),
            width,
            height,
            scale,
            presentable: false,
          }),
        ),
        false,
      )
  }
}

///|
fn WindowsButtonSession::scene(
  self : WindowsButtonSession,
) -> Result[@scene.SceneSnapshot, WindowsButtonSessionError] {
  if !self.presentable {
    return Err(Suspended)
  }
  match self.demo.scene(self.scale) {
    Ok(value) => Ok(value)
    Err(_) => Err(FixtureFailure)
  }
}

///|
fn windows_button_route_input(
  demo : @fixture.ButtonDemo,
  input : @primitives.InputEvent,
) -> Result[@fixture.ButtonDemo, WindowsButtonSessionError] {
  match input {
    @primitives.KeyPressed(key=@primitives.Tab, repeat=false, ..) =>
      if demo.button().is_focused() {
        Ok(demo.blur())
      } else {
        windows_button_fixture_result(demo.focus_button())
      }
    // Win32 reports printable keys as committed TextInput records, separate
    // from WM_KEYDOWN. These sample-only controls keep the shared Button model
    // platform neutral while still exercising disable/loading/reset natively.
    @primitives.TextInput(text~) if text == "d" || text == "D" =>
      windows_button_fixture_result(
        demo.with_enabled(!demo.button().is_enabled()),
      )
    @primitives.TextInput(text~) if text == "l" || text == "L" =>
      windows_button_fixture_result(
        demo.with_loading(!demo.button().is_loading()),
      )
    @primitives.TextInput(text~) if text == "r" || text == "R" =>
      windows_button_fixture_result(demo.reset_session())
    _ => Ok(demo.handle_input(input))
  }
}

///|
/// Consume one event for the fixture's HWND. Invalid/zero sizes suspend
/// presentation and disarm input; a later valid size starts from a canceled
/// session. The host still owns DPI and event ordering.
fn WindowsButtonSession::handle_event(
  self : WindowsButtonSession,
  event : @platform.Event,
) -> Result[(WindowsButtonSession, Bool), WindowsButtonSessionError] {
  if self.closed {
    return Ok((self, false))
  }
  // A session copy can outlive a newer immutable value sharing the fixture
  // and accessibility binding. Reject all event-driven transitions before
  // they can publish, suspend, or close that newer owner's state.
  if !windows_button_session_is_current(self) {
    return Err(StaleSession)
  }
  let mut next = { ..self, scale: event.scale(), }
  let mut repaint = false
  match event.kind() {
    @platform.Created | @platform.Wake => repaint = next.presentable
    @platform.Resized(width~, height~) =>
      if width.is_nan() ||
        width.is_inf() ||
        width <= 0.0 ||
        height.is_nan() ||
        height.is_inf() ||
        height <= 0.0 ||
        !windows_button_valid_scale(next.scale) {
        next = {
          ..next,
          demo: next.demo.blur(),
          width,
          height,
          presentable: false,
        }
      } else {
        match next.demo.resize(width, height) {
          Ok(demo) => {
            next = { ..next, demo, width, height, presentable: true, }
            repaint = true
          }
          Err(_) =>
            next = { ..next, demo: next.demo.blur(), presentable: false, }
        }
      }
    @platform.ScaleChanged =>
      if !windows_button_valid_scale(next.scale) {
        next = { ..next, demo: next.demo.blur(), presentable: false, }
      } else if next.presentable {
        repaint = true
      } else if next.width > 0.0 && next.height > 0.0 {
        match next.demo.resize(next.width, next.height) {
          Ok(demo) => {
            next = { ..next, demo, presentable: true, }
            repaint = true
          }
          Err(_) => next = { ..next, demo: next.demo.blur(), }
        }
      }
    @platform.FocusChanged(false) | @platform.VisibilityChanged(false) => {
      next = { ..next, demo: next.demo.blur(), }
      repaint = next.presentable
    }
    @platform.FocusChanged(true) | @platform.VisibilityChanged(true) =>
      repaint = next.presentable
    @platform.Input(input) if next.presentable => {
      let repeat_keydowns = match input {
        @primitives.KeyPressed(repeat=true, ..) => next.repeat_keydowns + 1
        _ => next.repeat_keydowns
      }
      let button_was_pressed = next.demo.button().is_pressed()
      let unmatched_key_releases = match input {
        @primitives.KeyReleased(key=@primitives.Enter, ..) if !button_was_pressed =>
          next.unmatched_key_releases + 1
        @primitives.KeyReleased(key=@primitives.Space, ..) if !button_was_pressed =>
          next.unmatched_key_releases + 1
        _ => next.unmatched_key_releases
      }
      let unmatched_pointer_releases = match input {
        @primitives.PointerButtonReleased(button=@primitives.Primary, ..) if !button_was_pressed =>
          next.unmatched_pointer_releases + 1
        _ => next.unmatched_pointer_releases
      }
      next = {
        ..next,
        repeat_keydowns,
        unmatched_key_releases,
        unmatched_pointer_releases,
      }
      match windows_button_route_input(next.demo, input) {
        Ok(demo) => {
          next = { ..next, demo, }
          repaint = true
        }
        Err(error) => return Err(error)
      }
    }
    @platform.CloseRequested | @platform.Destroyed | @platform.ExitRequested =>
      next = {
        ..next,
        demo: next.demo.blur(),
        presentable: false,
        closed: true,
      }
    _ => ()
  }
  Ok(
    (
      windows_button_session_advance(
        windows_button_session_reconcile_accessibility(next),
      ),
      repaint,
    ),
  )
}
