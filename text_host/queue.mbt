///|
/// Ordered portable text-input transport state for hosts that already expose a
/// host-local editor stream.
///
/// The queue owns the host-issued epoch, observation sequence, pending text
/// observations and parked ordinary platform events. A host adapter feeds its
/// native records in and exposes `take_text`/`take_parked` to the application.
/// It does not duplicate `TextSession` or the field value model.
pub struct TextHostQueue {
  priv mut window : @platform.WindowId?
  priv mut epoch : UInt64
  priv mut active : Bool
  priv mut sequence : Int64
  priv mut text : Array[TextInputEvent]
  priv mut parked : Array[@platform.Event]
  priv mut failure : @diagnostics.ErrorCode?
  priv mut state : TextInputState?
}

///|
/// Parked platform records are bounded so a consumer that pumps only text
/// cannot grow the queue without limit.
const TEXT_HOST_PARK_CAPACITY : Int32 = 1024

///|
fn text_host_queue_error(
  code : @diagnostics.ErrorCode,
  operation : String,
) -> @diagnostics.FrameworkError {
  @diagnostics.FrameworkError::new(code, operation, subsystem="text-host-queue")
}

///|
pub fn TextHostQueue::new() -> TextHostQueue {
  {
    window: None,
    epoch: 0UL,
    active: false,
    sequence: 0L,
    text: [],
    parked: [],
    failure: None,
    state: None,
  }
}

///|
/// Start one session and return its positive epoch. A second begin while the
/// queue is active is `Busy`.
pub fn TextHostQueue::begin(
  self : TextHostQueue,
  window : @platform.WindowId,
) -> Result[UInt64, @diagnostics.FrameworkError] {
  if self.active {
    return Err(text_host_queue_error(@diagnostics.Busy, "begin"))
  }
  if self.epoch == 18446744073709551615UL {
    return Err(text_host_queue_error(@diagnostics.ResourceExhausted, "begin"))
  }
  self.epoch += 1UL
  self.active = true
  self.window = Some(window)
  self.sequence = 0L
  self.text = []
  self.parked = []
  self.failure = None
  self.state = None
  Ok(self.epoch)
}

///|
/// Replace the owner state for the exact current epoch.
pub fn TextHostQueue::update(
  self : TextHostQueue,
  epoch : UInt64,
  state : TextInputState,
) -> Result[UInt64, @diagnostics.FrameworkError] {
  match self.check(epoch, "update") {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  self.state = Some(state)
  Ok(self.epoch)
}

///|
/// Cancel the current epoch and return the replacement. Text observations that
/// were not taken are dropped; parked platform events are retained.
pub fn TextHostQueue::cancel(
  self : TextHostQueue,
  epoch : UInt64,
) -> Result[UInt64, @diagnostics.FrameworkError] {
  match self.check(epoch, "cancel") {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  if self.epoch == 18446744073709551615UL {
    return Err(text_host_queue_error(@diagnostics.ResourceExhausted, "cancel"))
  }
  self.epoch += 1UL
  self.text = []
  self.state = None
  self.failure = None
  Ok(self.epoch)
}

///|
/// Revoke the session. Repeated or stale epochs are `StaleHandle`.
pub fn TextHostQueue::end(
  self : TextHostQueue,
  epoch : UInt64,
) -> Result[Unit, @diagnostics.FrameworkError] {
  match self.check(epoch, "end") {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  self.clear()
  Ok(())
}

///|
/// Drop all state without an epoch check. Hosts call this on window destruction
/// or host stop, where no further observation can be delivered.
pub fn TextHostQueue::reset(self : TextHostQueue) -> Unit {
  self.clear()
}

///|
pub fn TextHostQueue::is_active(self : TextHostQueue) -> Bool {
  self.active
}

///|
pub fn TextHostQueue::epoch(self : TextHostQueue) -> UInt64 {
  self.epoch
}

///|
pub fn TextHostQueue::state(self : TextHostQueue) -> TextInputState? {
  self.state
}

///|
pub fn TextHostQueue::failure(self : TextHostQueue) -> @diagnostics.ErrorCode? {
  self.failure
}

///|
/// Record a host observation that the portable vocabulary cannot express. The
/// failure stays readable until the queue is cancelled or ended; callers must
/// not substitute a successful insertion.
pub fn TextHostQueue::fail(
  self : TextHostQueue,
  code : @diagnostics.ErrorCode,
) -> Unit {
  self.failure = Some(code)
}

///|
/// Queue one ordered observation for the current session.
pub fn TextHostQueue::emit(
  self : TextHostQueue,
  kind : TextInputEventKind,
) -> Result[Unit, @diagnostics.FrameworkError] {
  if !self.active {
    return Err(text_host_queue_error(@diagnostics.StaleHandle, "emit"))
  }
  let window = match self.window {
    Some(value) => value
    None => return Err(text_host_queue_error(@diagnostics.StaleHandle, "emit"))
  }
  if self.sequence == 9223372036854775807L {
    return Err(text_host_queue_error(@diagnostics.ResourceExhausted, "emit"))
  }
  self.sequence += 1L
  self.text.push(TextInputEvent::new(window, self.sequence, self.epoch, kind))
  Ok(())
}

///|
/// Park one ordinary platform event. Returns false when the bounded queue is
/// full; the caller must not drop the event silently.
pub fn TextHostQueue::park(
  self : TextHostQueue,
  event : @platform.Event,
) -> Bool {
  if self.parked.length() >= TEXT_HOST_PARK_CAPACITY {
    return false
  }
  self.parked.push(event)
  true
}

///|
pub fn TextHostQueue::take_parked(self : TextHostQueue) -> @platform.Event? {
  if self.parked.length() == 0 {
    return None
  }
  Some(self.parked.remove(0))
}

///|
pub fn TextHostQueue::take_text(self : TextHostQueue) -> TextInputEvent? {
  if self.text.length() == 0 {
    return None
  }
  Some(self.text.remove(0))
}

///|
pub fn TextHostQueue::has_parked(self : TextHostQueue) -> Bool {
  self.parked.length() > 0
}

///|
/// Drop queued text observations without changing the epoch or parked platform
/// events. Hosts call this when the native route replaced its epoch, because
/// records copied under the previous native epoch can no longer be applied.
pub fn TextHostQueue::discard_text(self : TextHostQueue) -> Unit {
  self.text = []
}

///|
pub fn TextHostQueue::has_text(self : TextHostQueue) -> Bool {
  self.text.length() > 0
}

///|
fn TextHostQueue::check(
  self : TextHostQueue,
  epoch : UInt64,
  operation : String,
) -> Result[Unit, @diagnostics.FrameworkError] {
  if !self.active || epoch == 0UL || epoch != self.epoch {
    return Err(text_host_queue_error(@diagnostics.StaleHandle, operation))
  }
  Ok(())
}

///|
fn TextHostQueue::clear(self : TextHostQueue) -> Unit {
  self.active = false
  self.window = None
  self.sequence = 0L
  self.text = []
  self.parked = []
  self.failure = None
  self.state = None
}
