///|
extern "C" fn native_retained_direct_rebegin(
  host : Int32,
  window : Int32,
  released_epoch : Int32,
  acknowledged_sequence : Int32,
) -> Int32 = "gpui_retained_direct_rebegin"

///|
/// Begin a new direct owner after the consumer resolved its released direct
/// predecessor and all later ACKed platform records through the named native
/// sequence. Native retains physical-key history and requires the same
/// window/focus/keymap generation, empty FIFO and no unresolved input. This
/// does not certify consumer model/actions/scene completion. Unlike a general
/// begin, native refusal is side-effect free; Busy can be retried explicitly.
pub fn RetainedOrderedRoute::begin_after_resolved_cutoff(
  self : RetainedOrderedRoute,
  window : @platform.WindowId,
  root : UInt64,
  released_portable_epoch : UInt64,
  retired_native_sequence : Int32,
) -> Result[UInt64, @diagnostics.FrameworkError] {
  self.begin_after_resolved_cutoff_from(
    window,
    root,
    released_portable_epoch,
    retired_native_sequence,
    fn(token, native_epoch, sequence) {
      text_session_epoch_outcome(
        native_retained_direct_rebegin(
          self.host.token,
          token,
          native_epoch,
          sequence,
        ),
        "retained_direct_rebegin",
      )
    },
  )
}

///|
fn RetainedOrderedRoute::begin_after_resolved_cutoff_from(
  self : RetainedOrderedRoute,
  window : @platform.WindowId,
  root : UInt64,
  released_portable_epoch : UInt64,
  retired_native_sequence : Int32,
  native_begin : (Int32, Int32, Int32) -> Result[
    Int32,
    @diagnostics.FrameworkError,
  ],
) -> Result[UInt64, @diagnostics.FrameworkError] {
  let operation = "retained_direct_rebegin"
  if self.window is Some(_) ||
    self.root != 0UL ||
    self.native_epoch != 0 ||
    self.closed ||
    self.direct_binding ||
    self.direct_cutoff_complete {
    return Err(ubuntu_text_host_error(@diagnostics.Busy, operation))
  }
  if root == 0UL ||
    retired_native_sequence <= 0 ||
    released_portable_epoch == 0UL {
    return Err(ubuntu_text_host_error(@diagnostics.InvalidInput, operation))
  }
  let prior_native = match self.released_direct {
    Some((prior_window, portable, native)) if prior_window == window &&
      portable == released_portable_epoch &&
      self.portable_epoch == portable &&
      native > 0 => native
    _ => return Err(ubuntu_text_host_error(@diagnostics.StaleHandle, operation))
  }
  if self.portable_epoch == 18446744073709551615UL {
    return Err(
      ubuntu_text_host_error(@diagnostics.ResourceExhausted, operation),
    )
  }
  let token = match direct_window_token(window, operation) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let native = match
    native_begin(token, prior_native, retired_native_sequence) {
    Err(error) => return Err(error)
    Ok(value) if value > prior_native => value
    _ =>
      return Err(ubuntu_text_host_error(@diagnostics.InvalidInput, operation))
  }
  // Native prevalidates the whole rearm before mutation; reserving a portable
  // epoch earlier would turn a refused Busy retry into an owner change.
  self.portable_epoch += 1UL
  self.window = Some(window)
  self.root = root
  self.native_epoch = native
  self.direct_binding = true
  self.direct_cutoff_complete = false
  self.released_direct = None
  self.native_seat = 0L
  self.native_proxy = 0
  self.ordinal = 0L
  self.closed = false
  self.shortcuts.held = 0
  Ok(self.portable_epoch)
}
