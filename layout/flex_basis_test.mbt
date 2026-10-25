///|
fn basis_item(id : UInt64, value : Double) -> @layout.FlexItem {
  self_item(id, tree_points(12.0)).with_flex_basis(
    @layout.FlexBasis::points(value).unwrap(),
  )
}

///|
test "point flex basis independently overrides main size in all directions" {
  for
    direction in [
      @layout.FlowDirection::row(),
      @layout.FlowDirection::column(),
      @layout.FlowDirection::row_reverse(),
      @layout.FlowDirection::column_reverse(),
    ] {
    let container = alignment_container(direction, 100.0, 80.0)
    let result = unwrap_layout(
      @layout.layout_flex(container, [basis_item(1, 30.0)]),
    )
    let bounds = result.items()[0].bounds()
    match direction {
      Row | RowReverse => {
        assert_eq(bounds.size().width(), 30.0)
        assert_eq(bounds.size().height(), 12.0)
      }
      Column | ColumnReverse => {
        assert_eq(bounds.size().height(), 30.0)
        assert_eq(bounds.size().width(), 12.0)
      }
    }
  }
}

///|
test "basis builders preserve independent size and Auto restores authored main" {
  let container = alignment_container(@layout.FlowDirection::row(), 100.0, 80.0)
  let item = basis_item(1, 30.0).with_align_self(@layout.AlignSelf::end())
  let item = unwrap_item_flex(item, 0.0, 1.0)
  let item = unwrap_main_limits(item, 0.0, None)
  let item = self_cross_limits(item, 0.0, None).with_intrinsic(
    tree_size(90.0, 90.0),
  )
  let result = unwrap_layout(@layout.layout_flex(container, [item])).items()
  assert_eq(result[0].bounds().size().width(), 30.0)
  assert_eq(result[0].bounds().top(), 68.0)
  let result = unwrap_layout(
    @layout.layout_flex(container, [
      item.with_flex_basis(@layout.FlexBasis::auto()),
    ]),
  ).items()
  assert_eq(result[0].bounds().size().width(), 10.0)
}

///|
test "zero basis grows from zero rather than authored main" {
  let container = alignment_container(@layout.FlowDirection::row(), 100.0, 20.0)
  let result = unwrap_layout(
    @layout.layout_flex(container, [
      unwrap_item_flex(basis_item(1, 0.0), 1.0, 1.0),
      unwrap_item_flex(basis_item(2, 20.0), 1.0, 1.0),
    ]),
  ).items()
  assert_eq(result[0].bounds().size().width(), 40.0)
  assert_eq(result[1].bounds().size().width(), 60.0)
}

///|
test "shrink weights and main limits use independent basis" {
  let container = alignment_container(@layout.FlowDirection::row(), 60.0, 20.0)
  let result = unwrap_layout(
    @layout.layout_flex(container, [basis_item(1, 80.0), basis_item(2, 40.0)]),
  ).items()
  assert_eq(result[0].bounds().size().width(), 40.0)
  assert_eq(result[1].bounds().size().width(), 20.0)
  let result = unwrap_layout(
    @layout.layout_flex(container, [
      unwrap_main_limits(basis_item(1, 80.0), 50.0, None),
      basis_item(2, 40.0),
    ]),
  ).items()
  assert_eq(result[0].bounds().size().width(), 50.0)
  assert_eq(result[1].bounds().size().width(), 10.0)
}

///|
test "wrapping uses independent basis not authored main" {
  let container = alignment_container(@layout.FlowDirection::row(), 50.0, 40.0).with_wrap(
    @layout.FlexWrap::wrap(),
  )
  let result = unwrap_layout(
    @layout.layout_flex(container, [basis_item(1, 30.0), basis_item(2, 30.0)]),
  ).items()
  assert_eq(result[0].bounds().left(), 0.0)
  assert_eq(result[1].bounds().left(), 0.0)
  assert_true(result[1].bounds().top() > result[0].bounds().top())
}

///|
test "basis constructor and layout reject invalid raw values" {
  for value in [-1.0, 0.0 / 0.0, 1.0 / 0.0] {
    assert_true(@layout.FlexBasis::points(value) is Err(_))
  }
}

///|
test "recursive device grid retains and snaps point basis" {
  let style = @layout.FlexTreeStyle::new(@layout.FlowDirection::row())
  let node = @layout.FlexTreeNode::new(basis_item(2, 30.26), 1)
  for scale in [1.0, 2.0] {
    let result = @layout.layout_flex_tree_with_device_scale(
      1,
      tree_size(100.0, 80.0),
      style,
      [node],
      scale,
    ).unwrap()
    assert_eq(
      result.items()[0].bounds().size().width(),
      if scale == 1.0 {
        30.0
      } else {
        30.5
      },
    )
  }
}

///|
test "intrinsic flex containers reject point basis with default shrink negotiation" {
  let style = @layout.FlexTreeStyle::new(@layout.FlowDirection::row())
  let branch = tree_auto_item(
    2,
    @layout.Dimension::auto(),
    tree_points(20.0),
    tree_size(0.0, 0.0),
  )
  let child = basis_item(3, 30.0)
  assert_true(
    @layout.layout_flex_tree(1, tree_size(100.0, 80.0), style, [
      @layout.FlexTreeNode::new(branch, 1).with_children(style),
      @layout.FlexTreeNode::new(child, 2),
    ])
    is Err(@layout.TreeLayoutError::UnsupportedIntrinsicFlexBasis),
  )
  let viewport = @primitives.Rect::new(0.0, 0.0, 100.0, 80.0).unwrap()
  assert_true(
    @layout.layout_mixed_tree_at(
      1,
      viewport,
      @layout.FlexStyle(style),
      [
        @layout.MixedTreeNode::new(
          @layout.FlexChild(branch),
          1,
          Some(@layout.FlexStyle(style)),
        ),
        @layout.MixedTreeNode::new(@layout.FlexChild(child), 2, None),
      ],
      None,
    )
    is Err(@layout.TreeLayoutError::UnsupportedIntrinsicFlexBasis),
  )
}
