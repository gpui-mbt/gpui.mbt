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
  assert_true(authored_length_in_device_pixels(10.75, 2.0) is Ok(21.0))
  assert_true(authored_length_in_device_pixels(10.76, 2.0) is Ok(22.0))
  assert_true(measured_length_in_device_pixels(10.1, 2.0) is Ok(21.0))
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
    authored_length_in_device_pixels(-0.25, 2.0) is Err(NegativeValue),
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
  assert_true(raw.items()[1].bounds().top() == 10.75)
  assert_true(snapped.items()[1].bounds().top() == 10.5)
  assert_true(snapped.items()[1].bounds().size().height() == 10.5)
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
  assert_true(negative.items()[0].bounds().top() == -10.0)
  assert_true(negative.items()[0].bounds().size().height() == 40.0)

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
  assert_true(nested.items()[0].bounds().left() == 15.0)
  assert_true(nested.items()[1].bounds().left() == 25.5)
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
  assert_true(result.items()[0].bounds().left() == 0.5)
  assert_true(result.items()[0].bounds().size().width() == 10.5)
  assert_true(result.items()[0].bounds().size().height() == 10.5)
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

///|
test "device-grid tree honors 1x and non-2x scales without changing raw layout" {
  let style = FlexTreeStyle::new(FlowDirection::row()).with_wrap(
    FlexWrap::wrap(),
  )
  let viewport = device_grid_size(60.0, 10.0)
  let half_tie_nodes = [
    device_grid_tree_item(2, 1, 40.0, 10.5, None),
    device_grid_tree_item(3, 1, 40.0, 10.5, None),
  ]
  let raw = match layout_flex_tree(1, viewport, style, half_tie_nodes) {
    Ok(value) => value
    Err(_) => fail("raw scale-neutral layout was rejected")
  }
  let one_x = match
    layout_flex_tree_with_device_scale(1, viewport, style, half_tie_nodes, 1.0) {
    Ok(value) => value
    Err(_) => fail("one-times device-grid layout was rejected")
  }
  assert_true(raw.items()[1].bounds().top() == 10.5)
  assert_true(one_x.items()[1].bounds().top() == 10.0)

  let fractional_nodes = [
    device_grid_tree_item(2, 1, 40.0, 10.4, None),
    device_grid_tree_item(3, 1, 40.0, 10.4, None),
    device_grid_tree_item(4, 1, 40.0, 10.4, None),
  ]
  let one_and_half_x = match
    layout_flex_tree_with_device_scale(
      1, viewport, style, fractional_nodes, 1.5,
    ) {
    Ok(value) => value
    Err(_) => fail("one-and-a-half-times device-grid layout was rejected")
  }
  assert_true(one_and_half_x.items()[1].bounds().top() == 16.0 / 1.5)
  assert_true(one_and_half_x.items()[2].bounds().top() == 32.0 / 1.5)
}

///|
test "pre-edge-snap bounds retain solved phase with sparse identity lookup" {
  for scale in [1.0, 1.25, 1.5, 2.0] {
    for phase in [-80.5, -0.5, 0.0, 0.5] {
      let root = device_grid_rect(
        phase / scale,
        phase / scale,
        100 / scale,
        40 / scale,
      )
      let style = FlexTreeStyle::new(FlowDirection::row()).with_justify(
        JustifyContent::center(),
      )
      let item = FlexItem::new(
          2,
          device_grid_points(21 / scale),
          device_grid_points(10 / scale),
          device_grid_size(0, 0),
        )
        .with_flex(0, 0)
        .unwrap()
      let result = layout_mixed_tree_at(
        1,
        root,
        FlexStyle(style),
        [MixedTreeNode::new(FlexChild(item), 1, None)],
        Some(scale),
      ).unwrap()
      let raw = device_grid_rect(
        (phase + 39.5) / scale,
        phase / scale,
        21 / scale,
        10 / scale,
      )
      assert_true(result.bounds_before_edge_snap(1) == Some(root))
      phase_assert_bounds(result.bounds_before_edge_snap(2).unwrap(), raw)
      assert_true(result.bounds_before_edge_snap(99) == None)
      assert_true(
        result.root_bounds() ==
        logical_rect_from_device_pixels(
          device_grid_rect(phase, phase, 100, 40),
          scale,
          snap_edges=true,
        ).unwrap(),
      )
      phase_assert_bounds(
        result.items()[0].bounds(),
        logical_rect_from_device_pixels(
          device_grid_rect(phase + 39.5, phase, 21, 10),
          scale,
          snap_edges=true,
        ).unwrap(),
      )
      for (id, bounds) in result.before_edge_snap {
        let mut count = 0
        for (other, _) in result.before_edge_snap {
          if id == other {
            count = count + 1
          }
        }
        assert_eq(count, 1)
        let published = if id == 1 {
          result.root_bounds()
        } else {
          result.items()[0].bounds()
        }
        assert_true(bounds != published)
      }
      let unscaled = layout_mixed_tree_at(
        1,
        root,
        FlexStyle(style),
        [MixedTreeNode::new(FlexChild(item), 1, None)],
        None,
      ).unwrap()
      assert_eq(unscaled.before_edge_snap.length(), 0)
      assert_true(
        unscaled.bounds_before_edge_snap(1) == Some(unscaled.root_bounds()),
      )
      assert_true(
        unscaled.bounds_before_edge_snap(2) ==
        Some(unscaled.items()[0].bounds()),
      )
    }
  }
}

///|
test "flex pre-edge-snap metadata follows quantized metrics and unchanged fallback" {
  for scale in [1.0, 1.25, 1.5, 2.0] {
    let style = FlexTreeStyle::new(FlowDirection::row()).with_justify(
      JustifyContent::center(),
    )
    for width in [20.0, 21.0] {
      let item = FlexItem::new(
          2,
          Dimension::auto(),
          device_grid_points(10 / scale),
          device_grid_size((width - 0.25) / scale, 10 / scale),
        )
        .with_flex(0, 0)
        .unwrap()
      let result = layout_flex_tree_with_device_scale(
        1,
        device_grid_size(100 / scale, 40 / scale),
        style,
        [FlexTreeNode::new(item, 1)],
        scale,
      ).unwrap()
      let raw = device_grid_rect(
        (100 - width) / 2 / scale,
        0,
        width / scale,
        10 / scale,
      )
      assert_true(
        result.bounds_before_edge_snap(1) == Some(result.root_bounds()),
      )
      phase_assert_bounds(result.bounds_before_edge_snap(2).unwrap(), raw)
      phase_assert_bounds(
        result.items()[0].bounds(),
        logical_rect_from_device_pixels(
          device_grid_rect((100 - width) / 2, 0, width, 10),
          scale,
          snap_edges=true,
        ).unwrap(),
      )
      assert_true(result.bounds_before_edge_snap(99) == None)
      let raw_item = result.bounds_before_edge_snap(2).unwrap()
      assert_eq(
        result.before_edge_snap.length(),
        if raw_item == result.items()[0].bounds() {
          0
        } else {
          1
        },
      )
    }
  }
}

///|
fn phase_assert_bounds(
  actual : @primitives.Rect,
  expected : @primitives.Rect,
) -> Unit raise {
  for
    (a, b) in [
      (actual.left(), expected.left()),
      (actual.top(), expected.top()),
      (actual.right(), expected.right()),
      (actual.bottom(), expected.bottom()),
    ] {
    assert_true(a - b < 0.000000001 && a - b > -0.000000001)
  }
}
