///|
test "distributed content spacing preserves natural lines in both axes and wrap directions" {
  for
    direction in [@layout.FlowDirection::row(), @layout.FlowDirection::column()] {
    for
      (alignment, normal, reverse) in [
        (@layout.AlignContent::space_between(), [0.0, 50.0], [54.0, 0.0]),
        (@layout.AlignContent::space_around(), [9.0, 41.0], [45.0, 9.0]),
        (@layout.AlignContent::space_evenly(), [12.0, 38.0], [42.0, 12.0]),
      ] {
      for
        (wrap, expected) in [
          (@layout.FlexWrap::wrap(), normal),
          (@layout.FlexWrap::wrap_reverse(), reverse),
        ] {
        let result = unwrap_layout(
          @layout.layout_flex(
            content_container(direction, 60.0, 64.0)
            .with_align_content(alignment)
            .with_wrap(wrap),
            content_items(direction),
          ),
        )
        assert_eq(content_origins(result, direction), expected)
        assert_eq(result.items().map(item => item.id()), [1UL, 2UL])
        assert_eq(result.items().map(item => item.overflow()), [false, false])
        assert_true(!result.overflow())
        assert_eq(
          result
          .items()
          .map(item => {
            if direction == @layout.FlowDirection::row() {
              item.bounds().size().height()
            } else {
              item.bounds().size().width()
            }
          }),
          [10.0, 14.0],
        )
      }
    }
  }
}

///|
test "distributed content handles empty exact-fit single lines and nowrap" {
  for
    direction in [@layout.FlowDirection::row(), @layout.FlowDirection::column()] {
    for
      (alignment, single, single_reverse) in [
        (@layout.AlignContent::space_between(), [0.0, 0.0], [54.0, 50.0]),
        (@layout.AlignContent::space_around(), [25.0, 25.0], [29.0, 25.0]),
        (@layout.AlignContent::space_evenly(), [25.0, 25.0], [29.0, 25.0]),
      ] {
      for
        (wrap, expected_single, expected_exact) in [
          (@layout.FlexWrap::wrap(), single, [0.0, 14.0]),
          (@layout.FlexWrap::wrap_reverse(), single_reverse, [18.0, 0.0]),
        ] {
        let base = content_container(direction, 60.0, 64.0)
          .with_align_content(alignment)
          .with_wrap(wrap)
        let empty = unwrap_layout(@layout.layout_flex(base, []))
        assert_eq(empty.items().length(), 0)
        assert_true(!empty.overflow())
        let single_line = unwrap_layout(
          @layout.layout_flex(base, content_items(direction, main=20.0)),
        )
        assert_eq(content_origins(single_line, direction), expected_single)
        assert_true(!single_line.overflow())
        let exact = unwrap_layout(
          @layout.layout_flex(
            content_container(direction, 60.0, 28.0)
            .with_align_content(alignment)
            .with_wrap(wrap),
            content_items(direction),
          ),
        )
        assert_eq(content_origins(exact, direction), expected_exact)
        assert_true(!exact.overflow())
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
}

///|
test "distributed content overflow anchors physical start and retains reversed item alignment" {
  for
    direction in [@layout.FlowDirection::row(), @layout.FlowDirection::column()] {
    for
      alignment in [
        @layout.AlignContent::space_between(),
        @layout.AlignContent::space_around(),
        @layout.AlignContent::space_evenly(),
      ] {
      for
        (wrap, expected, flags, single) in [
          (@layout.FlexWrap::wrap(), [0.0, 14.0], [false, true], [0.0, 0.0]),
          (
            @layout.FlexWrap::wrap_reverse(),
            [18.0, 0.0],
            [true, false],
            [4.0, 0.0],
          ),
        ] {
        let result = unwrap_layout(
          @layout.layout_flex(
            content_container(direction, 60.0, 20.0)
            .with_align_content(alignment)
            .with_wrap(wrap),
            content_items(direction),
          ),
        )
        assert_eq(content_origins(result, direction), expected)
        assert_eq(result.items().map(item => item.overflow()), flags)
        assert_true(result.overflow())
        let result = unwrap_layout(
          @layout.layout_flex(
            content_container(direction, 60.0, 10.0)
            .with_align_content(alignment)
            .with_wrap(wrap),
            content_items(direction, main=20.0),
          ),
        )
        assert_eq(content_origins(result, direction), single)
        assert_true(result.overflow())
      }
    }
  }
}

///|
test "distributed line space does not enlarge items or main-axis gaps" {
  let first = @layout.FlexItem::new(
    1,
    tree_points(20.0),
    @layout.Dimension::auto(),
    tree_size(20.0, 0.0),
  )
  let first = match first.with_cross_limits(10.0, Some(18.0)) {
    Ok(value) => value
    Err(_) => fail("valid auto cross limit rejected")
  }
  let items = [first, wrap_item(2, 20.0, 14.0), wrap_item(3, 40.0, 18.0)]
  for
    (alignment, normal, reverse) in [
      (
        @layout.AlignContent::space_between(),
        [0.0, 0.0, 46.0],
        [50.0, 50.0, 0.0],
      ),
      (
        @layout.AlignContent::space_around(),
        [7.0, 7.0, 39.0],
        [43.0, 43.0, 7.0],
      ),
      (
        @layout.AlignContent::space_evenly(),
        [28.0 / 3.0, 28.0 / 3.0, 110.0 / 3.0],
        [122.0 / 3.0, 122.0 / 3.0, 28.0 / 3.0],
      ),
    ] {
    for
      (wrap, expected) in [
        (@layout.FlexWrap::wrap(), normal),
        (@layout.FlexWrap::wrap_reverse(), reverse),
      ] {
      let result = unwrap_layout(
        @layout.layout_flex(
          content_container(@layout.FlowDirection::row(), 60.0, 64.0)
          .with_align_content(alignment)
          .with_align(@layout.AlignItems::stretch())
          .with_wrap(wrap),
          items,
        ),
      )
      for index = 0; index < expected.length(); index = index + 1 {
        assert_true(
          (result.items()[index].bounds().top() - expected[index]).abs() <
          1.0e-12,
        )
      }
      assert_eq(result.items().map(item => item.bounds().left()), [
        0.0, 24.0, 0.0,
      ])
      assert_eq(result.items().map(item => item.bounds().size().height()), [
        14.0, 14.0, 18.0,
      ])
      assert_true(!result.overflow())
    }
  }
}

///|
test "distributed content builders retain inset bounds and independent main distribution" {
  for
    (alignment, expected) in [
      (@layout.AlignContent::space_between(), [4.0, 44.0]),
      (@layout.AlignContent::space_around(), [10.5, 37.5]),
      (@layout.AlignContent::space_evenly(), [38.0 / 3.0, 106.0 / 3.0]),
    ] {
    let base = @layout.FlexContainer::new(
        @layout.FlowDirection::row(),
        tree_size(60.0, 64.0),
      )
      .with_align_content(alignment)
      .with_insets(
        tree_insets(3.0, 2.0, 5.0, 1.0),
        tree_insets(1.0, 0.0, 1.0, 1.0),
      )
      .with_justify(@layout.JustifyContent::space_evenly())
      .with_align(@layout.AlignItems::center())
      .with_wrap(@layout.FlexWrap::wrap())
    let base = unwrap_wrap_gap(base, 4.0)
    let result = unwrap_layout(
      @layout.layout_flex(base, content_items(@layout.FlowDirection::row())),
    )
    for index = 0; index < expected.length(); index = index + 1 {
      assert_true(
        (result.items()[index].bounds().top() - expected[index]).abs() < 1.0e-12,
      )
    }
    assert_eq(result.items().map(item => item.bounds().left()), [10.0, 10.0])
    assert_true(!result.overflow())
  }
}

///|
test "distributed reverse overflow preserves small near-edge line geometry" {
  for
    direction in [@layout.FlowDirection::row(), @layout.FlowDirection::column()] {
    for
      alignment in [
        @layout.AlignContent::space_between(),
        @layout.AlignContent::space_around(),
        @layout.AlignContent::space_evenly(),
      ] {
      let items = if direction == @layout.FlowDirection::row() {
        [wrap_item(1, 40.0, 1.0e16), wrap_item(2, 40.0, 1.0)]
      } else {
        [wrap_column_item(1, 1.0e16, 40.0), wrap_column_item(2, 1.0, 40.0)]
      }
      let result = unwrap_layout(
        @layout.layout_flex(
          content_container(direction, 60.0, 21.0)
          .with_align_content(alignment)
          .with_wrap(@layout.FlexWrap::wrap_reverse()),
          items,
        ),
      )
      assert_eq(content_origins(result, direction), [5.0, 0.0])
      assert_eq(result.items().map(item => item.overflow()), [true, false])
      assert_true(result.overflow())
    }
  }
}

///|
test "distributed content rejects nonfinite aggregate line geometry" {
  for
    alignment in [
      @layout.AlignContent::space_between(),
      @layout.AlignContent::space_around(),
      @layout.AlignContent::space_evenly(),
    ] {
    for wrap in [@layout.FlexWrap::wrap(), @layout.FlexWrap::wrap_reverse()] {
      match
        @layout.layout_flex(
          content_container(@layout.FlowDirection::row(), 60.0, 1.0e308)
          .with_align_content(alignment)
          .with_wrap(wrap),
          [wrap_item(1, 40.0, 1.0e308), wrap_item(2, 40.0, 1.0e308)],
        ) {
        Err(@layout.NonFiniteValue) => ()
        _ => fail("nonfinite line aggregate accepted")
      }
    }
  }
}

///|
test "fitting distributed content anchors both outer edges across large finite ratios" {
  for
    direction in [@layout.FlowDirection::row(), @layout.FlowDirection::column()] {
    for
      (alignment, leading, gap) in [
        (@layout.AlignContent::space_between(), 0.0, 6.0),
        (@layout.AlignContent::space_around(), 2.0 / 3.0, 16.0 / 3.0),
        (@layout.AlignContent::space_evenly(), 1.0, 5.0),
      ] {
      let items = if direction == @layout.FlowDirection::row() {
        [
          wrap_item(1, 40.0, 1.0e16),
          wrap_item(2, 40.0, 1.0),
          wrap_item(3, 40.0, 1.0),
        ]
      } else {
        [
          wrap_column_item(1, 1.0e16, 40.0),
          wrap_column_item(2, 1.0, 40.0),
          wrap_column_item(3, 1.0, 40.0),
        ]
      }
      let result = unwrap_layout(
        @layout.layout_flex(
          content_container(direction, 60.0, 1.0e16 + 12.0)
          .with_align_content(alignment)
          .with_wrap(@layout.FlexWrap::wrap_reverse()),
          items,
        ),
      )
      let origins = content_origins(result, direction)
      assert_true((origins[2] - leading).abs() < 1.0e-12)
      assert_true((origins[1] - (leading + 1.0 + gap)).abs() < 1.0e-12)
      assert_eq(origins[0] + 1.0e16, 1.0e16 + 12.0 - leading)
      assert_true(!result.overflow())
    }
  }
}

///|
test "distributed content propagates through nested builders and device-scale copies" {
  for
    (alignment, root_y, normal, reverse, snapped_normal, snapped_reverse) in [
      (
        @layout.AlignContent::space_between(),
        1.0,
        [5.0, 45.0],
        [49.0, 5.0],
        [5.0, 45.0],
        [49.0, 5.0],
      ),
      (
        @layout.AlignContent::space_around(),
        18.0,
        [28.5, 55.5],
        [59.5, 28.5],
        [28.5, 55.5],
        [59.5, 28.5],
      ),
      (
        @layout.AlignContent::space_evenly(),
        18.0,
        [92.0 / 3.0, 160.0 / 3.0],
        [172.0 / 3.0, 92.0 / 3.0],
        [30.5, 53.5],
        [57.5, 30.5],
      ),
    ] {
    let root_style = @layout.FlexTreeStyle::new(@layout.FlowDirection::row())
      .with_align_content(alignment)
      .with_insets(tree_insets(1.0, 0.0, 1.0, 0.0), @layout.Insets::zero())
      .with_justify(@layout.JustifyContent::start())
      .with_align(@layout.AlignItems::start())
      .with_wrap(@layout.FlexWrap::wrap())
    let root_style = match root_style.with_gap(0.0) {
      Ok(value) => value
      Err(_) => fail("valid root gap rejected")
    }
    for
      (wrap, raw_expected, snapped_expected) in [
        (@layout.FlexWrap::wrap(), normal, snapped_normal),
        (@layout.FlexWrap::wrap_reverse(), reverse, snapped_reverse),
      ] {
      let child_style = @layout.FlexTreeStyle::new(@layout.FlowDirection::row())
        .with_align_content(alignment)
        .with_insets(
          tree_insets(3.0, 2.0, 5.0, 1.0),
          tree_insets(1.0, 0.0, 1.0, 1.0),
        )
        .with_justify(@layout.JustifyContent::end())
        .with_align(@layout.AlignItems::center())
        .with_wrap(wrap)
      let child_style = match child_style.with_gap(4.0) {
        Ok(value) => value
        Err(_) => fail("valid child gap rejected")
      }
      let nodes = [
        @layout.FlexTreeNode::new(tree_item(2, 60.0, 64.0), 1).with_children(
          child_style,
        ),
        @layout.FlexTreeNode::new(tree_item(3, 40.0, 10.0), 2),
        @layout.FlexTreeNode::new(tree_item(4, 40.0, 14.0), 2),
      ]
      for
        (result, expected) in [
          (
            @layout.layout_flex_tree(
              1,
              tree_size(60.0, 100.0),
              root_style,
              nodes,
            ),
            raw_expected,
          ),
          (
            @layout.layout_flex_tree_with_device_scale(
              1,
              tree_size(60.0, 100.0),
              root_style,
              nodes,
              2.0,
            ),
            snapped_expected,
          ),
        ] {
        let result = match result {
          Ok(value) => value
          Err(_) => fail("valid nested distributed layout rejected")
        }
        assert_eq(result.items().map(item => item.id()), [2UL, 3UL, 4UL])
        assert_eq(result.items()[0].bounds().top(), root_y)
        assert_eq(result.items().map(item => item.bounds().left()), [
          0.0, 18.0, 18.0,
        ])
        assert_eq(result.items().map(item => item.bounds().size().height()), [
          64.0, 10.0, 14.0,
        ])
        for index = 0; index < expected.length(); index = index + 1 {
          assert_true(
            (result.items()[index + 1].bounds().top() - expected[index]).abs() <
            1.0e-12,
          )
        }
        assert_true(!result.overflow())
      }
    }
  }
}

///|
test "three distributed lines retain fractional spacing at the device boundary" {
  for
    direction in [@layout.FlowDirection::row(), @layout.FlowDirection::column()] {
    let viewport = if direction == @layout.FlowDirection::row() {
      tree_size(60.0, 90.0)
    } else {
      tree_size(90.0, 60.0)
    }
    let nodes = [
      @layout.FlexTreeNode::new(tree_item(2, 40.0, 10.0), 1),
      @layout.FlexTreeNode::new(tree_item(3, 40.0, 14.0), 1),
      @layout.FlexTreeNode::new(tree_item(4, 40.0, 18.0), 1),
    ]
    for
      (alignment, normal, reverse) in [
        (
          @layout.AlignContent::space_between(),
          [0.0, 34.0, 72.0],
          [80.0, 42.0, 0.0],
        ),
        (
          @layout.AlignContent::space_around(),
          [6.5, 34.0, 65.5],
          [73.5, 42.0, 6.5],
        ),
        (
          @layout.AlignContent::space_evenly(),
          [10.0, 34.0, 62.0],
          [70.0, 42.0, 10.0],
        ),
      ] {
      for
        (wrap, expected) in [
          (@layout.FlexWrap::wrap(), normal),
          (@layout.FlexWrap::wrap_reverse(), reverse),
        ] {
        let style = @layout.FlexTreeStyle::new(direction)
          .with_align_content(alignment)
          .with_wrap(wrap)
        let style = match style.with_gap(4.0) {
          Ok(value) => value
          Err(_) => fail("valid line gap rejected")
        }
        let result = match
          @layout.layout_flex_tree_with_device_scale(
            1, viewport, style, nodes, 2.0,
          ) {
          Ok(value) => value
          Err(_) => fail("valid fractional distributed layout rejected")
        }
        assert_eq(
          result
          .items()
          .map(item => {
            if direction == @layout.FlowDirection::row() {
              item.bounds().top()
            } else {
              item.bounds().left()
            }
          }),
          expected,
        )
        assert_true(!result.overflow())
      }
    }
  }
}

///|
test "distributed content keeps the existing nowrap intrinsic approximation" {
  for
    alignment in [
      @layout.AlignContent::space_between(),
      @layout.AlignContent::space_around(),
      @layout.AlignContent::space_evenly(),
    ] {
    let style = @layout.FlexTreeStyle::new(@layout.FlowDirection::row())
      .with_align_content(alignment)
      .with_wrap(@layout.FlexWrap::wrap())
    let style = match style.with_gap(4.0) {
      Ok(value) => value
      Err(_) => fail("valid intrinsic gap rejected")
    }
    let branch = tree_auto_item(
      2,
      @layout.Dimension::auto(),
      @layout.Dimension::auto(),
      tree_size(0.0, 0.0),
    )
    let branch = match branch.with_flex(0.0, 0.0) {
      Ok(value) => value
      Err(_) => fail("valid intrinsic flex factors rejected")
    }
    let result = match
      @layout.layout_flex_tree(
        1,
        tree_size(60.0, 100.0),
        @layout.FlexTreeStyle::new(@layout.FlowDirection::row()),
        [
          @layout.FlexTreeNode::new(branch, 1).with_children(style),
          @layout.FlexTreeNode::new(tree_item(3, 40.0, 10.0), 2),
          @layout.FlexTreeNode::new(tree_item(4, 40.0, 14.0), 2),
        ],
      ) {
      Ok(value) => value
      Err(_) => fail("valid intrinsic distributed layout rejected")
    }
    assert_true(result.items()[0].bounds().size() == tree_size(84.0, 14.0))
    assert_eq(result.items()[1].bounds().left(), 0.0)
    assert_eq(result.items()[2].bounds().left(), 44.0)
    assert_true(result.overflow())
  }
}
