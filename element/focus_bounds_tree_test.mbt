///|
fn resize_scope_tree(width : Double, focusable : Bool) -> @element.ElementTree {
  unwrap_tree([
    @element.ElementNode::new(1, None, element_rect(0, 0, width, 200)),
    @element.ElementNode::new(2, Some(1), element_rect(0, 0, width / 2.0, 100))
    .with_focusable(focusable)
    .with_tab_stop(true),
    @element.ElementNode::new(
      3,
      Some(1),
      element_rect(width / 2.0, 0, width / 2.0, 100),
    )
    .with_focusable(true)
    .with_tab_stop(true),
  ])
}

///|
test "prepared resized bounds retain acquisition and reject replay" {
  let session = scope_session(resize_scope_tree(100, true))
  scope_ok(session.request_focus(session.target(), 2))
  let before = session.snapshot()
  let owner = before.focus_owner()
  let target = session.target()
  let proposal = scope_ok(
    session.prepare_bounds_tree(target, resize_scope_tree(200, true)),
  )
  assert_true(
    session.snapshot().node(1).unwrap().bounds() == element_rect(0, 0, 100, 200),
  )
  scope_ok(session.publish_bounds_tree(proposal))
  assert_true(
    session.snapshot().node(1).unwrap().bounds() == element_rect(0, 0, 200, 200),
  )
  assert_true(session.snapshot().focus_owner() == owner)
  assert_true(before.node(1).unwrap().bounds() == element_rect(0, 0, 100, 200))
  assert_true(
    session.publish_bounds_tree(proposal) is Err(@element.StaleTarget),
  )
}

///|
test "prepared bounds reject changed focus metadata and stale or foreign owners" {
  let session = scope_session(resize_scope_tree(100, true))
  scope_ok(session.request_focus(session.target(), 2))
  let original = session.snapshot()
  assert_true(
    session.prepare_bounds_tree(session.target(), resize_scope_tree(200, false))
    is Err(_),
  )
  assert_true(session.snapshot().focus_owner() == original.focus_owner())
  let proposal = scope_ok(
    session.prepare_bounds_tree(session.target(), resize_scope_tree(200, true)),
  )
  let other = scope_session(resize_scope_tree(100, true))
  assert_true(
    other.publish_bounds_tree(proposal) is Err(@element.ForeignTarget),
  )
  scope_ok(session.request_focus(session.target(), 3))
  assert_true(
    session.publish_bounds_tree(proposal) is Err(@element.StaleTarget),
  )
  assert_eq(session.focused(), Some(3UL))
  assert_true(
    session.snapshot().node(1).unwrap().bounds() == element_rect(0, 0, 100, 200),
  )
}

///|
test "prepared bounds preserve modal scope and restore handle" {
  let session = scope_session(scope_tree())
  scope_ok(session.request_focus(session.target(), 2))
  let handle = scope_open(session, 10)
  let owner = session.snapshot().focus_owner()
  let count = session.scope_count()
  let candidate = scope_tree()
  let proposal = scope_ok(
    session.prepare_bounds_tree(session.target(), candidate),
  )
  scope_ok(session.publish_bounds_tree(proposal))
  assert_eq(session.scope_count(), count)
  assert_true(session.snapshot().focus_owner() == owner)
  scope_ok(session.close_scope(session.target(), handle, scope_allow))
  assert_eq(session.focused(), Some(2UL))
}
