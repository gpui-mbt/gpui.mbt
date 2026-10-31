///|
extern "C" fn native_retained_terminal_seal(
  host : Int32,
  window : Int32,
  sequence : Int32,
) -> Int32 = "gpui_retained_terminal_seal"

///|
/// Native terminal evidence for one destroyed window and its acknowledged
/// final FIFO record. The host cannot create another window or dispatch
/// callbacks after this seal. Consumer actions, model and scene work must
/// already be resolved separately; this value does not certify those stages.
pub struct RetainedTerminalReceipt {
  priv window : @platform.WindowId
  priv sequence : Int32
}

///|
pub fn RetainedTerminalReceipt::window(
  self : RetainedTerminalReceipt,
) -> @platform.WindowId {
  self.window
}

///|
pub fn RetainedTerminalReceipt::native_sequence(
  self : RetainedTerminalReceipt,
) -> Int32 {
  self.sequence
}

///|
/// Seal only an unbound route after the actual destroyed record was ACKed.
/// Native checks the original window creation generation, final sequence,
/// empty FIFO and unresolved input state before atomically preventing future
/// window creation and callback dispatch. Failure preserves ownership.
pub fn RetainedOrderedRoute::seal_destroyed(
  self : RetainedOrderedRoute,
  window : @platform.WindowId,
  destroyed_native_sequence : Int32,
) -> Result[RetainedTerminalReceipt, @diagnostics.FrameworkError] {
  self.seal_destroyed_from(window, destroyed_native_sequence, fn(
    token,
    sequence,
  ) {
    outcome(
      native_retained_terminal_seal(self.host.token, token, sequence),
      "retained_terminal_seal",
    )
  })
}

///|
fn RetainedOrderedRoute::seal_destroyed_from(
  self : RetainedOrderedRoute,
  window : @platform.WindowId,
  sequence : Int32,
  native_seal : (Int32, Int32) -> Result[Unit, @diagnostics.FrameworkError],
) -> Result[RetainedTerminalReceipt, @diagnostics.FrameworkError] {
  let operation = "retained_terminal_seal"
  if self.window is Some(_) ||
    self.root != 0UL ||
    self.native_epoch != 0 ||
    self.closed ||
    self.direct_binding ||
    self.direct_cutoff_complete {
    return Err(ubuntu_text_host_error(@diagnostics.Busy, operation))
  }
  if sequence <= 0 {
    return Err(ubuntu_text_host_error(@diagnostics.InvalidInput, operation))
  }
  let token = match direct_window_token(window, operation) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  match native_seal(token, sequence) {
    Err(error) => Err(error)
    Ok(_) => Ok({ window, sequence, })
  }
}
