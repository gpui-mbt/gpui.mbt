///|
test "pointer hit bounds include near edges and exclude far edges" {
  let tree = unwrap_tree([
    @element.ElementNode::new(1, None, element_rect(0, 0, 100, 60)),
    @element.ElementNode::new(2, Some(1), element_rect(10, 5, 20, 30)),
  ])
  assert_true(tree.hit_test(element_point(10, 5)) == Some(2))
  assert_true(tree.hit_test(element_point(29.999, 34.999)) == Some(2))
  assert_true(tree.hit_test(element_point(30, 10)) == Some(1))
  assert_true(tree.dispatch_pointer(element_point(20, 35)).target() == Some(1))
  assert_true(tree.hit_test(element_point(100, 20)) is None)
  assert_true(tree.hit_test(element_point(20, 60)) is None)
  // Geometric containment remains closed; pointer coverage is half-open.
  assert_true(element_rect(10, 5, 20, 30).contains(element_point(30, 35)))
}

///|
test "zero extent nodes never receive pointer input" {
  let tree = unwrap_tree([
    @element.ElementNode::new(1, None, element_rect(0, 0, 100, 60)),
    @element.ElementNode::new(2, Some(1), element_rect(10, 5, 0, 30)),
    @element.ElementNode::new(3, Some(1), element_rect(10, 5, 20, 0)),
    @element.ElementNode::new(4, Some(1), element_rect(10, 5, 0, 0)),
  ])
  for
    point in [element_point(10, 10), element_point(20, 5), element_point(10, 5)] {
    assert_true(tree.hit_test(point) == Some(1))
    let event = @primitives.PointerButtonPressed(
      position=point,
      button=@primitives.Primary,
      modifiers=@primitives.Modifiers::none(),
    )
    assert_true(tree.dispatch_input(event).target() == Some(1))
  }
}

///|
test "shared edge belongs to the element starting at that edge" {
  // Reverse paint order must not let a later-painted left sibling steal the
  // shared edge from the right sibling that begins there.
  let tree = unwrap_tree([
    @element.ElementNode::new(1, None, element_rect(0, 0, 40, 20)),
    @element.ElementNode::new(2, Some(1), element_rect(20, 0, 20, 20)),
    @element.ElementNode::new(3, Some(1), element_rect(0, 0, 20, 20)),
  ])
  assert_true(tree.hit_test(element_point(20, 10)) == Some(2))
  assert_true(tree.hit_test(element_point(19.999, 10)) == Some(3))
}
