///|
/// Opt-in rendered-frame outside-down registration. This does not change the
/// legacy hit-ancestry dispatcher or reproduce GPUI's general listener order.
pub struct PointerOutsideFrame {
  priv tree : ElementTree
  priv listeners : Array[UInt64]
}

///|
/// Snapshot validated tree geometry and registrations. Registrations are unique
/// element IDs, delivered in stable back-to-front paint order. They are not
/// enabled by hit ancestry, pointer-events, hover, or content clipping.
pub fn PointerOutsideFrame::new(
  tree : ElementTree,
  listeners : Array[UInt64],
) -> Result[PointerOutsideFrame, ElementError] {
  let registered = copy_ids(listeners)
  for index = 0; index < registered.length(); index = index + 1 {
    if tree.node(registered[index]) is None {
      return Err(UnknownElement)
    }
    for previous = 0; previous < index; previous = previous + 1 {
      if registered[previous] == registered[index] {
        return Err(DuplicateId)
      }
    }
  }
  let snapshot : ElementTree = {
    nodes: copy_nodes(tree.nodes),
    physical_viewport: tree.physical_viewport,
    focused: tree.focused,
    lineage: tree.lineage,
    owner: tree.owner,
  }
  let ordered : Array[UInt64] = []
  for index in deferred_paint_indices(snapshot.nodes) {
    let id = snapshot.nodes[index].id
    for registered_id in registered {
      if id == registered_id {
        ordered.push(id)
      }
    }
  }
  Ok({ tree: snapshot, listeners: ordered, })
}

///|
/// Outside capture has no required hit target: a press can miss every node.
pub struct OutsidePointerContext {
  priv target : UInt64?
  priv current_target : UInt64
  priv stopped : Ref[Bool]
}

///|
pub fn OutsidePointerContext::target(self : OutsidePointerContext) -> UInt64? {
  self.target
}

///|
pub fn OutsidePointerContext::current_target(
  self : OutsidePointerContext,
) -> UInt64 {
  self.current_target
}

///|
pub fn OutsidePointerContext::phase(
  _self : OutsidePointerContext,
) -> EventPhase {
  Capture
}

///|
pub fn OutsidePointerContext::stop_propagation(
  self : OutsidePointerContext,
) -> Unit {
  self.stopped.val = true
}

///|
pub fn OutsidePointerContext::is_propagation_stopped(
  self : OutsidePointerContext,
) -> Bool {
  self.stopped.val
}

///|
pub struct OutsideDispatchOutcome {
  priv outside_visited : Array[UInt64]
  priv routed : DispatchOutcome
}

///|
pub fn OutsideDispatchOutcome::outside_visited(
  self : OutsideDispatchOutcome,
) -> Array[UInt64] {
  copy_ids(self.outside_visited)
}

///|
pub fn OutsideDispatchOutcome::routed(
  self : OutsideDispatchOutcome,
) -> DispatchOutcome {
  self.routed
}

///|
/// Deliver any-button outside-down capture, then the legacy normal route.
/// This ordering is a scoped portable contract, not general GPUI phase parity.
/// Both geometry and registry belong to this frame; route and eligible outside
/// listeners are fixed before callbacks. Stop/error prevents all later callbacks.
/// Releases and other events only take the normal route. No click is synthesized.
pub fn PointerOutsideFrame::dispatch_input_with(
  self : PointerOutsideFrame,
  event : @primitives.InputEvent,
  outside : (OutsidePointerContext, @primitives.InputEvent) -> Result[
    Unit,
    ElementError,
  ],
  callback : (DispatchContext, @primitives.InputEvent) -> Result[
    Unit,
    ElementError,
  ],
) -> Result[OutsideDispatchOutcome, ElementError] {
  let plan = self.tree.dispatch_input(event)
  let eligible : Array[UInt64] = []
  match event {
    @primitives.PointerButtonPressed(position~, ..) =>
      for id in self.listeners {
        match self.tree.node(id) {
          Some(node) if !pointer_in_bounds(node.bounds, position) =>
            eligible.push(id)
          _ => ()
        }
      }
    _ => ()
  }
  let stopped = Ref(false)
  let visited : Array[UInt64] = []
  for id in eligible {
    if stopped.val {
      break
    }
    visited.push(id)
    match
      outside({ target: plan.target, current_target: id, stopped, }, event) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
  }
  if stopped.val {
    return Ok({
      outside_visited: visited,
      routed: {
        target: plan.target,
        capture_visited: [],
        bubble_visited: [],
        stopped: true,
      },
    })
  }
  match
    execute_dispatch_plan(plan, context => {
      let result = callback(context, event)
      // Bridge retained outside contexts into the existing executor's stop flag.
      if stopped.val {
        context.stop_propagation()
      }
      if context.is_propagation_stopped() {
        stopped.val = true
      }
      result
    }) {
    Err(error) => Err(error)
    Ok(routed) => Ok({ outside_visited: visited, routed, })
  }
}
