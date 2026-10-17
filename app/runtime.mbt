///|
/// Logical window size and backing scale sampled by the application runtime.
/// Every scene passed to `present` must use this exact viewport and scale.
pub(all) struct WindowMetrics {
  width : Double
  height : Double
  scale : Double
}

///|
pub fn WindowMetrics::new(
  width : Double,
  height : Double,
  scale : Double,
) -> Result[WindowMetrics, @diagnostics.FrameworkError] {
  if !app_finite(width) ||
    !app_finite(height) ||
    !app_finite(scale) ||
    width <= 0.0 ||
    height <= 0.0 ||
    scale <= 0.0 {
    Err(app_error("window_metrics", "invalid window metrics"))
  } else {
    Ok({ width, height, scale, })
  }
}

///|
pub fn WindowMetrics::width(self : WindowMetrics) -> Double {
  self.width
}

///|
pub fn WindowMetrics::height(self : WindowMetrics) -> Double {
  self.height
}

///|
pub fn WindowMetrics::scale(self : WindowMetrics) -> Double {
  self.scale
}

///|
/// The logical viewport used by a scene snapshot for these metrics.
pub fn WindowMetrics::logical_rect(
  self : WindowMetrics,
) -> Result[@primitives.Rect, @diagnostics.FrameworkError] {
  match @primitives.Rect::new(0.0, 0.0, self.width, self.height) {
    Ok(value) => Ok(value)
    Err(_) => Err(app_error("window_metrics", "invalid viewport geometry"))
  }
}

///|
/// What the application wants the runtime to do after an event or frame.
pub(all) struct EventOutcome {
  repaint : Bool
  close : Bool
  exit : Bool
}

///|
pub fn EventOutcome::none() -> EventOutcome {
  { repaint: false, close: false, exit: false, }
}

///|
pub fn EventOutcome::repaint() -> EventOutcome {
  { repaint: true, close: false, exit: false, }
}

///|
pub fn EventOutcome::close() -> EventOutcome {
  { repaint: false, close: true, exit: false, }
}

///|
pub fn EventOutcome::exit() -> EventOutcome {
  { repaint: false, close: false, exit: true, }
}

///|
/// One application view driven by a single native window. Implementations own
/// application state and scene composition; the runtime owns event ordering,
/// metrics sampling, frame validation, close/destroy policy and bounded loops.
pub(open) trait WindowView {
  fn handle_event(Self, @platform.Event, WindowMetrics) -> Result[
    EventOutcome,
    @diagnostics.FrameworkError,
  ]
  fn scene(Self, WindowMetrics) -> Result[
    @scene.SceneSnapshot,
    @diagnostics.FrameworkError,
  ]
  fn after_present(Self, WindowMetrics) -> Result[
    EventOutcome,
    @diagnostics.FrameworkError,
  ]
  fn on_idle(Self, WindowMetrics) -> Result[
    EventOutcome,
    @diagnostics.FrameworkError,
  ]
}

///|
/// Why the runtime stopped. `Destroyed` covers both an application close and a
/// backend-initiated terminal event.
pub(all) enum RunStopReason {
  Destroyed
  MaxTicks
} derive(Eq)

///|
pub extend RunStopReason with Eq::{not_equal, equal}

///|
pub(all) struct WindowRunOutcome {
  reason : RunStopReason
  frames : Int32
  events : Int32
  last_sequence : Int64
}

///|
pub fn WindowRunOutcome::reason(self : WindowRunOutcome) -> RunStopReason {
  self.reason
}

///|
pub fn WindowRunOutcome::frames(self : WindowRunOutcome) -> Int32 {
  self.frames
}

///|
pub fn WindowRunOutcome::events(self : WindowRunOutcome) -> Int32 {
  self.events
}

///|
pub fn WindowRunOutcome::last_sequence(self : WindowRunOutcome) -> Int64 {
  self.last_sequence
}

///|
fn app_finite(value : Double) -> Bool {
  !value.is_nan() && !value.is_inf()
}

///|
fn app_error(
  operation : String,
  message : String,
) -> @diagnostics.FrameworkError {
  @diagnostics.FrameworkError::new(
    @diagnostics.InvalidInput,
    operation,
    subsystem="app",
    backend="window-runtime",
    message~,
  )
}

///|
fn[B : @platform.Backend] app_sample_metrics(
  backend : B,
  window : @platform.WindowId,
) -> Result[WindowMetrics, @diagnostics.FrameworkError] {
  let metrics = backend.window_metrics(window)
  match metrics {
    Err(error) => Err(error)
    Ok((width, height, scale)) => WindowMetrics::new(width, height, scale)
  }
}

///|
fn app_validate_scene(
  snapshot : @scene.SceneSnapshot,
  metrics : WindowMetrics,
) -> Result[Unit, @diagnostics.FrameworkError] {
  let viewport = metrics.logical_rect()
  match viewport {
    Err(error) => Err(error)
    Ok(rect) =>
      if snapshot.viewport() != rect {
        Err(
          app_error(
            "window_scene", "scene viewport does not match window metrics",
          ),
        )
      } else if snapshot.scale() != metrics.scale {
        Err(
          app_error("window_scene", "scene scale does not match window metrics"),
        )
      } else {
        Ok(())
      }
  }
}

///|
fn[B : @platform.Backend] app_stop_window(
  backend : B,
  window : @platform.WindowId,
  exit_requested : Bool,
) -> Result[Unit, @diagnostics.FrameworkError] {
  if exit_requested {
    let exit = backend.request_exit()
    match exit {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
  }
  backend.destroy_window(window)
}

///|
/// Run one already-created native window until it is destroyed or `max_ticks`
/// is reached. The caller owns host startup/shutdown. `after_present` and
/// `on_idle` let applications poll native work and drive bounded tests without
/// adding test hooks to this portable layer.
pub fn[B : @platform.Backend, V : WindowView] run_window(
  backend : B,
  window : @platform.WindowId,
  view : V,
  timeout_ms~ : Int32 = 16,
  max_ticks~ : Int32? = None,
  present_on_start~ : Bool = true,
) -> Result[WindowRunOutcome, @diagnostics.FrameworkError] {
  if timeout_ms < 0 {
    return Err(app_error("window_runtime", "timeout must be non-negative"))
  }
  match max_ticks {
    Some(limit) if limit < 0 =>
      return Err(app_error("window_runtime", "max_ticks must be non-negative"))
    _ => ()
  }
  let initial = app_sample_metrics(backend, window)
  let mut metrics = match initial {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let mut dirty = present_on_start
  let mut closing = false
  let mut done = false
  let mut frames = 0
  let mut events = 0
  let mut last_sequence : Int64 = 0
  let mut ticks = 0
  while !done {
    if max_ticks is Some(limit) && ticks >= limit {
      return Ok({ reason: MaxTicks, frames, events, last_sequence, })
    }
    ticks += 1
    if !closing && dirty {
      metrics = match app_sample_metrics(backend, window) {
        Err(error) => return Err(error)
        Ok(value) => value
      }
      let snapshot = match view.scene(metrics) {
        Err(error) => return Err(error)
        Ok(value) => value
      }
      match app_validate_scene(snapshot, metrics) {
        Err(error) => return Err(error)
        Ok(_) => ()
      }
      match backend.present(window, snapshot) {
        Err(error) => return Err(error)
        Ok(_) => ()
      }
      frames += 1
      dirty = false
      let outcome = match view.after_present(metrics) {
        Err(error) => return Err(error)
        Ok(value) => value
      }
      if outcome.exit {
        match app_stop_window(backend, window, true) {
          Err(error) => return Err(error)
          Ok(_) => ()
        }
        closing = true
      } else if outcome.close {
        match app_stop_window(backend, window, false) {
          Err(error) => return Err(error)
          Ok(_) => ()
        }
        closing = true
      } else if outcome.repaint {
        dirty = true
      }
    }
    let event = match backend.next_event(timeout_ms~) {
      Err(error) => return Err(error)
      Ok(None) => {
        if !closing {
          let outcome = match view.on_idle(metrics) {
            Err(error) => return Err(error)
            Ok(value) => value
          }
          if outcome.exit {
            match app_stop_window(backend, window, true) {
              Err(error) => return Err(error)
              Ok(_) => ()
            }
            closing = true
          } else if outcome.close {
            match app_stop_window(backend, window, false) {
              Err(error) => return Err(error)
              Ok(_) => ()
            }
            closing = true
          } else if outcome.repaint {
            dirty = true
          }
        }
        continue
      }
      Ok(Some(value)) => value
    }
    if event.window() == window {
      if event.sequence() <= last_sequence {
        return Err(
          app_error("window_event_sequence", "event sequence did not increase"),
        )
      }
      last_sequence = event.sequence()
      if event.kind() is @platform.Destroyed {
        done = true
      } else if !closing {
        events += 1
        let kind = event.kind()
        if kind is @platform.Resized(width=_, height=_) ||
          kind is @platform.ScaleChanged {
          metrics = match app_sample_metrics(backend, window) {
            Err(error) => return Err(error)
            Ok(value) => value
          }
        }
        let outcome = match view.handle_event(event, metrics) {
          Err(error) => return Err(error)
          Ok(value) => value
        }
        if outcome.exit {
          match app_stop_window(backend, window, true) {
            Err(error) => return Err(error)
            Ok(_) => ()
          }
          closing = true
        } else if outcome.close {
          match app_stop_window(backend, window, false) {
            Err(error) => return Err(error)
            Ok(_) => ()
          }
          closing = true
        } else if outcome.repaint {
          dirty = true
        }
      }
    } else if event.kind() is @platform.ExitRequested && !closing {
      events += 1
      let outcome = match view.handle_event(event, metrics) {
        Err(error) => return Err(error)
        Ok(value) => value
      }
      if outcome.exit {
        match app_stop_window(backend, window, true) {
          Err(error) => return Err(error)
          Ok(_) => ()
        }
        closing = true
      } else if outcome.close {
        match app_stop_window(backend, window, false) {
          Err(error) => return Err(error)
          Ok(_) => ()
        }
        closing = true
      } else if outcome.repaint {
        dirty = true
      }
    }
  }
  Ok({ reason: Destroyed, frames, events, last_sequence, })
}
