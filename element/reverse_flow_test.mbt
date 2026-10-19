///|
test "reverse flex changes hit geometry without reversing source or paint order" {
  let color = lifecycle_color(20, 40, 60)
  let root = @element.Element::root(
      1,
      @layout.FlexTreeStyle::new(@layout.FlowDirection::row_reverse()).with_justify(
        @layout.JustifyContent::end(),
      ),
    )
    .with_child(
      @element.Element::new(lifecycle_item(2, 20.0, 40.0)).with_background(
        Some(color),
      ),
    )
    .with_child(
      @element.Element::new(lifecycle_item(3, 30.0, 40.0)).with_background(
        Some(color),
      ),
    )
  let prepared = match root.request_layout(lifecycle_size(100.0, 40.0)) {
    Ok(value) =>
      match value.prepaint() {
        Ok(value) => value
        Err(_) => fail("reverse prepaint failed")
      }
    Err(_) => fail("reverse layout failed")
  }
  let tree = prepared.tree()
  assert_eq(tree.nodes().map(node => node.id()), [1UL, 2UL, 3UL])
  assert_eq(tree.nodes().map(node => node.bounds().left()), [0.0, 80.0, 50.0])
  assert_true(
    tree.hit_test(@primitives.Point::new(90.0, 20.0).unwrap()) == Some(2),
  )
  assert_true(
    tree.hit_test(@primitives.Point::new(60.0, 20.0).unwrap()) == Some(3),
  )
  let painted = prepared.paint()
  assert_eq(painted.command_at(0).unwrap().id(), 2UL)
  assert_eq(painted.command_at(1).unwrap().id(), 3UL)
}
