///|
fn percent_basis_item(id : UInt64, ratio : Double) -> @layout.FlexItem {
  basis_item(id, 1.0).with_flex_basis(
    @layout.FlexBasis::percent(ratio).unwrap(),
  )
}

///|
test "percentage basis uses inner main extent before gap in every direction" {
  for
    direction in [
      @layout.FlowDirection::row(),
      @layout.FlowDirection::column(),
      @layout.FlowDirection::row_reverse(),
      @layout.FlowDirection::column_reverse(),
    ] {
    let style = @layout.FlexTreeStyle::new(direction)
      .with_insets(
        tree_insets(2.0, 3.0, 4.0, 5.0),
        tree_insets(1.0, 1.0, 1.0, 1.0),
      )
      .with_gap(7.0)
      .unwrap()
    let result = @layout.layout_flex_tree(1, tree_size(100.0, 80.0), style, [
        @layout.FlexTreeNode::new(percent_basis_item(2, 0.25), 1),
        @layout.FlexTreeNode::new(percent_basis_item(3, 0.5), 1),
      ])
      .unwrap()
      .items()
    for index in 0..<2 {
      let bounds = result[index].bounds()
      let ratio = if index == 0 { 0.25 } else { 0.5 }
      match direction {
        Row | RowReverse => {
          assert_eq(bounds.size().width(), 90.0 * ratio)
          assert_eq(bounds.size().height(), 12.0)
        }
        Column | ColumnReverse => {
          assert_eq(bounds.size().height(), 72.0 * ratio)
          assert_eq(bounds.size().width(), 12.0)
        }
      }
    }
  }
}

///|
test "percentage basis controls shrink weights and min max freezing" {
  let container = alignment_container(@layout.FlowDirection::row(), 100.0, 30.0)
    .with_gap(10.0)
    .unwrap()
  let items = [percent_basis_item(1, 0.8), percent_basis_item(2, 0.4)]
  let result = unwrap_layout(@layout.layout_flex(container, items)).items()
  assert_eq(result[0].bounds().size().width(), 60.0)
  assert_eq(result[1].bounds().size().width(), 30.0)
  let result = unwrap_layout(
    @layout.layout_flex(container, [
      unwrap_main_limits(items[0], 70.0, None),
      items[1],
    ]),
  ).items()
  assert_eq(result[0].bounds().size().width(), 70.0)
  assert_eq(result[1].bounds().size().width(), 20.0)
  let result = unwrap_layout(
    @layout.layout_flex(container, [
      unwrap_main_limits(
        unwrap_item_flex(percent_basis_item(1, 0.2), 1.0, 1.0),
        0.0,
        Some(30.0),
      ),
      unwrap_item_flex(percent_basis_item(2, 0.2), 1.0, 1.0),
    ]),
  ).items()
  assert_eq(result[0].bounds().size().width(), 30.0)
  assert_eq(result[1].bounds().size().width(), 60.0)
}

///|
test "percentage basis zero and oversized ratios remain distinct from Auto" {
  let container = alignment_container(@layout.FlowDirection::row(), 100.0, 30.0)
  for (ratio, expected) in [(0.0, 0.0), (1.0, 100.0), (1.25, 125.0)] {
    let item = unwrap_item_flex(percent_basis_item(1, ratio), 0.0, 0.0)
      .with_align_self(@layout.AlignSelf::end())
      .with_intrinsic(tree_size(90.0, 90.0))
    let item = self_cross_limits(unwrap_main_limits(item, 0.0, None), 0.0, None)
    let result = unwrap_layout(@layout.layout_flex(container, [item])).items()
    assert_eq(result[0].bounds().size().width(), expected)
    assert_eq(result[0].bounds().top(), 18.0)
    let restored = unwrap_layout(
      @layout.layout_flex(container, [
        item.with_flex_basis(@layout.FlexBasis::auto()),
      ]),
    ).items()
    assert_eq(restored[0].bounds().size().width(), 10.0)
  }
}

///|
test "percentage wrap sizing is fixed before lines are formed" {
  for wrap in [@layout.FlexWrap::wrap(), @layout.FlexWrap::wrap_reverse()] {
    let container = alignment_container(
        @layout.FlowDirection::row(),
        100.0,
        50.0,
      )
      .with_wrap(wrap)
      .with_gap(1.0)
      .unwrap()
    let result = unwrap_layout(
      @layout.layout_flex(container, [
        percent_basis_item(1, 0.5),
        percent_basis_item(2, 0.5),
      ]),
    ).items()
    assert_eq(result[0].bounds().size().width(), 50.0)
    assert_eq(result[1].bounds().size().width(), 50.0)
    assert_eq(result[0].bounds().left(), 0.0)
    assert_eq(result[1].bounds().left(), 0.0)
    assert_true(result[0].bounds().top() != result[1].bounds().top())
  }
}

///|
test "percentage ratios are not snapped as point lengths" {
  let style = @layout.FlexTreeStyle::new(@layout.FlowDirection::row())
  for (scale, expected) in [(1.0, 34.0), (1.5, 52.0 / 1.5), (2.0, 34.5)] {
    let result = @layout.layout_flex_tree_with_device_scale(
        1,
        tree_size(101.0, 50.0),
        style,
        [@layout.FlexTreeNode::new(percent_basis_item(2, 0.34), 1)],
        scale,
      )
      .unwrap()
      .items()
    assert_eq(result[0].bounds().size().width(), expected)
  }
}

///|
test "nested percentages resolve against allocated parent in pure and mixed trees" {
  let style = @layout.FlexTreeStyle::new(@layout.FlowDirection::row())
  let parent = tree_auto_item(
    2,
    tree_points(180.0),
    @layout.Dimension::auto(),
    tree_size(0.0, 0.0),
  ).with_flex_basis(@layout.FlexBasis::percent(0.5).unwrap())
  let child = percent_basis_item(3, 0.5)
  let pure = @layout.layout_flex_tree(1, tree_size(200.0, 80.0), style, [
      @layout.FlexTreeNode::new(parent, 1).with_children(style),
      @layout.FlexTreeNode::new(child, 2),
    ])
    .unwrap()
    .items()
  let mixed = @layout.layout_mixed_tree_at(
      1,
      @primitives.Rect::new(0.0, 0.0, 200.0, 80.0).unwrap(),
      @layout.FlexStyle(style),
      [
        @layout.MixedTreeNode::new(
          @layout.FlexChild(parent),
          1,
          Some(@layout.FlexStyle(style)),
        ),
        @layout.MixedTreeNode::new(@layout.FlexChild(child), 2, None),
      ],
      Some(1.5),
    )
    .unwrap()
    .items()
  for items in [pure, mixed] {
    assert_eq(items[0].bounds().size().width(), 100.0)
    assert_eq(items[1].bounds().size().width(), 50.0)
    assert_eq(items[0].bounds().size().height(), 12.0)
  }
}

///|
test "intrinsic main axis still rejects percentage basis in pure and mixed trees" {
  let style = @layout.FlexTreeStyle::new(@layout.FlowDirection::row())
  let parent = tree_auto_item(
    2,
    @layout.Dimension::auto(),
    tree_points(20.0),
    tree_size(0.0, 0.0),
  )
  let child = percent_basis_item(3, 0.0)
  assert_true(
    @layout.layout_flex_tree(1, tree_size(100.0, 80.0), style, [
      @layout.FlexTreeNode::new(parent, 1).with_children(style),
      @layout.FlexTreeNode::new(child, 2),
    ])
    is Err(@layout.TreeLayoutError::UnsupportedIntrinsicFlexBasis),
  )
  assert_true(
    @layout.layout_mixed_tree_at(
      1,
      @primitives.Rect::new(0.0, 0.0, 100.0, 80.0).unwrap(),
      @layout.FlexStyle(style),
      [
        @layout.MixedTreeNode::new(
          @layout.FlexChild(parent),
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

///|
test "percentage basis rejects invalid ratios and finite product overflow" {
  for value in [-1.0, 0.0 / 0.0, 1.0 / 0.0] {
    assert_true(@layout.FlexBasis::percent(value) is Err(_))
  }
  let item = percent_basis_item(1, 1.0e308)
  assert_true(
    @layout.layout_flex(
      alignment_container(@layout.FlowDirection::row(), 100.0, 30.0),
      [item],
    )
    is Err(@layout.LayoutError::NonFiniteValue),
  )
  let result = unwrap_layout(
    @layout.layout_flex(
      alignment_container(@layout.FlowDirection::row(), 0.0, 30.0),
      [item],
    ),
  ).items()
  assert_eq(result[0].bounds().size().width(), 0.0)
}
