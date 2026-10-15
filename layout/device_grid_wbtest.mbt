///|
fn device_grid_size(width : Double, height : Double) -> @primitives.Size raise {
  match @primitives.Size::new(width, height) {
    Ok(value) => value
    Err(_) => fail("valid device-grid size was rejected")
  }
}

///|
fn device_grid_points(value : Double) -> Dimension raise {
  match Dimension::points(value) {
    Ok(result) => result
    Err(_) => fail("valid device-grid point dimension was rejected")
  }
}

///|
fn device_grid_rect(
  left : Double,
  top : Double,
  width : Double,
  height : Double,
) -> @primitives.Rect raise {
  match @primitives.Rect::new(left, top, width, height) {
    Ok(value) => value
    Err(_) => fail("valid device-grid rectangle was rejected")
  }
}

///|
fn device_grid_insets(value : Double) -> Insets raise {
  match Insets::all(value) {
    Ok(result) => result
    Err(_) => fail("valid device-grid inset was rejected")
  }
}

///|
fn device_grid_tree_item(
  id : UInt64,
  parent : UInt64,
  main : Double,
  cross : Double,
  children_style : FlexTreeStyle?,
) -> FlexTreeNode raise {
  let item = FlexItem::new(
    id,
    device_grid_points(main),
    device_grid_points(cross),
    device_grid_size(main, cross),
  )
  let item = match item.with_flex(0.0, 0.0) {
    Ok(value) => value
    Err(_) => fail("valid device-grid flex factors were rejected")
  }
  match children_style {
    None => FlexTreeNode::new(item, parent)
    Some(style) => FlexTreeNode::new(item, parent).with_children(style)
  }
}

///|
test "device-grid authored lengths, measured sizes, and negative absolute edges use distinct rules" {
  assert_true(snap_authored_length_to_device_grid(10.75, 2.0) is Ok(10.5))
  assert_true(snap_authored_length_to_device_grid(10.76, 2.0) is Ok(11.0))
  assert_true(ceil_measured_length_to_device_grid(10.1, 2.0) is Ok(10.5))
  let snapped = match
    snap_absolute_rect_to_device_grid(
      device_grid_rect(-0.25, -0.75, 0.75, 1.0),
      2.0,
    ) {
    Ok(value) => value
    Err(_) => fail("valid absolute device-grid bounds were rejected")
  }
  assert_eq(snapped.left(), 0.0)
  assert_eq(snapped.top(), -0.5)
  assert_eq(snapped.size().width(), 0.5)
  assert_eq(snapped.size().height(), 0.5)
  assert_true(
    snap_authored_length_to_device_grid(-0.25, 2.0) is Err(NegativeValue),
  )
}

///|
test "device-grid flex tree snaps authored wrap heights before layout" {
  let style = FlexTreeStyle::new(FlowDirection::row()).with_wrap(
    FlexWrap::wrap(),
  )
  let nodes = [
    device_grid_tree_item(2, 1, 40.0, 10.75, None),
    device_grid_tree_item(3, 1, 40.0, 10.75, None),
  ]
  let raw = match
    layout_flex_tree(1, device_grid_size(60.0, 10.0), style, nodes) {
    Ok(value) => value
    Err(_) => fail("raw flex tree layout was rejected")
  }
  let snapped = match
    layout_flex_tree_with_device_scale(
      1,
      device_grid_size(60.0, 10.0),
      style,
      nodes,
      2.0,
    ) {
    Ok(value) => value
    Err(_) => fail("device-grid flex tree layout was rejected")
  }
  assert_eq(raw.items()[1].bounds().top(), 10.75)
  assert_eq(snapped.items()[1].bounds().top(), 10.5)
  assert_eq(snapped.items()[1].bounds().size().height(), 10.5)
}

///|
test "device-grid flex tree rounds negative and nested origins from absolute edges" {
  let centered = FlexTreeStyle::new(FlowDirection::row()).with_align(
    AlignItems::center(),
  )
  let negative = match
    layout_flex_tree_with_device_scale(
      1,
      device_grid_size(60.0, 20.0),
      centered,
      [device_grid_tree_item(2, 1, 40.0, 40.5, None)],
      2.0,
    ) {
    Ok(value) => value
    Err(_) => fail("negative device-grid layout was rejected")
  }
  assert_eq(negative.items()[0].bounds().top(), -10.0)
  assert_eq(negative.items()[0].bounds().size().height(), 40.0)

  let root_style = FlexTreeStyle::new(FlowDirection::row()).with_justify(
    JustifyContent::center(),
  )
  let nested_style = FlexTreeStyle::new(FlowDirection::row()).with_justify(
    JustifyContent::center(),
  )
  let nested = match
    layout_flex_tree_with_device_scale(
      1,
      device_grid_size(60.5, 50.0),
      root_style,
      [
        device_grid_tree_item(2, 1, 30.25, 40.0, Some(nested_style)),
        device_grid_tree_item(3, 2, 9.5, 5.0, None),
      ],
      2.0,
    ) {
    Ok(value) => value
    Err(_) => fail("nested device-grid layout was rejected")
  }
  assert_eq(nested.items()[0].bounds().left(), 15.0)
  assert_eq(nested.items()[1].bounds().left(), 25.5)
}

///|
test "device-grid flex tree ceils measured sizes and preserves nonzero strokes" {
  let root_style = FlexTreeStyle::new(FlowDirection::row()).with_insets(
    Insets::zero(),
    device_grid_insets(0.1),
  )
  let item = FlexItem::new(
    2,
    Dimension::auto(),
    Dimension::auto(),
    device_grid_size(10.1, 10.1),
  )
  let node = FlexTreeNode::new(item, 1)
  let result = match
    layout_flex_tree_with_device_scale(
      1,
      device_grid_size(40.0, 20.0),
      root_style,
      [node],
      2.0,
    ) {
    Ok(value) => value
    Err(_) => fail("measured device-grid layout was rejected")
  }
  assert_eq(result.items()[0].bounds().left(), 0.5)
  assert_eq(result.items()[0].bounds().size().width(), 10.5)
  assert_eq(result.items()[0].bounds().size().height(), 10.5)
}

///|
test "device-grid layout rejects nonpositive and nonfinite scales" {
  let root_id : UInt64 = 1
  let root_size = device_grid_size(60.0, 30.0)
  let style = FlexTreeStyle::new(FlowDirection::row())
  let nodes = [device_grid_tree_item(2, 1, 40.0, 10.0, None)]
  assert_true(
    layout_flex_tree_with_device_scale(root_id, root_size, style, nodes, 0.0)
    is Err(Flex(NegativeValue)),
  )
  assert_true(
    layout_flex_tree_with_device_scale(
      root_id,
      root_size,
      style,
      nodes,
      0.0 / 0.0,
    )
    is Err(Flex(NonFiniteValue)),
  )
}
