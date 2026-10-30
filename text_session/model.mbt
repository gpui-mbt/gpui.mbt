///|
pub(all) enum SessionError {
  Closed
  Reentrant
  ForeignOwner
  StaleBinding
  StaleSession
  StaleRevision
  Replay
  OutOfOrder
  Unfocused
  PendingResolution
  InvalidPending
  WrongEndReason
  NoComposition
  CompositionActive
  InvalidBinding
  EmptyBatch
  Exhausted
  FieldFailure(@text_field.TextFieldError)
} derive(Eq)

///|
pub extend SessionError with Eq::{equal, not_equal}

///|
/// UTF-16 directional endpoints, or strict UTF-8 byte endpoints in the preedit.
/// Commit is composition-only: no active composition means rejection. Insert
/// represents an observed direct commit with no active preedit; it must not be
/// used as a fallback for a composing commit.
pub(all) enum SessionOperation {
  Preview(String, @text.TextSelection)
  PreviewUtf8(String, Int32, Int32)
  Commit(String)
  Insert(String)
  Cancel
}

///|
/// A request is not an observation of what the OS actually did.
pub(all) enum EndReason {
  Blur
  ExternalReplacement
} derive(Eq)

///|
pub extend EndReason with Eq::{equal, not_equal}

///|
pub(all) enum ObservedEnd {
  Committed(String)
  Cancelled
}

///|
/// Ordered accepted outcomes retain intermediate field values. In particular,
/// a committed value remains observable even when a replacement follows it.
pub(all) enum SessionOutcome {
  Previewed(@text_field.TextField)
  Committed(@text_field.TextField)
  Cancelled(@text_field.TextField)
  /// The application deliberately discarded preedit after its own cutoff;
  /// this is not an observation that the operating system canceled it.
  OwnerDiscarded(@text_field.TextField)
  Blurred(@text_field.TextField)
  Rebound(@text_field.TextField)
}

///|
/// Immutable readable state; this value is not a second live editing owner.
pub struct SessionSnapshot {
  priv field : @text_field.TextField
  priv window : @platform.WindowId
  priv root_id : UInt64
  priv session : UInt64
  priv revision : UInt64
  priv document_revision : UInt64
  priv sequence : UInt64
  priv closed : Bool
  priv pending : Bool
}

///|
pub fn SessionSnapshot::field(self : SessionSnapshot) -> @text_field.TextField {
  self.field
}

///|
pub fn SessionSnapshot::window(self : SessionSnapshot) -> @platform.WindowId {
  self.window
}

///|
pub fn SessionSnapshot::root_id(self : SessionSnapshot) -> UInt64 {
  self.root_id
}

///|
pub fn SessionSnapshot::session_id(self : SessionSnapshot) -> UInt64 {
  self.session
}

///|
pub fn SessionSnapshot::published_revision(self : SessionSnapshot) -> UInt64 {
  self.revision
}

///|
pub fn SessionSnapshot::committed_document_revision(
  self : SessionSnapshot,
) -> UInt64 {
  self.document_revision
}

///|
pub fn SessionSnapshot::delivery_watermark(self : SessionSnapshot) -> UInt64 {
  self.sequence
}

///|
pub fn SessionSnapshot::is_closed(self : SessionSnapshot) -> Bool {
  self.closed
}

///|
pub fn SessionSnapshot::has_pending_end(self : SessionSnapshot) -> Bool {
  self.pending
}

///|
/// Created only after atomic model publication. A host may acknowledge exactly
/// accepted_target, then publish geometry for snapshot. This is not an OS ACK.
pub struct BatchReceipt {
  priv accepted_target : SessionTarget
  priv snapshot : SessionSnapshot
  priv outcomes : Array[SessionOutcome]
}

///|
/// An immutable bounds-only proposal tied to one exact session publication.
/// It is not authority to publish a scene or change host geometry. A caller may
/// use the field to prepare those resources. Coordinated publication with other
/// owners is not provided by this value and requires a separate transaction.
pub struct BoundsProposal {
  priv publication : Identity
  priv target : SessionTarget
  priv field : @text_field.TextField
}

///|
pub fn BoundsProposal::field(self : BoundsProposal) -> @text_field.TextField {
  self.field
}

///|
pub fn BatchReceipt::accepted_target(self : BatchReceipt) -> SessionTarget {
  self.accepted_target
}

///|
pub fn BatchReceipt::snapshot(self : BatchReceipt) -> SessionSnapshot {
  self.snapshot
}

///|
pub fn BatchReceipt::outcomes(self : BatchReceipt) -> Array[SessionOutcome] {
  self.outcomes.copy()
}

///|
pub fn BatchReceipt::acknowledges(
  self : BatchReceipt,
  target : SessionTarget,
) -> Bool {
  same_target(self.accepted_target, target)
}

///|
priv struct LiveState {
  owner : Identity
  window_instance : Identity
  root_instance : Identity
  field_instance : Identity
  publication : Identity
  window : @platform.WindowId
  root_id : UInt64
  field : @text_field.TextField
  session : UInt64
  revision : UInt64
  document_revision : UInt64
  sequence : UInt64
  closed : Bool
  pending : PendingEnd?
}

///|
priv struct MutationGuard {
  mut busy : Bool
  mut violated : Bool
}

///|
/// UI-thread-confined mutable authority. Copying the handle shares both live
/// state and its reentrancy guard. There is no public clone or token constructor.
pub struct TextSession {
  priv state : Ref[LiveState]
  priv mutation_guard : MutationGuard
}

///|
fn validate_binding(
  window : @platform.WindowId,
  root_id : UInt64,
  field : @text_field.TextField,
) -> Result[Unit, SessionError] {
  if window.value() <= 0L || root_id == 0UL {
    return Err(InvalidBinding)
  }
  if field.is_composing() {
    return Err(CompositionActive)
  }
  Ok(())
}

///|
pub fn TextSession::new(
  window : @platform.WindowId,
  root_id : UInt64,
  field : @text_field.TextField,
) -> Result[TextSession, SessionError] {
  match validate_binding(window, root_id, field) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  Ok({
    state: Ref({
      owner: identity(),
      window_instance: identity(),
      root_instance: identity(),
      field_instance: identity(),
      publication: identity(),
      window,
      root_id,
      field,
      session: 1UL,
      revision: 0UL,
      document_revision: 0UL,
      sequence: 0UL,
      closed: false,
      pending: None,
    }),
    mutation_guard: { busy: false, violated: false, },
  })
}

///|
fn snapshot(state : LiveState) -> SessionSnapshot {
  {
    field: state.field,
    window: state.window,
    root_id: state.root_id,
    session: state.session,
    revision: state.revision,
    document_revision: state.document_revision,
    sequence: state.sequence,
    closed: state.closed,
    pending: state.pending is Some(_),
  }
}

///|
pub fn TextSession::snapshot(self : TextSession) -> SessionSnapshot {
  snapshot(self.state.val)
}

///|
fn capture_target(state : LiveState) -> Result[SessionTarget, SessionError] {
  if state.closed {
    return Err(Closed)
  }
  let sequence = match advance(state.sequence) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  Ok({
    owner: state.owner,
    window_instance: state.window_instance,
    root_instance: state.root_instance,
    field_instance: state.field_instance,
    window: state.window,
    root_id: state.root_id,
    field_id: state.field.id(),
    session: state.session,
    revision: state.revision,
    sequence,
  })
}

///|
/// Capture once at ingress; queued input must retain this exact target.
pub fn TextSession::target(
  self : TextSession,
) -> Result[SessionTarget, SessionError] {
  if self.state.val.pending is Some(_) {
    return Err(PendingResolution)
  }
  capture_target(self.state.val)
}

///|
fn validate_target(
  state : LiveState,
  target : SessionTarget,
) -> Result[Unit, SessionError] {
  if state.closed {
    return Err(Closed)
  }
  if !same_identity(state.owner, target.owner) {
    return Err(ForeignOwner)
  }
  if !same_identity(state.window_instance, target.window_instance) ||
    !same_identity(state.root_instance, target.root_instance) ||
    !same_identity(state.field_instance, target.field_instance) ||
    state.window != target.window ||
    state.root_id != target.root_id ||
    state.field.id() != target.field_id {
    return Err(StaleBinding)
  }
  if state.session != target.session {
    return Err(StaleSession)
  }
  if target.sequence <= state.sequence {
    return Err(Replay)
  }
  if state.revision != target.revision {
    return Err(StaleRevision)
  }
  let next = match advance(state.sequence) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if target.sequence != next {
    return Err(OutOfOrder)
  }
  Ok(())
}

///|
/// Every mutation, including lifecycle requests, goes through this guard.
/// Nested attempts poison the outer transaction even if a provider ignores
/// their error. All model state is published together after the identity check.
fn[T] TextSession::mutate(
  self : TextSession,
  prepare : (LiveState) -> Result[(LiveState, T), SessionError],
) -> Result[T, SessionError] {
  if self.mutation_guard.busy {
    self.mutation_guard.violated = true
    return Err(Reentrant)
  }
  self.mutation_guard.busy = true
  self.mutation_guard.violated = false
  let original = self.state.val
  let result = prepare(original)
  let invalidated = self.mutation_guard.violated ||
    !same_identity(original.publication, self.state.val.publication)
  self.mutation_guard.busy = false
  self.mutation_guard.violated = false
  if invalidated {
    return Err(Reentrant)
  }
  match result {
    Err(error) => Err(error)
    Ok((candidate, value)) => {
      self.state.val = { ..candidate, publication: identity(), }
      Ok(value)
    }
  }
}
