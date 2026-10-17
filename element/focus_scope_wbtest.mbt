///|
fn scope_wb_tree() -> ElementTree {
  let rect = @primitives.Rect::new(0, 0, 100, 100).unwrap()
  ElementTree::new([
    ElementNode::new(1, None, rect).with_focusable(true).with_tab_stop(true),
    ElementNode::new(2, None, rect).with_focusable(true),
    ElementNode::new(3, Some(2), rect).with_focusable(true).with_tab_stop(true),
    ElementNode::new(4, Some(2), rect).with_focusable(true).with_tab_stop(true),
  ])
  .unwrap()
  .with_focus(1)
  .unwrap()
}

///|
test "scope snapshots and input trees cannot mutate authoritative arrays" {
  let original = scope_wb_tree()
  let session = FocusScopeSession::new(original).unwrap()
  let snapshot = session.snapshot()
  original.nodes.clear()
  snapshot.nodes.clear()
  assert_eq(session.snapshot().nodes().length(), 4)
  let detached = session.snapshot().with_focus(3).unwrap()
  assert_true(detached.focused() == Some(3))
  assert_true(session.snapshot().focused() == Some(1))
  assert_true(session.snapshot().focus_owner() == snapshot.focus_owner())
}

///|
test "scope identity exhaustion is atomic and never wraps" {
  let tree = scope_wb_tree()
  let session = FocusScopeSession::new(tree).unwrap()
  let target = session.target()
  let before = session.snapshot().focus_owner()
  let calls = Ref(0)
  let hook = fn(_boundary : FocusScopeBoundary) {
    calls.val += 1
    Ok(())
  }
  let saved = focus_identity_sequence.val
  focus_identity_sequence.val = 0xffff_ffff_ffff_ffff
  let create = FocusScopeSession::new(tree)
  let open = session.open_scope(target, 2, hook)
  let focus = session.request_focus(target, 3)
  let end = focus_identity_sequence.val
  focus_identity_sequence.val = saved
  assert_true(create is Err(IdentityExhausted))
  assert_true(open is Err(IdentityExhausted))
  assert_true(focus is Err(IdentityExhausted))
  assert_true(end == 0xffff_ffff_ffff_ffff)
  assert_eq(calls.val, 0)
  assert_true(session.target() == target)
  assert_true(session.snapshot().focus_owner() == before)
  assert_eq(session.scope_count(), 0)
}

///|
test "scope handle allocation exhaustion after staged focus does not publish" {
  let session = FocusScopeSession::new(scope_wb_tree()).unwrap()
  let before = session.target()
  let owner = session.snapshot().focus_owner()
  let calls = Ref(0)
  let saved = focus_identity_sequence.val
  focus_identity_sequence.val = 0xffff_ffff_ffff_fffe
  let result = session.open_scope(before, 2, _ => {
    calls.val += 1
    Ok(())
  })
  let end = focus_identity_sequence.val
  focus_identity_sequence.val = saved
  assert_true(result is Err(IdentityExhausted))
  assert_true(end == 0xffff_ffff_ffff_ffff)
  assert_eq(calls.val, 0)
  assert_true(session.target() == before)
  assert_true(session.snapshot().focus_owner() == owner)
}

///|
test "scope revision exhaustion rejects mutations and boundary callbacks" {
  let session = FocusScopeSession::new(scope_wb_tree()).unwrap()
  let handle = session.open_scope(session.target(), 2, _ => Ok(())).unwrap()
  session.state.val = { ..session.state.val, revision: 0xffff_ffff_ffff_ffff, }
  let target = session.target()
  let before = session.snapshot().focus_owner()
  let calls = Ref(0)
  let hook = fn(_boundary : FocusScopeBoundary) {
    calls.val += 1
    Ok(())
  }
  assert_true(session.request_focus(target, 4) is Err(RevisionExhausted))
  assert_true(session.focus_next(target) is Err(RevisionExhausted))
  assert_true(
    session.close_scope(target, handle, hook) is Err(RevisionExhausted),
  )
  assert_true(session.remove_subtree(target, 3, hook) is Err(RevisionExhausted))
  assert_true(
    session.replace_tree(target, scope_wb_tree(), hook)
    is Err(RevisionExhausted),
  )
  assert_true(session.close(target, hook) is Err(RevisionExhausted))
  assert_eq(calls.val, 0)
  assert_true(session.target() == target)
  assert_true(session.snapshot().focus_owner() == before)
  assert_eq(session.scope_count(), 1)
  // Pure synchronous admission is still possible at the final revision.
  assert_true(session.dispatch_target_with(target, 3, _ => Ok(())) is Ok(_))
}

///|
test "scope no-op traversal survives exhausted revision and allocator" {
  let rect = @primitives.Rect::new(0, 0, 20, 20).unwrap()
  let tree = ElementTree::new([
    ElementNode::new(2, None, rect).with_focusable(true).with_tab_stop(true),
  ]).unwrap()
  let session = FocusScopeSession::new(tree).unwrap()
  let _ = session.open_scope(session.target(), 2, _ => Ok(())).unwrap()
  session.state.val = { ..session.state.val, revision: 0xffff_ffff_ffff_ffff, }
  let target = session.target()
  let owner = session.snapshot().focus_owner()
  let saved = focus_identity_sequence.val
  focus_identity_sequence.val = 0xffff_ffff_ffff_ffff
  let next = session.focus_next(target)
  let prev = session.focus_prev(target)
  focus_identity_sequence.val = saved
  assert_true(next is Ok(_))
  assert_true(prev is Ok(_))
  assert_true(session.target() == target)
  assert_true(session.snapshot().focus_owner() == owner)
}

///|
test "scope stale saved numeric identity cannot restore across lineage" {
  let session = FocusScopeSession::new(scope_wb_tree()).unwrap()
  let handle = session.open_scope(session.target(), 2, _ => Ok(())).unwrap()
  let foreign = scope_wb_tree().with_focus(4).unwrap().focus_owner().unwrap()
  let frame = session.state.val.scopes[0]
  session.state.val.scopes[0] = {
    ..frame,
    previous: Some(foreign),
    fallback: None,
  }
  session.close_scope(session.target(), handle, _ => Ok(())).unwrap()
  assert_true(session.snapshot().focused() == Some(1))
  assert_true(session.snapshot().focus_owner() != Some(foreign))
}

///|
test "exhausted dismissal release preserves guard and performs no callbacks" {
  let session = FocusScopeSession::new(scope_wb_tree()).unwrap()
  let handle = session.open_scope(session.target(), 2, _ => Ok(())).unwrap()
  session
  .close_scope(
    session.target(),
    handle,
    _ => Ok(()),
    dismissal_key=@primitives.Space,
  )
  .unwrap()
  session.state.val = { ..session.state.val, revision: 0xffff_ffff_ffff_ffff, }
  let target = session.target()
  let calls = Ref(0)
  let release = @primitives.KeyReleased(
    key=@primitives.Space,
    modifiers=@primitives.Modifiers::none(),
  )
  let result = session.dispatch_input_with(target, release, (_, _) => {
    calls.val += 1
    Ok(())
  })
  assert_true(result is Err(RevisionExhausted))
  assert_eq(calls.val, 0)
  assert_true(session.target() == target)
  assert_true(session.state.val.closing_keys == [@primitives.Space])
}
