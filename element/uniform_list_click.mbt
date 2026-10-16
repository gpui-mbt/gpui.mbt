///|
/// One-shot row outcomes from actual current tree routes, never pointer-Y math.
pub enum UniformListClickOutcome {
  Unchanged
  Pressed(index~ : Int32, id~ : UInt64)
  Cancelled
  Clicked(index~ : Int32, id~ : UInt64)
} derive(Eq)

///|
pub extend UniformListClickOutcome with Eq::{not_equal, equal}

///|
priv struct UniformListPress {
  index : Int32
  id : UInt64
  first : UInt64
  stride : UInt64
}

///|
/// Copies share consumption. Call reconcile after every successful fresh frame,
/// including frames with no input: an omitted or count-removed row cancels its
/// pending press, even if a later frame reuses the same numeric ID. A still-live
/// stable row can retain a press while scrolling. Explicitly cancel on logical
/// list/model replacement or changes to what descendant slots represent.
pub struct UniformListClickSession {
  priv list_id : UInt64
  priv pending : Ref[UniformListPress?]
}

///|
pub fn UniformListClickSession::new(
  list_id : UInt64,
) -> UniformListClickSession {
  { list_id, pending: Ref(None), }
}

///|
pub fn UniformListClickSession::cancel(self : UniformListClickSession) -> Bool {
  let changed = self.pending.val is Some(_)
  self.pending.val = None
  changed
}

///|
pub fn UniformListClickSession::reconcile(
  self : UniformListClickSession,
  tree : ElementTree,
) -> Bool {
  match self.pending.val {
    None => false
    Some(press) => {
      let live = match (tree.uniform_list(self.list_id), tree.node(press.id)) {
        (Some(list), Some(row)) =>
          list.spec.ids.first == press.first &&
          list.spec.ids.stride == press.stride &&
          press.index >= list.range.first &&
          press.index < list.range.limit &&
          row.parent == Some(self.list_id) &&
          row.pointer_events &&
          tree.node(self.list_id).unwrap().pointer_events
        _ => false
      }
      if live {
        false
      } else {
        self.cancel()
      }
    }
  }
}

///|
pub fn UniformListClickSession::dispatch(
  self : UniformListClickSession,
  tree : ElementTree,
  event : @primitives.InputEvent,
) -> UniformListClickOutcome {
  let cancelled = self.reconcile(tree)
  match event {
    @primitives.PointerButtonPressed(position~, button=@primitives.Primary, ..) => {
      let old = self.pending.val is Some(_)
      self.pending.val = uniform_routed_row(tree, self.list_id, position)
      match self.pending.val {
        Some(press) => Pressed(index=press.index, id=press.id)
        None => if cancelled || old { Cancelled } else { Unchanged }
      }
    }
    @primitives.PointerButtonReleased(position~, button=@primitives.Primary, ..) => {
      let pressed = self.pending.val
      self.pending.val = None
      match (pressed, uniform_routed_row(tree, self.list_id, position)) {
        (Some(press), Some(released)) if press.id == released.id &&
          press.index == released.index =>
          Clicked(index=press.index, id=press.id)
        (Some(_), _) => Cancelled
        _ => if cancelled { Cancelled } else { Unchanged }
      }
    }
    _ => if cancelled { Cancelled } else { Unchanged }
  }
}

///|
fn uniform_routed_row(
  tree : ElementTree,
  list_id : UInt64,
  position : @primitives.Point,
) -> UniformListPress? {
  let list = match tree.uniform_list(list_id) {
    None => return None
    Some(list) => list
  }
  let list_node = tree.node(list_id).unwrap()
  if !list_node.pointer_events ||
    !pointer_in_bounds(list_node.bounds, position) ||
    !tree.within_scroll_clips(list_node, position) {
    return None
  }
  for id in tree.dispatch_pointer(position).bubble() {
    match tree.node(id) {
      Some(row) if row.parent == Some(list_id) &&
        uniform_contains(list.spec, row.id) &&
        row.pointer_events &&
        pointer_in_bounds(row.bounds, position) => {
        let index = ((id - list.spec.ids.first) / list.spec.ids.stride).to_int()
        if index >= list.range.first &&
          index < list.range.limit &&
          id == list.spec.ids.first + index.to_uint64() * list.spec.ids.stride {
          return Some({
            index,
            id,
            first: list.spec.ids.first,
            stride: list.spec.ids.stride,
          })
        }
      }
      _ => ()
    }
  }
  None
}
