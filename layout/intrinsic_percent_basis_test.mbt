///|
test "intrinsic percent measures authored main then resolves final inner extent" {
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
      .with_flex_basis(@layout.FlexBasis::percent(0).unwrap()),
      tree_item(4, 20, 12)
      .with_flex(0, 0)
      .unwrap()
      .with_flex_basis(@layout.FlexBasis::percent(0.5).unwrap()),
      tree_item(5, 28, 8)
      .with_flex(0, 0)
      .unwrap()
      .with_flex_basis(@layout.FlexBasis::percent(1).unwrap()),
    ]
    for scale in [1.0, 1.5, 2.0] {
      for result in intrinsic_basis_results(direction, style, children, scale) {
        let items = result.unwrap().items()
        for i, expected in [96.0, 0.0, 48.0, 96.0] {
          let bounds = items[i].bounds()
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
test "intrinsic percent empty Auto leaves use zero contribution and retain percent" {
  let direction = @layout.FlowDirection::row()
  let style = @layout.FlexTreeStyle::new(direction).with_gap(4).unwrap()
  let children = []
  for id in [3UL, 4UL, 5UL] {
    children.push(
      tree_auto_item(
        id,
        @layout.Dimension::auto(),
        tree_points(10),
        tree_size(0, 10),
      )
      .with_flex(0, 0)
      .unwrap()
      .with_flex_basis(@layout.FlexBasis::percent(0.5).unwrap()),
    )
  }
  for result in intrinsic_basis_results(direction, style, children, 1) {
    let items = result.unwrap().items()
    assert_eq(items[0].bounds().size().width(), 8.0)
    for i in 1..<4 {
      assert_eq(items[i].bounds().size().width(), 4.0)
    }
  }
}

///|
test "intrinsic percent rejects flexible wrapping and unqualified content fallback" {
  let direction = @layout.FlowDirection::row()
  let style = @layout.FlexTreeStyle::new(direction)
  let child = tree_item(3, 40, 10)
    .with_flex(0, 0)
    .unwrap()
    .with_flex_basis(@layout.FlexBasis::percent(0.5).unwrap())
  let auto = tree_item(4, 10, 10).with_flex(0, 0).unwrap()
  for
    children in [
      [child.with_flex(1, 0).unwrap()],
      [child.with_flex(0, 1).unwrap()],
      [child, auto.with_flex(1, 0).unwrap()],
      [child, auto.with_flex(0, 1).unwrap()],
      [
        tree_auto_item(
          3,
          @layout.Dimension::auto(),
          tree_points(10),
          tree_size(40, 10),
        )
        .with_flex(0, 0)
        .unwrap()
        .with_flex_basis(@layout.FlexBasis::percent(0.5).unwrap()),
      ],
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

///|
test "intrinsic percent minimum floors measurement but maximum only bounds final box" {
  let direction = @layout.FlowDirection::row()
  let style = @layout.FlexTreeStyle::new(direction)
  let basis = tree_item(3, 40, 10)
    .with_flex(0, 0)
    .unwrap()
    .with_flex_basis(@layout.FlexBasis::percent(1).unwrap())
  for
    result in intrinsic_basis_results(
      direction,
      style,
      [basis.with_main_limits(0, Some(24)).unwrap()],
      1,
    ) {
    let items = result.unwrap().items()
    assert_eq(items[0].bounds().size().width(), 40.0)
    assert_eq(items[1].bounds().size().width(), 24.0)
  }
  for
    result in intrinsic_basis_results(
      direction,
      style,
      [
        basis
        .with_main_limits(60, None)
        .unwrap()
        .with_flex_basis(@layout.FlexBasis::percent(0).unwrap()),
      ],
      1,
    ) {
    let items = result.unwrap().items()
    assert_eq(items[0].bounds().size().width(), 60.0)
    assert_eq(items[1].bounds().size().width(), 60.0)
  }
}

///|
test "intrinsic percent nested Auto fallback stays unsupported in pure and mixed trees" {
  let direction = @layout.FlowDirection::row()
  let style = @layout.FlexTreeStyle::new(direction)
  let parent = tree_auto_item(
      2,
      @layout.Dimension::auto(),
      tree_points(20),
      tree_size(0, 0),
    )
    .with_flex(0, 0)
    .unwrap()
  let child = tree_auto_item(
      3,
      @layout.Dimension::auto(),
      tree_points(10),
      tree_size(0, 0),
    )
    .with_flex(0, 0)
    .unwrap()
    .with_flex_basis(@layout.FlexBasis::percent(0.5).unwrap())
  assert_true(
    @layout.layout_flex_tree(1, tree_size(320, 260), style, [
      @layout.FlexTreeNode::new(parent, 1).with_children(style),
      @layout.FlexTreeNode::new(child, 2).with_children(style),
    ])
    is Err(@layout.TreeLayoutError::UnsupportedIntrinsicFlexBasis),
  )
  assert_true(
    @layout.layout_mixed_tree_at(
      1,
      @primitives.Rect::new(0, 0, 320, 260).unwrap(),
      @layout.FlexStyle(style),
      [
        @layout.MixedTreeNode::new(
          @layout.FlexChild(parent),
          1,
          Some(@layout.FlexStyle(style)),
        ),
        @layout.MixedTreeNode::new(
          @layout.FlexChild(child),
          2,
          Some(@layout.FlexStyle(style)),
        ),
      ],
      None,
    )
    is Err(@layout.TreeLayoutError::UnsupportedIntrinsicFlexBasis),
  )
}

///|
test "intrinsic percent precision preserves raw Double and unsnapped representation" {
  let direction = @layout.FlowDirection::row()
  let style = @layout.FlexTreeStyle::new(direction)
  let child = tree_item(3, 199, 10)
    .with_flex(0, 0)
    .unwrap()
    .with_flex_basis(@layout.FlexBasis::percent(1).unwrap())
  for result in intrinsic_basis_results(direction, style, [child], 1.5) {
    let layout = result.unwrap()
    let raw = layout.bounds_before_edge_snap(2).unwrap()
    assert_eq(raw.size().width(), 298.0 / 1.5)
    assert_eq(
      layout.items()[0].bounds().size().width(),
      Float::from_double(298.0 / 1.5).to_double(),
    )
    assert_true(raw != layout.items()[0].bounds())
  }
  let parent = tree_auto_item(
      2,
      @layout.Dimension::auto(),
      tree_points(100),
      tree_size(0, 0),
    )
    .with_flex(0, 0)
    .unwrap()
  let raw = @layout.layout_flex_tree(1, tree_size(320, 260), style, [
    @layout.FlexTreeNode::new(parent, 1).with_children(style),
    @layout.FlexTreeNode::new(child, 2),
  ]).unwrap()
  assert_eq(raw.items()[0].bounds().size().width(), 199.0)
  assert_true(
    raw.bounds_before_edge_snap(2).unwrap() == raw.items()[0].bounds(),
  )
}

///|
test "intrinsic percent precision respects translated mixed and orthogonal container axes" {
  let outer = @layout.FlexTreeStyle::new(@layout.FlowDirection::column())
  let inner = @layout.FlexTreeStyle::new(@layout.FlowDirection::row())
  // Outer column means cross Auto is physical width, the inner row's main.
  let parent = tree_auto_item(
      2,
      tree_points(100),
      @layout.Dimension::auto(),
      tree_size(0, 0),
    )
    .with_flex(0, 0)
    .unwrap()
  let child = tree_item(3, 199, 10)
    .with_flex(0, 0)
    .unwrap()
    .with_flex_basis(@layout.FlexBasis::percent(1).unwrap())
  let layout = @layout.layout_mixed_tree_at(
    1,
    @primitives.Rect::new(10.25, 20.5, 320, 260).unwrap(),
    @layout.FlexStyle(outer),
    [
      @layout.MixedTreeNode::new(
        @layout.FlexChild(parent),
        1,
        Some(@layout.FlexStyle(inner)),
      ),
      @layout.MixedTreeNode::new(@layout.FlexChild(child), 2, None),
    ],
    Some(1.5),
  ).unwrap()
  let raw = layout.bounds_before_edge_snap(2).unwrap()
  assert_eq(raw.left(), 10.25)
  assert_eq(raw.top(), 20.5)
  assert_eq(raw.size().width(), 298.0 / 1.5)
  assert_eq(layout.items()[0].bounds().left(), 10.0)
  assert_eq(
    layout.items()[0].bounds().size().width(),
    Float::from_double(298.0 / 1.5).to_double(),
  )
}
