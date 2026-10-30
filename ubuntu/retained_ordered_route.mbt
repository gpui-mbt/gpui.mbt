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
/// A single session binding over retained Ubuntu native ingress. Native event
/// identities stay on the retained record; text observations receive a separate
/// per-binding ordinal only when this route prepares a candidate.
pub struct RetainedOrderedRoute {
  priv host : Host
  priv mut window : @platform.WindowId?
  priv mut root : UInt64
  priv mut portable_epoch : UInt64
  priv mut native_epoch : Int32
  priv mut native_seat : Int64
  priv mut native_proxy : Int32
  priv mut ordinal : Int64
  priv mut closed : Bool
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
    native_seat: 0L,
    native_proxy: 0,
    ordinal: 0L,
    closed: false,
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
/// The captured native epoch, or None while native ownership is uncertain.
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
/// Update the same native session while the retained FIFO is empty. Native
/// geometry publication is still subject to the host's own failure semantics.
pub fn RetainedOrderedRoute::update(
  self : RetainedOrderedRoute,
  epoch : UInt64,
  state : @text_host.TextInputState,
) -> Result[Unit, @diagnostics.FrameworkError] {
  let operation = "retained_update"
  if epoch != self.portable_epoch || self.closed {
    return Err(ubuntu_text_host_error(@diagnostics.StaleHandle, operation))
  }
  let window = match self.window {
    Some(value) => value
    None =>
      return Err(ubuntu_text_host_error(@diagnostics.StaleHandle, operation))
  }
  match self.require_empty(operation) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let native = match
    self.host.retained_update(window, self.native_epoch, state) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  if native != self.native_epoch {
    return Err(ubuntu_text_host_error(@diagnostics.StaleHandle, operation))
  }
  Ok(())
}

///|
/// Perform only the host cutoff. Any Left generated by cutoff remains in the
/// FIFO and the original binding stays alive until `release` succeeds.
pub fn RetainedOrderedRoute::try_end_when_drained(
  self : RetainedOrderedRoute,
  epoch : UInt64,
) -> Result[Unit, @diagnostics.FrameworkError] {
  self.end_from(epoch, fn() { self.require_empty("retained_end") }, fn(
    window,
    native_epoch,
  ) {
    self.host.retained_end(window, native_epoch)
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
  if !record.is_stale() {
    match native_event {
      Some(Platform(event)) =>
        match self.window {
          Some(window) if window != record.window() => ()
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
  if route.portable_epoch != self.epoch ||
    route.root != self.root ||
    route.ordinal != self.expected_ordinal ||
    route.shortcuts.held != self.expected_shortcuts ||
    route.native_seat != self.expected_seat ||
    route.native_proxy != self.expected_proxy {
    return Err(ubuntu_text_host_error(@diagnostics.StaleHandle, operation))
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
