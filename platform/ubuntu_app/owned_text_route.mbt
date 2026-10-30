///|
/// Owns one retained Linux text route and the exact portable editing owner.
/// The caller processes every retained receipt in order, applies generated
/// actions to the original shared model, and only then acknowledges it.
pub struct OwnedTextRoute {
  priv route : @ubuntu.RetainedOrderedRoute
  priv mut owner : @text_session.TextSession?
  priv mut binding : @text_session.SessionTarget?
}

///|
pub fn OwnedTextRoute::new(
  host : @ubuntu.Host,
) -> Result[OwnedTextRoute, @diagnostics.FrameworkError] {
  match @ubuntu.RetainedOrderedRoute::new(host) {
    Err(error) => Err(error)
    Ok(route) => Ok({ route, owner: None, binding: None, })
  }
}

///|
/// A failed native begin can retain ownership. If `binding_epoch()` remains
/// present after an error, the captured owner also remains attached here.
pub fn OwnedTextRoute::begin(
  self : OwnedTextRoute,
  owner : @text_session.TextSession,
  state : @text_host.TextInputState,
) -> Result[UInt64, @diagnostics.FrameworkError] {
  if self.route.binding_epoch() is Some(_) {
    return Err(
      @diagnostics.FrameworkError::new(@diagnostics.Busy, "owned_begin"),
    )
  }
  let target = match owner.target() {
    Ok(value) => value
    Err(_) =>
      return Err(
        @diagnostics.FrameworkError::new(
          @diagnostics.InvalidInput,
          "owned_begin",
        ),
      )
  }
  let result = self.route.begin(target.window(), target.root_id(), state)
  if self.route.binding_epoch() is Some(_) {
    self.owner = Some(owner)
    self.binding = Some(target)
  }
  result
}

///|
pub fn OwnedTextRoute::binding_epoch(self : OwnedTextRoute) -> UInt64? {
  self.route.binding_epoch()
}

///|
pub fn OwnedTextRoute::native_epoch(self : OwnedTextRoute) -> Int32? {
  self.route.native_epoch()
}

///|
pub fn OwnedTextRoute::peek(
  self : OwnedTextRoute,
) -> Result[@ubuntu.RetainedOrderedReceipt?, @diagnostics.FrameworkError] {
  self.route.peek()
}

///|
pub fn OwnedTextRoute::update(
  self : OwnedTextRoute,
  epoch : UInt64,
  state : @text_host.TextInputState,
) -> Result[Unit, @diagnostics.FrameworkError] {
  self.route.update(epoch, state)
}

///|
/// Cut off native ingress only; this does not settle an active composition or
/// acknowledge records already delivered into caller-owned storage.
pub fn OwnedTextRoute::try_end_when_drained(
  self : OwnedTextRoute,
  epoch : UInt64,
) -> Result[Unit, @diagnostics.FrameworkError] {
  self.route.try_end_when_drained(epoch)
}

///|
fn valid_resolution(
  owner : @text_session.TextSession,
  binding : @text_session.SessionTarget,
  resolution : @text_session.BatchReceipt,
) -> Bool {
  let mut blurred = false
  for item in resolution.outcomes() {
    if item is Blurred(_) {
      blurred = true
    }
  }
  let resolved = resolution.snapshot()
  let current = owner.snapshot()
  binding.same_binding(resolution.accepted_target()) &&
  blurred &&
  !resolved.has_pending_end() &&
  !resolved.is_closed() &&
  !resolved.field().is_composing() &&
  !resolved.field().is_focused() &&
  !current.has_pending_end() &&
  !current.is_closed() &&
  !current.field().is_composing() &&
  !current.field().is_focused() &&
  current.window() == resolved.window() &&
  current.root_id() == resolved.root_id() &&
  current.session_id() == resolved.session_id() &&
  current.published_revision() == resolved.published_revision() &&
  current.committed_document_revision() ==
  resolved.committed_document_revision() &&
  current.delivery_watermark() == resolved.delivery_watermark()
}

///|
fn OwnedTextRoute::check_resolution(
  self : OwnedTextRoute,
  receipt : @text_session.BatchReceipt,
  operation : String,
) -> Result[Unit, @diagnostics.FrameworkError] {
  match (self.owner, self.binding) {
    (Some(owner), Some(binding)) if valid_resolution(owner, binding, receipt) =>
      Ok(())
    _ =>
      Err(
        @diagnostics.FrameworkError::new(@diagnostics.InvalidInput, operation),
      )
  }
}

///|
/// After natural focus loss and matching Left ACK, complete native cutoff only
/// if the captured original owner has resolved blur. Before calling, apply all
/// generated actions to the original shared model. Left is not an OS cancel;
/// explicit owner discard is distinct from an observed cancel.
pub fn OwnedTextRoute::end_after_left(
  self : OwnedTextRoute,
  epoch : UInt64,
  resolution : @text_session.BatchReceipt,
) -> Result[Unit, @diagnostics.FrameworkError] {
  match self.check_resolution(resolution, "owned_end_after_left") {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  self.route.end_after_left(epoch)
}

///|
/// Release only the original resolved owner after its actions have reached the
/// shared model and the retained FIFO and native lifecycle are clear.
pub fn OwnedTextRoute::release(
  self : OwnedTextRoute,
  epoch : UInt64,
  resolution : @text_session.BatchReceipt,
) -> Result[Unit, @diagnostics.FrameworkError] {
  match self.check_resolution(resolution, "owned_release") {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  match self.route.release(epoch) {
    Err(error) => Err(error)
    Ok(_) => {
      self.owner = None
      self.binding = None
      Ok(())
    }
  }
}
