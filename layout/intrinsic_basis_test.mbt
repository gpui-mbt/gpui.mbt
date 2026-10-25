///|
fn intrinsic_basis_results(
  direction : @layout.FlowDirection,
  inner : @layout.FlexTreeStyle,
  children : Array[@layout.FlexItem],
  scale : Double,
) -> Array[Result[@layout.FlexTreeLayout, @layout.TreeLayoutError]] {
  let branch = tree_auto_item(
      2,
      @layout.Dimension::auto(),
      tree_points(100),
      tree_size(0, 0),
    )
    .with_flex(0, 0)
    .unwrap()
  let outer = @layout.FlexTreeStyle::new(direction)
  let pure = [@layout.FlexTreeNode::new(branch, 1).with_children(inner)]
  let mixed = [
    @layout.MixedTreeNode::new(
      @layout.FlexChild(branch),
      1,
      Some(@layout.FlexStyle(inner)),
    ),
  ]
  for child in children {
    pure.push(@layout.FlexTreeNode::new(child, 2))
    mixed.push(@layout.MixedTreeNode::new(@layout.FlexChild(child), 2, None))
  }
  [
    @layout.layout_flex_tree_with_device_scale(
      1,
      tree_size(320, 260),
      outer,
      pure,
      scale,
    ),
    @layout.layout_mixed_tree_at(
      1,
      @primitives.Rect::new(0, 0, 320, 260).unwrap(),
      @layout.FlexStyle(outer),
      mixed,
      Some(scale),
    ),
  ]
}

///|
test "intrinsic zero-flex point contribution differs from actual child size" {
  for
    direction in [
      @layout.FlowDirection::row(),
      @layout.FlowDirection::row_reverse(),
      @layout.FlowDirection::column(),
      @layout.FlowDirection::column_reverse(),
    ] {
    let column = direction is Column || direction is ColumnReverse
    let style = @layout.FlexTreeStyle::new(direction).with_gap(4).unwrap()
    let children = [
      tree_item(3, 40, 10)
      .with_flex(0, 0)
      .unwrap()
      .with_flex_basis(@layout.FlexBasis::points(16).unwrap()),
      tree_item(4, 20, 12)
      .with_flex(0, 0)
      .unwrap()
      .with_flex_basis(@layout.FlexBasis::points(32).unwrap()),
      tree_item(5, 30, 8)
      .with_flex(0, 0)
      .unwrap()
      .with_flex_basis(@layout.FlexBasis::points(24).unwrap()),
    ]
    for scale in [1.0, 1.5, 2.0] {
      for result in intrinsic_basis_results(direction, style, children, scale) {
        let items = result.unwrap().items()
        let main = if column {
          items[0].bounds().size().height()
        } else {
          items[0].bounds().size().width()
        }
        assert_eq(main, 110.0)
        for i, expected in [16.0, 32.0, 24.0] {
          let bounds = items[i + 1].bounds()
          assert_eq(
            if column {
              bounds.size().height()
            } else {
              bounds.size().width()
            },
            expected,
          )
        }
      }
    }
  }
}

///|
test "intrinsic zero-flex max limits bound children not parent contributions" {
  let direction = @layout.FlowDirection::row()
  let style = @layout.FlexTreeStyle::new(direction)
  for
    basis in [@layout.FlexBasis::auto(), @layout.FlexBasis::points(60).unwrap()] {
    let child = tree_item(3, 40, 10)
      .with_flex(0, 0)
      .unwrap()
      .with_flex_basis(basis)
      .with_main_limits(0, Some(24))
      .unwrap()
    for result in intrinsic_basis_results(direction, style, [child], 1) {
      let items = result.unwrap().items()
      assert_eq(
        items[0].bounds().size().width(),
        if basis is Auto {
          40.0
        } else {
          60.0
        },
      )
      assert_eq(items[1].bounds().size().width(), 24.0)
    }
  }
}

///|
test "intrinsic zero-flex points with auto main ignore fallback content" {
  let direction = @layout.FlowDirection::row()
  let style = @layout.FlexTreeStyle::new(direction)
  let child = tree_auto_item(
      3,
      @layout.Dimension::auto(),
      tree_points(10),
      tree_size(90, 10),
    )
    .with_flex(0, 0)
    .unwrap()
    .with_flex_basis(@layout.FlexBasis::points(20).unwrap())
  for result in intrinsic_basis_results(direction, style, [child], 1) {
    let items = result.unwrap().items()
    assert_eq(items[0].bounds().size().width(), 20.0)
    assert_eq(items[1].bounds().size().width(), 20.0)
  }
}

///|
test "intrinsic points reject flex negotiation and wrapping in pure and mixed trees" {
  let direction = @layout.FlowDirection::row()
  let style = @layout.FlexTreeStyle::new(direction)
  let child = tree_item(3, 40, 10)
    .with_flex(0, 0)
    .unwrap()
    .with_flex_basis(@layout.FlexBasis::points(20).unwrap())
  let auto = tree_item(4, 10, 10).with_flex(0, 0).unwrap()
  for
    children in [
      [child.with_flex(1, 0).unwrap()],
      [child.with_flex(0, 1).unwrap()],
      [child, auto.with_flex(1, 0).unwrap()],
      [child, auto.with_flex(0, 1).unwrap()],
      [child.with_flex_basis(@layout.FlexBasis::percent(0.5).unwrap())],
    ] {
    for result in intrinsic_basis_results(direction, style, children, 1) {
      assert_true(
        result is Err(@layout.TreeLayoutError::UnsupportedIntrinsicFlexBasis),
      )
    }
  }
  for wrap in [@layout.FlexWrap::wrap(), @layout.FlexWrap::wrap_reverse()] {
    for
      result in intrinsic_basis_results(
        direction,
        style.with_wrap(wrap),
        [child],
        1,
      ) {
      assert_true(
        result is Err(@layout.TreeLayoutError::UnsupportedIntrinsicFlexBasis),
      )
    }
  }
}
