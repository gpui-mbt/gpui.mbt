///|
// Independently authored public-API contracts for the retained modal session.
// These are core contracts, not observations of an upstream browser example.
fn[T] scope_ok(result : Result[T, @element.FocusScopeError]) -> T {
  match result {
    Ok(value) => value
    Err(_) => abort("valid focus-scope operation rejected")
  }
}

///|
fn scope_allow(
  _boundary : @element.FocusScopeBoundary,
) -> Result[Unit, @element.FocusScopeError] {
  Ok(())
}

///|
fn scope_tree() -> @element.ElementTree {
  unwrap_tree([
    @element.ElementNode::new(1, None, element_rect(0, 0, 1000, 200)),
    @element.ElementNode::new(2, Some(1), element_rect(0, 0, 80, 100))
    .with_focusable(true)
    .with_tab_stop(true),
    @element.ElementNode::new(3, Some(1), element_rect(0, 100, 80, 100))
    .with_focusable(true)
    .with_tab_stop(true),
    @element.ElementNode::new(10, Some(1), element_rect(100, 0, 200, 200)).with_focusable(
      true,
    ),
    @element.ElementNode::new(11, Some(10), element_rect(110, 10, 50, 50))
    .with_focusable(true)
    .with_tab_stop(true),
    @element.ElementNode::new(12, Some(10), element_rect(170, 10, 50, 50))
    .with_focusable(true)
    .with_tab_stop(true),
    @element.ElementNode::new(15, Some(10), element_rect(110, 100, 150, 80)).with_focusable(
      true,
    ),
    @element.ElementNode::new(16, Some(15), element_rect(120, 110, 50, 50))
    .with_focusable(true)
    .with_tab_stop(true),
    @element.ElementNode::new(20, Some(1), element_rect(400, 0, 200, 200)).with_focusable(
      true,
    ),
    @element.ElementNode::new(21, Some(20), element_rect(410, 10, 50, 50))
    .with_focusable(true)
    .with_tab_stop(true),
    @element.ElementNode::new(22, Some(20), element_rect(470, 10, 50, 50))
    .with_focusable(true)
    .with_tab_stop(true),
    @element.ElementNode::new(30, Some(1), element_rect(700, 0, 200, 200)).with_focusable(
      true,
    ),
    @element.ElementNode::new(31, Some(30), element_rect(710, 10, 50, 50))
    .with_focusable(true)
    .with_tab_stop(true),
  ])
}

///|
fn scope_session(tree : @element.ElementTree) -> @element.FocusScopeSession {
  scope_ok(@element.FocusScopeSession::new(tree))
}

///|
fn scope_open(
  session : @element.FocusScopeSession,
  root : UInt64,
) -> @element.FocusScopeHandle {
  scope_ok(session.open_scope(session.target(), root, scope_allow))
}

///|
fn scope_walk(
  session : @element.FocusScopeSession,
  count : Int32,
  backward : Bool,
) -> Array[UInt64] {
  let visited = []
  for _index = 0; _index < count; _index = _index + 1 {
    if backward {
      scope_ok(session.focus_prev(session.target()))
    } else {
      scope_ok(session.focus_next(session.target()))
    }
    match session.snapshot().focused() {
      Some(id) => visited.push(id)
      None => abort("focus-scope traversal lost focus")
    }
  }
  visited
}

///|
test "scope traversal keeps signed nested group paths anchors and wrap inside modal" {
  let tree = unwrap_tree([
    group_node(1, None, 0, false),
    group_node(2, Some(1), -2147483648, true),
    group_node(10, Some(1), 0, false),
    group_node(11, Some(10), -4, true),
    group_node(12, Some(10), 0, true),
    group_node(13, Some(10), 0, false),
    group_node(14, Some(10), 5, true),
    group_node(100, Some(10), 6, false).with_tab_group_index(Some(6)),
    group_node(101, Some(100), -1, true),
    group_node(120, Some(100), 9, false).with_tab_group_index(Some(-3)),
    group_node(121, Some(120), -7, true),
    group_node(122, Some(120), 7, true),
    group_node(102, Some(100), 2, true),
    group_node(200, Some(10), 7, false).with_tab_group_index(Some(7)),
    group_node(201, Some(200), 1, true),
    group_node(3, Some(1), 2147483647, true),
  ])
  let session = scope_session(owner_test_focus(tree, 2))
  let _handle = scope_open(session, 10)
  assert_true(session.snapshot().focused() == Some(11))
  assert_true(
    scope_walk(session, 10, false) ==
    [12, 14, 121, 122, 101, 102, 201, 11, 12, 14],
  )
  assert_true(
    scope_walk(session, 10, true) ==
    [12, 11, 201, 102, 101, 122, 121, 14, 12, 11],
  )
  scope_ok(session.request_focus(session.target(), 13))
  assert_true(scope_walk(session, 1, false) == [14])
  scope_ok(session.request_focus(session.target(), 13))
  assert_true(scope_walk(session, 1, true) == [12])
  scope_ok(session.request_focus(session.target(), 100))
  assert_true(scope_walk(session, 1, false) == [201])
  scope_ok(session.request_focus(session.target(), 100))
  assert_true(scope_walk(session, 1, true) == [102])
  assert_true(
    session.request_focus(session.target(), 2) is Err(@element.OutsideScope),
  )
}

///|
test "many scoped acquisitions close back to the exact saved owner once" {
  let before = owner_test_focus(scope_tree(), 2)
  let saved = before.focus_owner()
  let session = scope_session(before)
  let handle = scope_open(session, 10)
  let opened = session.snapshot()
  let _visited = scope_walk(session, 40, false)
  scope_ok(session.request_focus(session.target(), 12))
  let last = session.snapshot().focus_owner()
  assert_true(last != saved)
  scope_ok(session.close_scope(session.target(), handle, scope_allow))
  assert_eq(session.scope_count(), 0)
  assert_true(session.snapshot().focus_owner() == saved)
  assert_true(session.snapshot().node(10) is None)
  assert_true(session.snapshot().node(16) is None)
  assert_true(session.snapshot().node(20) is Some(_))
  assert_true(opened.node(10) is Some(_))
  assert_true(opened.focused() == Some(11))
  assert_true(before.focus_owner() == saved)
  let target = session.target()
  assert_true(
    session.close_scope(target, handle, scope_allow)
    is Err(@element.StaleHandle),
  )
  assert_true(session.snapshot().focus_owner() == saved)
  scope_ok(session.request_focus(target, 3))
  assert_true(session.snapshot().focused() == Some(3))
}

///|
test "nested sibling overlays restore the suspended scope exact acquisition" {
  let session = scope_session(owner_test_focus(scope_tree(), 2))
  let outer = scope_open(session, 10)
  scope_ok(session.request_focus(session.target(), 12))
  let outer_owner = session.snapshot().focus_owner()
  let inner = scope_open(session, 20)
  assert_eq(session.scope_count(), 2)
  assert_true(session.snapshot().focused() == Some(21))
  assert_true(scope_walk(session, 3, false) == [22, 21, 22])
  assert_true(
    session.request_focus(session.target(), 11) is Err(@element.OutsideScope),
  )
  scope_ok(session.close_scope(session.target(), inner, scope_allow))
  assert_eq(session.scope_count(), 1)
  assert_true(session.snapshot().focus_owner() == outer_owner)
  assert_true(session.snapshot().node(20) is None)
  assert_true(session.snapshot().node(10) is Some(_))
  scope_ok(session.close_scope(session.target(), outer, scope_allow))
  assert_true(session.snapshot().focused() == Some(2))
}

///|
test "closing an outer scope removes logical sibling overlay suffix roots" {
  let before = owner_test_focus(scope_tree(), 2)
  let session = scope_session(before)
  let outer = scope_open(session, 10)
  let middle = scope_open(session, 20)
  let inner = scope_open(session, 30)
  let calls = Ref(0)
  scope_ok(
    session.close_scope(session.target(), outer, _boundary => {
      calls.val += 1
      Ok(())
    }),
  )
  assert_eq(calls.val, 1)
  assert_eq(session.scope_count(), 0)
  assert_true(session.snapshot().focus_owner() == before.focus_owner())
  for id in [10UL, 11UL, 20UL, 21UL, 30UL, 31UL] {
    assert_true(session.snapshot().node(id) is None)
  }
  for handle in [outer, middle, inner] {
    assert_true(
      session.close_scope(session.target(), handle, scope_allow)
      is Err(@element.StaleHandle),
    )
  }
}

///|
test "descendant scopes are valid but equal roots and ancestors reject atomically" {
  let session = scope_session(owner_test_focus(scope_tree(), 2))
  let outer = scope_open(session, 10)
  let target = session.target()
  let owner = session.snapshot().focus_owner()
  let calls = Ref(0)
  for root in [1UL, 10UL, 999UL] {
    assert_true(
      session.open_scope(target, root, _boundary => {
        calls.val += 1
        Ok(())
      })
      is Err(@element.InvalidRoot),
    )
  }
  assert_eq(calls.val, 0)
  assert_eq(session.scope_count(), 1)
  assert_true(session.snapshot().focus_owner() == owner)
  let inner = scope_ok(session.open_scope(target, 15, scope_allow))
  assert_true(session.snapshot().focused() == Some(16))
  scope_ok(session.close_scope(session.target(), inner, scope_allow))
  assert_true(session.snapshot().focus_owner() == owner)
  assert_true(session.snapshot().node(15) is None)
  scope_ok(session.close_scope(session.target(), outer, scope_allow))
}

///|
test "invalid initial and fallback handles neither cancel interactions nor publish" {
  let session = scope_session(owner_test_focus(scope_tree(), 2))
  let target = session.target()
  let saved = session.snapshot().focus_owner()
  let calls = Ref(0)
  for initial in [1UL, 2UL, 999UL] {
    assert_true(
      session.open_scope(
        target,
        10,
        _boundary => {
          calls.val += 1
          Ok(())
        },
        initial~,
      )
      is Err(@element.InvalidInitialFocus),
    )
  }
  assert_true(
    session.open_scope(
      target,
      10,
      _boundary => {
        calls.val += 1
        Ok(())
      },
      fallback=999,
    )
    is Err(@element.InvalidFallback),
  )
  assert_eq(calls.val, 0)
  assert_eq(session.scope_count(), 0)
  assert_true(session.snapshot().focus_owner() == saved)
  let _handle = scope_ok(
    session.open_scope(target, 10, scope_allow, initial=12),
  )
  assert_true(session.snapshot().focused() == Some(12))
}

///|
test "no-stop root and singleton traversals preserve current revision and owner" {
  for singleton in [false, true] {
    let tree = unwrap_tree([
      group_node(1, None, 0, false),
      group_node(2, Some(1), 0, true),
      group_node(10, Some(1), 0, false),
      group_node(11, Some(10), 0, singleton),
    ])
    let session = scope_session(owner_test_focus(tree, 2))
    let handle = scope_open(session, 10)
    assert_true(
      session.snapshot().focused() == Some(if singleton { 11UL } else { 10UL }),
    )
    let target = session.target()
    let owner = session.snapshot().focus_owner()
    scope_ok(session.focus_next(target))
    scope_ok(session.focus_prev(target))
    assert_true(session.snapshot().focus_owner() == owner)
    scope_ok(session.close_scope(target, handle, scope_allow))
  }
}

///|
test "session copies share state while snapshots and returned node arrays detach" {
  let input = owner_test_focus(scope_tree(), 2)
  let saved = input.focus_owner()
  let session = scope_session(input)
  let copy = session
  let target = copy.target()
  let snapshot = session.snapshot()
  let nodes = snapshot.nodes()
  nodes.clear()
  let changed = owner_test_focus(snapshot, 3)
  let _handle = scope_open(session, 10)
  assert_eq(copy.scope_count(), 1)
  assert_true(copy.snapshot().focused() == Some(11))
  assert_true(copy.request_focus(target, 12) is Err(@element.StaleTarget))
  assert_true(input.focus_owner() == saved)
  assert_true(snapshot.focus_owner() == saved)
  assert_true(snapshot.node(10) is Some(_))
  assert_true(changed.focused() == Some(3))
  assert_true(copy.snapshot().node(2) is Some(_))
}

///|
test "foreign targets and handles never mutate even sessions made from same tree" {
  let tree = owner_test_focus(scope_tree(), 2)
  let left = scope_session(tree)
  let right = scope_session(tree)
  let foreign_target = left.target()
  let left_handle = scope_open(left, 10)
  let right_handle = scope_open(right, 10)
  let target = right.target()
  let owner = right.snapshot().focus_owner()
  assert_true(
    right.request_focus(foreign_target, 12) is Err(@element.ForeignTarget),
  )
  assert_true(
    right.close_scope(target, left_handle, scope_allow)
    is Err(@element.ForeignHandle),
  )
  assert_true(right.snapshot().focus_owner() == owner)
  assert_eq(right.scope_count(), 1)
  scope_ok(right.close_scope(target, right_handle, scope_allow))
  assert_eq(left.scope_count(), 1)
  assert_true(left.snapshot().node(10) is Some(_))
}

///|
test "all retained mutators reject a stale target before callbacks or publication" {
  let session = scope_session(owner_test_focus(scope_tree(), 2))
  let old = session.target()
  let handle = scope_open(session, 10)
  let owner = session.snapshot().focus_owner()
  let calls = Ref(0)
  let cancel = fn(_boundary) {
    calls.val += 1
    Ok(())
  }
  assert_true(session.request_focus(old, 12) is Err(@element.StaleTarget))
  assert_true(session.focus_next(old) is Err(@element.StaleTarget))
  assert_true(session.focus_prev(old) is Err(@element.StaleTarget))
  assert_true(session.open_scope(old, 20, cancel) is Err(@element.StaleTarget))
  assert_true(
    session.close_scope(old, handle, cancel) is Err(@element.StaleTarget),
  )
  assert_true(
    session.remove_subtree(old, 11, cancel) is Err(@element.StaleTarget),
  )
  assert_true(
    session.replace_tree(old, scope_tree(), cancel) is Err(@element.StaleTarget),
  )
  assert_true(
    session.refresh_layout(old, bounds_frame(380)) is Err(@element.StaleTarget),
  )
  assert_true(session.close(old, cancel) is Err(@element.StaleTarget))
  assert_true(
    session.scroll_wheel(old, element_point(115, 15), 0, 10)
    is Err(@element.StaleTarget),
  )
  assert_true(
    session.dispatch_input_with(old, session_move(115, 15), (_, _) => {
      calls.val += 1
      Ok(())
    })
    is Err(@element.StaleTarget),
  )
  assert_true(
    session.dispatch_target_with(old, 11, _context => {
      calls.val += 1
      Ok(())
    })
    is Err(@element.StaleTarget),
  )
  assert_eq(calls.val, 0)
  assert_true(session.snapshot().focus_owner() == owner)
  assert_eq(session.scope_count(), 1)
}

///|
test "modal input and semantic routes exclude background targets and ancestors" {
  let session = scope_session(owner_test_focus(scope_tree(), 2))
  let _handle = scope_open(session, 10)
  let target = session.target()
  let owner = session.snapshot().focus_owner()
  let keyboard = @primitives.KeyPressed(
    key=@primitives.Tab,
    modifiers=@primitives.Modifiers::none(),
    repeat=false,
  )
  for
    event in [
      session_move(115, 15),
      session_down(115, 15),
      session_up(115, 15),
      @primitives.Scroll(
        position=element_point(115, 15),
        delta=element_point(0, 10),
        modifiers=@primitives.Modifiers::none(),
      ),
      keyboard,
      @primitives.KeyReleased(
        key=@primitives.Enter,
        modifiers=@primitives.Modifiers::none(),
      ),
      @primitives.TextInput(text="modal text"),
    ] {
    let visited : Array[UInt64] = []
    let events : Array[@primitives.InputEvent] = []
    let outcome = scope_ok(
      session.dispatch_input_with(target, event, (context, delivered) => {
        visited.push(context.current_target())
        events.push(delivered)
        Ok(())
      }),
    )
    assert_true(outcome.target() == Some(11))
    assert_true(outcome.capture_visited() == [10, 11])
    assert_true(outcome.bubble_visited() == [11, 10])
    assert_true(visited == [10, 11, 11, 10])
    for delivered in events {
      assert_true(delivered == event)
    }
    assert_true(session.snapshot().focus_owner() == owner)
  }
  let semantic = scope_ok(
    session.dispatch_target_with(target, 16, _context => Ok(())),
  )
  assert_true(semantic.target() == Some(16))
  assert_true(semantic.capture_visited() == [10, 15, 16])
  assert_true(semantic.bubble_visited() == [16, 15, 10])
  let blocked_calls = Ref(0)
  for event in [session_move(10, 10), session_down(415, 15), session_up(10, 10)] {
    let outcome = scope_ok(
      session.dispatch_input_with(target, event, (_, _) => {
        blocked_calls.val += 1
        Ok(())
      }),
    )
    assert_true(outcome.target() is None)
    assert_true(outcome.capture_visited().is_empty())
    assert_true(outcome.bubble_visited().is_empty())
  }
  for id in [1UL, 2UL, 21UL] {
    assert_true(
      session.dispatch_target_with(target, id, _context => {
        blocked_calls.val += 1
        Ok(())
      })
      is Err(@element.OutsideScope),
    )
  }
  assert_eq(blocked_calls.val, 0)
  // Dispatch, including Tab, does not traverse or publish a revision.
  assert_true(session.snapshot().focus_owner() == owner)
  scope_ok(session.request_focus(target, 12))
}

///|
test "only top sibling overlay admits events and capture stop stays dispatch-local" {
  let session = scope_session(owner_test_focus(scope_tree(), 2))
  let _outer = scope_open(session, 10)
  let _inner = scope_open(session, 20)
  let target = session.target()
  let calls = Ref(0)
  let hidden = scope_ok(
    session.dispatch_input_with(target, session_down(115, 15), (_, _) => {
      calls.val += 1
      Ok(())
    }),
  )
  assert_true(hidden.target() is None)
  assert_eq(calls.val, 0)
  let stopped = scope_ok(
    session.dispatch_target_with(target, 21, context => {
      context.stop_propagation()
      Ok(())
    }),
  )
  assert_true(stopped.was_stopped())
  assert_true(stopped.capture_visited() == [20])
  assert_true(stopped.bubble_visited().is_empty())
  let next = scope_ok(
    session.dispatch_target_with(target, 21, _context => Ok(())),
  )
  assert_false(next.was_stopped())
  assert_true(next.capture_visited() == [20, 21])
  assert_true(next.bubble_visited() == [21, 20])
}

///|
test "failed interaction boundary keeps tree owner stack and current target live" {
  let before = owner_test_focus(scope_tree(), 2)
  let session = scope_session(before)
  let target = session.target()
  let calls = Ref(0)
  assert_true(
    session.open_scope(target, 10, _boundary => {
      calls.val += 1
      Err(@element.InteractionBoundaryRejected)
    })
    is Err(@element.InteractionBoundaryRejected),
  )
  assert_eq(calls.val, 1)
  assert_eq(session.scope_count(), 0)
  assert_true(session.snapshot().focus_owner() == before.focus_owner())
  let handle = scope_ok(session.open_scope(target, 10, scope_allow))
  let owner = session.snapshot().focus_owner()
  let target = session.target()
  let reject = fn(_boundary) {
    calls.val += 1
    Err(@element.InteractionBoundaryRejected)
  }
  assert_true(
    session.close_scope(target, handle, reject)
    is Err(@element.InteractionBoundaryRejected),
  )
  assert_true(
    session.remove_subtree(target, 10, reject)
    is Err(@element.InteractionBoundaryRejected),
  )
  assert_true(
    session.replace_tree(target, scope_tree(), reject)
    is Err(@element.InteractionBoundaryRejected),
  )
  assert_true(
    session.close(target, reject) is Err(@element.InteractionBoundaryRejected),
  )
  assert_eq(calls.val, 5)
  assert_eq(session.scope_count(), 1)
  assert_true(session.snapshot().node(10) is Some(_))
  assert_true(session.snapshot().focus_owner() == owner)
  scope_ok(session.close_scope(target, handle, scope_allow))
  assert_true(session.snapshot().focus_owner() == before.focus_owner())
}

///|
test "ignored reentrant mutations poison boundary callbacks without publication" {
  let session = scope_session(owner_test_focus(scope_tree(), 2))
  let target = session.target()
  let owner = session.snapshot().focus_owner()
  let rejected = Ref(false)
  assert_true(
    session.open_scope(target, 10, _boundary => {
      rejected.val = session.request_focus(session.target(), 3)
        is Err(@element.ReentrantMutation)
      Ok(())
    })
    is Err(@element.ReentrantMutation),
  )
  assert_true(rejected.val)
  assert_eq(session.scope_count(), 0)
  assert_true(session.snapshot().focus_owner() == owner)
  let handle = scope_ok(session.open_scope(target, 10, scope_allow))
  let target = session.target()
  let owner = session.snapshot().focus_owner()
  assert_true(
    session.close_scope(target, handle, _boundary => {
      let _ignored = session.remove_subtree(session.target(), 11, scope_allow)
      Ok(())
    })
    is Err(@element.ReentrantMutation),
  )
  assert_eq(session.scope_count(), 1)
  assert_true(session.snapshot().node(11) is Some(_))
  assert_true(session.snapshot().focus_owner() == owner)
  scope_ok(session.close_scope(target, handle, scope_allow))
}

///|
test "input and semantic callbacks cannot hide reentrant focus mutations" {
  let session = scope_session(owner_test_focus(scope_tree(), 2))
  let _handle = scope_open(session, 10)
  let target = session.target()
  let owner = session.snapshot().focus_owner()
  let nested_failed = Ref(false)
  assert_true(
    session.dispatch_input_with(target, session_move(115, 15), (_, _) => {
      nested_failed.val = session.request_focus(session.target(), 12)
        is Err(@element.ReentrantMutation)
      Ok(())
    })
    is Err(@element.ReentrantMutation),
  )
  assert_true(nested_failed.val)
  assert_true(session.snapshot().focus_owner() == owner)
  assert_true(
    session.dispatch_target_with(target, 11, _context => {
      let _ignored = session.focus_next(session.target())
      Ok(())
    })
    is Err(@element.ReentrantMutation),
  )
  assert_true(session.snapshot().focus_owner() == owner)
  assert_true(
    session.dispatch_target_with(target, 11, _context => {
      match session.snapshot().with_focus(1) {
        Err(error) => Err(error)
        Ok(_) => abort("nonfocusable root accepted focus")
      }
    })
    is Err(@element.Element(@element.NotFocusable)),
  )
  // Both callback guards are released after errors.
  let delivered = scope_ok(
    session.dispatch_target_with(target, 11, _context => Ok(())),
  )
  assert_true(delivered.target() == Some(11))
  scope_ok(session.request_focus(target, 12))
}

///|
test "subtree removal repairs focus inside top scope and invalidates old targets" {
  let session = scope_session(owner_test_focus(scope_tree(), 2))
  let handle = scope_open(session, 10)
  scope_ok(session.request_focus(session.target(), 12))
  let owner = session.snapshot().focus_owner()
  let old = session.target()
  scope_ok(session.remove_subtree(old, 11, scope_allow))
  assert_true(session.snapshot().focus_owner() == owner)
  assert_true(session.snapshot().node(11) is None)
  assert_true(
    session.close_scope(old, handle, scope_allow) is Err(@element.StaleTarget),
  )
  scope_ok(session.remove_subtree(session.target(), 12, scope_allow))
  assert_true(session.snapshot().focused() == Some(16))
  scope_ok(session.remove_subtree(session.target(), 15, scope_allow))
  assert_true(session.snapshot().focused() == Some(10))
  scope_ok(session.close_scope(session.target(), handle, scope_allow))
  assert_true(session.snapshot().focused() == Some(2))
}

///|
test "removing a suspended scope root removes its logical sibling child scopes" {
  let before = owner_test_focus(scope_tree(), 2)
  let session = scope_session(before)
  let outer = scope_open(session, 10)
  let inner = scope_open(session, 20)
  scope_ok(session.remove_subtree(session.target(), 10, scope_allow))
  assert_eq(session.scope_count(), 0)
  assert_true(session.snapshot().node(10) is None)
  assert_true(session.snapshot().node(20) is None)
  assert_true(session.snapshot().node(30) is Some(_))
  assert_true(session.snapshot().focus_owner() == before.focus_owner())
  for handle in [outer, inner] {
    assert_true(
      session.close_scope(session.target(), handle, scope_allow)
      is Err(@element.StaleHandle),
    )
  }
}

///|
test "missing saved owner uses explicit fallback then outside first live stop" {
  for explicit_fallback in [false, true] {
    let session = scope_session(owner_test_focus(scope_tree(), 2))
    let handle = if explicit_fallback {
      scope_ok(
        session.open_scope(session.target(), 10, scope_allow, fallback=3),
      )
    } else {
      scope_open(session, 10)
    }
    scope_ok(session.remove_subtree(session.target(), 2, scope_allow))
    scope_ok(session.close_scope(session.target(), handle, scope_allow))
    assert_true(session.snapshot().focused() == Some(3))
    assert_eq(session.scope_count(), 0)
  }
  let session = scope_session(owner_test_focus(scope_tree(), 2))
  let outer = scope_open(session, 10)
  scope_ok(session.request_focus(session.target(), 12))
  let inner = scope_open(session, 20)
  scope_ok(session.remove_subtree(session.target(), 12, scope_allow))
  scope_ok(session.close_scope(session.target(), inner, scope_allow))
  assert_true(session.snapshot().focused() == Some(11))
  scope_ok(session.close_scope(session.target(), outer, scope_allow))
  assert_true(session.snapshot().focused() == Some(2))
}

///|
test "replacement clears modal handles and never revives reused numeric ownership" {
  let original = owner_test_focus(scope_tree(), 2)
  let session = scope_session(original)
  let handle = scope_open(session, 10)
  let old = session.target()
  let replacement = owner_test_focus(scope_tree(), 3)
  let replacement_owner = replacement.focus_owner()
  scope_ok(session.replace_tree(old, replacement, scope_allow))
  assert_eq(session.scope_count(), 0)
  assert_true(session.snapshot().focus_owner() is None)
  assert_true(replacement.focus_owner() == replacement_owner)
  assert_true(session.snapshot().node(10) is Some(_))
  assert_true(session.request_focus(old, 2) is Err(@element.StaleTarget))
  assert_true(
    session.close_scope(session.target(), handle, scope_allow)
    is Err(@element.StaleHandle),
  )
  assert_true(session.snapshot().focus_owner() is None)
  scope_ok(session.request_focus(session.target(), 3))
  let new_owner = session.snapshot().focus_owner()
  assert_true(new_owner != replacement_owner)
  assert_true(new_owner != original.focus_owner())
  let new_handle = scope_open(session, 10)
  scope_ok(session.close_scope(session.target(), new_handle, scope_allow))
  assert_true(session.snapshot().focus_owner() == new_owner)
}

///|
test "bounds refresh preserves scope handle current focus and restoration lineage" {
  let before = owner_test_focus(bounds_frame(378).tree(), 3)
  let session = scope_session(before)
  let handle = scope_open(session, 2)
  let modal_owner = session.snapshot().focus_owner()
  let old = session.target()
  let frozen = session.snapshot()
  scope_ok(session.refresh_layout(old, bounds_frame(380)))
  assert_eq(session.scope_count(), 1)
  assert_true(session.snapshot().focus_owner() == modal_owner)
  assert_true(session.snapshot().hit_test(element_point(395, 20)) == Some(2))
  assert_true(frozen.hit_test(element_point(395, 20)) == Some(1))
  assert_true(session.focus_next(old) is Err(@element.StaleTarget))
  let target = session.target()
  assert_true(
    session.refresh_layout(
      target,
      viewport_prepaint(
        @element.Element::root(
          999,
          @layout.FlexTreeStyle::new(@layout.FlowDirection::row()),
        ),
        800,
        40,
      ),
    )
    is Err(_),
  )
  assert_true(session.snapshot().focus_owner() == modal_owner)
  scope_ok(session.close_scope(target, handle, scope_allow))
  assert_true(session.snapshot().focus_owner() == before.focus_owner())
}

///|
test "closed sessions reject retained targets handles dispatch and further mutation" {
  let session = scope_session(owner_test_focus(scope_tree(), 2))
  let handle = scope_open(session, 10)
  let old = session.target()
  let calls = Ref(0)
  scope_ok(
    session.close(old, _boundary => {
      calls.val += 1
      Ok(())
    }),
  )
  assert_eq(calls.val, 1)
  assert_eq(session.scope_count(), 0)
  let target = session.target()
  assert_true(session.request_focus(target, 2) is Err(@element.ClosedSession))
  assert_true(session.focus_next(target) is Err(@element.ClosedSession))
  assert_true(session.focus_prev(target) is Err(@element.ClosedSession))
  assert_true(
    session.open_scope(target, 20, scope_allow) is Err(@element.ClosedSession),
  )
  assert_true(
    session.close_scope(target, handle, scope_allow)
    is Err(@element.ClosedSession),
  )
  assert_true(session.close(target, scope_allow) is Err(@element.ClosedSession))
  assert_true(
    session.dispatch_input_with(target, session_down(10, 10), (_, _) => {
      calls.val += 1
      Ok(())
    })
    is Err(@element.ClosedSession),
  )
  assert_true(
    session.dispatch_target_with(target, 2, _context => {
      calls.val += 1
      Ok(())
    })
    is Err(@element.ClosedSession),
  )
  assert_eq(calls.val, 1)
}

///|
test "modal scroll wheel truncates nested viewport ancestors and does not publish" {
  let before = viewport_prepaint(viewport_nested(20, 30, 10), 100, 100).tree()
  let ordinary = before.scroll_wheel(element_point(10, 30), 0, 10).unwrap()
  assert_true(ordinary.map(viewport => viewport.id()) == [4, 1])
  let session = scope_session(before)
  let _outer = scope_ok(
    session.open_scope(session.target(), 4, scope_allow, initial=5),
  )
  let target = session.target()
  let owner = session.snapshot().focus_owner()
  let updates = scope_ok(
    session.scroll_wheel(target, element_point(10, 30), 0, 10),
  )
  assert_true(updates.map(viewport => viewport.id()) == [4])
  assert_true(updates[0].offset() == element_point(30, 20))
  assert_true(
    viewport_of(session.snapshot(), 4).offset() == element_point(30, 10),
  )
  assert_true(
    viewport_of(session.snapshot(), 1).offset() == element_point(0, 20),
  )
  assert_true(session.snapshot().focus_owner() == owner)
  updates.clear()
  assert_eq(
    scope_ok(session.scroll_wheel(target, element_point(10, 30), 0, 10)).length(),
    1,
  )
  assert_true(
    scope_ok(session.scroll_wheel(target, element_point(10, 10), 0, 10)).is_empty(),
  )
  assert_true(
    session.scroll_wheel(target, element_point(10, 30), @double.infinity, 0)
    is Err(@element.Scroll(@element.NonFiniteValue)),
  )
  let _inner = scope_ok(session.open_scope(target, 5, scope_allow))
  // A pointer target inside the modal must not scroll either outside ancestor.
  assert_true(
    scope_ok(
      session.scroll_wheel(session.target(), element_point(10, 30), 0, 10),
    ).is_empty(),
  )
}

///|
test "scope capacity rejects the thirty third open before hook and publication" {
  let nodes = [group_node(1, None, 0, false), group_node(2, Some(1), 0, true)]
  for index = 0; index < 33; index = index + 1 {
    nodes.push(group_node(index.to_uint64() + 10, Some(1), 0, true))
  }
  let before = owner_test_focus(unwrap_tree(nodes), 2)
  let session = scope_session(before)
  let handles : Array[@element.FocusScopeHandle] = []
  let calls = Ref(0)
  let cancel = fn(_boundary) {
    calls.val += 1
    Ok(())
  }
  for index = 0; index < 32; index = index + 1 {
    handles.push(
      scope_ok(
        session.open_scope(session.target(), index.to_uint64() + 10, cancel),
      ),
    )
  }
  assert_eq(session.scope_count(), 32)
  assert_eq(calls.val, 32)
  let target = session.target()
  let owner = session.snapshot().focus_owner()
  assert_true(
    session.open_scope(target, 42, cancel) is Err(@element.StackLimit),
  )
  assert_eq(calls.val, 32)
  assert_eq(session.scope_count(), 32)
  assert_true(session.snapshot().focus_owner() == owner)
  scope_ok(session.close_scope(target, handles[0], cancel))
  assert_eq(calls.val, 33)
  assert_eq(session.scope_count(), 0)
  assert_true(session.snapshot().focus_owner() == before.focus_owner())
  assert_true(session.snapshot().node(42) is Some(_))
}

///|
test "boundary hooks observe unpublished state and detached removal root arrays" {
  let session = scope_session(owner_test_focus(scope_tree(), 2))
  let boundaries : Array[@element.FocusScopeBoundary] = []
  let counts : Array[Int32] = []
  let focused : Array[UInt64?] = []
  let cancel = fn(boundary) {
    boundaries.push(boundary)
    counts.push(session.scope_count())
    focused.push(session.snapshot().focused())
    Ok(())
  }
  let outer = scope_ok(session.open_scope(session.target(), 10, cancel))
  let _inner = scope_ok(session.open_scope(session.target(), 20, cancel))
  scope_ok(session.close_scope(session.target(), outer, cancel))
  assert_true(counts == [0, 1, 2])
  assert_true(focused == [Some(2), Some(11), Some(21)])
  assert_true(boundaries[0].kind() == @element.Opened)
  assert_true(boundaries[0].previous_root() is None)
  assert_true(boundaries[0].next_root() == Some(10))
  assert_true(boundaries[0].removed_roots().is_empty())
  assert_true(boundaries[1].previous_root() == Some(10))
  assert_true(boundaries[1].next_root() == Some(20))
  assert_true(boundaries[2].kind() == @element.Removed)
  assert_true(boundaries[2].previous_root() == Some(20))
  assert_true(boundaries[2].next_root() is None)
  assert_true(boundaries[2].removed_roots() == [10, 20])
  let exposed = boundaries[2].removed_roots()
  exposed.clear()
  assert_true(boundaries[2].removed_roots() == [10, 20])
  scope_ok(session.replace_tree(session.target(), scope_tree(), cancel))
  assert_true(boundaries[3].kind() == @element.Replaced)
  assert_true(boundaries[3].previous_root() is None)
  assert_true(boundaries[3].next_root() is None)
  scope_ok(session.close(session.target(), cancel))
  assert_true(boundaries[4].kind() == @element.Closed)
  assert_true(session.snapshot().nodes().is_empty())
}

///|
test "dismissal quarantine swallows fresh and repeat presses until matching release" {
  let session = scope_session(owner_test_focus(scope_tree(), 2))
  let handle = scope_open(session, 10)
  scope_ok(
    session.close_scope(
      session.target(),
      handle,
      scope_allow,
      dismissal_key=@primitives.Escape,
    ),
  )
  let next = scope_open(session, 20)
  scope_ok(
    session.close_scope(
      session.target(),
      next,
      scope_allow,
      dismissal_key=@primitives.Enter,
    ),
  )
  let target = session.target()
  let owner = session.snapshot().focus_owner()
  let calls = Ref(0)
  let count = fn(_context, _event) {
    calls.val += 1
    Ok(())
  }
  for key in [@primitives.Escape, @primitives.Enter] {
    for repeat in [false, true] {
      let event = @primitives.KeyPressed(
        key~,
        modifiers=@primitives.Modifiers::new(
          shift=true,
          control=true,
          alt=false,
          meta=false,
        ),
        repeat~,
      )
      let outcome = scope_ok(session.dispatch_input_with(target, event, count))
      assert_true(outcome.target() is None)
      assert_true(session.target() == target)
    }
  }
  assert_eq(calls.val, 0)
  let other = scope_ok(
    session.dispatch_input_with(
      target,
      @primitives.KeyPressed(
        key=@primitives.Space,
        modifiers=@primitives.Modifiers::none(),
        repeat=true,
      ),
      count,
    ),
  )
  assert_true(other.target() == Some(2))
  assert_eq(calls.val, 4)
  let release = scope_ok(
    session.dispatch_input_with(
      target,
      @primitives.KeyReleased(
        key=@primitives.Escape,
        modifiers=@primitives.Modifiers::none(),
      ),
      count,
    ),
  )
  assert_true(release.target() is None)
  assert_eq(calls.val, 4)
  assert_true(session.snapshot().focus_owner() == owner)
  assert_true(session.target() != target)
  assert_true(
    session.dispatch_input_with(target, session_move(10, 10), count)
    is Err(@element.StaleTarget),
  )
  let target = session.target()
  let escape = scope_ok(
    session.dispatch_input_with(
      target,
      @primitives.KeyPressed(
        key=@primitives.Escape,
        modifiers=@primitives.Modifiers::none(),
        repeat=false,
      ),
      count,
    ),
  )
  assert_true(escape.target() == Some(2))
  assert_eq(calls.val, 8)
  let enter = scope_ok(
    session.dispatch_input_with(
      target,
      @primitives.KeyPressed(
        key=@primitives.Enter,
        modifiers=@primitives.Modifiers::none(),
        repeat=true,
      ),
      count,
    ),
  )
  assert_true(enter.target() is None)
  assert_eq(calls.val, 8)
  let _release = scope_ok(
    session.dispatch_input_with(
      target,
      @primitives.KeyReleased(
        key=@primitives.Enter,
        modifiers=@primitives.Modifiers::none(),
      ),
      count,
    ),
  )
  assert_true(session.target() != target)
  let enter = scope_ok(
    session.dispatch_input_with(
      session.target(),
      @primitives.KeyPressed(
        key=@primitives.Enter,
        modifiers=@primitives.Modifiers::none(),
        repeat=false,
      ),
      count,
    ),
  )
  assert_true(enter.target() == Some(2))
  assert_eq(calls.val, 12)
}

///|
test "explicit resumed fallback beats first stop but invalid scoped fallbacks reject" {
  let session = scope_session(owner_test_focus(scope_tree(), 2))
  let _outer = scope_open(session, 10)
  scope_ok(session.request_focus(session.target(), 12))
  let target = session.target()
  for fallback in [3UL, 21UL, 999UL] {
    assert_true(
      session.open_scope(target, 20, scope_allow, fallback~)
      is Err(@element.InvalidFallback),
    )
  }
  let inner = scope_ok(session.open_scope(target, 20, scope_allow, fallback=10))
  scope_ok(session.remove_subtree(session.target(), 12, scope_allow))
  scope_ok(session.close_scope(session.target(), inner, scope_allow))
  assert_true(session.snapshot().focused() == Some(10))
  assert_true(scope_walk(session, 1, false) == [11])
}

///|
test "empty restoration clears focus and root without focus destination rejects open" {
  let session = scope_session(
    unwrap_tree([
      group_node(10, None, 0, false),
      group_node(11, Some(10), 0, true),
    ]),
  )
  let handle = scope_open(session, 10)
  scope_ok(session.close_scope(session.target(), handle, scope_allow))
  assert_true(session.snapshot().focused() is None)
  assert_true(session.snapshot().focus_owner() is None)
  assert_true(session.snapshot().nodes().is_empty())
  let session = scope_session(
    unwrap_tree([
      group_node(10, None, 0, false).with_focusable(false),
      group_node(11, Some(10), 0, true).with_focusable(false),
    ]),
  )
  let target = session.target()
  assert_true(
    session.open_scope(target, 10, scope_allow)
    is Err(@element.InvalidInitialFocus),
  )
  assert_true(
    session.open_scope(target, 10, scope_allow, initial=11)
    is Err(@element.InvalidInitialFocus),
  )
  assert_eq(session.scope_count(), 0)
  assert_true(session.target() == target)
}

///|
test "same-id focus reacquisition invalidates cleanup without losing the newer owner" {
  let before = owner_test_focus(scope_tree(), 2)
  let session = scope_session(before)
  let handle = scope_open(session, 10)
  let old_target = session.target()
  let old_owner = session.snapshot().focus_owner()
  scope_ok(session.request_focus(old_target, 11))
  let new_owner = session.snapshot().focus_owner()
  assert_true(new_owner != old_owner)
  assert_true(session.target() != old_target)
  let calls = Ref(0)
  assert_true(
    session.close_scope(old_target, handle, _boundary => {
      calls.val += 1
      Ok(())
    })
    is Err(@element.StaleTarget),
  )
  assert_eq(calls.val, 0)
  assert_true(session.snapshot().focus_owner() == new_owner)
  assert_true(session.snapshot().node(10) is Some(_))
  scope_ok(session.close_scope(session.target(), handle, scope_allow))
  assert_true(session.snapshot().focus_owner() == before.focus_owner())
}

///|
test "closing a middle overlay removes its suffix and restores surviving outer scope" {
  let session = scope_session(owner_test_focus(scope_tree(), 2))
  let outer = scope_open(session, 10)
  scope_ok(session.request_focus(session.target(), 12))
  let saved = session.snapshot().focus_owner()
  let middle = scope_open(session, 20)
  let inner = scope_open(session, 30)
  scope_ok(session.close_scope(session.target(), middle, scope_allow))
  assert_eq(session.scope_count(), 1)
  assert_true(session.snapshot().focus_owner() == saved)
  assert_true(session.snapshot().node(10) is Some(_))
  assert_true(session.snapshot().node(20) is None)
  assert_true(session.snapshot().node(30) is None)
  assert_true(
    session.close_scope(session.target(), inner, scope_allow)
    is Err(@element.StaleHandle),
  )
  assert_true(scope_walk(session, 1, false) == [16])
  scope_ok(session.close_scope(session.target(), outer, scope_allow))
  assert_true(session.snapshot().focused() == Some(2))
}

///|
test "outside explicit fallback precedes the otherwise earlier surviving tab stop" {
  let session = scope_session(owner_test_focus(scope_tree(), 3))
  let handle = scope_ok(
    session.open_scope(session.target(), 10, scope_allow, fallback=31),
  )
  scope_ok(session.remove_subtree(session.target(), 3, scope_allow))
  scope_ok(session.close_scope(session.target(), handle, scope_allow))
  assert_true(session.snapshot().node(2) is Some(_))
  assert_true(session.snapshot().focused() == Some(31))
}

///|
test "removing explicit fallback leaves modal live then chooses surviving outside stop" {
  let session = scope_session(owner_test_focus(scope_tree(), 3))
  let handle = scope_ok(
    session.open_scope(session.target(), 10, scope_allow, fallback=31),
  )
  let owner = session.snapshot().focus_owner()
  scope_ok(session.remove_subtree(session.target(), 3, scope_allow))
  scope_ok(session.remove_subtree(session.target(), 30, scope_allow))
  assert_eq(session.scope_count(), 1)
  assert_true(session.snapshot().focus_owner() == owner)
  scope_ok(session.close_scope(session.target(), handle, scope_allow))
  assert_true(session.snapshot().focused() == Some(2))
  assert_eq(session.scope_count(), 0)
}

///|
test "live exact previous owner takes precedence over a different live explicit fallback" {
  let tree = owner_test_focus(scope_tree(), 2)
  let session = scope_session(tree)
  let handle = scope_ok(
    session.open_scope(session.target(), 10, scope_allow, fallback=31),
  )
  let _visited = scope_walk(session, 9, false)
  scope_ok(session.close_scope(session.target(), handle, scope_allow))
  assert_true(session.snapshot().focus_owner() == tree.focus_owner())
  assert_true(session.snapshot().focused() == Some(2))
  assert_true(session.snapshot().node(31) is Some(_))
}

///|
fn scope_adopted_tree() -> @element.ElementTree {
  unwrap_tree([
    @element.ElementNode::new(1, None, element_rect(0, 0, 1000, 240)),
    @element.ElementNode::new(2, Some(1), element_rect(0, 0, 80, 120))
    .with_focusable(true)
    .with_tab_stop(true),
    @element.ElementNode::new(3, Some(1), element_rect(0, 120, 80, 120))
    .with_focusable(true)
    .with_tab_stop(true),
    @element.ElementNode::new(10, Some(1), element_rect(100, 0, 200, 240)).with_focusable(
      true,
    ),
    @element.ElementNode::new(11, Some(10), element_rect(110, 10, 50, 60))
    .with_focusable(true)
    .with_tab_stop(true),
    @element.ElementNode::new(12, Some(10), element_rect(170, 10, 50, 60))
    .with_focusable(true)
    .with_tab_stop(true),
    @element.ElementNode::new(15, Some(10), element_rect(110, 120, 150, 90)).with_focusable(
      true,
    ),
    @element.ElementNode::new(16, Some(15), element_rect(120, 130, 50, 60))
    .with_focusable(true)
    .with_tab_stop(true),
    @element.ElementNode::new(20, Some(1), element_rect(400, 0, 200, 240)).with_focusable(
      true,
    ),
    @element.ElementNode::new(21, Some(20), element_rect(410, 10, 50, 60))
    .with_focusable(true)
    .with_tab_stop(true),
    @element.ElementNode::new(22, Some(20), element_rect(470, 10, 50, 60))
    .with_focusable(true)
    .with_tab_stop(true),
    @element.ElementNode::new(30, Some(1), element_rect(700, 0, 200, 240)).with_focusable(
      true,
    ),
    @element.ElementNode::new(31, Some(30), element_rect(710, 10, 50, 60))
    .with_focusable(true)
    .with_tab_stop(true),
  ])
}

///|
fn scope_adopt_without(removed : Array[UInt64]) -> @element.ElementTree {
  let kept = []
  for node in scope_adopted_tree().nodes() {
    if !removed.contains(node.id()) {
      kept.push(node)
    }
  }
  unwrap_tree(kept)
}

///|
test "adoption keeps modal frames exact owners and rebuilt geometry" {
  let before = owner_test_focus(scope_tree(), 2)
  let saved = before.focus_owner()
  let session = scope_session(before)
  let handle = scope_open(session, 10)
  scope_ok(session.request_focus(session.target(), 12))
  scope_ok(
    session.adopt_tree(
      session.target(),
      scope_adopted_tree(),
      Some(12),
      scope_allow,
    ),
  )
  assert_eq(session.scope_count(), 1)
  assert_true(session.focused() == Some(12))
  assert_true(
    session.snapshot().node(11) is Some(node) &&
    node.bounds().left() == 110.0 &&
    node.bounds().size().height() == 60.0,
  )
  scope_ok(session.close_scope(session.target(), handle, scope_allow))
  assert_eq(session.scope_count(), 0)
  assert_true(session.snapshot().focus_owner() == saved)
  assert_true(session.snapshot().node(10) is None)
  assert_true(session.snapshot().node(2) is Some(_))
}

///|
test "adoption rejects background focus and a stale revision without publishing" {
  let session = scope_session(owner_test_focus(scope_tree(), 2))
  let handle = scope_open(session, 10)
  let target = session.target()
  assert_true(
    session.adopt_tree(target, scope_adopted_tree(), Some(2), scope_allow)
    is Err(@element.OutsideScope),
  )
  assert_true(session.focused() == Some(11))
  assert_true(
    session.snapshot().node(11) is Some(node) &&
    node.bounds().size().height() == 50.0,
  )
  scope_ok(
    session.adopt_tree(
      session.target(),
      scope_adopted_tree(),
      Some(12),
      scope_allow,
    ),
  )
  assert_true(
    session.adopt_tree(target, scope_adopted_tree(), Some(11), scope_allow)
    is Err(@element.StaleTarget),
  )
  assert_true(session.focused() == Some(12))
  scope_ok(session.close_scope(session.target(), handle, scope_allow))
}

///|
test "adoption without a frame applies only the requested acquisition" {
  let session = scope_session(owner_test_focus(scope_tree(), 2))
  scope_ok(
    session.adopt_tree(
      session.target(),
      scope_adopted_tree(),
      Some(3),
      scope_allow,
    ),
  )
  assert_true(session.focused() == Some(3))
  scope_ok(
    session.adopt_tree(
      session.target(),
      scope_adopted_tree(),
      None,
      scope_allow,
    ),
  )
  assert_true(session.focused() is None)
  assert_true(session.snapshot().node(3) is Some(_))
}

///|
test "adoption of a tree without its scope root revokes the suffix once and restores" {
  let before = owner_test_focus(scope_tree(), 2)
  let saved = before.focus_owner()
  let session = scope_session(before)
  let handle = scope_open(session, 10)
  scope_ok(session.request_focus(session.target(), 12))
  let without = scope_adopt_without([10UL, 11UL, 12UL, 15UL, 16UL])
  let calls = Ref(0)
  let receipt : Ref[@element.FocusScopeBoundary?] = Ref(None)
  scope_ok(
    session.adopt_tree(session.target(), without, Some(20), boundary => {
      calls.val += 1
      receipt.val = Some(boundary)
      Ok(())
    }),
  )
  assert_eq(calls.val, 1)
  assert_eq(session.scope_count(), 0)
  assert_true(session.snapshot().focus_owner() == saved)
  assert_true(session.snapshot().node(10) is None)
  let boundary = receipt.val.unwrap()
  assert_true(boundary.kind() is @element.Removed)
  assert_true(boundary.removed_roots() == [10UL])
  assert_true(boundary.previous_root() == Some(10UL))
  assert_true(boundary.next_root() is None)
  assert_true(
    session.close_scope(session.target(), handle, scope_allow)
    is Err(@element.StaleHandle),
  )
}

///|
test "adoption revokes nested suffix roots and keeps the outer frame" {
  let session = scope_session(owner_test_focus(scope_tree(), 2))
  let outer = scope_open(session, 10)
  scope_ok(session.request_focus(session.target(), 12))
  let inner = scope_open(session, 20)
  assert_true(session.focused() == Some(21))
  let without = scope_adopt_without([20UL, 21UL, 22UL])
  scope_ok(session.adopt_tree(session.target(), without, None, scope_allow))
  assert_eq(session.scope_count(), 1)
  assert_true(session.focused() == Some(12))
  assert_true(session.snapshot().node(20) is None)
  assert_true(
    session.close_scope(session.target(), inner, scope_allow)
    is Err(@element.StaleHandle),
  )
  scope_ok(session.close_scope(session.target(), outer, scope_allow))
}

///|
test "adoption removal hook reentry rejects publication" {
  let session = scope_session(owner_test_focus(scope_tree(), 2))
  let handle = scope_open(session, 10)
  scope_ok(session.request_focus(session.target(), 12))
  let without = scope_adopt_without([10UL, 11UL, 12UL, 15UL, 16UL])
  assert_true(
    session.adopt_tree(session.target(), without, None, _boundary => {
      ignore(session.request_focus(session.target(), 2))
      Ok(())
    })
    is Err(@element.ReentrantMutation),
  )
  assert_eq(session.scope_count(), 1)
  assert_true(session.focused() == Some(12))
  scope_ok(session.close_scope(session.target(), handle, scope_allow))
}

///|
test "clearing focus keeps modal frames and is idempotent" {
  let before = owner_test_focus(scope_tree(), 2)
  let saved = before.focus_owner()
  let session = scope_session(before)
  let handle = scope_open(session, 10)
  let target = session.target()
  scope_ok(session.clear_focus(target))
  assert_true(session.focused() is None)
  assert_eq(session.scope_count(), 1)
  let after = session.target()
  assert_true(after != target)
  scope_ok(session.clear_focus(after))
  assert_true(session.target() == after)
  scope_ok(session.close_scope(after, handle, scope_allow))
  assert_true(session.snapshot().focus_owner() == saved)
  assert_true(session.focused() == Some(2))
}
