///|
extern "C" fn native_claim_retained_route(host : Int32) -> Int32 = "gpui_claim_retained_route"

///|
extern "C" fn native_retained_route_hold(
  host : Int32,
  enabled : Int32,
) -> Int32 = "gpui_retained_route_hold"

///|
extern "C" fn native_retained_route_native_epoch(
  host : Int32,
  window : Int32,
) -> Int32 = "gpui_retained_route_native_epoch"

///|
extern "C" fn native_retained_direct_begin(
  host : Int32,
  window : Int32,
) -> Int32 = "gpui_retained_direct_begin"

///|
extern "C" fn native_retained_direct_end(
  host : Int32,
  window : Int32,
  epoch : Int32,
) -> Int32 = "gpui_retained_direct_end_when_drained"

///|
#borrow(fields)
extern "C" fn native_peek_retained_key_proof(
  host : Int32,
  window : Int32,
  sequence : Int32,
  fields : FixedArray[Int32],
  capacity : Int32,
) -> Int32 = "gpui_peek_retained_key_proof"

///|
#borrow(text)
extern "C" fn native_retained_route_begin(
  host : Int32,
  window : Int32,
  text : Bytes,
  length : Int32,
  cursor : Int32,
  anchor : Int32,
  x : Int32,
  y : Int32,
  width : Int32,
  height : Int32,
) -> Int32 = "gpui_retained_route_begin"

///|
#borrow(text)
extern "C" fn native_retained_route_update(
  host : Int32,
  window : Int32,
  epoch : Int32,
  text : Bytes,
  length : Int32,
  cursor : Int32,
  anchor : Int32,
  x : Int32,
  y : Int32,
  width : Int32,
  height : Int32,
) -> Int32 = "gpui_retained_route_update"

///|
extern "C" fn native_retained_route_end(
  host : Int32,
  window : Int32,
  epoch : Int32,
) -> Int32 = "gpui_retained_route_end_when_drained"

///|
fn Host::retained_begin(
  self : Host,
  window : @platform.WindowId,
  state : @text_host.TextInputState,
) -> Result[Int32, @diagnostics.FrameworkError] {
  let operation = "retained_begin"
  let token = match direct_window_token(window, operation) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let (bytes, cursor, anchor) = match
    text_session_surrounding(state.document(), operation) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let (x, y, width, height) = match
    text_session_rect(state.caret(), operation) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  text_session_epoch_outcome(
    native_retained_route_begin(
      self.token,
      token,
      bytes,
      bytes.length(),
      cursor,
      anchor,
      x,
      y,
      width,
      height,
    ),
    operation,
  )
}

///|
fn Host::retained_update(
  self : Host,
  window : @platform.WindowId,
  epoch : Int32,
  state : @text_host.TextInputState,
) -> Result[Int32, @diagnostics.FrameworkError] {
  let operation = "retained_update"
  if epoch <= 0 {
    return Err(backend_error(3, operation))
  }
  let token = match direct_window_token(window, operation) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let (bytes, cursor, anchor) = match
    text_session_surrounding(state.document(), operation) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let (x, y, width, height) = match
    text_session_rect(state.caret(), operation) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  text_session_epoch_outcome(
    native_retained_route_update(
      self.token,
      token,
      epoch,
      bytes,
      bytes.length(),
      cursor,
      anchor,
      x,
      y,
      width,
      height,
    ),
    operation,
  )
}

///|
/// Validate caller data before creating an uncertain native obligation.
fn validate_retained_update_input(
  window : @platform.WindowId,
  epoch : Int32,
  state : @text_host.TextInputState,
  operation : String,
) -> Result[Unit, @diagnostics.FrameworkError] {
  if epoch <= 0 {
    return Err(backend_error(3, operation))
  }
  match direct_window_token(window, operation) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  match text_session_surrounding(state.document(), operation) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  match text_session_rect(state.caret(), operation) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  Ok(())
}

///|
fn Host::retained_end(
  self : Host,
  window : @platform.WindowId,
  epoch : Int32,
) -> Result[Unit, @diagnostics.FrameworkError] {
  let operation = "retained_end"
  if epoch <= 0 {
    return Err(backend_error(3, operation))
  }
  let token = match direct_window_token(window, operation) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  outcome(native_retained_route_end(self.token, token, epoch), operation)
}

///|
/// A host update whose failure may have changed native state. This immutable
/// value keeps the exact attempted input; it is not a scene or compositor ACK.
pub struct RetainedGeometryPending {
  priv window : @platform.WindowId
  priv root : UInt64
  priv epoch : UInt64
  priv native_epoch : Int32
  priv state : @text_host.TextInputState
  priv generation : UInt64
}

///|
pub fn RetainedGeometryPending::window(
  self : RetainedGeometryPending,
) -> @platform.WindowId {
  self.window
}

///|
pub fn RetainedGeometryPending::root(self : RetainedGeometryPending) -> UInt64 {
  self.root
}

///|
pub fn RetainedGeometryPending::epoch(self : RetainedGeometryPending) -> UInt64 {
  self.epoch
}

///|
pub fn RetainedGeometryPending::native_epoch(
  self : RetainedGeometryPending,
) -> Int32 {
  self.native_epoch
}

///|
pub fn RetainedGeometryPending::state(
  self : RetainedGeometryPending,
) -> @text_host.TextInputState {
  self.state
}

///|
pub fn RetainedGeometryPending::generation(
  self : RetainedGeometryPending,
) -> UInt64 {
  self.generation
}

///|
/// Native host accepted this exact update. This does not imply presentation or
/// compositor acknowledgement. Consumers must validate their owner separately.
pub struct RetainedGeometryReceipt {
  priv host_token : Int32
  priv pending : RetainedGeometryPending
}

///|
/// An opaque proof that this exact candidate was rejected before native
/// update. It permits only a same-route, same-owner retry while current.
pub struct RetainedGeometryPreflight {
  priv identity : GeometryRouteIdentity
  priv window : @platform.WindowId
  priv root : UInt64
  priv epoch : UInt64
  priv native_epoch : Int32
  priv geometry_generation : UInt64
  priv attempt_serial : UInt64
  priv state : @text_host.TextInputState
}

///|
pub fn RetainedGeometryPreflight::identity(
  self : RetainedGeometryPreflight,
) -> (@platform.WindowId, UInt64, UInt64, Int32) {
  (self.window, self.root, self.epoch, self.native_epoch)
}

///|
pub fn RetainedGeometryPreflight::state(
  self : RetainedGeometryPreflight,
) -> @text_host.TextInputState {
  self.state
}

///|
pub enum RetainedGeometryAttempt {
  GeometryAccepted(RetainedGeometryReceipt)
  GeometryPreflightRejected(
    @diagnostics.FrameworkError,
    RetainedGeometryPreflight
  )
  GeometryOutcomeUncertain(@diagnostics.FrameworkError)
}

///|
priv struct GeometryRouteIdentity {
  mut marker : Bool
}

///|
/// Owner-thread only; no callbacks may run while the marker is changed.
fn same_geometry_route(
  a : GeometryRouteIdentity,
  b : GeometryRouteIdentity,
) -> Bool {
  let old_a = a.marker
  let old_b = b.marker
  a.marker = !old_b
  let same = b.marker != old_b
  a.marker = old_a
  b.marker = old_b
  same
}

///|
pub fn RetainedGeometryReceipt::pending(
  self : RetainedGeometryReceipt,
) -> RetainedGeometryPending {
  self.pending
}

///|
/// A single session binding over retained Ubuntu native ingress. Native event
/// identities stay on the retained record; text observations receive a separate
/// per-binding ordinal only when this route prepares a candidate.
pub struct RetainedOrderedRoute {
  priv host : Host
  priv mut window : @platform.WindowId?
  priv mut root : UInt64
  priv mut portable_epoch : UInt64
  priv mut native_epoch : Int32
  priv mut direct_binding : Bool
  priv mut direct_cutoff_complete : Bool
  priv mut native_seat : Int64
  priv mut native_proxy : Int32
  priv mut ordinal : Int64
  priv mut closed : Bool
  priv mut pending_geometry : RetainedGeometryPending?
  priv mut geometry_generation : UInt64
  priv geometry_identity : GeometryRouteIdentity
  priv mut geometry_attempt_serial : UInt64
  priv mut geometry_handoff : GeometryHandoff?
  priv mut geometry_handoff_call : Bool
  priv shortcuts : ShortcutKeyTracker
}

///|
/// Claim this host's only retained route. Its claim lasts for the host lifetime;
/// legacy readers are unavailable in retained mode.
pub fn RetainedOrderedRoute::new(
  host : Host,
) -> Result[RetainedOrderedRoute, @diagnostics.FrameworkError] {
  match host.enable_terminal_retention() {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  match
    outcome(native_claim_retained_route(host.token), "claim_retained_route") {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  Ok({
    host,
    window: None,
    root: 0UL,
    portable_epoch: 0UL,
    native_epoch: 0,
    direct_binding: false,
    direct_cutoff_complete: false,
    native_seat: 0L,
    native_proxy: 0,
    ordinal: 0L,
    closed: false,
    pending_geometry: None,
    geometry_generation: 0UL,
    geometry_identity: { marker: false, },
    geometry_attempt_serial: 0UL,
    geometry_handoff: None,
    geometry_handoff_call: false,
    shortcuts: ShortcutKeyTracker::new(),
  })
}

///|
fn RetainedOrderedRoute::require_empty(
  self : RetainedOrderedRoute,
  operation : String,
) -> Result[Unit, @diagnostics.FrameworkError] {
  match self.host.peek_retained_editor() {
    Err(error) => Err(error)
    Ok(Some(_)) => Err(ubuntu_text_host_error(@diagnostics.Busy, operation))
    Ok(None) => Ok(())
  }
}

///|
/// Capture a fresh window/root and native session epoch. A previous binding
/// must be ended and released before another can begin.
pub fn RetainedOrderedRoute::begin(
  self : RetainedOrderedRoute,
  window : @platform.WindowId,
  root : UInt64,
  state : @text_host.TextInputState,
) -> Result[UInt64, @diagnostics.FrameworkError] {
  let operation = "retained_begin"
  if root == 0UL {
    return Err(ubuntu_text_host_error(@diagnostics.InvalidInput, operation))
  }
  if self.window is Some(_) {
    return Err(ubuntu_text_host_error(@diagnostics.Busy, operation))
  }
  if self.portable_epoch == 18446744073709551615UL {
    return Err(
      ubuntu_text_host_error(@diagnostics.ResourceExhausted, operation),
    )
  }
  match self.require_empty(operation) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  match outcome(native_retained_route_hold(self.host.token, 1), operation) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  // Reserve the original owner before the potentially side-effecting native
  // begin. A failed begin may still leave the native session requested.
  self.portable_epoch += 1UL
  self.native_epoch = 0
  self.native_seat = 0L
  self.native_proxy = 0
  self.window = Some(window)
  self.root = root
  self.ordinal = 0L
  self.closed = false
  self.direct_cutoff_complete = false
  self.shortcuts.held = 0
  match self.host.retained_begin(window, state) {
    Ok(native) => self.native_epoch = native
    Err(error) => {
      let observed = native_retained_route_native_epoch(
        self.host.token,
        window.value().to_int(),
      )
      if observed > 0 {
        self.native_epoch = observed
      } else {
        // Release only if native confirms that no input or active target exists.
        match
          outcome(native_retained_route_hold(self.host.token, 0), operation) {
          Ok(_) => {
            self.window = None
            self.root = 0UL
          }
          Err(_) => self.closed = true
        }
      }
      return Err(error)
    }
  }
  Ok(self.portable_epoch)
}

///|
/// Bind the retained FIFO to direct keyboard text when the native text-input
/// manager is unavailable. This preserves a window/root/epoch on every
/// retained candidate; it does not emulate IME composition or acknowledge
/// actions returned to the consumer.
pub fn RetainedOrderedRoute::begin_direct(
  self : RetainedOrderedRoute,
  window : @platform.WindowId,
  root : UInt64,
) -> Result[UInt64, @diagnostics.FrameworkError] {
  let operation = "retained_direct_begin"
  if root == 0UL {
    return Err(ubuntu_text_host_error(@diagnostics.InvalidInput, operation))
  }
  if self.window is Some(_) {
    return Err(ubuntu_text_host_error(@diagnostics.Busy, operation))
  }
  if self.portable_epoch == 18446744073709551615UL {
    return Err(
      ubuntu_text_host_error(@diagnostics.ResourceExhausted, operation),
    )
  }
  let token = match direct_window_token(window, operation) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  match self.require_empty(operation) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  match outcome(native_retained_route_hold(self.host.token, 1), operation) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  self.portable_epoch += 1UL
  self.window = Some(window)
  self.root = root
  self.native_epoch = 0
  self.direct_binding = true
  self.direct_cutoff_complete = false
  self.native_seat = 0L
  self.native_proxy = 0
  self.ordinal = 0L
  self.closed = false
  self.shortcuts.held = 0
  match
    text_session_epoch_outcome(
      native_retained_direct_begin(self.host.token, token),
      operation,
    ) {
    Ok(value) => self.native_epoch = value
    Err(error) => {
      // Native begin can fail before installing an active direct owner; still
      // retain the binding if native cannot release its hold.
      match outcome(native_retained_route_hold(self.host.token, 0), operation) {
        Ok(_) => {
          self.window = None
          self.root = 0UL
          self.direct_binding = false
        }
        Err(_) => self.closed = true
      }
      return Err(error)
    }
  }
  Ok(self.portable_epoch)
}

///|
/// The binding remains inspectable after a partially side-effecting begin
/// failure. None means the failed attempt was safely released.
pub fn RetainedOrderedRoute::binding_epoch(
  self : RetainedOrderedRoute,
) -> UInt64? {
  match self.window {
    Some(_) => Some(self.portable_epoch)
    None => None
  }
}

///|
/// The captured native text or direct-keyboard epoch, or None while native
/// ownership is uncertain.
pub fn RetainedOrderedRoute::native_epoch(
  self : RetainedOrderedRoute,
) -> Int32? {
  if self.native_epoch > 0 {
    Some(self.native_epoch)
  } else {
    None
  }
}

///|
/// The exact host update whose result is uncertain, if any. The caller must
/// separately retain its editing owner, pending actions and scene state.
pub fn RetainedOrderedRoute::pending_geometry(
  self : RetainedOrderedRoute,
) -> RetainedGeometryPending? {
  self.pending_geometry
}

///|
/// Update the same native IME session while the FIFO is empty. An error after
/// native entry retains the attempted state; it does not prove scene or
/// compositor publication. The native path sends document and caret, not the
/// optional portable preedit stored in the captured state.
pub fn RetainedOrderedRoute::update(
  self : RetainedOrderedRoute,
  epoch : UInt64,
  state : @text_host.TextInputState,
) -> Result[Unit, @diagnostics.FrameworkError] {
  match self.update_with_receipt(epoch, state) {
    Err(error) => Err(error)
    Ok(_) => Ok(())
  }
}

///|
/// Submit an update and capture the exact locally accepted native state.
pub fn RetainedOrderedRoute::update_with_receipt(
  self : RetainedOrderedRoute,
  epoch : UInt64,
  state : @text_host.TextInputState,
) -> Result[RetainedGeometryReceipt, @diagnostics.FrameworkError] {
  self.update_from(
    epoch,
    state,
    fn() { self.require_empty("retained_update") },
    fn(window, native_epoch, candidate) {
      self.host.retained_update(window, native_epoch, candidate)
    },
  )
}

///|
/// Attempt one exact geometry update. A preflight receipt is issued only when
/// the route proves the native update was never entered. All other errors are
/// uncertain and retain whatever pending candidate the route owns.
pub fn RetainedOrderedRoute::attempt_geometry(
  self : RetainedOrderedRoute,
  epoch : UInt64,
  state : @text_host.TextInputState,
) -> RetainedGeometryAttempt {
  self.attempt_geometry_from(
    epoch,
    state,
    fn() { self.require_empty("retained_update") },
    fn(window, native_epoch, candidate) {
      self.host.retained_update(window, native_epoch, candidate)
    },
  )
}

///|
fn RetainedOrderedRoute::attempt_geometry_from(
  self : RetainedOrderedRoute,
  epoch : UInt64,
  state : @text_host.TextInputState,
  empty : () -> Result[Unit, @diagnostics.FrameworkError],
  native_update : (@platform.WindowId, Int32, @text_host.TextInputState) -> Result[
    Int32,
    @diagnostics.FrameworkError,
  ],
) -> RetainedGeometryAttempt {
  let operation = "retained_update"
  if self.geometry_attempt_serial == 18446744073709551615UL {
    return GeometryOutcomeUncertain(
      ubuntu_text_host_error(@diagnostics.ResourceExhausted, operation),
    )
  }
  let window = match self.window {
    Some(value) => value
    None => {
      // Even a rejected new attempt revokes an earlier proof.
      self.geometry_attempt_serial += 1UL
      return GeometryOutcomeUncertain(
        ubuntu_text_host_error(@diagnostics.StaleHandle, operation),
      )
    }
  }
  if self.host.stopped ||
    self.closed ||
    self.direct_binding ||
    self.root == 0UL ||
    epoch != self.portable_epoch ||
    self.native_epoch <= 0 ||
    self.pending_geometry is Some(_) ||
    self.geometry_handoff is Some(_) {
    self.geometry_attempt_serial += 1UL
    return GeometryOutcomeUncertain(
      ubuntu_text_host_error(@diagnostics.StaleHandle, operation),
    )
  }
  let serial = self.geometry_attempt_serial
  let generation = self.geometry_generation
  let root = self.root
  let native_epoch = self.native_epoch
  match self.update_from(epoch, state, empty, native_update) {
    Ok(receipt) => GeometryAccepted(receipt)
    Err(error) =>
      // update_from increments geometry_generation and installs its pending
      // candidate before every native call. A reentrant or later operation
      // changes the attempt serial and prevents issuing a rejection proof.
      if self.geometry_attempt_serial == serial + 1UL &&
        self.geometry_generation == generation &&
        self.window == Some(window) &&
        self.root == root &&
        self.portable_epoch == epoch &&
        self.native_epoch == native_epoch &&
        !self.host.stopped &&
        !self.closed &&
        !self.direct_binding &&
        self.pending_geometry is None &&
        self.geometry_handoff is None {
        GeometryPreflightRejected(error, {
          identity: self.geometry_identity,
          window,
          root,
          epoch,
          native_epoch,
          geometry_generation: generation,
          attempt_serial: self.geometry_attempt_serial,
          state,
        })
      } else {
        GeometryOutcomeUncertain(error)
      }
  }
}

///|
/// Retry only the immutable candidate from this current route-bound proof.
/// A later attempted update, owner change, host failure or route replacement
/// makes the old proof unusable; no native action follows a failed recheck.
pub fn RetainedOrderedRoute::retry_preflight_geometry(
  self : RetainedOrderedRoute,
  proof : RetainedGeometryPreflight,
) -> RetainedGeometryAttempt {
  self.retry_preflight_geometry_from(
    proof,
    fn() {
      native_retained_route_native_epoch(
        self.host.token,
        proof.window.value().to_int(),
      ) ==
      proof.native_epoch
    },
    fn() { self.require_empty("retained_update") },
    fn(window, native_epoch, candidate) {
      self.host.retained_update(window, native_epoch, candidate)
    },
  )
}

///|
/// Synchronous local inspection only; this does not acknowledge any input or
/// publish a scene. A subsequent operation can revoke the proof immediately.
pub fn RetainedOrderedRoute::preflight_geometry_is_current(
  self : RetainedOrderedRoute,
  proof : RetainedGeometryPreflight,
) -> Bool {
  self.preflight_fields_current(proof) &&
  native_retained_route_native_epoch(
    self.host.token,
    proof.window.value().to_int(),
  ) ==
  proof.native_epoch &&
  self.preflight_fields_current(proof)
}

///|
fn RetainedOrderedRoute::retry_preflight_geometry_from(
  self : RetainedOrderedRoute,
  proof : RetainedGeometryPreflight,
  native_current : () -> Bool,
  empty : () -> Result[Unit, @diagnostics.FrameworkError],
  native_update : (@platform.WindowId, Int32, @text_host.TextInputState) -> Result[
    Int32,
    @diagnostics.FrameworkError,
  ],
) -> RetainedGeometryAttempt {
  if !self.preflight_fields_current(proof) ||
    !native_current() ||
    !self.preflight_fields_current(proof) {
    return GeometryOutcomeUncertain(
      ubuntu_text_host_error(
        @diagnostics.StaleHandle,
        "retained_preflight_retry",
      ),
    )
  }
  self.attempt_geometry_from(proof.epoch, proof.state, empty, native_update)
}

///|
fn RetainedOrderedRoute::preflight_fields_current(
  self : RetainedOrderedRoute,
  proof : RetainedGeometryPreflight,
) -> Bool {
  same_geometry_route(self.geometry_identity, proof.identity) &&
  !self.host.stopped &&
  !self.closed &&
  !self.direct_binding &&
  self.window == Some(proof.window) &&
  self.root == proof.root &&
  self.portable_epoch == proof.epoch &&
  self.native_epoch == proof.native_epoch &&
  self.geometry_generation == proof.geometry_generation &&
  self.geometry_attempt_serial == proof.attempt_serial &&
  self.pending_geometry is None &&
  self.geometry_handoff is None
}

///|
fn RetainedOrderedRoute::update_from(
  self : RetainedOrderedRoute,
  epoch : UInt64,
  state : @text_host.TextInputState,
  empty : () -> Result[Unit, @diagnostics.FrameworkError],
  native_update : (@platform.WindowId, Int32, @text_host.TextInputState) -> Result[
    Int32,
    @diagnostics.FrameworkError,
  ],
) -> Result[RetainedGeometryReceipt, @diagnostics.FrameworkError] {
  let operation = "retained_update"
  // Every update attempt revokes earlier preflight receipts, even when this
  // attempt is rejected before native entry. Never wrap and revive one.
  if self.geometry_attempt_serial == 18446744073709551615UL {
    return Err(
      ubuntu_text_host_error(@diagnostics.ResourceExhausted, operation),
    )
  }
  self.geometry_attempt_serial += 1UL
  if epoch != self.portable_epoch || self.closed {
    return Err(ubuntu_text_host_error(@diagnostics.StaleHandle, operation))
  }
  if self.direct_binding {
    return Err(
      ubuntu_text_host_error(@diagnostics.UnsupportedCapability, operation),
    )
  }
  if self.pending_geometry is Some(_) {
    return Err(ubuntu_text_host_error(@diagnostics.Busy, operation))
  }
  if self.geometry_handoff is Some(_) {
    return Err(ubuntu_text_host_error(@diagnostics.Busy, operation))
  }
  if self.geometry_generation == 18446744073709551615UL {
    return Err(
      ubuntu_text_host_error(@diagnostics.ResourceExhausted, operation),
    )
  }
  let window = match self.window {
    Some(value) => value
    None =>
      return Err(ubuntu_text_host_error(@diagnostics.StaleHandle, operation))
  }
  match
    validate_retained_update_input(window, self.native_epoch, state, operation) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  match empty() {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  self.geometry_generation += 1UL
  self.pending_geometry = Some({
    window,
    root: self.root,
    epoch,
    native_epoch: self.native_epoch,
    state,
    generation: self.geometry_generation,
  })
  self.retry_geometry_from(epoch, fn() { Ok(()) }, native_update)
}

///|
/// Retry the exact uncertain host state under its original binding. Success
/// clears only host uncertainty, not consumer or compositor obligations.
pub fn RetainedOrderedRoute::retry_geometry(
  self : RetainedOrderedRoute,
  epoch : UInt64,
) -> Result[RetainedGeometryReceipt, @diagnostics.FrameworkError] {
  self.retry_geometry_from(
    epoch,
    fn() { self.require_empty("retained_geometry_retry") },
    fn(window, native_epoch, candidate) {
      self.host.retained_update(window, native_epoch, candidate)
    },
  )
}

///|
fn RetainedOrderedRoute::retry_geometry_from(
  self : RetainedOrderedRoute,
  epoch : UInt64,
  empty : () -> Result[Unit, @diagnostics.FrameworkError],
  native_update : (@platform.WindowId, Int32, @text_host.TextInputState) -> Result[
    Int32,
    @diagnostics.FrameworkError,
  ],
) -> Result[RetainedGeometryReceipt, @diagnostics.FrameworkError] {
  let operation = "retained_geometry_retry"
  let pending = match self.pending_geometry {
    Some(value) => value
    None =>
      return Err(ubuntu_text_host_error(@diagnostics.StaleHandle, operation))
  }
  if self.geometry_handoff is Some(GeometryReserved(_)) {
    return Err(ubuntu_text_host_error(@diagnostics.Busy, operation))
  }
  if epoch != pending.epoch ||
    self.portable_epoch != pending.epoch ||
    self.root != pending.root ||
    self.window != Some(pending.window) ||
    self.native_epoch != pending.native_epoch ||
    self.closed ||
    self.direct_binding {
    return Err(ubuntu_text_host_error(@diagnostics.StaleHandle, operation))
  }
  match empty() {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let native = match
    native_update(pending.window, pending.native_epoch, pending.state) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  if native != pending.native_epoch {
    return Err(ubuntu_text_host_error(@diagnostics.StaleHandle, operation))
  }
  self.pending_geometry = None
  Ok({ host_token: self.host.token, pending, })
}

///|
/// Whether no later local geometry attempt or native binding replacement has
/// invalidated the receipt. This alone says nothing about the caller's editing
/// owner, queued observations, compositor or scene.
pub fn RetainedOrderedRoute::geometry_receipt_is_current(
  self : RetainedOrderedRoute,
  receipt : RetainedGeometryReceipt,
) -> Bool {
  let value = receipt.pending
  self.host.token == receipt.host_token &&
  self.window == Some(value.window) &&
  self.root == value.root &&
  self.portable_epoch == value.epoch &&
  self.native_epoch == value.native_epoch &&
  !self.closed &&
  !self.direct_binding &&
  self.pending_geometry is None &&
  self.geometry_generation == value.generation &&
  native_retained_route_native_epoch(
    self.host.token,
    value.window.value().to_int(),
  ) ==
  value.native_epoch
}

///|
/// Perform only the host cutoff. A direct binding also rejects cutoff while a
/// physical key or XKB composition is unresolved. Any IME Left generated by
/// cutoff remains in the FIFO; the binding stays alive until `release`.
pub fn RetainedOrderedRoute::try_end_when_drained(
  self : RetainedOrderedRoute,
  epoch : UInt64,
) -> Result[Unit, @diagnostics.FrameworkError] {
  self.end_from(epoch, fn() { self.require_empty("retained_end") }, fn(
    window,
    native_epoch,
  ) {
    if self.direct_binding {
      let token = match direct_window_token(window, "retained_direct_end") {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      outcome(
        native_retained_direct_end(self.host.token, token, native_epoch),
        "retained_direct_end",
      )
    } else {
      self.host.retained_end(window, native_epoch)
    }
  })
}

///|
fn RetainedOrderedRoute::end_from(
  self : RetainedOrderedRoute,
  epoch : UInt64,
  empty : () -> Result[Unit, @diagnostics.FrameworkError],
  cutoff : (@platform.WindowId, Int32) -> Result[
    Unit,
    @diagnostics.FrameworkError,
  ],
) -> Result[Unit, @diagnostics.FrameworkError] {
  let operation = "retained_end"
  if self.pending_geometry is Some(_) {
    return Err(ubuntu_text_host_error(@diagnostics.Busy, operation))
  }
  if self.geometry_handoff is Some(_) {
    return Err(ubuntu_text_host_error(@diagnostics.Busy, operation))
  }
  if epoch != self.portable_epoch || self.closed {
    return Err(ubuntu_text_host_error(@diagnostics.StaleHandle, operation))
  }
  let window = match self.window {
    Some(value) => value
    None =>
      return Err(ubuntu_text_host_error(@diagnostics.StaleHandle, operation))
  }
  match empty() {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  match cutoff(window, self.native_epoch) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  self.closed = true
  self.direct_cutoff_complete = self.direct_binding
  Ok(())
}

///|
/// Release an ended binding only after all terminal records have been ACKed.
pub fn RetainedOrderedRoute::release(
  self : RetainedOrderedRoute,
  epoch : UInt64,
) -> Result[Unit, @diagnostics.FrameworkError] {
  self.release_from(epoch, fn() { self.require_empty("retained_release") }, fn() {
    outcome(native_retained_route_hold(self.host.token, 0), "retained_release")
  })
}

///|
fn RetainedOrderedRoute::release_from(
  self : RetainedOrderedRoute,
  epoch : UInt64,
  empty : () -> Result[Unit, @diagnostics.FrameworkError],
  release_native : () -> Result[Unit, @diagnostics.FrameworkError],
) -> Result[Unit, @diagnostics.FrameworkError] {
  let operation = "retained_release"
  if self.pending_geometry is Some(_) {
    return Err(ubuntu_text_host_error(@diagnostics.Busy, operation))
  }
  if self.geometry_handoff is Some(_) {
    return Err(ubuntu_text_host_error(@diagnostics.Busy, operation))
  }
  if epoch != self.portable_epoch || !self.closed {
    return Err(ubuntu_text_host_error(@diagnostics.StaleHandle, operation))
  }
  match empty() {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  match release_native() {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  self.window = None
  self.root = 0UL
  self.native_epoch = 0
  self.direct_binding = false
  self.direct_cutoff_complete = false
  self.native_seat = 0L
  self.native_proxy = 0
  self.closed = false
  self.shortcuts.held = 0
  Ok(())
}

///|
/// A native record prepared for this route. Unhandled includes stale, foreign,
/// unsupported replacement/position, and unmapped native records; it remains
/// owned and requires an explicit terminal policy.
pub(all) enum RetainedOrderedEvent {
  Text(@text_host.TextInputEvent)
  Platform(@platform.Event)
  Lifecycle(TextSessionTarget, TextSessionEvent)
  Unhandled(EditorEvent?)
}

///|
/// A native printable key release which has no portable key mapping. This is
/// evidence for an explicit owner policy, not permission to discard the event:
/// the caller must first account for any matching press delivered elsewhere.
pub struct RetainedPrintableRelease {
  priv target : TextSessionTarget
  priv keysym : Int32
  priv modifiers : @primitives.Modifiers
}

///|
pub fn RetainedPrintableRelease::target(
  self : RetainedPrintableRelease,
) -> TextSessionTarget {
  self.target
}

///|
pub fn RetainedPrintableRelease::keysym(
  self : RetainedPrintableRelease,
) -> Int32 {
  self.keysym
}

///|
pub fn RetainedPrintableRelease::modifiers(
  self : RetainedPrintableRelease,
) -> @primitives.Modifiers {
  self.modifiers
}

///|
/// Native admission evidence since a single keyboard focus enter. It is not
/// evidence that the consumer dispatched or resolved a previous press.
pub(all) enum RetainedPhysicalPrior {
  Unknown
  NoPressObservedSinceFocus
  PressAdmitted(Int32, @platform.WindowId)
}

///|
pub struct RetainedPhysicalRelease {
  priv target : TextSessionTarget
  priv physical_key : Int32
  priv focus_generation : Int32
  priv prior : RetainedPhysicalPrior
  priv host_window_generation : Int32?
  priv claim_before_any_window : Bool
}

///|
pub fn RetainedPhysicalRelease::target(
  self : RetainedPhysicalRelease,
) -> TextSessionTarget {
  self.target
}

///|
pub fn RetainedPhysicalRelease::physical_key(
  self : RetainedPhysicalRelease,
) -> Int32 {
  self.physical_key
}

///|
pub fn RetainedPhysicalRelease::focus_generation(
  self : RetainedPhysicalRelease,
) -> Int32 {
  self.focus_generation
}

///|
pub fn RetainedPhysicalRelease::prior(
  self : RetainedPhysicalRelease,
) -> RetainedPhysicalPrior {
  self.prior
}

///|
/// Creation-attempt generation within this native host lifetime. None means
/// the proof counter was unavailable or exhausted. It does not identify or
/// resolve any application owner.
pub fn RetainedPhysicalRelease::host_window_generation(
  self : RetainedPhysicalRelease,
) -> Int32? {
  self.host_window_generation
}

///|
/// Whether this route claimed its host before any window creation attempt.
/// This says nothing about owners in a previous host or another input path.
pub fn RetainedPhysicalRelease::claim_before_any_window(
  self : RetainedPhysicalRelease,
) -> Bool {
  self.claim_before_any_window
}

///|
/// An explicitly typed direct-keyboard insertion at one retained FIFO head.
/// The value carries no proof of application, model, scene or ACK completion.
pub struct RetainedDirectInsert {
  priv window : @platform.WindowId
  priv root : UInt64
  priv epoch : UInt64
  priv native_epoch : Int32
  priv native_sequence : Int32
  priv ordinal : Int64
  priv text : String
}

///|
pub fn RetainedDirectInsert::window(
  self : RetainedDirectInsert,
) -> @platform.WindowId {
  self.window
}

///|
pub fn RetainedDirectInsert::root(self : RetainedDirectInsert) -> UInt64 {
  self.root
}

///|
pub fn RetainedDirectInsert::epoch(self : RetainedDirectInsert) -> UInt64 {
  self.epoch
}

///|
pub fn RetainedDirectInsert::native_epoch(self : RetainedDirectInsert) -> Int32 {
  self.native_epoch
}

///|
pub fn RetainedDirectInsert::native_sequence(
  self : RetainedDirectInsert,
) -> Int32 {
  self.native_sequence
}

///|
pub fn RetainedDirectInsert::ordinal(self : RetainedDirectInsert) -> Int64 {
  self.ordinal
}

///|
pub fn RetainedDirectInsert::text(self : RetainedDirectInsert) -> String {
  self.text
}

///|
pub struct RetainedOrderedReceipt {
  priv route : RetainedOrderedRoute
  priv record : RetainedEditorRecord
  priv event : RetainedOrderedEvent
  priv epoch : UInt64
  priv root : UInt64
  priv expected_ordinal : Int64
  priv candidate_ordinal : Int64
  priv expected_shortcuts : Int32
  priv candidate_shortcuts : Int32
  priv expected_seat : Int64
  priv expected_proxy : Int32
  priv candidate_seat : Int64
  priv candidate_proxy : Int32
  priv printable_release : RetainedPrintableRelease?
  priv direct_insert : RetainedDirectInsert?
}

///|
/// The direct insertion is not also delivered by `event()` as platform text.
/// The original owner must retain its application stage before this receipt is
/// ACKed; a typed insertion is not a composition commit or replacement edit.
pub fn RetainedOrderedReceipt::direct_insert(
  self : RetainedOrderedReceipt,
) -> RetainedDirectInsert? {
  self.direct_insert
}

///|
/// A printable key release without command modifiers and with the matching native
/// owner. It stays an Unhandled receipt until the consumer makes and records
/// an explicit policy decision and performs its normal exact-head ACK. No
/// TextSession action, model update, or prior press is implied by this value.
pub fn RetainedOrderedReceipt::printable_release_candidate(
  self : RetainedOrderedReceipt,
) -> RetainedPrintableRelease? {
  self.printable_release
}

///|
/// Copy admission-time physical evidence for this exact FIFO head, when the
/// raw Wayland keyboard path observed it. None includes forwarded keysyms and
/// unknown focus snapshots. The result is not an ACK or a proof that an older
/// focus owner has been resolved. Once ACKed this accessor returns stale.
pub fn RetainedOrderedReceipt::physical_release_evidence(
  self : RetainedOrderedReceipt,
) -> Result[RetainedPhysicalRelease?, @diagnostics.FrameworkError] {
  let candidate = match self.printable_release {
    Some(value) => value
    None => return Ok(None)
  }
  let route = self.route
  if route.closed ||
    route.window != Some(candidate.target.window) ||
    route.root != self.root ||
    route.portable_epoch != self.epoch ||
    route.native_epoch != candidate.target.epoch ||
    route.native_seat != candidate.target.seat ||
    route.native_proxy != candidate.target.proxy_generation {
    return Err(
      ubuntu_text_host_error(
        @diagnostics.StaleHandle,
        "retained_physical_release_evidence",
      ),
    )
  }
  let fields = FixedArray::make(8, 0)
  let operation = "retained_physical_release_evidence"
  let status = native_peek_retained_key_proof(
    self.record.host.token,
    self.record.window.value().to_int(),
    self.record.sequence,
    fields,
    fields.length(),
  )
  if status < 0 {
    return Err(backend_error(-status, operation))
  }
  if status == 0 {
    return Ok(None)
  }
  if status != 1 {
    return Err(ubuntu_text_host_error(@diagnostics.InvalidInput, operation))
  }
  match decode_physical_release(candidate, fields, operation) {
    Ok(value) => Ok(Some(value))
    Err(error) => Err(error)
  }
}

///|
fn decode_physical_release(
  candidate : RetainedPrintableRelease,
  fields : FixedArray[Int32],
  operation : String,
) -> Result[RetainedPhysicalRelease, @diagnostics.FrameworkError] {
  if fields.length() < 8 ||
    fields[0] != 1 ||
    fields[1] < 0 ||
    fields[2] <= 0 ||
    fields[6] < 0 ||
    (fields[7] != 0 && fields[7] != 1) {
    return Err(ubuntu_text_host_error(@diagnostics.InvalidInput, operation))
  }
  let prior = match fields[3] {
    0 if fields[4] == 0 && fields[5] == 0 => Unknown
    1 if fields[4] == 0 && fields[5] == 0 => NoPressObservedSinceFocus
    2 if fields[4] > 0 &&
      fields[4].to_int64() < candidate.target.sequence &&
      fields[5].to_int64() == candidate.target.window.value() =>
      PressAdmitted(fields[4], @platform.WindowId::new(fields[5].to_int64()))
    _ =>
      return Err(ubuntu_text_host_error(@diagnostics.InvalidInput, operation))
  }
  Ok({
    target: candidate.target,
    physical_key: fields[1],
    focus_generation: fields[2],
    prior,
    host_window_generation: if fields[6] > 0 {
      Some(fields[6])
    } else {
      None
    },
    claim_before_any_window: fields[7] == 1,
  })
}

///|
pub fn RetainedOrderedReceipt::event(
  self : RetainedOrderedReceipt,
) -> RetainedOrderedEvent {
  self.event
}

///|
/// Original native window, never the portable binding identity.
pub fn RetainedOrderedReceipt::native_window(
  self : RetainedOrderedReceipt,
) -> @platform.WindowId {
  self.record.window()
}

///|
/// Original host-wide sequence, separate from the text-only ordinal.
pub fn RetainedOrderedReceipt::native_sequence(
  self : RetainedOrderedReceipt,
) -> Int32 {
  self.record.sequence()
}

///|
pub fn RetainedOrderedReceipt::native_event(
  self : RetainedOrderedReceipt,
) -> EditorEvent? {
  self.record.event()
}

///|
pub fn RetainedOrderedReceipt::is_native_stale(
  self : RetainedOrderedReceipt,
) -> Bool {
  self.record.is_stale()
}

///|
/// Raw native field for an unmapped record; inspection does not acknowledge it.
pub fn RetainedOrderedReceipt::raw_field(
  self : RetainedOrderedReceipt,
  index : Int32,
) -> Double? {
  self.record.raw_field(index)
}

///|
pub fn RetainedOrderedReceipt::direct_epoch(
  self : RetainedOrderedReceipt,
) -> Int32 {
  self.record.direct_epoch()
}

///|
pub fn RetainedOrderedReceipt::composition_epoch(
  self : RetainedOrderedReceipt,
) -> Int32 {
  self.record.composition_epoch()
}

///|
pub fn RetainedOrderedReceipt::is_native_revoked(
  self : RetainedOrderedReceipt,
) -> Bool {
  self.record.is_revoked()
}

///|
pub fn RetainedOrderedReceipt::is_direct_origin(
  self : RetainedOrderedReceipt,
) -> Bool {
  self.record.is_direct_origin()
}

///|
pub fn RetainedOrderedReceipt::root(self : RetainedOrderedReceipt) -> UInt64 {
  self.root
}

///|
pub fn RetainedOrderedReceipt::epoch(self : RetainedOrderedReceipt) -> UInt64 {
  self.epoch
}

///|
/// Prepare the same candidate on repeated peeks without advancing either the
/// text ordinal or shortcut state. No native record is dequeued here.
pub fn RetainedOrderedRoute::peek(
  self : RetainedOrderedRoute,
) -> Result[RetainedOrderedReceipt?, @diagnostics.FrameworkError] {
  let record = match self.host.peek_retained_editor() {
    Err(error) => return Err(error)
    Ok(None) => return Ok(None)
    Ok(Some(value)) => value
  }
  match self.prepare(record) {
    Err(error) => Err(error)
    Ok(value) => Ok(Some(value))
  }
}

///|
fn RetainedOrderedRoute::prepare(
  self : RetainedOrderedRoute,
  record : RetainedEditorRecord,
) -> Result[RetainedOrderedReceipt, @diagnostics.FrameworkError] {
  let operation = "retained_peek"
  let native_event = record.event()
  let mut next_ordinal = self.ordinal
  let mut next_seat = self.native_seat
  let mut next_proxy = self.native_proxy
  let candidate = ShortcutKeyTracker::{ held: self.shortcuts.held, }
  let mut prepared : RetainedOrderedEvent = Unhandled(native_event)
  let mut printable_release : RetainedPrintableRelease? = None
  let mut direct_insert : RetainedDirectInsert? = None
  if !record.is_stale() {
    match native_event {
      Some(Platform(event)) =>
        match self.window {
          Some(window) if window != record.window() => ()
          Some(window) if self.direct_binding &&
            !self.closed &&
            self.root != 0UL &&
            self.portable_epoch != 0UL &&
            self.native_epoch > 0 &&
            record.is_direct_origin() &&
            !record.is_revoked() &&
            record.composition_epoch() == 0 &&
            record.direct_epoch() == self.native_epoch &&
            event.window() == window &&
            event.sequence() == record.sequence().to_int64() &&
            event.kind() is @platform.Input(@primitives.TextInput(text~)) => {
            if self.ordinal == 9223372036854775807L {
              return Err(
                ubuntu_text_host_error(
                  @diagnostics.ResourceExhausted,
                  operation,
                ),
              )
            }
            next_ordinal = self.ordinal + 1L
            direct_insert = Some({
              window,
              root: self.root,
              epoch: self.portable_epoch,
              native_epoch: self.native_epoch,
              native_sequence: record.sequence(),
              ordinal: next_ordinal,
              text,
            })
          }
          _ if self.direct_binding &&
            event.kind() is @platform.Input(@primitives.TextInput(..)) => ()
          Some(window) if self.direct_binding &&
            self.direct_cutoff_complete &&
            self.closed &&
            !record.is_direct_origin() &&
            !record.is_revoked() &&
            record.composition_epoch() == 0 &&
            event.window() == window &&
            event.sequence() == record.sequence().to_int64() &&
            (
              event.kind() is @platform.Input(@primitives.KeyPressed(..)) ||
              event.kind() is @platform.Input(@primitives.KeyReleased(..))
            ) => prepared = Platform(event)
          _ if self.direct_binding &&
            self.direct_cutoff_complete &&
            (
              event.kind() is @platform.Input(@primitives.KeyPressed(..)) ||
              event.kind() is @platform.Input(@primitives.KeyReleased(..))
            ) => ()
          _ if self.direct_binding &&
            (
              event.kind() is @platform.Input(@primitives.KeyPressed(..)) ||
              event.kind() is @platform.Input(@primitives.KeyReleased(..)) ||
              event.kind() is @platform.Input(@primitives.TextInput(..))
            ) &&
            (
              !record.is_direct_origin() ||
              record.direct_epoch() != self.native_epoch
            ) => ()
          _ => prepared = Platform(event)
        }
      Some(TextSession(target, event)) => {
        let matches = match self.window {
          Some(window) =>
            window == target.window && target.epoch == self.native_epoch
          None => false
        }
        let initial_enter = self.native_seat == 0L &&
          self.native_proxy == 0 &&
          event is Entered
        let same_proxy = self.native_seat == target.seat &&
          self.native_proxy == target.proxy_generation
        if matches && (initial_enter || same_proxy) {
          match event {
            Entered => {
              if initial_enter {
                next_seat = target.seat
                next_proxy = target.proxy_generation
              }
              prepared = Lifecycle(target, event)
            }
            Left => prepared = Lifecycle(target, event)
            Commit(deletion=Some(deletion), ..) if deletion.length_bytes != 0 =>
              ()
            Commit(position=Some(_), ..) => ()
            _ =>
              match candidate.translate(event) {
                Emit(kind) => {
                  if self.ordinal == 9223372036854775807L {
                    return Err(
                      ubuntu_text_host_error(
                        @diagnostics.ResourceExhausted,
                        operation,
                      ),
                    )
                  }
                  next_ordinal = self.ordinal + 1L
                  prepared = Text(
                    @text_host.TextInputEvent::new(
                      target.window,
                      next_ordinal,
                      self.portable_epoch,
                      kind,
                    ),
                  )
                }
                Forward(key, pressed, modifiers) => {
                  let kind = if pressed {
                    @platform.Input(
                      @primitives.KeyPressed(key~, repeat=false, modifiers~),
                    )
                  } else {
                    @platform.Input(@primitives.KeyReleased(key~, modifiers~))
                  }
                  prepared = Platform(
                    @platform.Event::new(
                      target.window,
                      target.sequence,
                      record.raw_field(3).unwrap_or(1.0),
                      kind,
                    ),
                  )
                }
                Skip =>
                  match event {
                    ForwardedReleased(keysym~, key=None, modifiers~) if keysym >=
                      0x21 &&
                      keysym <= 0x7e &&
                      !modifiers.control() &&
                      !modifiers.alt() &&
                      !modifiers.meta() =>
                      printable_release = Some({ target, keysym, modifiers, })
                    _ => ()
                  }
                Unsupported => ()
              }
          }
        }
      }
      None => ()
    }
  }
  Ok({
    route: self,
    record,
    event: prepared,
    epoch: self.portable_epoch,
    root: self.root,
    expected_ordinal: self.ordinal,
    candidate_ordinal: next_ordinal,
    expected_shortcuts: self.shortcuts.held,
    candidate_shortcuts: candidate.held,
    expected_seat: self.native_seat,
    expected_proxy: self.native_proxy,
    candidate_seat: next_seat,
    candidate_proxy: next_proxy,
    printable_release,
    direct_insert,
  })
}

///|
/// ACK only after the original TextSession, its actions, and shared-model stage
/// are complete, or their exact owner/stage is retained for resumption. For
/// Lifecycle/Unhandled, an explicit terminal policy is required first. A
/// failed native ACK leaves the candidate ordinal and shortcut state unchanged.
pub fn RetainedOrderedReceipt::ack(
  self : RetainedOrderedReceipt,
) -> Result[Unit, @diagnostics.FrameworkError] {
  self.ack_from(
    fn() {
      match self.physical_release_evidence() {
        Err(error) => Err(error)
        Ok(_) => Ok(())
      }
    },
    fn() { self.record.ack() },
  )
}

///|
fn RetainedOrderedReceipt::ack_from(
  self : RetainedOrderedReceipt,
  check : () -> Result[Unit, @diagnostics.FrameworkError],
  native_ack : () -> Result[Unit, @diagnostics.FrameworkError],
) -> Result[Unit, @diagnostics.FrameworkError] {
  self.finish_ack(fn() {
    // Recheck immediately before exact-head ACK. No callback dispatch occurs
    // between the two native owner-thread operations. None is not an ACK
    // policy: the consumer must resolve that separately.
    if self.printable_release is Some(_) {
      match check() {
        Err(error) => return Err(error)
        Ok(_) => ()
      }
    }
    native_ack()
  })
}

///|
fn RetainedOrderedReceipt::finish_ack(
  self : RetainedOrderedReceipt,
  native_ack : () -> Result[Unit, @diagnostics.FrameworkError],
) -> Result[Unit, @diagnostics.FrameworkError] {
  let route = self.route
  let operation = "retained_ack"
  if route.pending_geometry is Some(_) {
    return Err(ubuntu_text_host_error(@diagnostics.Busy, operation))
  }
  if route.geometry_handoff is Some(_) {
    return Err(ubuntu_text_host_error(@diagnostics.Busy, operation))
  }
  if route.portable_epoch != self.epoch ||
    route.root != self.root ||
    route.ordinal != self.expected_ordinal ||
    route.shortcuts.held != self.expected_shortcuts ||
    route.native_seat != self.expected_seat ||
    route.native_proxy != self.expected_proxy {
    return Err(ubuntu_text_host_error(@diagnostics.StaleHandle, operation))
  }
  match self.direct_insert {
    Some(insert) if route.closed ||
      !route.direct_binding ||
      route.window != Some(insert.window) ||
      route.native_epoch != insert.native_epoch ||
      route.root != insert.root ||
      route.portable_epoch != insert.epoch =>
      return Err(ubuntu_text_host_error(@diagnostics.StaleHandle, operation))
    _ => ()
  }
  match native_ack() {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  route.ordinal = self.candidate_ordinal
  route.shortcuts.held = self.candidate_shortcuts
  route.native_seat = self.candidate_seat
  route.native_proxy = self.candidate_proxy
  Ok(())
}

///|
priv enum GeometryHandoff {
  GeometryReserved(GeometryOwnedText)
  GeometryOwned(GeometryOwnedText)
}

///|
/// An original native text observation transferred into the route's one-slot
/// geometry recovery buffer. It has not been applied to a field or model.
pub struct GeometryOwnedText {
  priv receipt : RetainedOrderedReceipt
  priv target : TextSessionTarget
  priv native_text : TextSessionEvent
  priv portable_text : @text_host.TextInputEvent
  priv geometry_generation : UInt64
}

///|
pub fn GeometryOwnedText::window(
  self : GeometryOwnedText,
) -> @platform.WindowId {
  self.target.window
}

///|
pub fn GeometryOwnedText::root(self : GeometryOwnedText) -> UInt64 {
  self.receipt.root
}

///|
pub fn GeometryOwnedText::epoch(self : GeometryOwnedText) -> UInt64 {
  self.receipt.epoch
}

///|
pub fn GeometryOwnedText::native_epoch(self : GeometryOwnedText) -> Int32 {
  self.target.epoch
}

///|
pub fn GeometryOwnedText::native_sequence(self : GeometryOwnedText) -> Int32 {
  self.receipt.record.sequence
}

///|
pub fn GeometryOwnedText::geometry_generation(
  self : GeometryOwnedText,
) -> UInt64 {
  self.geometry_generation
}

///|
pub fn GeometryOwnedText::native_target(
  self : GeometryOwnedText,
) -> TextSessionTarget {
  self.target
}

///|
pub fn GeometryOwnedText::event(
  self : GeometryOwnedText,
) -> @text_host.TextInputEvent {
  self.portable_text
}

///|
/// Return an independent copy of the full source text payload, including
/// preedit fallback and styles. This value cannot mutate the retained slot.
pub fn GeometryOwnedText::native_text(
  self : GeometryOwnedText,
) -> TextSessionEvent {
  match self.native_text {
    Preedit(text~, fallback~, cursor_utf16~, styles~) =>
      Preedit(
        text~,
        fallback~,
        cursor_utf16~,
        styles=styles.map(fn(value) { value }),
      )
    other => other
  }
}

///|
/// The route-owned, ACKed observation, or None while its native ACK is
/// unresolved. This is evidence of retained ownership, not model application.
pub fn RetainedOrderedRoute::owned_geometry_text(
  self : RetainedOrderedRoute,
) -> GeometryOwnedText? {
  if self.geometry_handoff_call {
    return None
  }
  match self.geometry_handoff {
    Some(GeometryOwned(value)) => Some(value)
    _ => None
  }
}

///|
/// A slot reserved before an unsuccessful native ACK. The native head still
/// owns this observation; it must not be applied or taken as ACKed.
pub fn RetainedOrderedRoute::reserved_geometry_text(
  self : RetainedOrderedRoute,
) -> GeometryOwnedText? {
  if self.geometry_handoff_call {
    return None
  }
  match self.geometry_handoff {
    Some(GeometryReserved(value)) => Some(value)
    _ => None
  }
}

///|
/// While the native ACK call is in progress, neither reserved nor owned is a
/// settled outcome. This is not evidence of success or failure.
pub fn RetainedOrderedRoute::geometry_handoff_in_progress(
  self : RetainedOrderedRoute,
) -> Bool {
  self.geometry_handoff_call
}

///|
/// Transfer the route-owned observation to a caller that has already reserved
/// bounded storage for the same editing owner. Call only after geometry retry
/// succeeded. The caller must retain this value and process it before later
/// route events, preserving its owner, stages and host lifetime. This transfer
/// is not an assertion that any application action has completed.
pub fn RetainedOrderedRoute::take_owned_geometry_text(
  self : RetainedOrderedRoute,
  epoch : UInt64,
) -> Result[GeometryOwnedText, @diagnostics.FrameworkError] {
  let operation = "take_owned_geometry_text"
  let owned = match self.geometry_handoff {
    Some(GeometryOwned(value)) => value
    _ => return Err(ubuntu_text_host_error(@diagnostics.StaleHandle, operation))
  }
  if self.pending_geometry is Some(_) {
    return Err(ubuntu_text_host_error(@diagnostics.Busy, operation))
  }
  if epoch != owned.receipt.epoch ||
    self.portable_epoch != epoch ||
    self.root != owned.receipt.root ||
    self.window != Some(owned.target.window) ||
    self.native_epoch != owned.target.epoch ||
    self.closed {
    return Err(ubuntu_text_host_error(@diagnostics.StaleHandle, operation))
  }
  self.geometry_handoff = None
  Ok(owned)
}

///|
/// Reserve one recognized original text FIFO head while geometry is uncertain,
/// then ACK that exact native head into the route-owned slot. An ACK failure
/// keeps both the slot and native head; repeat with the same receipt to retry.
/// Other event kinds, foreign or stale targets remain in native ownership.
pub fn RetainedOrderedRoute::handoff_geometry_head(
  self : RetainedOrderedRoute,
  receipt : RetainedOrderedReceipt,
) -> Result[Unit, @diagnostics.FrameworkError] {
  self.handoff_geometry_from(
    receipt,
    fn() { self.host.peek_retained_editor() },
    fn(record) { record.ack() },
  )
}

///|
fn geometry_text_identity(
  receipt : RetainedOrderedReceipt,
) -> (TextSessionTarget, TextSessionEvent, @text_host.TextInputEvent)? {
  match (receipt.record.event(), receipt.event) {
    (Some(TextSession(target, source)), Text(portable)) =>
      match source {
        Preedit(..) | Commit(deletion=None, position=None, ..) =>
          Some((target, source, portable))
        _ => None
      }
    _ => None
  }
}

///|
fn geometry_same_target(a : TextSessionTarget, b : TextSessionTarget) -> Bool {
  a.window == b.window &&
  a.sequence == b.sequence &&
  a.epoch == b.epoch &&
  a.seat == b.seat &&
  a.proxy_generation == b.proxy_generation &&
  a.serial == b.serial
}

///|
fn RetainedOrderedRoute::handoff_geometry_from(
  self : RetainedOrderedRoute,
  receipt : RetainedOrderedReceipt,
  peek : () -> Result[RetainedEditorRecord?, @diagnostics.FrameworkError],
  ack : (RetainedEditorRecord) -> Result[Unit, @diagnostics.FrameworkError],
) -> Result[Unit, @diagnostics.FrameworkError] {
  let operation = "handoff_geometry_head"
  if self.geometry_handoff_call {
    return Err(ubuntu_text_host_error(@diagnostics.Busy, operation))
  }
  let pending = match self.pending_geometry {
    Some(value) => value
    None =>
      return Err(ubuntu_text_host_error(@diagnostics.StaleHandle, operation))
  }
  if self.closed ||
    self.direct_binding ||
    self.window != Some(pending.window) ||
    self.root != pending.root ||
    self.portable_epoch != pending.epoch ||
    self.native_epoch != pending.native_epoch ||
    receipt.record.host.token != self.host.token ||
    receipt.root != pending.root ||
    receipt.epoch != pending.epoch ||
    receipt.record.window != pending.window {
    return Err(ubuntu_text_host_error(@diagnostics.StaleHandle, operation))
  }
  let (original_target, _, _) = match geometry_text_identity(receipt) {
    Some(value) => value
    None =>
      return Err(
        ubuntu_text_host_error(@diagnostics.UnsupportedCapability, operation),
      )
  }
  let fresh = match peek() {
    Err(error) => return Err(error)
    Ok(None) =>
      return Err(ubuntu_text_host_error(@diagnostics.StaleHandle, operation))
    Ok(Some(value)) => value
  }
  if fresh.is_stale() ||
    fresh.is_revoked() ||
    fresh.window() != pending.window ||
    fresh.sequence() != receipt.record.sequence ||
    original_target.window != pending.window ||
    original_target.sequence != fresh.sequence().to_int64() ||
    original_target.epoch != pending.native_epoch {
    return Err(ubuntu_text_host_error(@diagnostics.StaleHandle, operation))
  }
  let prepared = match self.prepare(fresh) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let (target, source, portable) = match geometry_text_identity(prepared) {
    Some(value) => value
    None =>
      return Err(
        ubuntu_text_host_error(@diagnostics.UnsupportedCapability, operation),
      )
  }
  if !geometry_same_target(target, original_target) ||
    prepared.expected_ordinal != self.ordinal ||
    prepared.expected_shortcuts != self.shortcuts.held ||
    prepared.expected_seat != self.native_seat ||
    prepared.expected_proxy != self.native_proxy {
    return Err(ubuntu_text_host_error(@diagnostics.StaleHandle, operation))
  }
  let value = match self.geometry_handoff {
    Some(GeometryOwned(_)) =>
      return Err(ubuntu_text_host_error(@diagnostics.Busy, operation))
    Some(GeometryReserved(value)) => {
      if value.geometry_generation != pending.generation ||
        !geometry_same_target(value.target, target) {
        return Err(ubuntu_text_host_error(@diagnostics.Busy, operation))
      }
      value
    }
    None => {
      let value = {
        receipt: prepared,
        target,
        native_text: source,
        portable_text: portable,
        geometry_generation: pending.generation,
      }
      self.geometry_handoff = Some(GeometryReserved(value))
      value
    }
  }
  self.geometry_handoff_call = true
  let result = ack(fresh)
  self.geometry_handoff_call = false
  match result {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  self.ordinal = value.receipt.candidate_ordinal
  self.shortcuts.held = value.receipt.candidate_shortcuts
  self.native_seat = value.receipt.candidate_seat
  self.native_proxy = value.receipt.candidate_proxy
  self.geometry_handoff = Some(GeometryOwned(value))
  Ok(())
}
