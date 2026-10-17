///|
fn deferred_test_tree(interactive : Bool) -> ElementTree {
  let bounds = @primitives.Rect::new(0, 0, 80, 80).unwrap()
  let color = Some(@primitives.Color::rgba(1, 2, 3, 255).unwrap())
  let popup = {
    ..ElementNode::new(3, Some(2), bounds)
    .with_background(color)
    .with_pointer_events(interactive),
    deferred: Some(0),
  }
  let child = {
    ..ElementNode::new(
      4,
      Some(3),
      @primitives.Rect::new(20, 20, 30, 30).unwrap(),
    )
    .with_background(color)
    .with_pointer_events(interactive),
    deferred: Some(0),
  }
  ElementTree::new([
    ElementNode::new(1, None, bounds).with_background(color),
    ElementNode::new(2, Some(1), bounds)
    .with_background(color)
    .with_focusable(true)
    .with_tab_stop(true),
    popup,
    child.with_focusable(true).with_tab_stop(true),
    ElementNode::new(5, Some(1), bounds)
    .with_background(color)
    .with_focusable(true)
    .with_tab_stop(true),
  ]).unwrap()
}

///|
test "deferred paint and reverse hits do not change structural preorder" {
  let tree = deferred_test_tree(true)
  let ids : Array[UInt64] = tree.nodes().map(node => node.id())
  assert_eq(ids, [1, 2, 3, 4, 5])
  let painted : Array[UInt64] = tree
    .to_scene()
    .commands()
    .map(command => command.id())
  assert_eq(painted, [1, 2, 5, 3, 4])
  let point = @primitives.Point::new(30, 30).unwrap()
  assert_true(tree.hit_test(point) == Some(4))
  assert_eq(tree.dispatch_pointer(point).capture(), [1, 2, 3, 4])
  assert_eq(tree.dispatch_pointer(point).bubble(), [4, 3, 2, 1])
  assert_true(tree.hit_test(@primitives.Point::new(50, 30).unwrap()) == Some(3))
  assert_true(tree.hit_test(@primitives.Point::new(80, 30).unwrap()) is None)
}

///|
test "deferred plain popup remains transparent and earlier snapshots stay immutable" {
  let transparent = deferred_test_tree(false)
  assert_true(
    transparent.hit_test(@primitives.Point::new(30, 30).unwrap()) == Some(5),
  )
  let tree = deferred_test_tree(true)
  let focused = tree.with_focus(5).unwrap()
  let owner = focused.focus_owner()
  let removed = focused.without_subtree(2).unwrap()
  assert_true(removed.focus_owner() == owner)
  assert_eq(removed.nodes().map(node => node.id()), [1, 5])
  assert_eq(removed.to_scene().commands().map(command => command.id()), [1, 5])
  assert_eq(focused.to_scene().commands().map(command => command.id()), [
    1, 2, 5, 3, 4,
  ])
  assert_true(focused.focus_prev().unwrap().focused() == Some(4))
  assert_true(
    tree.with_focus(2).unwrap().focus_next().unwrap().focused() == Some(4),
  )
  assert_true(
    tree.with_focus(4).unwrap().without_subtree(2).unwrap().focus_owner()
    is None,
  )
}
