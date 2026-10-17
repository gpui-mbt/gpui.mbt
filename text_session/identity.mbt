///|
/// A private mutable cell gives an incarnation observable alias identity.
/// Do not use physical_equal: that intrinsic is documented as optimizer- and
/// backend-dependent. No callbacks or suspension occur during this probe.
priv struct Identity {
  marker : Ref[Bool]
}

///|
fn identity() -> Identity {
  { marker: Ref(false), }
}

///|
fn same_identity(left : Identity, right : Identity) -> Bool {
  left.marker.val = true
  let same = right.marker.val
  left.marker.val = false
  same
}

///|
const MAX_COUNTER : UInt64 = 0xffff_ffff_ffff_ffffUL

///|
fn advance(value : UInt64) -> Result[UInt64, SessionError] {
  if value == MAX_COUNTER {
    Err(Exhausted)
  } else {
    Ok(value + 1UL)
  }
}

///|
/// An opaque ingress receipt. Numeric accessors are diagnostics, not identity.
pub struct SessionTarget {
  priv owner : Identity
  priv window_instance : Identity
  priv root_instance : Identity
  priv field_instance : Identity
  priv window : @platform.WindowId
  priv root_id : UInt64
  priv field_id : UInt64
  priv session : UInt64
  priv revision : UInt64
  priv sequence : UInt64
}

///|
pub fn SessionTarget::window(self : SessionTarget) -> @platform.WindowId {
  self.window
}

///|
pub fn SessionTarget::root_id(self : SessionTarget) -> UInt64 {
  self.root_id
}

///|
pub fn SessionTarget::field_id(self : SessionTarget) -> UInt64 {
  self.field_id
}

///|
pub fn SessionTarget::session_id(self : SessionTarget) -> UInt64 {
  self.session
}

///|
pub fn SessionTarget::published_revision(self : SessionTarget) -> UInt64 {
  self.revision
}

///|
pub fn SessionTarget::delivery_sequence(self : SessionTarget) -> UInt64 {
  self.sequence
}

///|
fn same_target(left : SessionTarget, right : SessionTarget) -> Bool {
  same_identity(left.owner, right.owner) &&
  same_identity(left.window_instance, right.window_instance) &&
  same_identity(left.root_instance, right.root_instance) &&
  same_identity(left.field_instance, right.field_instance) &&
  left.window == right.window &&
  left.root_id == right.root_id &&
  left.field_id == right.field_id &&
  left.session == right.session &&
  left.revision == right.revision &&
  left.sequence == right.sequence
}

///|
/// Completion authority for one explicit end request, shared by copied values.
pub struct PendingEnd {
  priv identity : Identity
  priv target : SessionTarget
  priv reason : EndReason
}

///|
pub fn PendingEnd::target(self : PendingEnd) -> SessionTarget {
  self.target
}

///|
pub fn PendingEnd::reason(self : PendingEnd) -> EndReason {
  self.reason
}
