///|
/// Admission and lifecycle failures. Every error preserves authoritative session
/// state. User callback effects are external and cannot be rolled back.
pub(all) enum FocusScopeError {
  ForeignTarget
  StaleTarget
  ForeignHandle
  StaleHandle
  ClosedSession
  IdentityExhausted
  RevisionExhausted
  InvalidRoot
  InvalidInitialFocus
  InvalidFallback
  OutsideScope
  StackLimit
  ReentrantMutation
  InteractionBoundaryRejected
  Element(ElementError)
  Scroll(ScrollError)
} derive(Eq)

///|
pub extend FocusScopeError with Eq::{not_equal, equal}

///|
/// One modal lifetime, independent of the number of focus acquisitions.
pub struct FocusScopeHandle {
  priv session : UInt64
  priv identity : UInt64
} derive(Eq)

///|
pub extend FocusScopeHandle with Eq::{not_equal, equal}

///|
/// Synchronous admission to exactly one current session revision. This is not
/// an OS accessibility, native capture, or asynchronous input transport token.
pub struct FocusScopeTarget {
  priv session : UInt64
  priv revision : UInt64
} derive(Eq)

///|
/// A same-topology bounds replacement for one exact focus-scope revision.
/// It is not a receipt for scene, text-session, or native-host publication.
pub struct FocusBoundsProposal {
  priv target : FocusScopeTarget
  priv tree : ElementTree
  priv revision : UInt64
}

///|
pub extend FocusScopeTarget with Eq::{not_equal, equal}

///|
pub(all) enum FocusScopeBoundaryKind {
  Opened
  Removed
  Replaced
  Closed
} derive(Eq)

///|
pub extend FocusScopeBoundaryKind with Eq::{not_equal, equal}

///|
/// A synchronous cancellation obligation delivered before publication. The
/// integrating owner must cancel Button gestures and pending/active drags,
/// release or quarantine native capture, and separately observe any text-session
/// end contract. Return InteractionBoundaryRejected if that is not possible.
pub struct FocusScopeBoundary {
  priv boundary_kind : FocusScopeBoundaryKind
  priv before : UInt64?
  priv after : UInt64?
  priv removed : Array[UInt64]
}

///|
pub fn FocusScopeBoundary::kind(
  self : FocusScopeBoundary,
) -> FocusScopeBoundaryKind {
  self.boundary_kind
}

///|
pub fn FocusScopeBoundary::previous_root(self : FocusScopeBoundary) -> UInt64? {
  self.before
}

///|
pub fn FocusScopeBoundary::next_root(self : FocusScopeBoundary) -> UInt64? {
  self.after
}

///|
pub fn FocusScopeBoundary::removed_roots(
  self : FocusScopeBoundary,
) -> Array[UInt64] {
  copy_ids(self.removed)
}

///|
priv struct FocusScopeFrame {
  identity : UInt64
  root : UInt64
  previous : FocusOwner?
  fallback : FocusOwner?
}

///|
priv struct FocusScopeState {
  tree : ElementTree
  scopes : Array[FocusScopeFrame]
  revision : UInt64
  closed : Bool
  closing_keys : Array[@primitives.Key]
}

///|
/// UI-thread-confined live owner around immutable ElementTree. Copies share
/// authoritative state and revocation. snapshot() is a detached observation.
/// The host owns the per-window instance and the existing Tab command binding.
pub struct FocusScopeSession {
  priv identity : UInt64
  priv state : Ref[FocusScopeState]
  priv busy : Ref[Bool]
  priv violated : Ref[Bool]
}

///|
pub fn FocusScopeSession::new(
  tree : ElementTree,
) -> Result[FocusScopeSession, FocusScopeError] {
  match allocate_focus_identity() {
    None => Err(IdentityExhausted)
    Some(identity) =>
      Ok({
        identity,
        state: Ref({
          tree: focus_scope_copy_tree(tree),
          scopes: [],
          revision: 0,
          closed: false,
          closing_keys: [],
        }),
        busy: Ref(false),
        violated: Ref(false),
      })
  }
}

///|
fn focus_scope_copy_tree(tree : ElementTree) -> ElementTree {
  { ..tree, nodes: copy_nodes(tree.nodes), }
}

///|
pub fn FocusScopeSession::snapshot(self : FocusScopeSession) -> ElementTree {
  focus_scope_copy_tree(self.state.val.tree)
}

///|
/// Reading is allowed during callbacks and after terminal close; admission
/// still rejects closed sessions and nested calls.
pub fn FocusScopeSession::target(self : FocusScopeSession) -> FocusScopeTarget {
  { session: self.identity, revision: self.state.val.revision, }
}

///|
pub fn FocusScopeSession::scope_count(self : FocusScopeSession) -> Int32 {
  self.state.val.scopes.length()
}

///|
/// Current exact acquisition. Reading is allowed during dispatch callbacks and
/// after terminal close; it never grants admission.
pub fn FocusScopeSession::focused(self : FocusScopeSession) -> UInt64? {
  self.state.val.tree.focused
}

///|
/// Drop the current acquisition while every open scope keeps its boundary. An
/// owner calls this when the window or keyboard target lost focus. A session
/// that already has no focus and no owner is unchanged and keeps its revision.
pub fn FocusScopeSession::clear_focus(
  self : FocusScopeSession,
  target : FocusScopeTarget,
) -> Result[Unit, FocusScopeError] {
  match self.validate(target) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let state = self.state.val
  if state.tree.focused is None && state.tree.focus_owner() is None {
    return Ok(())
  }
  let revision = match focus_scope_revision(state) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  self.state.val = { ..state, tree: state.tree.clear_focus(), revision, }
  Ok(())
}

///|
fn focus_scope_root(scopes : Array[FocusScopeFrame]) -> UInt64? {
  if scopes.length() == 0 {
    None
  } else {
    Some(scopes[scopes.length() - 1].root)
  }
}

///|
fn focus_scope_contains(tree : ElementTree, root : UInt64, id : UInt64) -> Bool {
  let mut current = Some(id)
  while current is Some(value) {
    match tree.node(value) {
      None => return false
      Some(node) => {
        if value == root {
          return true
        }
        current = node.parent
      }
    }
  }
  false
}

///|
fn focus_scope_admits(tree : ElementTree, root : UInt64?, id : UInt64) -> Bool {
  match root {
    None => tree.node(id) is Some(_)
    Some(root) => focus_scope_contains(tree, root, id)
  }
}

///|
fn FocusScopeSession::validate(
  self : FocusScopeSession,
  target : FocusScopeTarget,
) -> Result[Unit, FocusScopeError] {
  if self.busy.val {
    self.violated.val = true
    return Err(ReentrantMutation)
  }
  if self.state.val.closed {
    return Err(ClosedSession)
  }
  if target.session != self.identity {
    return Err(ForeignTarget)
  }
  if target.revision != self.state.val.revision {
    return Err(StaleTarget)
  }
  Ok(())
}

///|
fn focus_scope_revision(
  state : FocusScopeState,
) -> Result[UInt64, FocusScopeError] {
  if state.revision == 0xffff_ffff_ffff_ffff {
    Err(RevisionExhausted)
  } else {
    Ok(state.revision + 1)
  }
}

///|
fn focus_scope_element_error(error : ElementError) -> FocusScopeError {
  match error {
    FocusIdentityExhausted => IdentityExhausted
    _ => Element(error)
  }
}

///|
fn focus_scope_first(
  tree : ElementTree,
  root : UInt64?,
) -> Result[ElementTree, FocusScopeError] {
  let cleared = tree.clear_focus()
  let next = match cleared.traverse_focus_within(false, root) {
    Ok(value) => value
    Err(error) => return Err(focus_scope_element_error(error))
  }
  if next.focused is Some(_) {
    return Ok(next)
  }
  match root {
    Some(root) =>
      match tree.node(root) {
        Some(node) if node.focusable =>
          match cleared.with_focus(root) {
            Ok(value) => Ok(value)
            Err(error) => Err(focus_scope_element_error(error))
          }
        _ => Ok(cleared)
      }
    None => Ok(cleared)
  }
}

///|
fn focus_scope_restore(
  tree : ElementTree,
  scopes : Array[FocusScopeFrame],
  previous : FocusOwner?,
  fallback : FocusOwner?,
) -> Result[ElementTree, FocusScopeError] {
  let root = focus_scope_root(scopes)
  for captured in [previous, fallback] {
    if captured is Some(owner) && focus_scope_admits(tree, root, owner.id) {
      match tree.with_focus_owner(owner) {
        Ok(value) => return Ok(value)
        Err(_) => ()
      }
    }
  }
  focus_scope_first(tree, root)
}

///|
// Hooks are non-raising Result callbacks. A failed hook or ignored reentrant
// attempt prevents publication. An abort/panic is not a recoverable error.
fn FocusScopeSession::publish_boundary(
  self : FocusScopeSession,
  next : FocusScopeState,
  kind : FocusScopeBoundaryKind,
  removed : Array[UInt64],
  cancel_interactions : (FocusScopeBoundary) -> Result[Unit, FocusScopeError],
) -> Result[Unit, FocusScopeError] {
  let boundary : FocusScopeBoundary = {
    boundary_kind: kind,
    before: focus_scope_root(self.state.val.scopes),
    after: focus_scope_root(next.scopes),
    removed: copy_ids(removed),
  }
  self.busy.val = true
  self.violated.val = false
  let result = cancel_interactions(boundary)
  self.busy.val = false
  if self.violated.val {
    return Err(ReentrantMutation)
  }
  match result {
    Err(error) => Err(error)
    Ok(_) => {
      self.state.val = next
      Ok(())
    }
  }
}

///|
/// A new root may be inside the current scope or a disjoint overlay sibling,
/// but may not contain any active outer root. Explicit initial/fallback nodes
/// are validated atomically. Fallback is captured in the resumed outer scope.
pub fn FocusScopeSession::open_scope(
  self : FocusScopeSession,
  target : FocusScopeTarget,
  root : UInt64,
  cancel_interactions : (FocusScopeBoundary) -> Result[Unit, FocusScopeError],
  initial? : UInt64,
  fallback? : UInt64,
) -> Result[FocusScopeHandle, FocusScopeError] {
  match self.validate(target) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let state = self.state.val
  if state.scopes.length() >= 32 {
    return Err(StackLimit)
  }
  if state.tree.node(root) is None {
    return Err(InvalidRoot)
  }
  for frame in state.scopes {
    if focus_scope_contains(state.tree, root, frame.root) {
      return Err(InvalidRoot)
    }
  }
  let revision = match focus_scope_revision(state) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if initial is Some(id) &&
    (
      !focus_scope_contains(state.tree, root, id) ||
      !(state.tree.node(id) is Some(node) && node.focusable)
    ) {
    return Err(InvalidInitialFocus)
  }
  if fallback is Some(id) &&
    (
      !focus_scope_admits(state.tree, focus_scope_root(state.scopes), id) ||
      focus_scope_contains(state.tree, root, id) ||
      !(state.tree.node(id) is Some(node) && node.focusable)
    ) {
    return Err(InvalidFallback)
  }
  let tree = match initial {
    Some(id) =>
      match state.tree.with_focus(id) {
        Ok(value) => value
        Err(error) => return Err(focus_scope_element_error(error))
      }
    None =>
      match focus_scope_first(state.tree, Some(root)) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
  }
  if tree.focused is None {
    return Err(InvalidInitialFocus)
  }
  let captured_fallback = match fallback {
    None => None
    Some(id) =>
      match state.tree.with_focus(id) {
        Ok(value) => value.focus_owner()
        Err(error) => return Err(focus_scope_element_error(error))
      }
  }
  let identity = match allocate_focus_identity() {
    Some(value) => value
    None => return Err(IdentityExhausted)
  }
  let scopes = state.scopes.copy()
  scopes.push({
    identity,
    root,
    previous: state.tree.focus_owner(),
    fallback: captured_fallback,
  })
  match
    self.publish_boundary(
      { ..state, tree, scopes, revision, },
      Opened,
      [],
      cancel_interactions,
    ) {
    Err(error) => Err(error)
    Ok(_) => Ok({ session: self.identity, identity, })
  }
}

///|
pub fn FocusScopeSession::request_focus(
  self : FocusScopeSession,
  target : FocusScopeTarget,
  id : UInt64,
) -> Result[Unit, FocusScopeError] {
  match self.validate(target) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let state = self.state.val
  if !focus_scope_admits(state.tree, focus_scope_root(state.scopes), id) {
    return Err(OutsideScope)
  }
  let revision = match focus_scope_revision(state) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  match state.tree.with_focus(id) {
    Err(error) => Err(focus_scope_element_error(error))
    Ok(tree) => {
      self.state.val = { ..state, tree, revision, }
      Ok(())
    }
  }
}

///|
fn FocusScopeSession::traverse(
  self : FocusScopeSession,
  target : FocusScopeTarget,
  backward : Bool,
) -> Result[Unit, FocusScopeError] {
  match self.validate(target) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let state = self.state.val
  let tree = match
    state.tree.traverse_focus_within(backward, focus_scope_root(state.scopes)) {
    Ok(value) => value
    Err(error) => return Err(focus_scope_element_error(error))
  }
  if tree.focus_owner() == state.tree.focus_owner() {
    return Ok(())
  }
  let revision = match focus_scope_revision(state) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  self.state.val = { ..state, tree, revision, }
  Ok(())
}

///|
/// Invoke from the host's existing Tab command; dispatch_input_with only routes.
pub fn FocusScopeSession::focus_next(
  self : FocusScopeSession,
  target : FocusScopeTarget,
) -> Result[Unit, FocusScopeError] {
  self.traverse(target, false)
}

///|
pub fn FocusScopeSession::focus_prev(
  self : FocusScopeSession,
  target : FocusScopeTarget,
) -> Result[Unit, FocusScopeError] {
  self.traverse(target, true)
}

///|
fn focus_scope_route(
  tree : ElementTree,
  root : UInt64?,
  plan : DispatchPlan,
) -> DispatchPlan {
  match plan.target {
    None => empty_dispatch_plan()
    Some(id) => {
      if !focus_scope_admits(tree, root, id) {
        return empty_dispatch_plan()
      }
      let capture : Array[UInt64] = []
      let mut admitted = root is None
      for ancestor in plan.capture {
        if root == Some(ancestor) {
          admitted = true
        }
        if admitted {
          capture.push(ancestor)
        }
      }
      let bubble : Array[UInt64] = []
      for index = capture.length() - 1; index >= 0; index = index - 1 {
        bubble.push(capture[index])
      }
      { target: Some(id), capture, bubble, }
    }
  }
}

///|
fn FocusScopeSession::run_dispatch(
  self : FocusScopeSession,
  plan : DispatchPlan,
  callback : (DispatchContext) -> Result[Unit, ElementError],
) -> Result[DispatchOutcome, FocusScopeError] {
  self.busy.val = true
  self.violated.val = false
  let result = execute_dispatch_plan(plan, callback)
  self.busy.val = false
  if self.violated.val {
    return Err(ReentrantMutation)
  }
  match result {
    Ok(value) => Ok(value)
    Err(error) => Err(focus_scope_element_error(error))
  }
}

///|
/// Route every input family through the active boundary. Pure dispatch leaves
/// the revision unchanged. Dismissal repeats/releases are swallowed globally;
/// consuming the matching release advances revision and retires that guard.
pub fn FocusScopeSession::dispatch_input_with(
  self : FocusScopeSession,
  target : FocusScopeTarget,
  event : @primitives.InputEvent,
  callback : (DispatchContext, @primitives.InputEvent) -> Result[
    Unit,
    ElementError,
  ],
) -> Result[DispatchOutcome, FocusScopeError] {
  match self.validate(target) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let state = self.state.val
  for key in state.closing_keys {
    if event is @primitives.KeyPressed(key=pressed, ..) && pressed == key {
      return self.run_dispatch(empty_dispatch_plan(), context => {
        callback(context, event)
      })
    }
    if event is @primitives.KeyReleased(key=released, ..) && released == key {
      let revision = match focus_scope_revision(state) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      let closing_keys = state.closing_keys.filter(value => value != key)
      self.state.val = { ..state, revision, closing_keys, }
      return self.run_dispatch(empty_dispatch_plan(), context => {
        callback(context, event)
      })
    }
  }
  let plan = focus_scope_route(
    state.tree,
    focus_scope_root(state.scopes),
    state.tree.dispatch_input(event),
  )
  self.run_dispatch(plan, context => callback(context, event))
}

///|
/// Scope admission for an already validated synchronous semantic action. The
/// owner must still perform AccessibilityModel NodeId/action/enabled/loading
/// validation; this neither replaces those checks nor fences external AX.
pub fn FocusScopeSession::dispatch_target_with(
  self : FocusScopeSession,
  target : FocusScopeTarget,
  id : UInt64,
  callback : (DispatchContext) -> Result[Unit, ElementError],
) -> Result[DispatchOutcome, FocusScopeError] {
  match self.validate(target) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let state = self.state.val
  let root = focus_scope_root(state.scopes)
  if !focus_scope_admits(state.tree, root, id) {
    return Err(OutsideScope)
  }
  self.run_dispatch(
    focus_scope_route(state.tree, root, state.tree.dispatch_target(id)),
    callback,
  )
}

///|
/// Resolve scroll offsets only along the truncated modal bubble route. Like
/// ElementTree.scroll_wheel, this does not install offsets or refresh layout.
pub fn FocusScopeSession::scroll_wheel(
  self : FocusScopeSession,
  target : FocusScopeTarget,
  position : @primitives.Point,
  delta_x : Double,
  delta_y : Double,
) -> Result[Array[ScrollViewport], FocusScopeError] {
  match self.validate(target) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let state = self.state.val
  let route = focus_scope_route(
    state.tree,
    focus_scope_root(state.scopes),
    state.tree.dispatch_pointer(position),
  )
  match
    state.tree.scroll_wheel_on_route(position, delta_x, delta_y, route.bubble) {
    Ok(value) => Ok(value)
    Err(error) => Err(Scroll(error))
  }
}

///|
/// Stage bounds from a separately built element tree, preserving this session's
/// focus acquisition, scope stack and non-bounds metadata. Both trees must
/// have the same preorder, parent links and input metadata. Scroll, deferred,
/// anchored, clipped and uniform-list layouts are conservatively unsupported.
/// The root bounds may change, which permits a window resize. No state is
/// published and no host or scene synchronization is implied.
pub fn FocusScopeSession::prepare_bounds_tree(
  self : FocusScopeSession,
  target : FocusScopeTarget,
  tree : ElementTree,
) -> Result[FocusBoundsProposal, FocusScopeError] {
  match self.validate(target) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let state = self.state.val
  let revision = match focus_scope_revision(state) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let old = state.tree.nodes
  let fresh = tree.nodes
  if old.length() == 0 ||
    old.length() != fresh.length() ||
    state.tree.physical_viewport is Some(_) ||
    tree.physical_viewport is Some(_) {
    return Err(Element(LayoutBoundsMismatch))
  }
  let nodes : Array[ElementNode] = []
  for index = 0; index < old.length(); index = index + 1 {
    let a = old[index]
    let b = fresh[index]
    if a.scroll_viewport is Some(_) ||
      b.scroll_viewport is Some(_) ||
      a.uniform_list is Some(_) ||
      b.uniform_list is Some(_) ||
      a.deferred is Some(_) ||
      b.deferred is Some(_) ||
      a.deferred_group is Some(_) ||
      b.deferred_group is Some(_) ||
      a.anchored_after is Some(_) ||
      b.anchored_after is Some(_) ||
      a.window_clip is Some(_) ||
      b.window_clip is Some(_) ||
      a.id != b.id ||
      a.parent != b.parent ||
      a.focusable != b.focusable ||
      a.tab_index != b.tab_index ||
      a.tab_group_index != b.tab_group_index ||
      a.tab_stop != b.tab_stop ||
      a.pointer_events != b.pointer_events {
      return Err(Element(LayoutBoundsMismatch))
    }
    nodes.push({ ..a, bounds: b.bounds, })
  }
  Ok({ target, tree: { ..state.tree, nodes, }, revision, })
}

///|
/// Publish only while the exact original session target is current. This
/// operation performs no callback or layout work. It only commits focus-tree
/// bounds; coordinating other owners remains the caller's responsibility.
pub fn FocusScopeSession::publish_bounds_tree(
  self : FocusScopeSession,
  proposal : FocusBoundsProposal,
) -> Result[Unit, FocusScopeError] {
  match self.validate(proposal.target) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let state = self.state.val
  self.state.val = {
    ..state,
    tree: proposal.tree,
    revision: proposal.revision,
  }
  Ok(())
}

///|
/// Same-topology bounds-only refresh retains every scope and exact acquisition.
pub fn FocusScopeSession::refresh_layout(
  self : FocusScopeSession,
  target : FocusScopeTarget,
  prepainted : Prepainted,
) -> Result[Unit, FocusScopeError] {
  match self.validate(target) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let state = self.state.val
  let revision = match focus_scope_revision(state) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  match state.tree.with_layout_bounds(prepainted) {
    Err(error) => Err(focus_scope_element_error(error))
    Ok(tree) => {
      self.state.val = { ..state, tree, revision, }
      Ok(())
    }
  }
}

///|
fn focus_scope_adopt_suffix(
  state : FocusScopeState,
  adopted : ElementTree,
) -> Result[
  (ElementTree, Array[FocusScopeFrame], Array[UInt64]),
  FocusScopeError,
] {
  let mut first = state.scopes.length()
  for index = 0; index < state.scopes.length(); index = index + 1 {
    if first == state.scopes.length() &&
      adopted.node(state.scopes[index].root) is None {
      first = index
    }
  }
  let scopes : Array[FocusScopeFrame] = []
  for index = 0; index < first; index = index + 1 {
    scopes.push(state.scopes[index])
  }
  let removed : Array[UInt64] = []
  if first == state.scopes.length() {
    return Ok((adopted, scopes, removed))
  }
  let mut tree = adopted
  for index = first; index < state.scopes.length(); index = index + 1 {
    let root = state.scopes[index].root
    removed.push(root)
    if tree.node(root) is Some(_) {
      tree = match tree.without_subtree(root) {
        Ok(value) => value
        Err(error) => return Err(focus_scope_element_error(error))
      }
    }
  }
  let outer = state.scopes[first]
  let tree = match
    focus_scope_restore(tree, scopes, outer.previous, outer.fallback) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  Ok((tree, scopes, removed))
}

///|
/// Adopt a rebuilt tree for this exact revision while keeping the live modal
/// frames. This is frame adoption, not reconciliation: the caller asserts that
/// every retained numeric id denotes the same binding as before. The session
/// lineage is transplanted, so captured restore owners stay valid for surviving
/// ids. A missing scope root revokes that suffix and restores once, in which
/// case `focused` is ignored. Otherwise `focused` is the exact caller-requested
/// acquisition and must be live, focusable and inside the active scope.
pub fn FocusScopeSession::adopt_tree(
  self : FocusScopeSession,
  target : FocusScopeTarget,
  tree : ElementTree,
  focused : UInt64?,
  cancel_interactions : (FocusScopeBoundary) -> Result[Unit, FocusScopeError],
) -> Result[Unit, FocusScopeError] {
  match self.validate(target) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let state = self.state.val
  let revision = match focus_scope_revision(state) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let adopted : ElementTree = {
    nodes: copy_nodes(tree.nodes),
    physical_viewport: tree.physical_viewport,
    focused: None,
    lineage: state.tree.lineage,
    owner: None,
  }
  let (tree, scopes, removed) = match focus_scope_adopt_suffix(state, adopted) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  if removed.length() > 0 {
    return self.publish_boundary(
      { ..state, tree, scopes, revision, },
      Removed,
      removed,
      cancel_interactions,
    )
  }
  let tree = match focused {
    None => tree.clear_focus()
    Some(id) => {
      if !focus_scope_admits(tree, focus_scope_root(scopes), id) {
        return Err(OutsideScope)
      }
      match tree.with_focus(id) {
        Err(error) => return Err(focus_scope_element_error(error))
        Ok(value) => value
      }
    }
  }
  self.state.val = { ..state, tree, scopes, revision, }
  Ok(())
}

///|
fn focus_scope_remove_suffix(
  state : FocusScopeState,
  first : Int32,
  extra : UInt64?,
) -> Result[
  (ElementTree, Array[FocusScopeFrame], Array[UInt64]),
  FocusScopeError,
] {
  let mut tree = state.tree
  let removed : Array[UInt64] = []
  if extra is Some(id) {
    tree = match tree.without_subtree(id) {
      Ok(value) => value
      Err(error) => return Err(focus_scope_element_error(error))
    }
    removed.push(id)
  }
  for index = first; index < state.scopes.length(); index = index + 1 {
    let root = state.scopes[index].root
    if tree.node(root) is Some(_) {
      tree = match tree.without_subtree(root) {
        Ok(value) => value
        Err(error) => return Err(focus_scope_element_error(error))
      }
      removed.push(root)
    }
  }
  let scopes : Array[FocusScopeFrame] = []
  for index = 0; index < first; index = index + 1 {
    scopes.push(state.scopes[index])
  }
  if first < state.scopes.length() {
    let outer = state.scopes[first]
    tree = match
      focus_scope_restore(tree, scopes, outer.previous, outer.fallback) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
  } else if tree.focus_owner() is None && state.tree.focus_owner() is Some(_) {
    tree = match focus_scope_first(tree, focus_scope_root(scopes)) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
  }
  Ok((tree, scopes, removed))
}

///|
/// Destructive modal close: remove this root and every logical child overlay
/// root, revoke that suffix, then restore once from the outermost closed frame.
/// A stale target cannot overwrite caller-requested newer focus. Pass the actual
/// dismissal key to quarantine all subsequent presses until its release.
pub fn FocusScopeSession::close_scope(
  self : FocusScopeSession,
  target : FocusScopeTarget,
  handle : FocusScopeHandle,
  cancel_interactions : (FocusScopeBoundary) -> Result[Unit, FocusScopeError],
  dismissal_key? : @primitives.Key,
) -> Result[Unit, FocusScopeError] {
  match self.validate(target) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  if handle.session != self.identity {
    return Err(ForeignHandle)
  }
  let state = self.state.val
  let mut first = -1
  for index = 0; index < state.scopes.length(); index = index + 1 {
    if state.scopes[index].identity == handle.identity {
      first = index
    }
  }
  if first < 0 {
    return Err(StaleHandle)
  }
  let revision = match focus_scope_revision(state) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let (tree, scopes, removed) = match
    focus_scope_remove_suffix(state, first, None) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let closing_keys = state.closing_keys.copy()
  if dismissal_key is Some(key) && !closing_keys.contains(key) {
    closing_keys.push(key)
  }
  self.publish_boundary(
    { ..state, tree, scopes, revision, closing_keys, },
    Removed,
    removed,
    cancel_interactions,
  )
}

///|
/// Removal of a scope root or its ancestor destroys that logical suffix,
/// including disjoint overlay children. Ordinary focused-child removal keeps
/// the scope and selects its first remaining stop/root, or clears focus.
pub fn FocusScopeSession::remove_subtree(
  self : FocusScopeSession,
  target : FocusScopeTarget,
  id : UInt64,
  cancel_interactions : (FocusScopeBoundary) -> Result[Unit, FocusScopeError],
) -> Result[Unit, FocusScopeError] {
  match self.validate(target) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let state = self.state.val
  if state.tree.node(id) is None {
    return Err(Element(UnknownElement))
  }
  let revision = match focus_scope_revision(state) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let mut first = state.scopes.length()
  for index = 0; index < state.scopes.length(); index = index + 1 {
    if focus_scope_contains(state.tree, id, state.scopes[index].root) {
      first = index
      break
    }
  }
  let (tree, scopes, removed) = match
    focus_scope_remove_suffix(state, first, Some(id)) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  self.publish_boundary(
    { ..state, tree, scopes, revision, },
    Removed,
    removed,
    cancel_interactions,
  )
}

///|
/// Replacement/retyping revokes every modal and prior admission, clears focus,
/// and adopts only a detached tree. This API performs no reconciliation.
pub fn FocusScopeSession::replace_tree(
  self : FocusScopeSession,
  target : FocusScopeTarget,
  tree : ElementTree,
  cancel_interactions : (FocusScopeBoundary) -> Result[Unit, FocusScopeError],
) -> Result[Unit, FocusScopeError] {
  match self.validate(target) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let state = self.state.val
  let revision = match focus_scope_revision(state) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  self.publish_boundary(
    {
      ..state,
      tree: focus_scope_copy_tree(tree.clear_focus()),
      scopes: [],
      revision,
    },
    Replaced,
    state.scopes.map(frame => frame.root),
    cancel_interactions,
  )
}

///|
/// Terminal close revokes all copies. The empty snapshot remains readable;
/// further input, focus, layout and lifecycle mutations return ClosedSession.
pub fn FocusScopeSession::close(
  self : FocusScopeSession,
  target : FocusScopeTarget,
  cancel_interactions : (FocusScopeBoundary) -> Result[Unit, FocusScopeError],
) -> Result[Unit, FocusScopeError] {
  match self.validate(target) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let state = self.state.val
  let revision = match focus_scope_revision(state) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let tree : ElementTree = {
    ..state.tree,
    nodes: [],
    focused: None,
    owner: None,
  }
  self.publish_boundary(
    { ..state, tree, scopes: [], revision, closed: true, },
    Closed,
    state.scopes.map(frame => frame.root),
    cancel_interactions,
  )
}
