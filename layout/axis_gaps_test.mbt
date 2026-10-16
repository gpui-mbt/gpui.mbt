///|
fn[T] axis_gap_ok(result : Result[T, @layout.LayoutError]) -> T raise {
  match result {
    Ok(value) => value
    Err(_) => fail("valid physical gap input was rejected")
  }
}

///|
fn axis_gaps(
  container : @layout.FlexContainer,
  x : Double,
  y : Double,
) -> @layout.FlexContainer raise {
  axis_gap_ok(axis_gap_ok(container.with_gap_x(x)).with_gap_y(y))
}

///|
fn axis_style(
  style : @layout.FlexTreeStyle,
  x : Double,
  y : Double,
) -> @layout.FlexTreeStyle raise {
  axis_gap_ok(axis_gap_ok(style.with_gap_x(x)).with_gap_y(y))
}

///|
fn axis_oriented_gaps(
  container : @layout.FlexContainer,
  direction : @layout.FlowDirection,
  main : Double,
  cross : Double,
) -> @layout.FlexContainer raise {
  if direction is @layout.Row {
    axis_gaps(container, main, cross)
  } else {
    axis_gaps(container, cross, main)
  }
}

///|
fn axis_tree_layout(
  size : @primitives.Size,
  style : @layout.FlexTreeStyle,
  nodes : Array[@layout.FlexTreeNode],
  scale~ : Double? = None,
) -> @layout.FlexTreeLayout raise {
  let result = match scale {
    None => @layout.layout_flex_tree(1, size, style, nodes)
    Some(scale) =>
      @layout.layout_flex_tree_with_device_scale(1, size, style, nodes, scale)
  }
  match result {
    Ok(value) => value
    Err(_) => fail("valid physical-gap tree was rejected")
  }
}

///|
test "physical gaps select the item axis in row and column nowrap" {
  for
    (direction, main_gap) in [
      (@layout.FlowDirection::row(), 3.5),
      (@layout.FlowDirection::column(), 7.5),
    ] {
    let result = unwrap_layout(
      @layout.layout_flex(
        axis_gaps(alignment_container(direction, 100.0, 20.0), 3.5, 7.5),
        [alignment_item(1, 20.0, 10.0), alignment_item(2, 20.0, 10.0)],
      ),
    )
    assert_eq(grow_main_bounds(result, direction), [
      (0.0, 20.0),
      (20.0 + main_gap, 20.0),
    ])
    assert_eq(content_origins(result, direction), [0.0, 0.0])
    assert_true(!result.overflow())
  }
}

///|
test "independent physical gaps place items and lines under wrap and reverse" {
  for
    (direction, second_main, third_cross, reverse_third) in [
      (@layout.FlowDirection::row(), 44.0, 26.0, 20.0),
      (@layout.FlowDirection::column(), 52.0, 18.0, 28.0),
    ] {
    for
      (wrap, expected_cross) in [
        (@layout.FlexWrap::wrap(), [0.0, 0.0, third_cross]),
        (@layout.FlexWrap::wrap_reverse(), [54.0, 50.0, reverse_third]),
      ] {
      let result = unwrap_layout(
        @layout.layout_flex(
          axis_gaps(alignment_container(direction, 100.0, 64.0), 4.0, 12.0)
          .with_wrap(wrap)
          .with_align_content(@layout.AlignContent::start()),
          [
            alignment_item(1, 40.0, 10.0),
            alignment_item(2, 40.0, 14.0),
            alignment_item(3, 40.0, 18.0),
          ],
        ),
      )
      assert_eq(grow_main_bounds(result, direction), [
        (0.0, 40.0),
        (second_main, 40.0),
        (0.0, 40.0),
      ])
      assert_eq(content_origins(result, direction), expected_cross)
      assert_eq(result.items().map(item => item.id()), [1UL, 2UL, 3UL])
      assert_true(!result.overflow())
    }
  }
}

///|
test "only the main gap changes the greedy line break including zero override" {
  for
    direction in [@layout.FlowDirection::row(), @layout.FlowDirection::column()] {
    let base = alignment_container(direction, 60.0, 64.0)
      .with_wrap(@layout.FlexWrap::wrap())
      .with_align_content(@layout.AlignContent::start())
    for
      (main_gap, cross_gap, expected_main, expected_cross) in [
        (0.0, 200.0, [0.0, 30.0], [0.0, 0.0]),
        (0.25, 0.0, [0.0, 0.0], [0.0, 10.0]),
        (0.25, 7.5, [0.0, 0.0], [0.0, 17.5]),
      ] {
      let result = unwrap_layout(
        @layout.layout_flex(
          axis_oriented_gaps(
            unwrap_gap(base, 4.0),
            direction,
            main_gap,
            cross_gap,
          ),
          [alignment_item(1, 30.0, 10.0), alignment_item(2, 30.0, 10.0)],
        ),
      )
      assert_eq(
        result
        .items()
        .map(item => alignment_main_origin(item.bounds(), direction)),
        expected_main,
      )
      assert_eq(content_origins(result, direction), expected_cross)
      assert_true(!result.overflow())
    }
  }
}

///|
test "main gap alone enters full and partial grow and shrink budgets" {
  for
    direction in [@layout.FlowDirection::row(), @layout.FlowDirection::column()] {
    for
      (basis, grow, shrink, expected, overflow) in [
        (20.0, 1.0, 1.0, 44.0, false),
        (60.0, 0.0, 1.0, 44.0, false),
        (20.0, 0.25, 1.0, 26.0, false),
        (60.0, 0.0, 0.25, 46.0, true),
      ] {
      let result = unwrap_layout(
        @layout.layout_flex(
          axis_oriented_gaps(
            alignment_container(direction, 100.0, 20.0),
            direction,
            12.0,
            999.0,
          ),
          [
            grow_item(1, basis, grow, shrink~),
            grow_item(2, basis, grow, shrink~),
          ],
        ),
      )
      assert_eq(grow_main_bounds(result, direction), [
        (0.0, expected),
        (expected + 12.0, expected),
      ])
      assert_true(result.overflow() == overflow)
    }
  }
}

///|
test "wrapped grow and main limit redistribution use only item gaps" {
  for
    direction in [@layout.FlowDirection::row(), @layout.FlowDirection::column()] {
    for wrap in [@layout.FlexWrap::wrap(), @layout.FlexWrap::wrap_reverse()] {
      let first = axis_gap_ok(
        grow_item(1, 20.0, 1.0).with_main_limits(0.0, Some(30.0)),
      )
      let result = unwrap_layout(
        @layout.layout_flex(
          axis_oriented_gaps(
            alignment_container(direction, 100.0, 100.0),
            direction,
            12.0,
            20.0,
          )
          .with_wrap(wrap)
          .with_align_content(@layout.AlignContent::start()),
          [first, grow_item(2, 20.0, 1.0), grow_item(3, 60.0, 1.0)],
        ),
      )
      assert_eq(grow_main_bounds(result, direction), [
        (0.0, 30.0),
        (42.0, 58.0),
        (0.0, 100.0),
      ])
      assert_true(!result.overflow())
    }
  }
}

///|
test "cross gap participates in every content alignment in both flow axes" {
  for
    direction in [@layout.FlowDirection::row(), @layout.FlowDirection::column()] {
    for
      (alignment, normal, reverse) in [
        (@layout.AlignContent::start(), [0.0, 22.0], [54.0, 28.0]),
        (@layout.AlignContent::center(), [14.0, 36.0], [40.0, 14.0]),
        (@layout.AlignContent::end(), [28.0, 50.0], [26.0, 0.0]),
        (@layout.AlignContent::stretch(), [0.0, 36.0], [54.0, 14.0]),
        (@layout.AlignContent::space_between(), [0.0, 50.0], [54.0, 0.0]),
        (@layout.AlignContent::space_around(), [7.0, 43.0], [47.0, 7.0]),
        (
          @layout.AlignContent::space_evenly(),
          [28.0 / 3.0, 122.0 / 3.0],
          [134.0 / 3.0, 28.0 / 3.0],
        ),
      ] {
      for
        (wrap, expected) in [
          (@layout.FlexWrap::wrap(), normal),
          (@layout.FlexWrap::wrap_reverse(), reverse),
        ] {
        let result = unwrap_layout(
          @layout.layout_flex(
            axis_oriented_gaps(
              alignment_container(direction, 60.0, 64.0),
              direction,
              4.0,
              12.0,
            )
            .with_wrap(wrap)
            .with_align_content(alignment),
            content_items(direction),
          ),
        )
        let actual = content_origins(result, direction)
        for i = 0; i < actual.length(); i = i + 1 {
          assert_true((actual[i] - expected[i]).abs() < 0.0000001)
        }
        assert_true(!result.overflow())
      }
    }
  }
}

///|
test "cross gaps retain overflow alignment without changing main placement" {
  for
    direction in [@layout.FlowDirection::row(), @layout.FlowDirection::column()] {
    for
      (alignment, normal, reverse) in [
        (@layout.AlignContent::center(), [-8.0, 14.0], [18.0, -8.0]),
        (@layout.AlignContent::end(), [-16.0, 6.0], [26.0, 0.0]),
        (@layout.AlignContent::space_around(), [0.0, 22.0], [26.0, 0.0]),
      ] {
      for
        (wrap, expected) in [
          (@layout.FlexWrap::wrap(), normal),
          (@layout.FlexWrap::wrap_reverse(), reverse),
        ] {
        let result = unwrap_layout(
          @layout.layout_flex(
            axis_oriented_gaps(
              alignment_container(direction, 60.0, 20.0),
              direction,
              1.0,
              12.0,
            )
            .with_wrap(wrap)
            .with_align_content(alignment),
            content_items(direction),
          ),
        )
        assert_eq(content_origins(result, direction), expected)
        assert_eq(grow_main_bounds(result, direction), [
          (0.0, 40.0),
          (0.0, 40.0),
        ])
        assert_true(result.overflow())
      }
    }
  }
}

///|
test "independent line gaps preserve auto cross stretch limits" {
  for
    direction in [@layout.FlowDirection::row(), @layout.FlowDirection::column()] {
    let first = axis_gap_ok(
      @layout.FlexItem::new(
        1,
        unwrap_points(40.0),
        @layout.Dimension::auto(),
        unwrap_size(0.0, 0.0),
      ).with_cross_limits(10.0, Some(18.0)),
    )
    let second = alignment_item(2, 40.0, 14.0)
    let result = unwrap_layout(
      @layout.layout_flex(
        axis_oriented_gaps(
          alignment_container(direction, 60.0, 64.0),
          direction,
          4.0,
          12.0,
        )
        .with_wrap(@layout.FlexWrap::wrap())
        .with_align(@layout.AlignItems::stretch()),
        [first, second],
      ),
    )
    let bounds = result.items()[0].bounds()
    assert_eq(
      if direction is @layout.Row {
        bounds.size().height()
      } else {
        bounds.size().width()
      },
      18.0,
    )
    assert_eq(content_origins(result, direction), [0.0, 36.0])
  }
}

///|
test "gap setters preserve other axes reset both axes and retain immutable snapshots" {
  for
    direction in [@layout.FlowDirection::row(), @layout.FlowDirection::column()] {
    let base = alignment_container(direction, 50.0, 60.0)
      .with_wrap(@layout.FlexWrap::wrap())
      .with_align_content(@layout.AlignContent::start())
    let both = unwrap_gap(base, 4.0)
    let x_first = axis_gap_ok(both.with_gap_x(0.0))
    let xy = axis_gap_ok(x_first.with_gap_y(7.5))
    let yx = axis_gap_ok(axis_gap_ok(both.with_gap_y(7.5)).with_gap_x(0.0))
    let reset = unwrap_gap(xy, 2.0)
    let items = [
      alignment_item(1, 20.0, 10.0),
      alignment_item(2, 20.0, 10.0),
      alignment_item(3, 20.0, 10.0),
    ]
    for
      (style, x, y) in [
        (base, 0.0, 0.0),
        (both, 4.0, 4.0),
        (x_first, 0.0, 4.0),
        (xy, 0.0, 7.5),
        (yx, 0.0, 7.5),
        (reset, 2.0, 2.0),
      ] {
      let result = unwrap_layout(@layout.layout_flex(style, items))
      let main = if direction is @layout.Row { x } else { y }
      let cross = if direction is @layout.Row { y } else { x }
      assert_eq(grow_main_bounds(result, direction), [
        (0.0, 20.0),
        (20.0 + main, 20.0),
        (0.0, 20.0),
      ])
      assert_eq(content_origins(result, direction), [0.0, 0.0, 10.0 + cross])
    }
  }
}

///|
test "all immutable container builders preserve independent gaps in either order" {
  for
    direction in [@layout.FlowDirection::row(), @layout.FlowDirection::column()] {
    let base = alignment_container(direction, 80.0, 80.0)
    let build = fn(container : @layout.FlexContainer) {
      container
      .with_wrap(@layout.FlexWrap::wrap_reverse())
      .with_insets(
        tree_insets(1.0, 2.0, 3.0, 4.0),
        tree_insets(2.0, 1.0, 2.0, 1.0),
      )
      .with_justify(@layout.JustifyContent::space_evenly())
      .with_align(@layout.AlignItems::end())
      .with_align_content(@layout.AlignContent::center())
    }
    let early = build(axis_gaps(base, 3.5, 7.5))
    let late = axis_gaps(build(base), 3.5, 7.5)
    let items = [
      alignment_item(1, 30.0, 10.0),
      alignment_item(2, 30.0, 14.0),
      alignment_item(3, 40.0, 10.0),
    ]
    assert_eq(
      wrap_line_bounds(unwrap_layout(@layout.layout_flex(early, items)).items()),
      wrap_line_bounds(unwrap_layout(@layout.layout_flex(late, items)).items()),
    )
  }
}

///|
test "all gap entry points reject nonfinite and negative values consistently" {
  let container = alignment_container(@layout.FlowDirection::row(), 60.0, 60.0)
  let style = @layout.FlexTreeStyle::new(@layout.FlowDirection::row())
  for
    (value, expected) in [
      (-0.25, true),
      (0.0 / 0.0, false),
      (1.0 / 0.0, false),
      (-1.0 / 0.0, false),
    ] {
    for
      result in [
        container.with_gap(value),
        container.with_gap_x(value),
        container.with_gap_y(value),
      ] {
      match result {
        Err(error) =>
          if expected {
            assert_true(error is @layout.NegativeValue)
          } else {
            assert_true(error is @layout.NonFiniteValue)
          }
        Ok(_) => fail("invalid container gap accepted")
      }
    }
    for
      result in [
        style.with_gap(value),
        style.with_gap_x(value),
        style.with_gap_y(value),
      ] {
      match result {
        Err(error) =>
          if expected {
            assert_true(error is @layout.NegativeValue)
          } else {
            assert_true(error is @layout.NonFiniteValue)
          }
        Ok(_) => fail("invalid tree gap accepted")
      }
    }
  }
  assert_true(container.with_gap_x(-0.0) is Ok(_))
  assert_true(style.with_gap_y(-0.0) is Ok(_))
}

///|
test "only used main and cross gap aggregates can overflow" {
  for
    direction in [@layout.FlowDirection::row(), @layout.FlowDirection::column()] {
    let items = [
      alignment_item(1, 10.0, 10.0),
      alignment_item(2, 10.0, 10.0),
      alignment_item(3, 10.0, 10.0),
    ]
    let unused = axis_oriented_gaps(
      alignment_container(direction, 60.0, 20.0),
      direction,
      0.0,
      1.0e308,
    )
    assert_true(@layout.layout_flex(unused, items) is Ok(_))
    let huge_main = axis_oriented_gaps(
      alignment_container(direction, 60.0, 20.0),
      direction,
      1.0e308,
      0.0,
    )
    assert_true(@layout.layout_flex(huge_main, items) is Err(NonFiniteValue))
    let huge_cross = axis_oriented_gaps(
      alignment_container(direction, 10.0, 20.0),
      direction,
      0.0,
      1.0e308,
    ).with_wrap(@layout.FlexWrap::wrap())
    assert_true(@layout.layout_flex(huge_cross, items) is Err(NonFiniteValue))
  }
}

///|
test "tree gap setters preserve physical axes and reset both overrides" {
  for
    direction in [@layout.FlowDirection::row(), @layout.FlowDirection::column()] {
    let base = @layout.FlexTreeStyle::new(direction)
      .with_wrap(@layout.FlexWrap::wrap())
      .with_align_content(@layout.AlignContent::start())
    let both = axis_gap_ok(base.with_gap(4.0))
    let x_first = axis_gap_ok(both.with_gap_x(0.0))
    let xy = axis_gap_ok(x_first.with_gap_y(7.5))
    let yx = axis_gap_ok(axis_gap_ok(both.with_gap_y(7.5)).with_gap_x(0.0))
    let reset = axis_gap_ok(xy.with_gap(2.0))
    let nodes = [
      @layout.FlexTreeNode::new(alignment_item(2, 20.0, 10.0), 1),
      @layout.FlexTreeNode::new(alignment_item(3, 20.0, 10.0), 1),
      @layout.FlexTreeNode::new(alignment_item(4, 20.0, 10.0), 1),
    ]
    let size = if direction is @layout.Row {
      tree_size(50.0, 60.0)
    } else {
      tree_size(60.0, 50.0)
    }
    for
      (style, x, y) in [
        (base, 0.0, 0.0),
        (both, 4.0, 4.0),
        (x_first, 0.0, 4.0),
        (xy, 0.0, 7.5),
        (yx, 0.0, 7.5),
        (reset, 2.0, 2.0),
      ] {
      let result = axis_tree_layout(size, style, nodes)
      let main = if direction is @layout.Row { x } else { y }
      let cross = if direction is @layout.Row { y } else { x }
      assert_eq(
        result
        .items()
        .map(item => alignment_main_origin(item.bounds(), direction)),
        [0.0, 20.0 + main, 0.0],
      )
      assert_eq(
        result
        .items()
        .map(item => alignment_cross_origin(item.bounds(), direction)),
        [0.0, 0.0, 10.0 + cross],
      )
    }
  }
}

///|
test "tree style builders preserve both gaps before or after other settings" {
  for
    direction in [@layout.FlowDirection::row(), @layout.FlowDirection::column()] {
    let base = @layout.FlexTreeStyle::new(direction)
    let build = fn(style : @layout.FlexTreeStyle) {
      style
      .with_wrap(@layout.FlexWrap::wrap_reverse())
      .with_insets(
        tree_insets(1.0, 2.0, 3.0, 4.0),
        tree_insets(2.0, 1.0, 2.0, 1.0),
      )
      .with_justify(@layout.JustifyContent::space_evenly())
      .with_align(@layout.AlignItems::end())
      .with_align_content(@layout.AlignContent::center())
    }
    let early = build(axis_style(base, 3.5, 7.5))
    let late = axis_style(build(base), 3.5, 7.5)
    let nodes = [
      @layout.FlexTreeNode::new(alignment_item(2, 30.0, 10.0), 1),
      @layout.FlexTreeNode::new(alignment_item(3, 30.0, 14.0), 1),
      @layout.FlexTreeNode::new(alignment_item(4, 40.0, 10.0), 1),
    ]
    let first = axis_tree_layout(tree_size(80.0, 80.0), early, nodes)
    let second = axis_tree_layout(tree_size(80.0, 80.0), late, nodes)
    assert_true(
      first.items().map(item => item.bounds()) ==
      second.items().map(item => item.bounds()),
    )
  }
}

///|
test "nested intrinsic sizing adds only the flow-selected gap and ignores cross gaps" {
  for
    direction in [@layout.FlowDirection::row(), @layout.FlowDirection::column()] {
    for
      wrap in [
        @layout.FlexWrap::no_wrap(),
        @layout.FlexWrap::wrap(),
        @layout.FlexWrap::wrap_reverse(),
      ] {
      let root = axis_style(
        @layout.FlexTreeStyle::new(@layout.FlowDirection::row()),
        5.5,
        300.0,
      )
      let child = axis_style(@layout.FlexTreeStyle::new(direction), 7.5, 3.5).with_wrap(
        wrap,
      )
      let branch = @layout.FlexTreeNode::new(
        tree_auto_item(
          2,
          @layout.Dimension::auto(),
          @layout.Dimension::auto(),
          tree_size(0.0, 0.0),
        ),
        1,
      ).with_children(child)
      let result = axis_tree_layout(tree_size(200.0, 100.0), root, [
        branch,
        @layout.FlexTreeNode::new(alignment_item(3, 20.0, 10.0), 2),
        @layout.FlexTreeNode::new(alignment_item(4, 30.0, 14.0), 2),
        @layout.FlexTreeNode::new(alignment_item(5, 10.0, 10.0), 1),
      ])
      let width = if direction is @layout.Row { 57.5 } else { 14.0 }
      let height = if direction is @layout.Row { 14.0 } else { 53.5 }
      assert_eq(result.items()[0].bounds().size().width(), width)
      assert_eq(result.items()[0].bounds().size().height(), height)
      assert_eq(result.items()[3].bounds().left(), width + 5.5)
      assert_true(!result.overflow())
    }
  }
}

///|
test "device scale snaps both physical gaps before line breaking and placement" {
  for
    direction in [@layout.FlowDirection::row(), @layout.FlowDirection::column()] {
    let style = axis_style(@layout.FlexTreeStyle::new(direction), 3.25, 7.75)
      .with_wrap(@layout.FlexWrap::wrap())
      .with_align_content(@layout.AlignContent::start())
    let nodes = [
      @layout.FlexTreeNode::new(alignment_item(2, 20.0, 10.0), 1),
      @layout.FlexTreeNode::new(alignment_item(3, 20.0, 10.0), 1),
      @layout.FlexTreeNode::new(alignment_item(4, 20.0, 10.0), 1),
    ]
    let size = tree_size(50.0, 50.0)
    let raw = axis_tree_layout(size, style, nodes)
    let snapped = axis_tree_layout(size, style, nodes, scale=Some(2.0))
    let raw_main = if direction is @layout.Row { 23.25 } else { 27.75 }
    let raw_cross = if direction is @layout.Row { 17.75 } else { 13.25 }
    let snapped_main = if direction is @layout.Row { 23.0 } else { 27.5 }
    let snapped_cross = if direction is @layout.Row { 17.5 } else { 13.0 }
    assert_eq(
      alignment_main_origin(raw.items()[1].bounds(), direction),
      raw_main,
    )
    assert_eq(
      alignment_cross_origin(raw.items()[2].bounds(), direction),
      raw_cross,
    )
    assert_eq(
      alignment_main_origin(snapped.items()[1].bounds(), direction),
      snapped_main,
    )
    assert_eq(
      alignment_cross_origin(snapped.items()[2].bounds(), direction),
      snapped_cross,
    )
    // Authored main-gap rounding also changes an otherwise overflowing exact fit.
    let edge_size = if direction is @layout.Row {
      tree_size(43.0, 100.0)
    } else {
      tree_size(100.0, 47.5)
    }
    let raw_edge = axis_tree_layout(edge_size, style, nodes)
    let snap_edge = axis_tree_layout(edge_size, style, nodes, scale=Some(2.0))
    assert_eq(
      alignment_main_origin(raw_edge.items()[1].bounds(), direction),
      0.0,
    )
    assert_eq(
      alignment_main_origin(snap_edge.items()[1].bounds(), direction),
      snapped_main,
    )
  }
}

///|
test "nested device-scale layout carries child gaps separately from root gaps" {
  let root = axis_style(
    @layout.FlexTreeStyle::new(@layout.FlowDirection::row()),
    5.25,
    99.25,
  ).with_align(@layout.AlignItems::center())
  let child = axis_style(
      @layout.FlexTreeStyle::new(@layout.FlowDirection::row()),
      3.25,
      7.75,
    )
    .with_wrap(@layout.FlexWrap::wrap())
    .with_align_content(@layout.AlignContent::start())
  let nodes = [
    @layout.FlexTreeNode::new(alignment_item(2, 10.0, 40.0), 1),
    @layout.FlexTreeNode::new(alignment_item(3, 50.0, 40.0), 1).with_children(
      child,
    ),
    @layout.FlexTreeNode::new(alignment_item(4, 20.0, 10.0), 3),
    @layout.FlexTreeNode::new(alignment_item(5, 20.0, 10.0), 3),
    @layout.FlexTreeNode::new(alignment_item(6, 20.0, 10.0), 3),
  ]
  let raw = axis_tree_layout(tree_size(100.0, 100.0), root, nodes)
  let snapped = axis_tree_layout(
    tree_size(100.0, 100.0),
    root,
    nodes,
    scale=Some(2.0),
  )
  assert_eq(raw.items()[3].bounds().left(), 38.5)
  assert_eq(raw.items()[4].bounds().top(), 47.75)
  assert_eq(snapped.items()[3].bounds().left(), 38.0)
  assert_eq(snapped.items()[4].bounds().top(), 47.5)
  assert_true(!raw.overflow() && !snapped.overflow())
}

///|
test "equal physical gaps retain the legacy gap behavior for every wrap mode" {
  for
    direction in [@layout.FlowDirection::row(), @layout.FlowDirection::column()] {
    for
      wrap in [
        @layout.FlexWrap::no_wrap(),
        @layout.FlexWrap::wrap(),
        @layout.FlexWrap::wrap_reverse(),
      ] {
      for
        content in [
          @layout.AlignContent::start(),
          @layout.AlignContent::center(),
          @layout.AlignContent::end(),
          @layout.AlignContent::stretch(),
          @layout.AlignContent::space_between(),
          @layout.AlignContent::space_around(),
          @layout.AlignContent::space_evenly(),
        ] {
        for gap in [0.0, 3.5, 12.0] {
          let base = alignment_container(direction, 60.0, 64.0)
            .with_wrap(wrap)
            .with_align_content(content)
          let items = content_items(direction)
          let legacy = unwrap_layout(
            @layout.layout_flex(unwrap_gap(base, gap), items),
          )
          let physical = unwrap_layout(
            @layout.layout_flex(axis_gaps(base, gap, gap), items),
          )
          assert_eq(
            wrap_line_bounds(legacy.items()),
            wrap_line_bounds(physical.items()),
          )
          assert_true(legacy.overflow() == physical.overflow())
        }
      }
    }
  }
}

///|
test "intrinsic measurement uses the individually snapped main gap" {
  for
    direction in [@layout.FlowDirection::row(), @layout.FlowDirection::column()] {
    let root = axis_style(
      @layout.FlexTreeStyle::new(@layout.FlowDirection::row()),
      5.25,
      99.25,
    )
    let child = axis_style(@layout.FlexTreeStyle::new(direction), 3.25, 7.75)
    let nodes = [
      @layout.FlexTreeNode::new(
        tree_auto_item(
          2,
          @layout.Dimension::auto(),
          @layout.Dimension::auto(),
          tree_size(0.0, 0.0),
        ),
        1,
      ).with_children(child),
      @layout.FlexTreeNode::new(alignment_item(3, 20.0, 10.0), 2),
      @layout.FlexTreeNode::new(alignment_item(4, 20.0, 10.0), 2),
      @layout.FlexTreeNode::new(alignment_item(5, 10.0, 10.0), 1),
    ]
    let result = axis_tree_layout(
      tree_size(100.0, 100.0),
      root,
      nodes,
      scale=Some(2.0),
    )
    let width = if direction is @layout.Row { 43.0 } else { 10.0 }
    let height = if direction is @layout.Row { 10.0 } else { 47.5 }
    assert_eq(result.items()[0].bounds().size().width(), width)
    assert_eq(result.items()[0].bounds().size().height(), height)
    assert_eq(result.items()[3].bounds().left(), width + 5.0)
  }
}

///|
test "empty and singleton containers do not apply otherwise huge gaps" {
  for
    direction in [@layout.FlowDirection::row(), @layout.FlowDirection::column()] {
    for
      wrap in [
        @layout.FlexWrap::no_wrap(),
        @layout.FlexWrap::wrap(),
        @layout.FlexWrap::wrap_reverse(),
      ] {
      let container = axis_gaps(
        alignment_container(direction, 60.0, 60.0),
        1.0e308,
        1.0e308,
      ).with_wrap(wrap)
      let empty = unwrap_layout(@layout.layout_flex(container, []))
      let singleton = unwrap_layout(
        @layout.layout_flex(container, [alignment_item(1, 10.0, 10.0)]),
      )
      assert_eq(empty.items().length(), 0)
      assert_eq(singleton.items().length(), 1)
      assert_true(!empty.overflow() && !singleton.overflow())
    }
  }
}
