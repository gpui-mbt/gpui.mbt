///|
/// Copied platform event alias used by scripted signatures.
pub type ScriptedEvent = @platform.Event

///|
/// Copied platform window identity alias used by scripted signatures.
pub type ScriptedWindowId = @platform.WindowId

///|
/// Deterministic in-memory backend for application-runtime and backend tests.
/// It owns no native resources and presents only copied scene snapshots.
pub struct ScriptedBackend {
  priv window : @platform.WindowId
  priv mut width : Double
  priv mut height : Double
  priv mut scale : Double
  priv events : Array[@platform.Event]
  priv mut next_sequence : Int64
  priv presents : Array[@scene.SceneSnapshot]
  priv mut stop_calls : Int32
  priv mut destroy_calls : Int32
  priv mut close_calls : Int32
  priv mut exit_calls : Int32
  priv mut wake_calls : Int32
  priv mut failure : @diagnostics.FrameworkError?
  priv mut destroy_emits_destroyed : Bool
}

///|
/// Create one scripted window with a caller-supplied logical size and scale.
pub fn ScriptedBackend::new(
  width : Double,
  height : Double,
  scale : Double,
) -> Result[ScriptedBackend, @diagnostics.FrameworkError] {
  if !scripted_finite(width) ||
    !scripted_finite(height) ||
    !scripted_finite(scale) ||
    width <= 0.0 ||
    height <= 0.0 ||
    scale <= 0.0 {
    return Err(scripted_error("new", "invalid window metrics"))
  }
  Ok({
    window: @platform.WindowId::new(1L),
    width,
    height,
    scale,
    events: [],
    next_sequence: 1,
    presents: [],
    stop_calls: 0,
    destroy_calls: 0,
    close_calls: 0,
    exit_calls: 0,
    wake_calls: 0,
    failure: None,
    destroy_emits_destroyed: true,
  })
}

///|
fn scripted_finite(value : Double) -> Bool {
  !value.is_nan() && !value.is_inf()
}

///|
fn scripted_error(
  operation : String,
  message : String,
) -> @diagnostics.FrameworkError {
  @diagnostics.FrameworkError::new(
    @diagnostics.InvalidInput,
    operation,
    subsystem="platform-testing",
    backend="scripted-backend",
    message~,
  )
}

///|
pub fn ScriptedBackend::window(self : ScriptedBackend) -> ScriptedWindowId {
  self.window
}

///|
/// Enqueue a copied event for the scripted window. Sequence numbers increase
/// monotonically from one.
pub fn ScriptedBackend::enqueue(
  self : ScriptedBackend,
  kind : @platform.EventKind,
  scale : Double,
) -> Result[ScriptedEvent, @diagnostics.FrameworkError] {
  if !scripted_finite(scale) || scale <= 0.0 {
    return Err(scripted_error("enqueue", "invalid event scale"))
  }
  if self.next_sequence == 9223372036854775807L {
    return Err(scripted_error("enqueue", "event sequence exhausted"))
  }
  let event = @platform.Event::new(self.window, self.next_sequence, scale, kind)
  self.next_sequence += 1L
  self.events.push(event)
  Ok(event)
}

///|
/// Enqueue an event with an explicit sequence, for ordering-regression tests.
pub fn ScriptedBackend::enqueue_with_sequence(
  self : ScriptedBackend,
  kind : @platform.EventKind,
  scale : Double,
  sequence : Int64,
) -> Result[Unit, @diagnostics.FrameworkError] {
  if !scripted_finite(scale) ||
    scale <= 0.0 ||
    sequence < 0L ||
    sequence >= 9223372036854775807L {
    return Err(scripted_error("enqueue_with_sequence", "invalid event"))
  }
  self.events.push(@platform.Event::new(self.window, sequence, scale, kind))
  Ok(())
}

///|
pub fn ScriptedBackend::set_metrics(
  self : ScriptedBackend,
  width : Double,
  height : Double,
  scale : Double,
) -> Result[Unit, @diagnostics.FrameworkError] {
  if !scripted_finite(width) ||
    !scripted_finite(height) ||
    !scripted_finite(scale) ||
    width <= 0.0 ||
    height <= 0.0 ||
    scale <= 0.0 {
    return Err(scripted_error("set_metrics", "invalid window metrics"))
  }
  self.width = width
  self.height = height
  self.scale = scale
  Ok(())
}

///|
pub fn ScriptedBackend::fail_next_event(
  self : ScriptedBackend,
  failure : @diagnostics.FrameworkError,
) -> Unit {
  self.failure = Some(failure)
}

///|
pub fn ScriptedBackend::set_destroy_emits_destroyed(
  self : ScriptedBackend,
  enabled : Bool,
) -> Unit {
  self.destroy_emits_destroyed = enabled
}

///|
pub fn ScriptedBackend::present_count(self : ScriptedBackend) -> Int32 {
  self.presents.length()
}

///|
pub fn ScriptedBackend::presents(
  self : ScriptedBackend,
) -> Array[@scene.SceneSnapshot] {
  self.presents.copy()
}

///|
pub fn ScriptedBackend::last_present(
  self : ScriptedBackend,
) -> @scene.SceneSnapshot? {
  let count = self.presents.length()
  if count == 0 {
    None
  } else {
    Some(self.presents[count - 1])
  }
}

///|
pub fn ScriptedBackend::destroy_count(self : ScriptedBackend) -> Int32 {
  self.destroy_calls
}

///|
pub fn ScriptedBackend::request_close_count(self : ScriptedBackend) -> Int32 {
  self.close_calls
}

///|
pub fn ScriptedBackend::request_exit_count(self : ScriptedBackend) -> Int32 {
  self.exit_calls
}

///|
pub fn ScriptedBackend::stop_count(self : ScriptedBackend) -> Int32 {
  self.stop_calls
}

///|
pub fn ScriptedBackend::wake_count(self : ScriptedBackend) -> Int32 {
  self.wake_calls
}

///|
pub extend ScriptedBackend with @platform.Backend::{
  require_capability,
  stop,
  create_window,
  set_title,
  set_size,
  window_metrics,
  next_event,
  present,
  request_close,
  destroy_window,
  wake,
  request_exit,
}

///|
pub impl @platform.Backend for ScriptedBackend with fn require_capability(
  self,
  capability : @platform.Capability,
) -> Result[Unit, @diagnostics.FrameworkError] {
  ignore(self)
  ignore(capability)
  Ok(())
}

///|
pub impl @platform.Backend for ScriptedBackend with fn stop(self) -> Result[
  Unit,
  @diagnostics.FrameworkError,
] {
  self.stop_calls += 1
  Ok(())
}

///|
pub impl @platform.Backend for ScriptedBackend with fn create_window(
  self,
  title : String,
  width : Double,
  height : Double,
) -> Result[ScriptedWindowId, @diagnostics.FrameworkError] {
  ignore(title)
  match self.set_metrics(width, height, self.scale) {
    Err(error) => Err(error)
    Ok(_) => Ok(self.window)
  }
}

///|
pub impl @platform.Backend for ScriptedBackend with fn set_title(
  self,
  window : ScriptedWindowId,
  title : String,
) -> Result[Unit, @diagnostics.FrameworkError] {
  if window != self.window {
    return Err(scripted_error("set_title", "unknown window"))
  }
  if title.length() == 0 {
    return Err(scripted_error("set_title", "empty title"))
  }
  Ok(())
}

///|
pub impl @platform.Backend for ScriptedBackend with fn set_size(
  self,
  window : ScriptedWindowId,
  width : Double,
  height : Double,
) -> Result[Unit, @diagnostics.FrameworkError] {
  if window != self.window {
    return Err(scripted_error("set_size", "unknown window"))
  }
  self.set_metrics(width, height, self.scale)
}

///|
pub impl @platform.Backend for ScriptedBackend with fn window_metrics(
  self,
  window : ScriptedWindowId,
) -> Result[(Double, Double, Double), @diagnostics.FrameworkError] {
  if window != self.window {
    return Err(scripted_error("window_metrics", "unknown window"))
  }
  Ok((self.width, self.height, self.scale))
}

///|
pub impl @platform.Backend for ScriptedBackend with fn next_event(
  self,
  timeout_ms~ : Int32 = 16,
) -> Result[ScriptedEvent?, @diagnostics.FrameworkError] {
  ignore(timeout_ms)
  match self.failure {
    Some(failure) => {
      self.failure = None
      Err(failure)
    }
    None =>
      if self.events.length() == 0 {
        Ok(None)
      } else {
        Ok(Some(self.events.remove(0)))
      }
  }
}

///|
pub impl @platform.Backend for ScriptedBackend with fn present(
  self,
  window : ScriptedWindowId,
  snapshot : @scene.SceneSnapshot,
) -> Result[Unit, @diagnostics.FrameworkError] {
  if window != self.window {
    return Err(scripted_error("present", "unknown window"))
  }
  self.presents.push(snapshot)
  Ok(())
}

///|
pub impl @platform.Backend for ScriptedBackend with fn request_close(
  self,
  window : ScriptedWindowId,
) -> Result[Unit, @diagnostics.FrameworkError] {
  if window != self.window {
    return Err(scripted_error("request_close", "unknown window"))
  }
  self.close_calls += 1
  Ok(())
}

///|
pub impl @platform.Backend for ScriptedBackend with fn destroy_window(
  self,
  window : ScriptedWindowId,
) -> Result[Unit, @diagnostics.FrameworkError] {
  if window != self.window {
    return Err(scripted_error("destroy_window", "unknown window"))
  }
  self.destroy_calls += 1
  if self.destroy_emits_destroyed {
    let _ = self.enqueue(@platform.Destroyed, self.scale)
  }
  Ok(())
}

///|
pub impl @platform.Backend for ScriptedBackend with fn wake(self) -> Result[
  Unit,
  @diagnostics.FrameworkError,
] {
  self.wake_calls += 1
  let _ = self.enqueue(@platform.Wake, self.scale)
  Ok(())
}

///|
pub impl @platform.Backend for ScriptedBackend with fn request_exit(self) -> Result[
  Unit,
  @diagnostics.FrameworkError,
] {
  self.exit_calls += 1
  Ok(())
}
