///|
/// Invalid current bindings, unrepresentable activation geometry, or nested
/// dispatch. Every error leaves the session unchanged, even on release.
pub enum DragDispatchError {
  DuplicateSourceBinding(UInt64)
  DuplicateTargetBinding(UInt64)
  UnknownSourceBinding(UInt64)
  UnknownTargetBinding(UInt64)
  CursorOffsetOverflow(UInt64)
  ReentrantDispatch
} derive(Eq)

///|
pub extend DragDispatchError with Eq::{not_equal, equal}

///|
/// A current source value in one homogeneous, compile-time typed channel.
pub struct DragSource[T] {
  priv id : UInt64
  priv payload : T
}

///|
pub fn[T] DragSource::new(id : UInt64, payload : T) -> DragSource[T] {
  { id, payload, }
}

///|
/// A current target. The optional predicate must be pure/read-only. Apply
/// application effects to a returned Dropped outcome after dispatch completes.
pub struct DropTarget[T] {
  priv id : UInt64
  priv can_drop : ((T) -> Bool)?
}

///|
pub fn[T] DropTarget::new(
  id : UInt64,
  can_drop? : (T) -> Bool,
) -> DropTarget[T] {
  { id, can_drop, }
}

///|
/// Detached, non-restorable session view. Payloads are shallow: reference
/// values in T retain their identity, without deep-copy or immutability claims.
/// Pending intentionally contains no payload or latest pointer position.
pub enum DragSnapshot[T] {
  Idle
  Pending(source~ : UInt64, origin~ : @primitives.Point)
  Active(
    source~ : UInt64,
    origin~ : @primitives.Point,
    position~ : @primitives.Point,
    cursor_offset~ : @primitives.Point,
    payload~ : T
  )
} derive(Eq)

///|
pub extend DragSnapshot with Eq::{not_equal, equal}

///|
/// State changes and a one-shot typed drop, not a window repaint scheduler.
pub enum DragDispatchOutcome[T] {
  Unchanged
  Admitted
  Activated
  Moved
  Cancelled
  Rejected(UInt64)
  Dropped(UInt64, T)
} derive(Eq)

///|
pub extend DragDispatchOutcome with Eq::{not_equal, equal}

///|
pub fn[T] DragDispatchOutcome::state_changed(
  self : DragDispatchOutcome[T],
) -> Bool {
  !(self is Unchanged)
}

///|
/// Activation and accepted drops stop this bounded drag route. A rejecting
/// target consumes the attempt without stopping other application input.
pub fn[T] DragDispatchOutcome::was_stopped(
  self : DragDispatchOutcome[T],
) -> Bool {
  self is Activated || self is Dropped(_, _)
}

///|
priv struct DragSessionCell[T] {
  mut state : DragSnapshot[T]
  mut in_predicate : Bool
}

///|
/// One admitted pointer session. Copies share consumption and cancellation;
/// independent new() calls do not. The host owns native pointer capture and
/// explicit lifecycle cancellation before invalidated numeric source IDs are reused.
pub struct DragSession[T] {
  priv cell : Ref[DragSessionCell[T]]
}

///|
pub fn[T] DragSession::new() -> DragSession[T] {
  { cell: Ref({ state: Idle, in_predicate: false, }), }
}

///|
pub fn[T] DragSession::snapshot(self : DragSession[T]) -> DragSnapshot[T] {
  self.cell.val.state
}

///|
/// Clear a pending or active session; return whether its state changed.
pub fn[T] DragSession::cancel(self : DragSession[T]) -> Bool {
  match self.cell.val.state {
    Idle => false
    _ => {
      self.cell.val.state = Idle
      true
    }
  }
}

///|
/// Dispatch current bindings against ElementTree's existing topmost/bubble
/// route, own half-open bounds, pointer enablement, and ancestor scroll clips.
/// This does not implement GPUI's global hitbox/occlusion/native capture system.
///
/// Both binding arrays are structurally copied and completely validated before
/// mutation or predicates. T is not cloned. Registry validation costs
/// O((S+T)N + S² + T²), with O(S+T) snapshot space, plus existing tree routing.
/// All Err values preserve state. In particular, callers must repair/retry an
/// invalid release or explicitly cancel; silently ignoring Err retains it.
pub fn[T] DragSession::dispatch(
  self : DragSession[T],
  tree : ElementTree,
  event : @primitives.InputEvent,
  current_sources : Array[DragSource[T]],
  current_targets : Array[DropTarget[T]],
) -> Result[DragDispatchOutcome[T], DragDispatchError] {
  if self.cell.val.in_predicate {
    return Err(ReentrantDispatch)
  }
  let sources : Array[DragSource[T]] = []
  let targets : Array[DropTarget[T]] = []
  for source in current_sources {
    sources.push(source)
  }
  for target in current_targets {
    targets.push(target)
  }
  for i = 0; i < sources.length(); i = i + 1 {
    for j = 0; j < i; j = j + 1 {
      if sources[j].id == sources[i].id {
        return Err(DuplicateSourceBinding(sources[i].id))
      }
    }
    if tree.node(sources[i].id) is None {
      return Err(UnknownSourceBinding(sources[i].id))
    }
  }
  for i = 0; i < targets.length(); i = i + 1 {
    for j = 0; j < i; j = j + 1 {
      if targets[j].id == targets[i].id {
        return Err(DuplicateTargetBinding(targets[i].id))
      }
    }
    if tree.node(targets[i].id) is None {
      return Err(UnknownTargetBinding(targets[i].id))
    }
  }
  // Missing a live binding is valid; a missing node cancels pending ownership.
  // Do not use focus lineage: normal rerenders create fresh ElementTrees.
  match self.cell.val.state {
    Pending(source~, ..) if tree.node(source) is None => {
      self.cell.val.state = Idle
      return Ok(Cancelled)
    }
    _ => ()
  }
  match event {
    @primitives.PointerButtonPressed(position~, button=@primitives.Primary, ..) => {
      if !(self.cell.val.state is Idle) {
        return Ok(Unchanged)
      }
      for id in tree.dispatch_input(event).bubble() {
        if tree.drag_session_eligible(id, position) {
          for source in sources {
            if source.id == id {
              self.cell.val.state = Pending(source=id, origin=position)
              return Ok(Admitted)
            }
          }
        }
      }
      Ok(Unchanged)
    }
    @primitives.PointerMoved(position~) =>
      match self.cell.val.state {
        Idle => Ok(Unchanged)
        Pending(source~, origin~) => {
          if !drag_session_crossed_threshold(origin, position) {
            return Ok(Unchanged)
          }
          for binding in sources {
            if binding.id == source {
              // Registry validation established this node is live. Resolve its
              // current bounds and payload only at activation, never on press.
              let node = tree.node(source).unwrap()
              let cursor_offset = match
                @primitives.Point::new(
                  position.x() - node.bounds.left(),
                  position.y() - node.bounds.top(),
                ) {
                Err(_) => return Err(CursorOffsetOverflow(source))
                Ok(offset) => offset
              }
              self.cell.val.state = Active(
                source~,
                origin~,
                position~,
                cursor_offset~,
                payload=binding.payload,
              )
              return Ok(Activated)
            }
          }
          Ok(Unchanged)
        }
        Active(source~, origin~, position=previous, cursor_offset~, payload~) => {
          if position == previous {
            return Ok(Unchanged)
          }
          self.cell.val.state = Active(
            source~,
            origin~,
            position~,
            cursor_offset~,
            payload~,
          )
          Ok(Moved)
        }
      }
    @primitives.PointerButtonReleased(position~, ..) =>
      match self.cell.val.state {
        Idle => Ok(Unchanged)
        Pending(..) => {
          self.cell.val.state = Idle
          Ok(Cancelled)
        }
        Active(payload~, ..) => {
          // Finish every selection/validation before consuming or invoking a
          // predicate. The first eligible target consumes even when rejecting.
          let mut selected : DropTarget[T]? = None
          for id in tree.dispatch_input(event).bubble() {
            if selected is None && tree.drag_session_eligible(id, position) {
              for target in targets {
                if target.id == id {
                  selected = Some(target)
                }
              }
            }
          }
          self.cell.val.state = Idle
          match selected {
            None => Ok(Cancelled)
            Some(target) => {
              self.cell.val.in_predicate = true
              let accepted = match target.can_drop {
                None => true
                Some(predicate) => predicate(payload)
              }
              self.cell.val.in_predicate = false
              if accepted {
                Ok(Dropped(target.id, payload))
              } else {
                Ok(Rejected(target.id))
              }
            }
          }
        }
      }
    _ => Ok(Unchanged)
  }
}

///|
fn ElementTree::drag_session_eligible(
  self : ElementTree,
  id : UInt64,
  position : @primitives.Point,
) -> Bool {
  match self.node(id) {
    Some(node) =>
      node.pointer_events &&
      pointer_in_bounds(node.bounds, position) &&
      self.within_scroll_clips(node, position)
    None => false
  }
}

///|
fn drag_session_crossed_threshold(
  origin : @primitives.Point,
  position : @primitives.Point,
) -> Bool {
  // The existing bounded-axis helper avoids overflow, including subtraction
  // between opposite finite extremes. Cap above 2 so exact 2 stays pending.
  let dx = drag_axis_distance(origin.x(), position.x(), 3.0)
  let dy = drag_axis_distance(origin.y(), position.y(), 3.0)
  dx * dx + dy * dy > 4.0
}
