///|
/// State adapter between AppKit host events and the reusable portable Button
/// fixture. It owns no platform resources; the executable owns the Host/window.
struct MacButtonSession {
  demo : @fixture.ButtonDemo
  width : Double
  height : Double
  scale : Double
  presentable : Bool
  session_generation : UInt64
  session_generation_source : Ref[UInt64?]
  accessibility_binding : MacButtonAXBinding?
}

///|
enum MacButtonSessionError {
  InvalidMetrics
  FixtureFailure
  Suspended
  StaleSession
}

///|
fn mac_button_fixture_result(
  result : Result[@fixture.ButtonDemo, @fixture.ButtonDemoError],
) -> Result[@fixture.ButtonDemo, MacButtonSessionError] {
  match result {
    Ok(value) => Ok(value)
    Err(_) => Err(FixtureFailure)
  }
}

///|
fn mac_button_valid_scale(scale : Double) -> Bool {
  !scale.is_nan() && !scale.is_inf() && scale > 0.0
}

///|
const MAC_BUTTON_SESSION_MAX_GENERATION : UInt64 = 0xffff_ffff_ffff_ffff

///|
/// Require both the portable fixture and the host-only session value to be
/// current. A scale update can stale a copied session without changing the
/// semantic fixture revision.
fn mac_button_session_is_current(session : MacButtonSession) -> Bool {
  session.session_generation_source.val == Some(session.session_generation) &&
  session.demo.is_current()
}

///|
/// Advance the host-session owner fence after returning changed state. At
/// exhaustion, invalidate the source instead of wrapping to an old value.
fn mac_button_session_advance(session : MacButtonSession) -> MacButtonSession {
  match session.session_generation_source.val {
    Some(current) if current == session.session_generation =>
      if current == MAC_BUTTON_SESSION_MAX_GENERATION {
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
fn MacButtonSession::new(
  width : Double,
  height : Double,
  scale : Double,
) -> Result[MacButtonSession, MacButtonSessionError] {
  if width.is_nan() ||
    width.is_inf() ||
    width <= 0.0 ||
    height.is_nan() ||
    height.is_inf() ||
    height <= 0.0 ||
    !mac_button_valid_scale(scale) {
    return Err(InvalidMetrics)
  }
  match @fixture.ButtonDemo::new(width, height) {
    Ok(demo) =>
      Ok({
        demo,
        width,
        height,
        scale,
        presentable: true,
        session_generation: 1UL,
        session_generation_source: Ref(Some(1UL)),
        accessibility_binding: None,
      })
    Err(_) => Err(FixtureFailure)
  }
}

///|
fn MacButtonSession::demo(self : MacButtonSession) -> @fixture.ButtonDemo {
  self.demo
}

///|
fn MacButtonSession::is_presentable(self : MacButtonSession) -> Bool {
  self.presentable
}

///|
/// Reconcile a pending draw with the host's authoritative current metrics.
/// Exact matches are a no-op so polling cannot cancel an armed gesture.
fn MacButtonSession::sync_metrics(
  self : MacButtonSession,
  width : Double,
  height : Double,
  scale : Double,
) -> (MacButtonSession, Bool) {
  if !mac_button_session_is_current(self) {
    return (self, false)
  }
  if width.is_nan() ||
    width.is_inf() ||
    width <= 0.0 ||
    height.is_nan() ||
    height.is_inf() ||
    height <= 0.0 ||
    !mac_button_valid_scale(scale) {
    return (
      mac_button_session_advance({
        demo: self.demo.blur(),
        width,
        height,
        scale,
        presentable: false,
        session_generation: self.session_generation,
        session_generation_source: self.session_generation_source,
        accessibility_binding: self.accessibility_binding,
      }),
      false,
    )
  }
  if self.presentable &&
    self.width == width &&
    self.height == height &&
    self.scale == scale {
    return (self, false)
  }
  if self.presentable && self.width == width && self.height == height {
    return (mac_button_session_advance({ ..self, scale, }), true)
  }
  match self.demo.resize(width, height) {
    Ok(demo) =>
      (
        mac_button_session_advance({
          demo,
          width,
          height,
          scale,
          presentable: true,
          session_generation: self.session_generation,
          session_generation_source: self.session_generation_source,
          accessibility_binding: self.accessibility_binding,
        }),
        true,
      )
    Err(_) =>
      (
        mac_button_session_advance({
          demo: self.demo.blur(),
          width,
          height,
          scale,
          presentable: false,
          session_generation: self.session_generation,
          session_generation_source: self.session_generation_source,
          accessibility_binding: self.accessibility_binding,
        }),
        false,
      )
  }
}

///|
fn MacButtonSession::scene(
  self : MacButtonSession,
) -> Result[@scene.SceneSnapshot, MacButtonSessionError] {
  if !self.presentable {
    return Err(Suspended)
  }
  match self.demo.scene(self.scale) {
    Ok(value) => Ok(value)
    Err(_) => Err(FixtureFailure)
  }
}

///|
fn mac_button_route_input(
  demo : @fixture.ButtonDemo,
  input : @primitives.InputEvent,
) -> Result[@fixture.ButtonDemo, MacButtonSessionError] {
  match input {
    @primitives.KeyPressed(key=@primitives.Tab, repeat=false, ..) =>
      if demo.button().is_focused() {
        Ok(demo.blur())
      } else {
        mac_button_fixture_result(demo.focus_button())
      }
    @primitives.KeyPressed(key=@primitives.Character(key), repeat=false, ..) =>
      if key == "d" || key == "D" {
        mac_button_fixture_result(
          demo.with_enabled(!demo.button().is_enabled()),
        )
      } else if key == "l" || key == "L" {
        mac_button_fixture_result(
          demo.with_loading(!demo.button().is_loading()),
        )
      } else if key == "r" || key == "R" {
        mac_button_fixture_result(demo.reset_session())
      } else {
        Ok(demo.handle_input(input))
      }
    _ => Ok(demo.handle_input(input))
  }
}

///|
/// Consume one event for this window. Invalid or zero dimensions suspend
/// presentation and disarm input; the next positive resize reuses the fixture
/// only after that cancellation has taken effect.
fn MacButtonSession::handle_event(
  self : MacButtonSession,
  event : @platform.Event,
) -> Result[(MacButtonSession, Bool), MacButtonSessionError] {
  if !mac_button_session_is_current(self) {
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
        height <= 0.0 {
        next = {
          ..next,
          demo: next.demo.blur(),
          width,
          height,
          presentable: false,
        }
      } else if !mac_button_valid_scale(next.scale) {
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
      if !mac_button_valid_scale(next.scale) {
        next = { ..next, demo: next.demo.blur(), presentable: false, }
      } else if next.presentable {
        repaint = true
      } else {
        match next.demo.resize(next.width, next.height) {
          Ok(demo) => {
            next = { ..next, demo, presentable: true, }
            repaint = true
          }
          Err(_) =>
            next = { ..next, demo: next.demo.blur(), presentable: false, }
        }
      }
    @platform.FocusChanged(false) | @platform.VisibilityChanged(false) => {
      next = { ..next, demo: next.demo.blur(), }
      repaint = next.presentable
    }
    @platform.FocusChanged(true) | @platform.VisibilityChanged(true) =>
      repaint = next.presentable
    @platform.Input(input) if next.presentable =>
      match mac_button_route_input(next.demo, input) {
        Ok(demo) => {
          next = { ..next, demo, }
          repaint = true
        }
        Err(error) => return Err(error)
      }
    @platform.CloseRequested | @platform.Destroyed | @platform.ExitRequested =>
      next = { ..next, demo: next.demo.blur(), presentable: false, }
    _ => ()
  }
  Ok((mac_button_session_advance(next), repaint))
}
