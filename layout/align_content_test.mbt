///|
fn content_container(
  direction : @layout.FlowDirection,
  main : Double,
  cross : Double,
) -> @layout.FlexContainer raise {
  let size = if direction == @layout.FlowDirection::row() {
    unwrap_wrap_size(main, cross)
  } else {
    unwrap_wrap_size(cross, main)
  }
  unwrap_wrap_gap(@layout.FlexContainer::new(direction, size), 4.0)
}

///|
fn content_items(
  direction : @layout.FlowDirection,
  main~ : Double = 40.0,
) -> Array[@layout.FlexItem] raise {
  if direction == @layout.FlowDirection::row() {
    [wrap_item(1, main, 10.0), wrap_item(2, main, 14.0)]
  } else {
    [wrap_column_item(1, 10.0, main), wrap_column_item(2, 14.0, main)]
  }
}

///|
fn content_origins(
  result : @layout.FlexLayout,
  direction : @layout.FlowDirection,
) -> Array[Double] {
  result
  .items()
  .map(item => {
    if direction == @layout.FlowDirection::row() {
      item.bounds().top()
    } else {
      item.bounds().left()
    }
  })
}

///|
test "align-content places unequal wrapped lines in both axes and wrap directions" {
  for
    direction in [@layout.FlowDirection::row(), @layout.FlowDirection::column()] {
    for
      (alignment, normal, reverse) in [
        (@layout.AlignContent::start(), [0.0, 14.0], [54.0, 36.0]),
        (@layout.AlignContent::center(), [18.0, 32.0], [36.0, 18.0]),
        (@layout.AlignContent::end(), [36.0, 50.0], [18.0, 0.0]),
        (@layout.AlignContent::stretch(), [0.0, 32.0], [54.0, 18.0]),
      ] {
      let base = content_container(direction, 60.0, 64.0).with_align_content(
        alignment,
      )
      for
        (wrap, expected) in [
          (@layout.FlexWrap::wrap(), normal),
          (@layout.FlexWrap::wrap_reverse(), reverse),
        ] {
        let result = unwrap_layout(
          @layout.layout_flex(base.with_wrap(wrap), content_items(direction)),
        )
        assert_eq(content_origins(result, direction), expected)
        assert_eq(result.items().map(item => item.id()), [1UL, 2UL])
        assert_true(!result.overflow())
        assert_eq(result.items().map(item => item.overflow()), [false, false])
      }
    }
  }
}

///|
test "explicit align-content keeps signed overflow while stretch remains safe" {
  for
    direction in [@layout.FlowDirection::row(), @layout.FlowDirection::column()] {
    for
      (alignment, normal, reverse, normal_flags, reverse_flags) in [
        (
          @layout.AlignContent::start(),
          [0.0, 14.0],
          [10.0, -8.0],
          [false, true],
          [false, true],
        ),
        (
          @layout.AlignContent::center(),
          [-4.0, 10.0],
          [14.0, -4.0],
          [true, true],
          [true, true],
        ),
        (
          @layout.AlignContent::end(),
          [-8.0, 6.0],
          [18.0, 0.0],
          [true, false],
          [true, false],
        ),
        (
          @layout.AlignContent::stretch(),
          [0.0, 14.0],
          [18.0, 0.0],
          [false, true],
          [true, false],
        ),
      ] {
      let base = content_container(direction, 60.0, 20.0).with_align_content(
        alignment,
      )
      for
        (wrap, expected, flags) in [
          (@layout.FlexWrap::wrap(), normal, normal_flags),
          (@layout.FlexWrap::wrap_reverse(), reverse, reverse_flags),
        ] {
        let result = unwrap_layout(
          @layout.layout_flex(base.with_wrap(wrap), content_items(direction)),
        )
        assert_eq(content_origins(result, direction), expected)
        assert_eq(result.items().map(item => item.overflow()), flags)
        assert_true(result.overflow())
      }
    }
  }
}

///|
test "align-content handles empty exact-fit and single wrapped lines without changing nowrap" {
  for
    direction in [@layout.FlowDirection::row(), @layout.FlowDirection::column()] {
    for
      (alignment, single_origin) in [
        (@layout.AlignContent::start(), 0.0),
        (@layout.AlignContent::center(), 25.0),
        (@layout.AlignContent::end(), 50.0),
        (@layout.AlignContent::stretch(), 0.0),
      ] {
      let base = content_container(direction, 60.0, 64.0).with_align_content(
        alignment,
      )
      for wrap in [@layout.FlexWrap::wrap(), @layout.FlexWrap::wrap_reverse()] {
        let empty = unwrap_layout(@layout.layout_flex(base.with_wrap(wrap), []))
        assert_eq(empty.items().length(), 0)
        assert_true(!empty.overflow())
        let exact = unwrap_layout(
          @layout.layout_flex(
            content_container(direction, 60.0, 28.0)
            .with_align_content(alignment)
            .with_wrap(wrap),
            content_items(direction),
          ),
        )
        assert_eq(
          content_origins(exact, direction),
          if wrap == @layout.FlexWrap::wrap() {
            [0.0, 14.0]
          } else {
            [18.0, 0.0]
          },
        )
        assert_true(!exact.overflow())
      }
      let single = unwrap_layout(
        @layout.layout_flex(
          base.with_wrap(@layout.FlexWrap::wrap()),
          content_items(direction, main=20.0),
        ),
      )
      assert_eq(content_origins(single, direction), [
        single_origin, single_origin,
      ])
      assert_true(!single.overflow())
      let nowrap = unwrap_layout(
        @layout.layout_flex(
          base
          .with_wrap(@layout.FlexWrap::no_wrap())
          .with_align(@layout.AlignItems::center()),
          content_items(direction, main=20.0),
        ),
      )
      assert_eq(content_origins(nowrap, direction), [27.0, 25.0])
      assert_true(!nowrap.overflow())
    }
  }
}

///|
test "align-content stretch grows line boxes while item stretching still respects cross limits" {
  let first = @layout.FlexItem::new(
    1,
    tree_points(40.0),
    @layout.Dimension::auto(),
    tree_size(40.0, 0.0),
  )
  let first = match first.with_cross_limits(10.0, Some(18.0)) {
    Ok(value) => value
    Err(_) => fail("valid cross limits rejected")
  }
  for
    (alignment, y, height) in [
      (@layout.AlignContent::start(), 0.0, 10.0),
      (@layout.AlignContent::center(), 18.0, 10.0),
      (@layout.AlignContent::end(), 36.0, 10.0),
      (@layout.AlignContent::stretch(), 0.0, 18.0),
    ] {
    let result = unwrap_layout(
      @layout.layout_flex(
        content_container(@layout.FlowDirection::row(), 60.0, 64.0)
        .with_align_content(alignment)
        .with_align(@layout.AlignItems::stretch())
        .with_wrap(@layout.FlexWrap::wrap()),
        [first, wrap_item(2, 40.0, 14.0)],
      ),
    )
    assert_eq(result.items()[0].bounds().top(), y)
    assert_eq(result.items()[0].bounds().size().height(), height)
    assert_eq(result.items()[1].bounds().size().height(), 14.0)
    assert_true(!result.overflow())
  }
}

///|
test "container builders preserve align-content and use inner bounds" {
  let base = @layout.FlexContainer::new(
      @layout.FlowDirection::row(),
      tree_size(60.0, 64.0),
    )
    .with_align_content(@layout.AlignContent::end())
    .with_insets(
      tree_insets(3.0, 2.0, 5.0, 1.0),
      tree_insets(1.0, 0.0, 1.0, 1.0),
    )
    .with_justify(@layout.JustifyContent::end())
    .with_align(@layout.AlignItems::center())
    .with_wrap(@layout.FlexWrap::wrap())
  let base = unwrap_wrap_gap(base, 4.0)
  let result = unwrap_layout(
    @layout.layout_flex(base, content_items(@layout.FlowDirection::row())),
  )
  assert_eq(wrap_line_bounds(result.items()), [
    (18.0, 30.0, 40.0, 10.0),
    (18.0, 44.0, 40.0, 14.0),
  ])
  assert_true(!result.overflow())
}

///|
test "tree builders and device-scale copying preserve nested align-content" {
  let root_style = @layout.FlexTreeStyle::new(@layout.FlowDirection::row())
    .with_align_content(@layout.AlignContent::center())
    .with_insets(tree_insets(1.0, 0.0, 1.0, 0.0), @layout.Insets::zero())
    .with_justify(@layout.JustifyContent::start())
    .with_align(@layout.AlignItems::start())
    .with_wrap(@layout.FlexWrap::wrap())
  let root_style = match root_style.with_gap(0.0) {
    Ok(value) => value
    Err(_) => fail("valid root gap rejected")
  }
  let child_style = @layout.FlexTreeStyle::new(@layout.FlowDirection::row())
    .with_align_content(@layout.AlignContent::end())
    .with_insets(
      tree_insets(3.0, 2.0, 5.0, 1.0),
      tree_insets(1.0, 0.0, 1.0, 1.0),
    )
    .with_justify(@layout.JustifyContent::end())
    .with_align(@layout.AlignItems::center())
    .with_wrap(@layout.FlexWrap::wrap())
  let child_style = match child_style.with_gap(4.0) {
    Ok(value) => value
    Err(_) => fail("valid nested gap rejected")
  }
  let nodes = [
    @layout.FlexTreeNode::new(tree_item(2, 60.0, 64.0), 1).with_children(
      child_style,
    ),
    @layout.FlexTreeNode::new(tree_item(3, 40.0, 10.0), 2),
    @layout.FlexTreeNode::new(tree_item(4, 40.0, 14.0), 2),
  ]
  for
    result in [
      @layout.layout_flex_tree(1, tree_size(60.0, 100.0), root_style, nodes),
      @layout.layout_flex_tree_with_device_scale(
        1,
        tree_size(60.0, 100.0),
        root_style,
        nodes,
        2.0,
      ),
    ] {
    let result = match result {
      Ok(value) => value
      Err(_) => fail("valid nested align-content tree rejected")
    }
    assert_eq(result.items().map(item => item.id()), [2UL, 3UL, 4UL])
    assert_eq(
      result
      .items()
      .map(item => {
        let bounds = item.bounds()
        (
          bounds.left(),
          bounds.top(),
          bounds.size().width(),
          bounds.size().height(),
        )
      }),
      [
        (0.0, 18.0, 60.0, 64.0),
        (18.0, 48.0, 40.0, 10.0),
        (18.0, 62.0, 40.0, 14.0),
      ],
    )
    assert_true(!result.overflow())
  }
}

///|
test "reverse align-content anchors survive widely different finite line sizes" {
  let base = content_container(@layout.FlowDirection::row(), 60.0, 21.0).with_wrap(
    @layout.FlexWrap::wrap_reverse(),
  )
  for
    alignment in [@layout.AlignContent::stretch(), @layout.AlignContent::end()] {
    let result = unwrap_layout(
      @layout.layout_flex(base.with_align_content(alignment), [
        wrap_item(1, 40.0, 1.0e16),
        wrap_item(2, 40.0, 1.0),
      ]),
    )
    assert_eq(content_origins(result, @layout.FlowDirection::row()), [5.0, 0.0])
    assert_eq(result.items().map(item => item.overflow()), [true, false])
    assert_true(result.overflow())
  }
  let result = unwrap_layout(
    @layout.layout_flex(
      base.with_align_content(@layout.AlignContent::start()),
      [wrap_item(1, 40.0, 1.0), wrap_item(2, 40.0, 1.0e16)],
    ),
  )
  assert_eq(result.items()[0].bounds().top(), 20.0)
  assert_eq(result.items()[0].bounds().bottom(), 21.0)
  assert_true(!result.items()[0].overflow())
  assert_true(result.overflow())
}

///|
test "reverse single wrapped line keeps content and item alignment independent" {
  for
    direction in [@layout.FlowDirection::row(), @layout.FlowDirection::column()] {
    for
      (alignment, expected) in [
        (@layout.AlignContent::start(), [54.0, 50.0]),
        (@layout.AlignContent::center(), [29.0, 25.0]),
        (@layout.AlignContent::end(), [4.0, 0.0]),
        (@layout.AlignContent::stretch(), [54.0, 50.0]),
      ] {
      let result = unwrap_layout(
        @layout.layout_flex(
          content_container(direction, 60.0, 64.0)
          .with_align_content(alignment)
          .with_wrap(@layout.FlexWrap::wrap_reverse()),
          content_items(direction, main=20.0),
        ),
      )
      assert_eq(content_origins(result, direction), expected)
      assert_true(!result.overflow())
    }
  }
}

///|
test "content alignment preserves fractional signed device-grid boundaries" {
  let nodes = [
    @layout.FlexTreeNode::new(tree_item(2, 40.0, 10.75), 1),
    @layout.FlexTreeNode::new(tree_item(3, 40.0, 14.75), 1),
  ]
  for
    (alignment, wrap, expected) in [
      (
        @layout.AlignContent::center(),
        @layout.FlexWrap::wrap(),
        [(-4.5, 10.5), (10.0, 14.5)],
      ),
      (
        @layout.AlignContent::end(),
        @layout.FlexWrap::wrap(),
        [(-8.5, 10.0), (5.5, 14.5)],
      ),
      (
        @layout.AlignContent::center(),
        @layout.FlexWrap::wrap_reverse(),
        [(14.0, 10.5), (-4.5, 14.5)],
      ),
      (
        @layout.AlignContent::end(),
        @layout.FlexWrap::wrap_reverse(),
        [(18.5, 10.5), (0.0, 14.5)],
      ),
    ] {
    let style = @layout.FlexTreeStyle::new(@layout.FlowDirection::row())
      .with_align_content(alignment)
      .with_wrap(wrap)
    let style = match style.with_gap(4.25) {
      Ok(value) => value
      Err(_) => fail("valid fractional gap rejected")
    }
    let result = match
      @layout.layout_flex_tree_with_device_scale(
        1,
        tree_size(60.0, 20.25),
        style,
        nodes,
        2.0,
      ) {
      Ok(value) => value
      Err(_) => fail("valid fractional align-content tree rejected")
    }
    assert_eq(
      result
      .items()
      .map(item => (item.bounds().top(), item.bounds().size().height())),
      expected,
    )
    assert_eq(result.root_bounds().size().height(), 20.0)
    assert_true(result.overflow())
  }
}
