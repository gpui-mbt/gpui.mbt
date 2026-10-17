///|
fn[A : Eq] outside_equal(actual : A, expected : A) -> Unit {
  if actual != expected {
    abort("outside equality assertion failed")
  }
}

///|
fn outside_true(value : Bool) -> Unit {
  if !value {
    abort("outside assertion failed")
  }
}

///|
fn outside_frame(
  tree : @element.ElementTree,
  ids : Array[UInt64],
) -> @element.PointerOutsideFrame {
  match @element.PointerOutsideFrame::new(tree, ids) {
    Ok(frame) => frame
    Err(_) => abort("valid frame rejected")
  }
}

///|
fn outside_test_tree() -> @element.ElementTree {
  unwrap_tree([
    @element.ElementNode::new(1, None, element_rect(0.0, 0.0, 100.0, 100.0)),
    @element.ElementNode::new(2, Some(1), element_rect(20.0, 20.0, 20.0, 20.0)),
    @element.ElementNode::new(3, Some(1), element_rect(60.0, 60.0, 20.0, 20.0)),
  ])
}

///|
fn outside_down(
  x : Double,
  y : Double,
  button : @primitives.MouseButton,
) -> @primitives.InputEvent {
  @primitives.PointerButtonPressed(
    position=element_point(x, y),
    button~,
    modifiers=@primitives.Modifiers::new(
      shift=false,
      control=false,
      alt=false,
      meta=false,
    ),
  )
}

///|
test "legacy missing outside capability and opt-in any-button capture" {
  let tree = outside_test_tree()
  let frame = outside_frame(tree, [2])
  for button in [@primitives.Primary, @primitives.Secondary, @primitives.Middle] {
    let event = outside_down(90.0, 90.0, button)
    let old = tree.dispatch_input(event)
    outside_equal(old.capture(), [1])
    let calls : Array[UInt64] = []
    let result = frame.dispatch_input_with(
      event,
      (context, received) => {
        outside_true(received == event)
        outside_true(context.phase() == @element.Capture)
        outside_equal(context.target(), Some(1))
        calls.push(context.current_target())
        Ok(())
      },
      (context, _) => {
        calls.push(context.current_target())
        Ok(())
      },
    )
    match result {
      Err(_) => abort("dispatch failed")
      Ok(outcome) => {
        outside_equal(outcome.outside_visited(), [2])
        outside_equal(outcome.routed().capture_visited(), old.capture())
        outside_equal(outcome.routed().bubble_visited(), old.bubble())
      }
    }
    outside_equal(calls, [2, 1, 1])
  }
}

///|
test "up move keyboard never invoke outside-down and legacy routes survive" {
  let tree = outside_test_tree()
  let frame = outside_frame(tree, [2])
  let events = [
    @primitives.PointerButtonReleased(
      position=element_point(90.0, 90.0),
      button=@primitives.Secondary,
      modifiers=@primitives.Modifiers::new(
        shift=false,
        control=false,
        alt=false,
        meta=false,
      ),
    ),
    @primitives.PointerMoved(position=element_point(90.0, 90.0)),
    @primitives.KeyPressed(
      key=@primitives.Escape,
      modifiers=@primitives.Modifiers::new(
        shift=false,
        control=false,
        alt=false,
        meta=false,
      ),
      repeat=false,
    ),
  ]
  for event in events {
    let result = frame.dispatch_input_with(
      event,
      (_, _) => {
        abort("unexpected outside callback")
        Ok(())
      },
      (_, _) => Ok(()),
    )
    match result {
      Err(_) => abort("dispatch failed")
      Ok(outcome) => {
        outside_equal(outcome.outside_visited(), [])
        outside_equal(
          outcome.routed().target(),
          tree.dispatch_input(event).target(),
        )
      }
    }
  }
}

///|
test "raw half-open bounds ignore occlusion and capture can miss every node" {
  let tree = unwrap_tree([
    @element.ElementNode::new(1, None, element_rect(0.0, 0.0, 100.0, 100.0)),
    @element.ElementNode::new(2, Some(1), element_rect(20.0, 20.0, 20.0, 20.0)),
    @element.ElementNode::new(3, Some(1), element_rect(20.0, 20.0, 20.0, 20.0)),
  ])
  let frame = outside_frame(tree, [2])
  for (x, expected) in [(20.0, 0), (39.0, 0), (40.0, 1), (200.0, 1)] {
    let calls = Ref(0)
    let result = frame.dispatch_input_with(
      outside_down(x, 20.0, @primitives.Primary),
      (context, _) => {
        calls.val += 1
        if x == 200.0 {
          outside_equal(context.target(), None)
        }
        Ok(())
      },
      (_, _) => Ok(()),
    )
    outside_true(result is Ok(_))
    outside_equal(calls.val, expected)
  }
}

///|
test "outside capture ordering stop errors and registry validation" {
  let tree = outside_test_tree()
  outside_true(
    @element.PointerOutsideFrame::new(tree, [99])
    is Err(@element.UnknownElement),
  )
  outside_true(
    @element.PointerOutsideFrame::new(tree, [2, 2]) is Err(@element.DuplicateId),
  )
  let frame = outside_frame(tree, [3, 2])
  let event = outside_down(90.0, 90.0, @primitives.Primary)
  let result = frame.dispatch_input_with(
    event,
    (context, _) => {
      context.stop_propagation()
      Ok(())
    },
    (_, _) => {
      abort("normal route after stop")
      Ok(())
    },
  )
  match result {
    Err(_) => abort("dispatch failed")
    Ok(outcome) => {
      outside_equal(outcome.outside_visited(), [2])
      outside_true(outcome.routed().was_stopped())
      outside_equal(outcome.routed().capture_visited(), [])
    }
  }
  let error = match tree.with_focus(99) {
    Err(error) => error
    Ok(_) => abort("missing error")
  }
  let failed = frame.dispatch_input_with(event, (_, _) => Err(error), (_, _) => {
    abort("normal route after error")
    Ok(())
  })
  outside_true(failed is Err(@element.UnknownElement))
}

///|
test "registrations are copied and changes appear only in a new frame" {
  let tree = outside_test_tree()
  let ids : Array[UInt64] = [3]
  let frame = outside_frame(tree, ids)
  ids[0] = 2
  let event = outside_down(90.0, 90.0, @primitives.Secondary)
  let result = frame.dispatch_input_with(
    event,
    (_, _) => {
      ids.push(3)
      Ok(())
    },
    (_, _) => Ok(()),
  )
  match result {
    Ok(outcome) => outside_equal(outcome.outside_visited(), [3])
    Err(_) => abort("dispatch failed")
  }
  let next = outside_frame(tree, ids)
  match next.dispatch_input_with(event, (_, _) => Ok(()), (_, _) => Ok(())) {
    Ok(outcome) => outside_equal(outcome.outside_visited(), [2, 3])
    Err(_) => abort("dispatch failed")
  }
}

///|
test "ordinary stop and retained outside context stop both terminate normal route" {
  let frame = outside_frame(outside_test_tree(), [2])
  let event = outside_down(90.0, 90.0, @primitives.Primary)
  for use_retained in [false, true] {
    let retained : Ref[@element.OutsidePointerContext?] = Ref(None)
    let calls = Ref(0)
    let result = frame.dispatch_input_with(
      event,
      (context, _) => {
        retained.val = Some(context)
        Ok(())
      },
      (context, _) => {
        calls.val += 1
        if use_retained {
          match retained.val {
            Some(outside) => outside.stop_propagation()
            None => abort("missing retained context")
          }
        } else {
          context.stop_propagation()
        }
        Ok(())
      },
    )
    outside_equal(calls.val, 1)
    match result {
      Ok(outcome) => outside_true(outcome.routed().was_stopped())
      Err(_) => abort("dispatch failed")
    }
    match retained.val {
      Some(context) => outside_true(context.is_propagation_stopped())
      None => abort("missing context")
    }
  }
}

///|
test "zero-area registration and pointer-disabled listener remain outside eligible" {
  let tree = unwrap_tree([
    @element.ElementNode::new(1, None, element_rect(0.0, 0.0, 100.0, 100.0)),
    @element.ElementNode::new(2, Some(1), element_rect(20.0, 20.0, 0.0, 0.0)).with_pointer_events(
      false,
    ),
  ])
  let frame = outside_frame(tree, [2])
  match
    frame.dispatch_input_with(
      outside_down(20.0, 20.0, @primitives.Primary),
      (_, _) => Ok(()),
      (_, _) => Ok(()),
    ) {
    Ok(outcome) => outside_equal(outcome.outside_visited(), [2])
    Err(_) => abort("dispatch failed")
  }
}

///|
test "outside capture follows production deferred paint order rather than registration" {
  let rendered = priority_frame([(10, 2), (20, 1)], 1.0)
  let frame = outside_frame(rendered.tree(), [10, 20])
  match
    frame.dispatch_input_with(
      outside_down(300.0, 220.0, @primitives.Primary),
      (_, _) => Ok(()),
      (_, _) => Ok(()),
    ) {
    Ok(outcome) => outside_equal(outcome.outside_visited(), [20, 10])
    Err(_) => abort("dispatch failed")
  }
}
