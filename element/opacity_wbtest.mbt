///|
test "nested deferred groups reset opacity independently of priority order" {
  for (outer_priority, inner_priority) in [(2, 0), (1, 1), (0, 2)] {
    let nodes = nested_wb_frame(outer_priority, inner_priority, 3, 4).tree.nodes
    for i = 0; i < nodes.length(); i = i + 1 {
      let local_opacity = match nodes[i].id {
        1 => 0.1
        20 => 0.2
        10 => 0.5
        12 => 0.3
        13 => 0.7
        _ => 1.0
      }
      nodes[i] = nodes[i].with_opacity(local_opacity).unwrap()
    }
    let tree = ElementTree::new(nodes).unwrap()
    let values = effective_element_opacities(tree.nodes)
    for i = 0; i < nodes.length(); i = i + 1 {
      if nodes[i].id == 10 {
        assert_eq(values[i], 0.2 * 0.5)
      }
      if nodes[i].id == 13 {
        assert_eq(values[i], 0.3 * 0.7)
      }
      if nodes[i].id == 30 {
        assert_eq(values[i], 1.0)
      }
    }
  }
}

///|
test "malformed local opacity is rejected at the tree boundary" {
  let node = ElementNode::new(
    1,
    None,
    @primitives.Rect::new(0, 0, 10, 10).unwrap(),
  )
  assert_true(
    ElementTree::new([{ ..node, opacity: 0.0 / 0.0, }]) is Err(InvalidOpacity),
  )
}
