///|
test "device grid reverse distributed spacing uses physical origin f32 accumulation" {
  for
    direction in [
      @layout.FlowDirection::row_reverse(),
      @layout.FlowDirection::column_reverse(),
    ] {
    let row = direction is RowReverse
    for
      wrap in [
        @layout.FlexWrap::no_wrap(),
        @layout.FlexWrap::wrap(),
        @layout.FlexWrap::wrap_reverse(),
      ] {
      let padding = if row {
        tree_insets(0, 10, 0, 14)
      } else {
        tree_insets(14, 0, 10, 0)
      }
      let style = @layout.FlexTreeStyle::new(direction)
        .with_wrap(wrap)
        .with_gap(6)
        .unwrap()
        .with_insets(padding, @layout.Insets::zero())
        .with_justify(@layout.JustifyContent::space_around())
      let pure : Array[@layout.FlexTreeNode] = []
      let mixed : Array[@layout.MixedTreeNode] = []
      for index, size in [12.0, 20.0, 49.0] {
        let item = tree_item((index + 2).to_uint64(), size, 10)
          .with_flex(0, 0)
          .unwrap()
        pure.push(@layout.FlexTreeNode::new(item, 1))
        mixed.push(@layout.MixedTreeNode::new(@layout.FlexChild(item), 1, None))
      }
      let viewport = if row { tree_size(142, 100) } else { tree_size(100, 142) }
      for scale in [1.0, 1.5, 2.0] {
        let results = [
          @layout.layout_flex_tree_with_device_scale(
            1, viewport, style, pure, scale,
          ),
          @layout.layout_mixed_tree_at(
            1,
            @primitives.Rect::new(0, 0, viewport.width(), viewport.height()).unwrap(),
            @layout.FlexStyle(style),
            mixed,
            Some(scale),
          ),
        ]
        for result in results {
          let box = result.unwrap().items()[1].bounds()
          let main = if row { box.left() } else { box.top() }
          // At scale 1 this is 81.5000076 device pixels, not exact 81.5.
          if scale == 1.0 {
            assert_eq(main, 82.0)
          }
        }
      }
      // Raw logical layout is intentionally still Double: it exposes 81.5.
      let raw = @layout.layout_flex_tree(1, viewport, style, pure)
      .unwrap()
      .items()[1].bounds()
      assert_eq(if row { raw.left() } else { raw.top() }, 81.5)
      let raw_mixed = @layout.layout_mixed_tree_at(
        1,
        @primitives.Rect::new(0, 0, viewport.width(), viewport.height()).unwrap(),
        @layout.FlexStyle(style),
        mixed,
        None,
      )
      .unwrap()
      .items()[1].bounds()
      assert_eq(if row { raw_mixed.left() } else { raw_mixed.top() }, 81.5)
    }
  }
}

///|
test "device grid forward distributed spacing preserves f32 near and far edges" {
  for
    direction in [@layout.FlowDirection::row(), @layout.FlowDirection::column()] {
    let row = direction is Row
    let style = @layout.FlexTreeStyle::new(direction)
      .with_gap(6)
      .unwrap()
      .with_insets(
        if row {
          tree_insets(0, 10, 0, 0)
        } else {
          tree_insets(0, 0, 10, 0)
        },
        @layout.Insets::zero(),
      )
      .with_justify(@layout.JustifyContent::space_around())
    let nodes : Array[@layout.FlexTreeNode] = []
    for index, size in [12.0, 20.0, 49.0] {
      nodes.push(
        @layout.FlexTreeNode::new(
          tree_item((index + 2).to_uint64(), size, 10).with_flex(0, 0).unwrap(),
          1,
        ),
      )
    }
    let result = @layout.layout_flex_tree_with_device_scale(
      1,
      if row {
        tree_size(142, 100)
      } else {
        tree_size(100, 142)
      },
      style,
      nodes,
      1.5,
    ).unwrap()
    let bounds = result.items()[1].bounds()
    assert_eq(if row { bounds.left() } else { bounds.top() }, 56.0 / 1.5)
    assert_eq(
      if row {
        bounds.size().width()
      } else {
        bounds.size().height()
      },
      20.0,
    )
  }
}

///|
test "device distributed percent basis retains established far edge" {
  for
    wrap in [
      @layout.FlexWrap::no_wrap(),
      @layout.FlexWrap::wrap(),
      @layout.FlexWrap::wrap_reverse(),
    ] {
    let style = @layout.FlexTreeStyle::new(
        @layout.FlowDirection::column_reverse(),
      )
      .with_wrap(wrap)
      .with_gap(2)
      .unwrap()
      .with_insets(tree_insets(3, 14, 13, 2), tree_insets(0, 2, 2, 0))
      .with_justify(@layout.JustifyContent::space_around())
    let first = tree_item(2, 10, 25)
      .with_flex(0, 0)
      .unwrap()
      .with_flex_basis(@layout.FlexBasis::points(45).unwrap())
    let second = tree_item(3, 10, 57)
      .with_flex(0, 0)
      .unwrap()
      .with_flex_basis(@layout.FlexBasis::percent(1.0 / 3.0).unwrap())
    let pure = [
      @layout.FlexTreeNode::new(first, 1),
      @layout.FlexTreeNode::new(second, 1),
    ]
    let mixed = [
      @layout.MixedTreeNode::new(@layout.FlexChild(first), 1, None),
      @layout.MixedTreeNode::new(@layout.FlexChild(second), 1, None),
    ]
    for
      result in [
        @layout.layout_flex_tree_with_device_scale(
          1,
          tree_size(179, 487),
          style,
          pure,
          2,
        ),
        @layout.layout_mixed_tree_at(
          1,
          @primitives.Rect::new(0, 0, 179, 487).unwrap(),
          @layout.FlexStyle(style),
          mixed,
          Some(2),
        ),
      ] {
      let box = result.unwrap().items()[1].bounds()
      assert_eq(box.top(), 69.5)
      assert_eq(box.size().height(), 156.0)
    }
  }
}

///|
test "translated distributed container preserves established device path" {
  let style = @layout.FlexTreeStyle::new(@layout.FlowDirection::row_reverse())
    .with_gap(6)
    .unwrap()
    .with_insets(tree_insets(0, 10, 0, 14), @layout.Insets::zero())
    .with_justify(@layout.JustifyContent::space_around())
  let mixed : Array[@layout.MixedTreeNode] = []
  for index, size in [12.0, 20.0, 49.0] {
    mixed.push(
      @layout.MixedTreeNode::new(
        @layout.FlexChild(
          tree_item((index + 2).to_uint64(), size, 10).with_flex(0, 0).unwrap(),
        ),
        1,
        None,
      ),
    )
  }
  let result = @layout.layout_mixed_tree_at(
    1,
    @primitives.Rect::new(47, 0, 142, 100).unwrap(),
    @layout.FlexStyle(style),
    mixed,
    Some(1),
  ).unwrap()
  assert_eq(result.items()[1].bounds().left(), 128.0)
}

///|
test "nested pure distributed container preserves absolute origin precision" {
  let root_style = @layout.FlexTreeStyle::new(@layout.FlowDirection::row()).with_insets(
    tree_insets(0, 0, 0, 47),
    @layout.Insets::zero(),
  )
  let child_style = @layout.FlexTreeStyle::new(
      @layout.FlowDirection::row_reverse(),
    )
    .with_gap(6)
    .unwrap()
    .with_insets(tree_insets(0, 10, 0, 14), @layout.Insets::zero())
    .with_justify(@layout.JustifyContent::space_around())
  let nodes = [
    @layout.FlexTreeNode::new(
      tree_item(2, 142, 100).with_flex(0, 0).unwrap(),
      1,
    ).with_children(child_style),
  ]
  for index, size in [12.0, 20.0, 49.0] {
    nodes.push(
      @layout.FlexTreeNode::new(
        tree_item((index + 3).to_uint64(), size, 10).with_flex(0, 0).unwrap(),
        2,
      ),
    )
  }
  let result = @layout.layout_flex_tree_with_device_scale(
    1,
    tree_size(189, 100),
    root_style,
    nodes,
    1,
  ).unwrap()
  assert_eq(result.items()[2].bounds().left(), 128.0)
}
