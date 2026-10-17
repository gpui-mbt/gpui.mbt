///|
fn[A : Eq] outside_equal(actual : A, expected : A) -> Unit {
  if actual != expected {
    abort("outside equality assertion failed")
  }
}

///|
test "frame snapshots geometry and route before outside callbacks mutate sources" {
  let bounds = match @primitives.Rect::new(0.0, 0.0, 10.0, 10.0) {
    Ok(v) => v
    Err(_) => abort("bounds")
  }
  let far = match @primitives.Rect::new(100.0, 100.0, 10.0, 10.0) {
    Ok(v) => v
    Err(_) => abort("bounds")
  }
  let position = match @primitives.Point::new(5.0, 5.0) {
    Ok(v) => v
    Err(_) => abort("point")
  }
  let tree = match
    ElementTree::new([
      ElementNode::new(1, None, bounds),
      ElementNode::new(2, Some(1), far),
    ]) {
    Ok(v) => v
    Err(_) => abort("tree")
  }
  let frame = match PointerOutsideFrame::new(tree, [2]) {
    Ok(v) => v
    Err(_) => abort("frame")
  }
  tree.nodes[0] = ElementNode::new(1, None, far)
  tree.nodes[1] = ElementNode::new(2, Some(1), bounds)
  let event = @primitives.PointerButtonPressed(
    position~,
    button=@primitives.Primary,
    modifiers=@primitives.Modifiers::new(
      shift=false,
      control=false,
      alt=false,
      meta=false,
    ),
  )
  let result = frame.dispatch_input_with(
    event,
    (context, _) => {
      outside_equal(context.target(), Some(1))
      frame.tree.nodes[0] = ElementNode::new(1, None, far)
      frame.listeners.push(1)
      Ok(())
    },
    (context, _) => {
      outside_equal(context.current_target(), 1)
      Ok(())
    },
  )
  match result {
    Ok(outcome) => {
      outside_equal(outcome.outside_visited(), [2])
      outside_equal(outcome.routed().target(), Some(1))
    }
    Err(_) => abort("dispatch failed")
  }
}
