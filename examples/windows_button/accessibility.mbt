///|
/// Opaque export identity for one continuously-present Button fixture node in
/// one Windows sample session. The source NodeId is retained only in the
/// session-owned map below.
pub struct WindowsButtonAccessibilityId {
  registry_owner : @accessibility.NodeId
  sequence : UInt64
} derive(Eq)

///|
pub extend WindowsButtonAccessibilityId with Eq::{not_equal, equal}

///|
pub struct WindowsButtonAccessibilityNode {
  id : WindowsButtonAccessibilityId
  parent : WindowsButtonAccessibilityId?
  children : Array[WindowsButtonAccessibilityId]
  role : @accessibility.AccessibilityRole
  name : String
  bounds : @primitives.Rect
  enabled : Bool
  loading : Bool
  focused : Bool
  actions : Array[@accessibility.AccessibilityAction]
}

///|
pub fn WindowsButtonAccessibilityNode::id(
  self : WindowsButtonAccessibilityNode,
) -> WindowsButtonAccessibilityId {
  self.id
}

///|
pub fn WindowsButtonAccessibilityNode::parent(
  self : WindowsButtonAccessibilityNode,
) -> WindowsButtonAccessibilityId? {
  self.parent
}

///|
pub fn WindowsButtonAccessibilityNode::children(
  self : WindowsButtonAccessibilityNode,
) -> Array[WindowsButtonAccessibilityId] {
  let copied : Array[WindowsButtonAccessibilityId] = []
  for child in self.children {
    copied.push(child)
  }
  copied
}

///|
pub fn WindowsButtonAccessibilityNode::role(
  self : WindowsButtonAccessibilityNode,
) -> @accessibility.AccessibilityRole {
  self.role
}

///|
pub fn WindowsButtonAccessibilityNode::name(
  self : WindowsButtonAccessibilityNode,
) -> String {
  self.name
}

///|
pub fn WindowsButtonAccessibilityNode::bounds(
  self : WindowsButtonAccessibilityNode,
) -> @primitives.Rect {
  self.bounds
}

///|
pub fn WindowsButtonAccessibilityNode::is_enabled(
  self : WindowsButtonAccessibilityNode,
) -> Bool {
  self.enabled
}

///|
pub fn WindowsButtonAccessibilityNode::is_loading(
  self : WindowsButtonAccessibilityNode,
) -> Bool {
  self.loading
}

///|
pub fn WindowsButtonAccessibilityNode::is_focused(
  self : WindowsButtonAccessibilityNode,
) -> Bool {
  self.focused
}

///|
pub fn WindowsButtonAccessibilityNode::supported_actions(
  self : WindowsButtonAccessibilityNode,
) -> Array[@accessibility.AccessibilityAction] {
  let copied : Array[@accessibility.AccessibilityAction] = []
  for action in self.actions {
    copied.push(action)
  }
  copied
}

///|
/// Copied semantic data for the Windows Button sample. An unavailable
/// snapshot is empty, and its tokens cannot be resolved until a later
/// available publication allocates fresh identities.
pub struct WindowsButtonAccessibilitySnapshot {
  source_revision : UInt64
  available : Bool
  nodes : Array[WindowsButtonAccessibilityNode]
}

///|
pub fn WindowsButtonAccessibilitySnapshot::revision(
  self : WindowsButtonAccessibilitySnapshot,
) -> UInt64 {
  self.source_revision
}

///|
pub fn WindowsButtonAccessibilitySnapshot::is_available(
  self : WindowsButtonAccessibilitySnapshot,
) -> Bool {
  self.available
}

///|
pub fn WindowsButtonAccessibilitySnapshot::nodes(
  self : WindowsButtonAccessibilitySnapshot,
) -> Array[WindowsButtonAccessibilityNode] {
  let copied : Array[WindowsButtonAccessibilityNode] = []
  for node in self.nodes {
    copied.push({
      ..node,
      children: node.children(),
      actions: node.supported_actions(),
    })
  }
  copied
}

///|
pub(all) enum WindowsButtonAccessibilityError {
  Unavailable
  SessionClosed
  StaleSnapshot
  ForeignOwner
  StaleTarget
  IdentityExhausted
  ActionRejected(@accessibility.ActionError)
}

///|
struct WindowsButtonAccessibilityEntry {
  export_id : WindowsButtonAccessibilityId
  node_id : @accessibility.NodeId
}

///|
struct WindowsButtonAccessibilityState {
  registry_owner : @accessibility.NodeId
  next_sequence : UInt64
  sequence_exhausted : Bool
  source_revision : UInt64
  available : Bool
  closed : Bool
  entries : Array[WindowsButtonAccessibilityEntry]
  current : WindowsButtonAccessibilitySnapshot
}

///|
/// The copied sample binding is confined to its Windows UI-owner session. It
/// stores source IDs only for the current published tree and routes no action
/// itself; ButtonDemo remains the sole owner of the activation effect.
struct WindowsButtonAccessibilityBinding {
  state : Ref[WindowsButtonAccessibilityState]
}

///|
const WINDOWS_BUTTON_ACCESSIBILITY_MAX_UINT64 : UInt64 = 0xffff_ffff_ffff_ffff

///|
fn windows_button_accessibility_empty(
  revision : UInt64,
  available : Bool,
) -> WindowsButtonAccessibilitySnapshot {
  { source_revision: revision, available, nodes: [], }
}

///|
fn windows_button_accessibility_owner() -> Result[
  @accessibility.NodeId,
  WindowsButtonAccessibilityError,
] {
  let model = match @accessibility.AccessibilityModel::new() {
    Ok(value) => value
    Err(_) => return Err(IdentityExhausted)
  }
  let bounds = match @primitives.Rect::new(0.0, 0.0, 0.0, 0.0) {
    Ok(value) => value
    Err(_) => {
      model.close()
      return Err(IdentityExhausted)
    }
  }
  let snapshot = match
    model.publish([
      @accessibility.NodeSpec::new(
        1UL,
        None,
        @accessibility.Window,
        "Windows Button session identity",
        bounds,
      ),
    ]) {
    Ok(value) => value
    Err(_) => {
      model.close()
      return Err(IdentityExhausted)
    }
  }
  let owner = snapshot.nodes()[0].id()
  model.close()
  Ok(owner)
}

///|
fn windows_button_accessibility_find_source(
  entries : Array[WindowsButtonAccessibilityEntry],
  node_id : @accessibility.NodeId,
) -> Int {
  let mut index = 0
  while index < entries.length() {
    if entries[index].node_id == node_id {
      return index
    }
    index += 1
  }
  -1
}

///|
fn windows_button_accessibility_find_export(
  entries : Array[WindowsButtonAccessibilityEntry],
  export_id : WindowsButtonAccessibilityId,
) -> Int {
  let mut index = 0
  while index < entries.length() {
    if entries[index].export_id == export_id {
      return index
    }
    index += 1
  }
  -1
}

///|
fn windows_button_accessibility_export_for_node(
  entries : Array[WindowsButtonAccessibilityEntry],
  node_id : @accessibility.NodeId?,
) -> WindowsButtonAccessibilityId? {
  match node_id {
    None => None
    Some(value) => {
      let index = windows_button_accessibility_find_source(entries, value)
      if index < 0 {
        None
      } else {
        Some(entries[index].export_id)
      }
    }
  }
}

///|
fn windows_button_accessibility_copy_children(
  entries : Array[WindowsButtonAccessibilityEntry],
  children : Array[@accessibility.NodeId],
) -> Array[WindowsButtonAccessibilityId] {
  let result : Array[WindowsButtonAccessibilityId] = []
  for child in children {
    match windows_button_accessibility_export_for_node(entries, Some(child)) {
      Some(export_id) => result.push(export_id)
      None => ()
    }
  }
  result
}

///|
fn windows_button_accessibility_copy_snapshot(
  snapshot : @accessibility.AccessibilitySnapshot,
  entries : Array[WindowsButtonAccessibilityEntry],
  available : Bool,
) -> WindowsButtonAccessibilitySnapshot {
  if !available {
    return windows_button_accessibility_empty(snapshot.revision(), false)
  }
  let source_nodes = snapshot.nodes()
  let nodes : Array[WindowsButtonAccessibilityNode] = []
  for source in source_nodes {
    let index = windows_button_accessibility_find_source(entries, source.id())
    if index >= 0 {
      nodes.push({
        id: entries[index].export_id,
        parent: windows_button_accessibility_export_for_node(
          entries,
          source.parent(),
        ),
        children: windows_button_accessibility_copy_children(
          entries,
          source.children(),
        ),
        role: source.role(),
        name: source.name(),
        bounds: source.bounds(),
        enabled: source.is_enabled(),
        loading: source.is_loading(),
        focused: source.is_focused(),
        actions: source.supported_actions(),
      })
    }
  }
  { source_revision: snapshot.revision(), available: true, nodes, }
}

///|
fn windows_button_accessibility_new(
  snapshot : @accessibility.AccessibilitySnapshot,
  available : Bool,
) -> Result[WindowsButtonAccessibilityBinding, WindowsButtonAccessibilityError] {
  let registry_owner = match windows_button_accessibility_owner() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let binding = {
    state: Ref({
      registry_owner,
      next_sequence: 1UL,
      sequence_exhausted: false,
      source_revision: 0UL,
      available: false,
      closed: false,
      entries: [],
      current: windows_button_accessibility_empty(0UL, false),
    }),
  }
  match windows_button_accessibility_publish(binding, snapshot, available) {
    Ok(_) => Ok(binding)
    Err(error) => Err(error)
  }
}

///|
/// Reconcile copied semantics against the new committed source snapshot.
/// Tokens survive only when the complete source NodeId remains present in the
/// immediately previous available publication.
fn windows_button_accessibility_publish(
  binding : WindowsButtonAccessibilityBinding,
  snapshot : @accessibility.AccessibilitySnapshot,
  available : Bool,
) -> Result[Unit, WindowsButtonAccessibilityError] {
  let state = binding.state.val
  if state.closed {
    return Err(SessionClosed)
  }
  if !available {
    binding.state.val = {
      ..state,
      source_revision: snapshot.revision(),
      available: false,
      entries: [],
      current: windows_button_accessibility_empty(snapshot.revision(), false),
    }
    return Ok(())
  }

  let source_nodes = snapshot.nodes()
  let next_sequence = Ref(state.next_sequence)
  let sequence_exhausted = Ref(state.sequence_exhausted)
  let entries : Array[WindowsButtonAccessibilityEntry] = []
  for source in source_nodes {
    let prior = if state.available {
      windows_button_accessibility_find_source(state.entries, source.id())
    } else {
      -1
    }
    let export_id = if prior >= 0 {
      state.entries[prior].export_id
    } else if sequence_exhausted.val {
      return Err(IdentityExhausted)
    } else {
      let sequence = next_sequence.val
      if sequence == WINDOWS_BUTTON_ACCESSIBILITY_MAX_UINT64 {
        sequence_exhausted.val = true
      } else {
        next_sequence.val = sequence + 1UL
      }
      { registry_owner: state.registry_owner, sequence, }
    }
    entries.push({ export_id, node_id: source.id(), })
  }
  let current = windows_button_accessibility_copy_snapshot(
    snapshot, entries, true,
  )
  binding.state.val = {
    ..state,
    next_sequence: next_sequence.val,
    sequence_exhausted: sequence_exhausted.val,
    source_revision: snapshot.revision(),
    available: true,
    entries,
    current,
  }
  Ok(())
}

///|
fn windows_button_accessibility_matches_source(
  state : WindowsButtonAccessibilityState,
  snapshot : @accessibility.AccessibilitySnapshot,
) -> Bool {
  if !state.available || state.source_revision != snapshot.revision() {
    return false
  }
  let nodes = snapshot.nodes()
  if state.entries.length() != nodes.length() {
    return false
  }
  let mut index = 0
  while index < nodes.length() {
    if state.entries[index].node_id != nodes[index].id() {
      return false
    }
    index += 1
  }
  true
}

///|
fn windows_button_accessibility_snapshot(
  binding : WindowsButtonAccessibilityBinding,
  source : @accessibility.AccessibilitySnapshot,
  available : Bool,
) -> Result[WindowsButtonAccessibilitySnapshot, WindowsButtonAccessibilityError] {
  let state = binding.state.val
  if state.closed {
    return Ok(windows_button_accessibility_empty(state.source_revision, false))
  }
  if !available {
    return Ok(windows_button_accessibility_empty(state.source_revision, false))
  }
  if !windows_button_accessibility_matches_source(state, source) {
    return Err(StaleSnapshot)
  }
  Ok({ ..state.current, nodes: state.current.nodes(), })
}

///|
fn windows_button_accessibility_resolve(
  binding : WindowsButtonAccessibilityBinding,
  source : @accessibility.AccessibilitySnapshot,
  available : Bool,
  export_id : WindowsButtonAccessibilityId,
) -> Result[@accessibility.NodeId, WindowsButtonAccessibilityError] {
  let state = binding.state.val
  if state.closed {
    return Err(SessionClosed)
  }
  if !available || !state.available {
    return Err(Unavailable)
  }
  if export_id.registry_owner != state.registry_owner {
    return Err(ForeignOwner)
  }
  if !windows_button_accessibility_matches_source(state, source) {
    return Err(StaleSnapshot)
  }
  let index = windows_button_accessibility_find_export(state.entries, export_id)
  if index < 0 {
    return Err(StaleTarget)
  }
  Ok(state.entries[index].node_id)
}

///|
fn windows_button_accessibility_close(
  binding : WindowsButtonAccessibilityBinding,
  source_revision : UInt64,
) -> Unit {
  let state = binding.state.val
  if !state.closed {
    binding.state.val = {
      ..state,
      source_revision,
      available: false,
      closed: true,
      entries: [],
      current: windows_button_accessibility_empty(source_revision, false),
    }
  }
}
