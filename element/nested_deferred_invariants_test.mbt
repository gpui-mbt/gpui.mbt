///|
test "nested deferred preserves structural input focus tab and drag ancestry" {
  let frame = nested_frame(2, 3, 1, 3, true, false, 1.25)
  let tree = frame.tree()
  assert_eq(tree.nodes().map(node => node.id()), [
    1, 2, 3, 4, 19, 10, 14, 11, 15, 16, 17, 13, 18, 12, 39, 30, 34, 31, 35, 36, 37,
    33, 38, 32, 6, 5,
  ])
  let point = @primitives.Point::new(84, 72).unwrap()
  assert_true(tree.hit_test(point) == Some(13))
  assert_eq(tree.dispatch_pointer(point).capture(), [1, 2, 19, 10, 15, 17, 13])
  assert_eq(tree.dispatch_pointer(point).bubble(), [13, 17, 15, 10, 19, 2, 1])
  assert_true(
    tree.with_focus(11).unwrap().focus_next().unwrap().focused() == Some(13),
  )
  assert_true(
    tree.with_focus(12).unwrap().focus_prev().unwrap().focused() == Some(13),
  )
  let drag = @element.DragGesture::new(0).unwrap().begin(13, point)
  let focused = tree.with_focus(13).unwrap()
  let owner = focused.focus_owner()
  let moved = nested_frame(2, 3, 1, 3, true, true, 1.25)
  let refreshed = focused.with_layout_bounds(moved).unwrap()
  assert_true(refreshed.focus_owner() == owner)
  assert_true(refreshed.node(drag.source().unwrap()) is Some(_))
  assert_true(
    refreshed.hit_test(@primitives.Point::new(100, 84).unwrap()) == Some(13),
  )
  assert_true(
    refreshed.node(13).unwrap().bounds() ==
    @primitives.Rect::new(96, 80, 40, 32).unwrap(),
  )
  assert_true(
    focused.node(13).unwrap().bounds() ==
    @primitives.Rect::new(80, 68, 40, 32).unwrap(),
  )
  // Children with a lower priority really paint behind, and lose a hit to,
  // their parent. The core retains its existing single-topmost-target model.
  assert_true(
    nested_frame(2, 0, 3, 1, true, false, 1.25).tree().hit_test(point) ==
    Some(10),
  )
  assert_true(
    tree.hit_test(@primitives.Point::new(120, 72).unwrap()) != Some(13),
  )
}

///|
test "nested deferred copy removal restoration and priority refresh are immutable" {
  let frame = nested_frame(1, 1, 1, 1, true, false, 1)
  let tree = frame.tree().with_focus(33).unwrap()
  let owner = tree.focus_owner()
  let copied = @element.ElementTree::new(
    tree
    .nodes()
    .map(node => {
      node
      .with_background(node.background())
      .with_focusable(node.is_focusable())
      .with_pointer_events(node.accepts_pointer_events())
      .with_tab_index(node.tab_index)
      .with_tab_group_index(node.tab_group_index)
      .with_tab_stop(node.tab_stop)
    }),
  ).unwrap()
  assert_true(copied.to_scene().commands() == tree.to_scene().commands())
  let removed = tree.without_subtree(17).unwrap()
  let removed_frame = nested_frame(1, 1, 1, 1, false, false, 1)
  assert_true(
    tree.with_layout_bounds(removed_frame) is Err(@element.LayoutBoundsMismatch),
  )
  assert_true(
    removed.with_layout_bounds(frame) is Err(@element.LayoutBoundsMismatch),
  )
  assert_true(removed.focus_owner() == owner)
  assert_true(
    removed.to_scene().commands() ==
    nested_frame(1, 1, 1, 1, false, false, 1).paint().commands(),
  )
  assert_true(tree.node(13) is Some(_))
  assert_true(tree.without_subtree(16) is Err(@element.InvalidAnchoredShape))
  assert_true(
    tree.with_focus(13).unwrap().without_subtree(17).unwrap().focus_owner()
    is None,
  )
  let outer_removed = tree.without_subtree(19).unwrap()
  assert_true(outer_removed.node(10) is None)
  assert_true(outer_removed.node(13) is None)
  assert_true(outer_removed.node(33) is Some(_))
  assert_true(outer_removed.focus_owner() == owner)
  assert_true(
    nested_frame(1, 1, 1, 1, true, false, 1).paint().commands() ==
    frame.paint().commands(),
  )
  for
    changed in [
      nested_frame(2, 1, 1, 1, true, false, 1),
      nested_frame(1, 2, 1, 1, true, false, 1),
      nested_frame(1, 1, 1, 2, true, false, 1),
    ] {
    assert_true(
      tree.with_layout_bounds(changed) is Err(@element.LayoutBoundsMismatch),
    )
  }
  assert_true(tree.focus_owner() == owner)
}

///|
test "nested deferred third level and undeferred nested compositions reject explicitly" {
  let column = @layout.FlexTreeStyle::new(@layout.FlowDirection::column())
  let outer = nested_outer(10, 0, 0, true, 24, 24)
  let third_popup = nested_plain(100, 120, 100)
    .with_children_style(column)
    .with_child(nested_plain(3, 0, 0))
    .with_child(outer)
  assert_true(
    @element.Element::anchored_after(
      101,
      102,
      third_popup,
      @element.TopLeft,
      @element.Local,
      @primitives.Point::new(0, 0).unwrap(),
    )
    is Err(@element.UnsupportedAnchoredComposition),
  )
  // Construction may prepare a valid two-level popup before its caller adds
  // deferred(). Publishing it without deferring the outer wrapper is rejected.
  let undeferred_outer = @element.Element::anchored_after(
    19,
    3,
    outer.children[0],
    @element.TopLeft,
    @element.Local,
    @primitives.Point::new(24, 24).unwrap(),
  ).unwrap()
  let root = @element.Element::root(1, column)
    .with_child(nested_plain(3, 0, 0))
    .with_child(undeferred_outer)
  assert_true(
    root.request_layout(@primitives.Size::new(320, 240).unwrap())
    is Err(@element.UnsupportedAnchoredComposition),
  )
  let inner = @element.Element::anchored_after(
    107,
    106,
    nested_box(103, 40, 32),
    @element.TopLeft,
    @element.Local,
    @primitives.Point::new(0, 0).unwrap(),
  ).unwrap()
  let popup = nested_plain(104, 96, 72)
    .with_children_style(column)
    .with_child(nested_plain(106, 0, 0))
    .with_child(inner)
  assert_true(
    @element.Element::anchored_after(
      109,
      3,
      popup,
      @element.TopLeft,
      @element.Local,
      @primitives.Point::new(0, 0).unwrap(),
    )
    is Err(@element.UnsupportedAnchoredComposition),
  )
  assert_true(outer.deferred() is Err(@element.UnsupportedAnchoredComposition))
  assert_true(
    nested_box(200, 10, 10).deferred()
    is Err(@element.UnsupportedAnchoredComposition),
  )
}
