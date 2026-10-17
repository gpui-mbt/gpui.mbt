///|
// This is an executable host integration fixture. FocusScopeSession gates every
// input before any real Button or DragSession controller sees it. The host owns
// cancellation; ElementTree snapshots alone cannot cancel controller state.
struct ScopeControllerHost {
  scope : @element.FocusScopeSession
  background : Ref[@button.Button]
  modal : Ref[@button.Button]
  drag : @element.DragSession[String]
  root : Ref[UInt64?]
  callbacks : Ref[Int32]
  deliveries : Ref[Int32]
  background_activations : Ref[Int32]
  modal_activations : Ref[Int32]
  drops : Ref[Int32]
  boundaries : Array[@element.FocusScopeBoundary]
  boundary_focus : Array[UInt64?]
}

///|
fn scope_controller_host() -> ScopeControllerHost {
  let background = @button.Button::new(
    2,
    button_test_rect(10, 20, 100, 40),
    "Background action",
  ).unwrap()
  let modal = @button.Button::new(
    11,
    button_test_rect(320, 20, 100, 40),
    "Modal action",
  ).unwrap()
  let tree = @element.ElementTree::new([
      @element.ElementNode::new(1, None, button_test_rect(0, 0, 520, 220)),
      background.element_node(Some(1)),
      @element.ElementNode::new(3, Some(1), button_test_rect(140, 20, 100, 40)),
      @element.ElementNode::new(10, Some(1), button_test_rect(300, 0, 200, 200)),
      modal.element_node(Some(10)),
      @element.ElementNode::new(
        12,
        Some(10),
        button_test_rect(320, 100, 100, 40),
      ),
    ])
    .unwrap()
    .with_focus(2)
    .unwrap()
  {
    scope: @element.FocusScopeSession::new(tree).unwrap(),
    background: Ref(background.with_focus(true)),
    modal: Ref(modal),
    drag: @element.DragSession::new(),
    root: Ref(None),
    callbacks: Ref(0),
    deliveries: Ref(0),
    background_activations: Ref(0),
    modal_activations: Ref(0),
    drops: Ref(0),
    boundaries: [],
    boundary_focus: [],
  }
}

///|
fn ScopeControllerHost::cancel_interactions(
  self : ScopeControllerHost,
  boundary : @element.FocusScopeBoundary,
) -> Result[Unit, @element.FocusScopeError] {
  self.boundaries.push(boundary)
  // Publication is still pending: reading sees the previous committed tree.
  self.boundary_focus.push(self.scope.snapshot().focused())
  self.background.val = self.background.val.cancel_press()
  self.modal.val = self.modal.val.cancel_press()
  let _ = self.drag.cancel()
  Ok(())
}

///|
fn ScopeControllerHost::open(
  self : ScopeControllerHost,
) -> @element.FocusScopeHandle {
  let handle = self.scope
    .open_scope(
      self.scope.target(),
      10,
      boundary => self.cancel_interactions(boundary),
      initial=11,
    )
    .unwrap()
  // Host binding ownership changes only after successful scope publication.
  self.root.val = Some(10)
  handle
}

///|
fn ScopeControllerHost::close(
  self : ScopeControllerHost,
  handle : @element.FocusScopeHandle,
  dismissal_key? : @primitives.Key,
) -> Unit {
  self.scope
  .close_scope(
    self.scope.target(),
    handle,
    boundary => self.cancel_interactions(boundary),
    dismissal_key?,
  )
  .unwrap()
  self.root.val = None
}

///|
fn ScopeControllerHost::dispatch(
  self : ScopeControllerHost,
  event : @primitives.InputEvent,
) -> @element.DispatchOutcome {
  let tree = self.scope.snapshot()
  self.background.val = self.background.val.with_focus(
    tree.focused() == Some(2),
  )
  self.modal.val = self.modal.val.with_focus(tree.focused() == Some(11))
  // Pass only bindings belonging to the currently published scope. A raw
  // DragSession move can advance without hit-testing; never feed it before the
  // scope callback admits an event, even when pointer capture was previously held.
  let sources : Array[@element.DragSource[String]] = []
  let targets : Array[@element.DropTarget[String]] = []
  if self.root.val is None && tree.node(2) is Some(_) {
    sources.push(@element.DragSource::new(2, "background payload"))
  }
  if tree.node(11) is Some(_) {
    sources.push(@element.DragSource::new(11, "modal payload"))
  }
  if self.root.val is None && tree.node(3) is Some(_) {
    targets.push(@element.DropTarget::new(3))
  }
  if tree.node(12) is Some(_) {
    targets.push(@element.DropTarget::new(12))
  }
  self.scope
  .dispatch_input_with(self.scope.target(), event, (context, delivered) => {
    self.callbacks.val += 1
    if context.phase() == @element.EventPhase::Bubble &&
      context.current_target() == context.target() {
      self.deliveries.val += 1
      let drag_outcome = match
        self.drag.dispatch(tree, delivered, sources, targets) {
        Ok(value) => value
        Err(_) => abort("scope-filtered host drag bindings rejected")
      }
      if drag_outcome is @element.Dropped(_, _) {
        self.drops.val += 1
      }
      if context.target() == 2 {
        let (next, input) = self.background.val.handle_input(delivered)
        self.background.val = next
        if input.effect() is @button.Activated {
          self.background_activations.val += 1
        }
      }
      if context.target() == 11 {
        let (next, input) = self.modal.val.handle_input(delivered)
        self.modal.val = next
        if input.effect() is @button.Activated {
          self.modal_activations.val += 1
        }
      }
    }
    Ok(())
  })
  .unwrap()
}

///|
fn scope_controller_move(x : Double, y : Double) -> @primitives.InputEvent {
  @primitives.PointerMoved(position=button_test_point(x, y))
}

///|
fn scope_controller_press(mode : Int32, modal : Bool) -> @primitives.InputEvent {
  if mode == 0 {
    button_test_pointer(true, if modal { 340.0 } else { 30.0 }, 40, true)
  } else {
    button_test_key_down(
      if mode == 1 {
        @primitives.Space
      } else {
        @primitives.Enter
      },
      false,
    )
  }
}

///|
fn scope_controller_release(
  mode : Int32,
  modal : Bool,
) -> @primitives.InputEvent {
  if mode == 0 {
    button_test_pointer(false, if modal { 340.0 } else { 30.0 }, 40, true)
  } else {
    button_test_key_up(
      if mode == 1 {
        @primitives.Space
      } else {
        @primitives.Enter
      },
    )
  }
}

///|
test "scope boundary explicitly cancels real pointer and keyboard Button gestures" {
  // Pointer, Space release activation, and Enter's held-key latch all cross
  // both the open boundary and the modal teardown boundary.
  for mode in [0, 1, 2] {
    let host = scope_controller_host()
    let _ = host.dispatch(scope_controller_press(mode, false))
    assert_true(host.background.val.is_pressed())
    let background_count = host.background_activations.val
    let handle = host.open()
    assert_true(!host.background.val.is_pressed())
    assert_true(host.drag.snapshot() is @element.Idle)
    assert_true(host.scope.snapshot().focused() == Some(11))
    assert_true(host.boundaries[0].kind() is @element.Opened)
    assert_true(host.boundaries[0].previous_root() is None)
    assert_true(host.boundaries[0].next_root() == Some(10))
    assert_eq(host.boundaries[0].removed_roots(), [])
    assert_eq(host.boundary_focus, [Some(2)])
    let _ = host.dispatch(scope_controller_release(mode, false))
    assert_eq(host.background_activations.val, background_count)
    assert_eq(host.modal_activations.val, 0)

    let _ = host.dispatch(scope_controller_press(mode, true))
    assert_true(host.modal.val.is_pressed())
    let modal_count = host.modal_activations.val
    host.close(handle)
    assert_true(!host.modal.val.is_pressed())
    assert_true(host.drag.snapshot() is @element.Idle)
    assert_true(host.scope.snapshot().focused() == Some(2))
    assert_true(host.boundaries[1].kind() is @element.Removed)
    assert_true(host.boundaries[1].previous_root() == Some(10))
    assert_true(host.boundaries[1].next_root() is None)
    assert_eq(host.boundaries[1].removed_roots(), [10])
    assert_true(host.scope.snapshot().node(10) is None)
    assert_true(host.scope.snapshot().node(11) is None)
    assert_eq(host.boundary_focus, [Some(2), Some(11)])
    let _ = host.dispatch(scope_controller_release(mode, false))
    assert_eq(host.background_activations.val, background_count)
    assert_eq(host.modal_activations.val, modal_count)
    assert_eq(host.drops.val, 0)
  }
}

///|
test "scope gate precedes real drag delivery and cancels pending and active sessions" {
  for active in [false, true] {
    let host = scope_controller_host()
    let _ = host.dispatch(button_test_pointer(true, 30, 40, true))
    assert_true(host.drag.snapshot() is @element.Pending(source=2, ..))
    if active {
      let _ = host.dispatch(scope_controller_move(34, 40))
      assert_true(host.drag.snapshot() is @element.Active(source=2, ..))
    }
    let handle = host.open()
    assert_true(host.drag.snapshot() is @element.Idle)
    let callback_count = host.callbacks.val
    let delivery_count = host.deliveries.val
    for
      event in [
        scope_controller_move(150, 40),
        button_test_pointer(false, 150, 40, true),
        button_test_pointer(true, 30, 40, true),
        // This move has no hit at all. It must not reach DragSession, whose
        // active-move branch itself does not need a hit-test target.
        scope_controller_move(900, 900),
      ] {
      let outcome = host.dispatch(event)
      assert_true(outcome.target() is None)
      assert_eq(outcome.capture_visited(), [])
      assert_eq(outcome.bubble_visited(), [])
      assert_eq(host.callbacks.val, callback_count)
      assert_eq(host.deliveries.val, delivery_count)
      assert_true(host.drag.snapshot() is @element.Idle)
    }
    let _ = host.dispatch(scope_controller_move(340, 40))
    assert_true(host.drag.snapshot() is @element.Idle)
    assert_eq(host.deliveries.val, delivery_count + 1)

    let _ = host.dispatch(button_test_pointer(true, 340, 40, true))
    assert_true(host.drag.snapshot() is @element.Pending(source=11, ..))
    if active {
      let _ = host.dispatch(scope_controller_move(344, 40))
      assert_true(host.drag.snapshot() is @element.Active(source=11, ..))
    }
    // Even a live modal drag cannot consume an out-of-scope captured move.
    let before = host.drag.snapshot()
    let callbacks = host.callbacks.val
    let _ = host.dispatch(scope_controller_move(150, 40))
    assert_true(host.drag.snapshot() == before)
    assert_eq(host.callbacks.val, callbacks)
    host.close(handle)
    assert_true(host.drag.snapshot() is @element.Idle)
    let _ = host.dispatch(button_test_pointer(false, 150, 40, true))
    assert_true(host.drag.snapshot() is @element.Idle)
    assert_eq(host.drops.val, 0)
    assert_eq(host.background_activations.val, 0)
    assert_eq(host.modal_activations.val, 0)
  }
}

///|
test "scope dismissal key quarantine survives restoration before Button delivery" {
  for key in [@primitives.Enter, @primitives.Space] {
    let host = scope_controller_host()
    let handle = host.open()
    let _ = host.dispatch(button_test_key_down(key, false))
    assert_true(host.modal.val.is_pressed())
    host.close(handle, dismissal_key=key)
    assert_true(!host.modal.val.is_pressed())
    assert_true(host.scope.snapshot().focused() == Some(2))
    let callbacks = host.callbacks.val
    let deliveries = host.deliveries.val
    // A duplicate down is quarantined too, even when a host labels it fresh.
    for
      event in [
        button_test_key_down(key, true),
        button_test_key_down(key, true),
        button_test_key_down(key, false),
        button_test_key_up(key),
      ] {
      let outcome = host.dispatch(event)
      assert_true(outcome.target() is None)
      assert_eq(outcome.capture_visited(), [])
      assert_eq(outcome.bubble_visited(), [])
      assert_eq(host.callbacks.val, callbacks)
      assert_eq(host.deliveries.val, deliveries)
      assert_true(!host.background.val.is_pressed())
      assert_eq(host.background_activations.val, 0)
    }
    let _ = host.dispatch(button_test_key_down(key, false))
    let _ = host.dispatch(button_test_key_up(key))
    assert_eq(host.background_activations.val, 1)
    assert_true(!host.background.val.is_pressed())
  }
}

///|
test "unreleased native capture simulation rejects scope publication without cancelling controllers" {
  let host = scope_controller_host()
  let _ = host.dispatch(button_test_pointer(true, 30, 40, true))
  let _ = host.dispatch(scope_controller_move(34, 40))
  let target = host.scope.target()
  let owner = host.scope.snapshot().focus_owner()
  let drag = host.drag.snapshot()
  let capture_released = Ref(false)
  let attempts = Ref(0)
  // There is no native capture API here. This flag models a host refusing to
  // publish a scope boundary until its real native-capture teardown succeeds.
  let boundary = boundary => {
    attempts.val += 1
    if !capture_released.val {
      Err(@element.InteractionBoundaryRejected)
    } else {
      host.cancel_interactions(boundary)
    }
  }
  assert_true(
    host.scope.open_scope(target, 10, boundary, initial=11)
    is Err(@element.InteractionBoundaryRejected),
  )
  assert_eq(attempts.val, 1)
  assert_true(host.scope.snapshot().focused() == Some(2))
  assert_true(host.scope.snapshot().focus_owner() == owner)
  assert_true(host.background.val.is_pressed())
  assert_true(host.drag.snapshot() == drag)
  assert_eq(host.boundaries.length(), 0)
  capture_released.val = true
  // Reusing the original target proves failure did not advance the session.
  let handle = host.scope.open_scope(target, 10, boundary, initial=11).unwrap()
  host.root.val = Some(10)
  assert_eq(attempts.val, 2)
  assert_true(!host.background.val.is_pressed())
  assert_true(host.drag.snapshot() is @element.Idle)

  let _ = host.dispatch(button_test_pointer(true, 340, 40, true))
  let _ = host.dispatch(scope_controller_move(344, 40))
  let modal_target = host.scope.target()
  let modal_owner = host.scope.snapshot().focus_owner()
  let modal_drag = host.drag.snapshot()
  capture_released.val = false
  assert_true(
    host.scope.close_scope(modal_target, handle, boundary)
    is Err(@element.InteractionBoundaryRejected),
  )
  assert_true(host.scope.snapshot().focused() == Some(11))
  assert_true(host.scope.snapshot().focus_owner() == modal_owner)
  assert_true(host.modal.val.is_pressed())
  assert_true(host.drag.snapshot() == modal_drag)
  capture_released.val = true
  host.scope.close_scope(modal_target, handle, boundary).unwrap()
  host.root.val = None
  assert_true(host.scope.snapshot().focused() == Some(2))
  assert_true(!host.modal.val.is_pressed())
  assert_true(host.drag.snapshot() is @element.Idle)
}

///|
test "ignored nested scope mutation rejects publication but cannot roll back host cancellation" {
  let host = scope_controller_host()
  let _ = host.dispatch(button_test_pointer(true, 30, 40, true))
  let _ = host.dispatch(scope_controller_move(34, 40))
  let target = host.scope.target()
  let owner = host.scope.snapshot().focus_owner()
  let nested_rejected = Ref(false)
  let result = host.scope.open_scope(
    target,
    10,
    boundary => {
      let _ = host.cancel_interactions(boundary)
      nested_rejected.val = host.scope.request_focus(target, 2)
        is Err(@element.ReentrantMutation)
      // The host incorrectly ignores the nested error. The outer mutation must
      // still reject, but arbitrary controller side effects cannot be undone.
      Ok(())
    },
    initial=11,
  )
  assert_true(nested_rejected.val)
  assert_true(result is Err(@element.ReentrantMutation))
  assert_true(host.scope.snapshot().focused() == Some(2))
  assert_true(host.scope.snapshot().focus_owner() == owner)
  assert_true(!host.background.val.is_pressed())
  assert_true(host.drag.snapshot() is @element.Idle)
  let _ = host.scope
    .open_scope(
      target,
      10,
      boundary => host.cancel_interactions(boundary),
      initial=11,
    )
    .unwrap()
  assert_true(host.scope.snapshot().focused() == Some(11))
}

///|
test "terminal scope teardown cancels real controllers and revokes every copied session" {
  for modal in [false, true] {
    for mode in [0, 1, 2] {
      let host = scope_controller_host()
      if modal {
        let _ = host.open()
      }
      let _ = host.dispatch(scope_controller_press(mode, modal))
      if mode == 0 {
        let _ = host.dispatch(
          scope_controller_move(if modal { 344.0 } else { 34.0 }, 40),
        )
        assert_true(host.drag.snapshot() is @element.Active(..))
      }
      assert_true(
        if modal {
          host.modal.val.is_pressed()
        } else {
          host.background.val.is_pressed()
        },
      )
      let copied_session = host.scope
      let admitted = copied_session.target()
      let callbacks = host.callbacks.val
      host.scope
      .close(admitted, boundary => host.cancel_interactions(boundary))
      .unwrap()
      assert_true(!host.background.val.is_pressed())
      assert_true(!host.modal.val.is_pressed())
      assert_true(host.drag.snapshot() is @element.Idle)
      assert_eq(host.scope.snapshot().nodes().length(), 0)
      assert_true(host.scope.snapshot().focused() is None)
      let boundary = host.boundaries[host.boundaries.length() - 1]
      assert_true(boundary.kind() is @element.Closed)
      assert_true(
        boundary.previous_root() == (if modal { Some(10) } else { None }),
      )
      assert_true(boundary.next_root() is None)
      assert_eq(boundary.removed_roots(), if modal { [10] } else { [] })
      assert_true(
        copied_session.dispatch_input_with(
          admitted,
          scope_controller_release(mode, modal),
          (_, _) => {
            host.callbacks.val += 1
            Ok(())
          },
        )
        is Err(@element.ClosedSession),
      )
      assert_eq(host.callbacks.val, callbacks)
    }
  }
}

///|
test "host cancels owned gestures after an empty scoped release before later inside releases" {
  for active in [false, true] {
    // Cover both an out-of-scope background hit and a release with no tree hit.
    for outside_x in [30.0, 900.0] {
      let host = scope_controller_host()
      let _ = host.open()
      let _ = host.dispatch(button_test_pointer(true, 340, 40, true))
      assert_true(host.modal.val.is_pressed())
      assert_true(host.drag.snapshot() is @element.Pending(source=11, ..))
      if active {
        let _ = host.dispatch(scope_controller_move(344, 40))
        assert_true(host.drag.snapshot() is @element.Active(source=11, ..))
      }
      let before_drag = host.drag.snapshot()
      let callbacks = host.callbacks.val
      let deliveries = host.deliveries.val
      let released = button_test_pointer(false, outside_x, 40, true)
      let outcome = host.dispatch(released)
      assert_true(outcome.target() is None)
      assert_eq(outcome.capture_visited(), [])
      assert_eq(outcome.bubble_visited(), [])
      assert_eq(host.callbacks.val, callbacks)
      assert_eq(host.deliveries.val, deliveries)
      // Empty routing alone cannot clear application-owned gesture state.
      assert_true(host.modal.val.is_pressed())
      assert_true(host.drag.snapshot() == before_drag)
      // The integrating host owns this admitted modal gesture. It observes the
      // undelivered release outcome and explicitly cancels both controllers,
      // without forwarding out-of-scope input around the session's gate.
      if released is @primitives.PointerButtonReleased(..) &&
        outcome.target() is None {
        host.modal.val = host.modal.val.cancel_press()
        assert_true(host.drag.cancel())
      }
      assert_true(!host.modal.val.is_pressed())
      assert_true(host.drag.snapshot() is @element.Idle)
      assert_true(host.scope.snapshot().focused() == Some(11))
      // Try the real drop target first, then the real Button. Neither later
      // in-scope release can revive the cancelled drag or button gesture.
      let drop_release = host.dispatch(
        button_test_pointer(false, 340, 120, true),
      )
      assert_true(drop_release.target() == Some(12))
      let button_release = host.dispatch(
        button_test_pointer(false, 340, 40, true),
      )
      assert_true(button_release.target() == Some(11))
      assert_eq(host.deliveries.val, deliveries + 2)
      assert_eq(host.drops.val, 0)
      assert_eq(host.modal_activations.val, 0)
      assert_eq(host.background_activations.val, 0)
      assert_true(!host.modal.val.is_pressed())
      assert_true(host.drag.snapshot() is @element.Idle)
    }
  }
}
