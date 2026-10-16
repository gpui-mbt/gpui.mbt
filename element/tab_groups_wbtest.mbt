///|
test "group prefix links share ancestors and unwind closed subtrees" {
  let bounds = match @primitives.Rect::new(0, 0, 10, 10) {
    Ok(value) => value
    Err(_) => abort("invalid bounds")
  }
  let nodes = [
    ElementNode::new(1, None, bounds)
    .with_tab_group_index(Some(2))
    .with_tab_index(8),
    ElementNode::new(2, Some(1), bounds).with_tab_index(3),
    ElementNode::new(3, Some(1), bounds)
    .with_tab_group_index(Some(-1))
    .with_tab_index(9),
    ElementNode::new(4, Some(3), bounds).with_tab_index(5),
    ElementNode::new(5, Some(1), bounds).with_tab_index(4),
    ElementNode::new(6, None, bounds).with_tab_index(7),
  ]
  let order = tab_order(nodes)
  assert_eq(order.keys.length(), 6)
  assert_eq(order.prefixes.length(), 2)
  let expected = [[8, 2], [3, 2], [9, -1, 2], [5, -1, 2], [4, 2], [7]]
  for index = 0; index < expected.length(); index = index + 1 {
    tab_path(order, index, order.left_path)
    assert_true(order.left_path == expected[index])
  }
  assert_true(order.keys[0].prefix == order.keys[1].prefix)
  assert_true(order.keys[0].prefix == order.keys[4].prefix)
  assert_true(order.keys[2].prefix == order.keys[3].prefix)
  order.left_path[0] = 99
  assert_true(tab_precedes(order, 3, 1))
  assert_true(order.left_path == [5, -1, 2])
  assert_true(order.right_path == [3, 2])
  assert_true(tab_precedes(order, 4, 5))
}

///|
test "group builder defensively copies children and traversal owns input node arrays" {
  let style = @layout.FlexTreeStyle::new(@layout.FlowDirection::row())
  let root = Element::root(1, style).with_child(Element::root(2, style))
  let grouped = root.with_tab_group_index(Some(-3))
  let cleared = grouped.with_tab_group_index(None)
  root.children[0] = Element::root(9, style)
  grouped.children.push(Element::root(8, style))
  assert_true(grouped.children[0].id == 2)
  assert_true(cleared.children[0].id == 2)
  assert_eq(cleared.children.length(), 1)
  assert_eq(root.children.length(), 1)
  let bounds = match @primitives.Rect::new(0, 0, 10, 10) {
    Ok(value) => value
    Err(_) => abort("invalid bounds")
  }
  let nodes = [
    ElementNode::new(1, None, bounds).with_tab_group_index(Some(6)),
    ElementNode::new(2, Some(1), bounds)
    .with_focusable(true)
    .with_tab_stop(true)
    .with_tab_index(1),
    ElementNode::new(3, None, bounds)
    .with_focusable(true)
    .with_tab_stop(true)
    .with_tab_index(2),
  ]
  let tree = match ElementTree::new(nodes) {
    Ok(value) => value
    Err(_) => abort("invalid tree")
  }
  nodes[0] = nodes[0].with_tab_group_index(Some(-6))
  let exposed = tree.nodes()
  exposed[0] = exposed[0].with_tab_group_index(None)
  let next = match tree.focus_next() {
    Ok(value) => value
    Err(_) => abort("invalid traversal")
  }
  assert_true(next.focused() == Some(3))
  assert_true(tree.nodes[0].tab_group_index == Some(6))
  assert_true(tree.focused() is None)
}

///|
test "group traversal no-op avoids exhausted allocator while a new destination fails" {
  let bounds = match @primitives.Rect::new(0, 0, 10, 10) {
    Ok(value) => value
    Err(_) => abort("invalid bounds")
  }
  let tree = match
    ElementTree::new([
      ElementNode::new(1, None, bounds)
      .with_tab_group_index(Some(-4))
      .with_focusable(true),
      ElementNode::new(2, Some(1), bounds)
      .with_focusable(true)
      .with_tab_stop(true),
    ]) {
    Ok(value) => value
    Err(_) => abort("invalid tree")
  }
  let focused = match tree.with_focus(2) {
    Ok(value) => value
    Err(_) => abort("invalid focus")
  }
  let other = match tree.with_focus(1) {
    Ok(value) => value
    Err(_) => abort("invalid focus")
  }
  let saved = focus_identity_sequence.val
  focus_identity_sequence.val = 0xffff_ffff_ffff_ffff
  let next = focused.focus_next()
  let prev = focused.focus_prev()
  let changed = other.focus_next()
  let explicit = focused.with_focus(2)
  focus_identity_sequence.val = saved
  for result in [next, prev] {
    match result {
      Ok(value) => assert_true(value.focus_owner() == focused.focus_owner())
      Err(_) => fail("group singleton allocated identity")
    }
  }
  assert_true(changed is Err(FocusIdentityExhausted))
  assert_true(explicit is Err(FocusIdentityExhausted))
}

///|
test "deep group key storage is linear and comparison scratch is reused" {
  let bounds = match @primitives.Rect::new(0, 0, 10, 10) {
    Ok(value) => value
    Err(_) => abort("invalid bounds")
  }
  let depth = 1024
  let nodes : Array[ElementNode] = []
  for index = 0; index < depth; index = index + 1 {
    let parent = if index == 0 { None } else { Some(index.to_uint64()) }
    nodes.push(
      ElementNode::new(index.to_uint64() + 1, parent, bounds)
      .with_tab_group_index(Some(2))
      .with_tab_index(9),
    )
  }
  nodes.push(ElementNode::new(2000, None, bounds).with_tab_index(1))
  let order = tab_order(nodes)
  assert_eq(order.keys.length(), depth + 1)
  assert_eq(order.prefixes.length(), depth)
  assert_true(order.left_path.is_empty())
  assert_true(order.right_path.is_empty())
  assert_true(tab_precedes(order, depth, depth - 1))
  assert_eq(order.left_path.length(), 1)
  assert_eq(order.right_path.length(), depth + 1)
  assert_true(tab_precedes(order, 0, 1) == false)
  assert_eq(order.left_path.length(), 2)
  assert_eq(order.right_path.length(), 3)
  assert_eq(order.keys.length(), depth + 1)
  assert_eq(order.prefixes.length(), depth)
}
