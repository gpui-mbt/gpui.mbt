///|
fn metadata_root_frame(width : Double, inset : Double) -> @element.Prepainted {
  let style = @layout.FlexTreeStyle::new(@layout.FlowDirection::row()).with_insets(
    @layout.Insets::new(0.0, inset, 0.0, inset).unwrap(),
    @layout.Insets::zero(),
  )
  @element.Element::root(1, style)
  .with_focusable(true)
  .request_layout_root_box(lifecycle_size(width, 20.0))
  .unwrap()
  .prepaint()
  .unwrap()
}

///|
test "root box viewport survives focus copies and same viewport bounds refresh" {
  let initial = metadata_root_frame(10.0, 7.0)
  let focused = initial.tree().with_focus(1).unwrap()
  let owner = focused.focus_owner().unwrap()
  let updated = focused
    .with_layout_bounds(metadata_root_frame(10.0, 9.0))
    .unwrap()
  assert_true(updated.focus_owner() == Some(owner))
  assert_eq(updated.nodes()[0].bounds().size().width(), 18.0)
  for
    tree in [
      focused,
      updated,
      updated.clear_focus(),
      updated.clear_focus().with_focus_owner(owner).unwrap(),
    ] {
    assert_true(tree.hit_test(element_point(9.9, 5.0)) == Some(1))
    assert_true(tree.hit_test(element_point(10.0, 5.0)) is None)
  }
  assert_true(
    focused.with_layout_bounds(metadata_root_frame(11.0, 7.0))
    is Err(LayoutBoundsMismatch),
  )
  let legacy = @element.Element::root(
      1,
      @layout.FlexTreeStyle::new(@layout.FlowDirection::row()),
    )
    .with_focusable(true)
    .request_layout(lifecycle_size(10.0, 20.0))
    .unwrap()
    .prepaint()
    .unwrap()
  assert_true(focused.with_layout_bounds(legacy) is Err(LayoutBoundsMismatch))
  assert_true(
    legacy.tree().with_layout_bounds(initial) is Err(LayoutBoundsMismatch),
  )
}

///|
test "root box scrollport uses authored box but wheel route uses physical viewport" {
  let style = @layout.FlexTreeStyle::new(@layout.FlowDirection::row()).with_insets(
    @layout.Insets::new(0.0, 7.0, 0.0, 7.0).unwrap(),
    @layout.Insets::zero(),
  )
  let frame = @element.Element::root(1, style)
    .with_scroll_offset(element_point(0.0, 0.0))
    .with_child(@element.Element::new(viewport_item(2, 30.0, 5.0)))
    .request_layout_root_box(lifecycle_size(10.0, 20.0))
    .unwrap()
    .prepaint()
    .unwrap()
  let tree = frame.tree()
  let scroll = tree.scroll_viewport(1).unwrap()
  assert_eq(scroll.bounds().size().width(), 14.0)
  assert_true(scroll.max_offset().x() > 0.0)
  assert_eq(
    tree.scroll_wheel(element_point(10.0, 2.0), 3.0, 0.0).unwrap().length(),
    0,
  )
  assert_eq(
    tree.scroll_wheel(element_point(9.0, 2.0), 3.0, 0.0).unwrap().length(),
    1,
  )
}

///|
test "root box viewport survives pointer outside snapshot and constrains drag admission" {
  let tree = metadata_root_frame(10.0, 7.0).tree()
  let frame = @element.PointerOutsideFrame::new(tree, [1]).unwrap()
  let outside = Ref(0)
  let routed = Ref(0)
  let _ = frame
    .dispatch_input_with(
      session_down(11.0, 5.0),
      fn(_, _) {
        outside.val = outside.val + 1
        Ok(())
      },
      fn(_, _) {
        routed.val = routed.val + 1
        Ok(())
      },
    )
    .unwrap()
  // Point remains geometrically inside authored R: outside listeners preserve
  // their geometry-only semantics, but normal input cannot target outside V.
  assert_eq(outside.val, 0)
  assert_eq(routed.val, 0)
  let _ = frame
    .dispatch_input_with(
      session_down(15.0, 5.0),
      fn(_, _) {
        outside.val = outside.val + 1
        Ok(())
      },
      fn(_, _) {
        routed.val = routed.val + 1
        Ok(())
      },
    )
    .unwrap()
  assert_true(outside.val > 0)
  let session : @element.DragSession[String] = @element.DragSession::new()
  let sources = [@element.DragSource::new(1, "root")]
  let _ = session.dispatch(tree, session_down(10.0, 5.0), sources, []).unwrap()
  assert_true(session.snapshot() is @element.Idle)
  let _ = session.dispatch(tree, session_down(9.0, 5.0), sources, []).unwrap()
  assert_true(session.snapshot() is @element.Pending(..))
}

///|
test "focus scope snapshots retain root physical viewport" {
  let session = scope_session(metadata_root_frame(10.0, 7.0).tree())
  assert_true(session.snapshot().hit_test(element_point(11.0, 5.0)) is None)
  let _ = scope_open(session, 1)
  assert_true(session.snapshot().hit_test(element_point(11.0, 5.0)) is None)
  assert_true(session.snapshot().hit_test(element_point(9.0, 5.0)) == Some(1))
}
