///|
fn root_box_layout(
  result : Result[@layout.FlexTreeLayout, @layout.TreeLayoutError],
) -> @layout.FlexTreeLayout raise {
  match result {
    Ok(value) => value
    Err(_) => fail("valid authored root-box layout rejected")
  }
}

///|
fn root_box_rect(bounds : @primitives.Rect) -> (Double, Double, Double, Double) {
  (bounds.left(), bounds.top(), bounds.size().width(), bounds.size().height())
}

///|
test "root-box minima apply independently around each inset threshold even without children" {
  for
    direction in [
      @layout.FlowDirection::row(),
      @layout.FlowDirection::column(),
      @layout.FlowDirection::row_reverse(),
      @layout.FlowDirection::column_reverse(),
    ] {
    for
      wrap in [
        @layout.FlexWrap::no_wrap(),
        @layout.FlexWrap::wrap(),
        @layout.FlexWrap::wrap_reverse(),
      ] {
      let style = @layout.FlexTreeStyle::new(direction)
        .with_wrap(wrap)
        .with_insets(
          tree_insets(2.0, 3.0, 4.0, 5.0),
          tree_insets(1.0, 2.0, 3.0, 4.0),
        )
      for width in [13.0, 14.0, 15.0] {
        for height in [9.0, 10.0, 11.0] {
          for populated in [false, true] {
            let nodes = if populated {
              [@layout.FlexTreeNode::new(tree_item(2, 0.0, 0.0), 1)]
            } else {
              []
            }
            let result = root_box_layout(
              @layout.layout_flex_root_box(
                1,
                tree_size(width, height),
                style,
                nodes,
              ),
            )
            assert_eq(result.root_id(), 1UL)
            assert_eq(
              root_box_rect(result.root_bounds()),
              (
                0.0,
                0.0,
                if width < 14.0 {
                  14.0
                } else {
                  width
                },
                if height < 10.0 {
                  10.0
                } else {
                  height
                },
              ),
            )
            assert_eq(result.overflow(), width < 14.0 || height < 10.0)
            assert_eq(result.items().length(), if populated { 1 } else { 0 })
            assert_true(
              result.bounds_before_edge_snap(1) == Some(result.root_bounds()),
            )
            assert_true(result.bounds_before_edge_snap(999) is None)
            if populated {
              assert_eq(result.items()[0].id(), 2UL)
              assert_true(!result.items()[0].overflow())
            }
          }
        }
      }
    }
  }
}

///|
test "root-box zero offers distinguish padding border combined and absent insets" {
  let asymmetric = tree_insets(2.0, 3.0, 4.0, 5.0)
  for
    (
      padding,
      border,
      expected_width,
      expected_height,
      expected_left,
      expected_top,
    ) in [
      (asymmetric, @layout.Insets::zero(), 8.0, 6.0, 5.0, 2.0),
      (@layout.Insets::zero(), asymmetric, 8.0, 6.0, 5.0, 2.0),
      (asymmetric, asymmetric, 16.0, 12.0, 10.0, 4.0),
      (@layout.Insets::zero(), @layout.Insets::zero(), 0.0, 0.0, 0.0, 0.0),
    ] {
    let style = @layout.FlexTreeStyle::new(@layout.FlowDirection::row()).with_insets(
      padding, border,
    )
    for populated in [false, true] {
      let nodes = if populated {
        [@layout.FlexTreeNode::new(tree_item(2, 0.0, 0.0), 1)]
      } else {
        []
      }
      let result = root_box_layout(
        @layout.layout_flex_root_box(1, tree_size(0.0, 0.0), style, nodes),
      )
      assert_eq(
        root_box_rect(result.root_bounds()),
        (0.0, 0.0, expected_width, expected_height),
      )
      assert_eq(
        result.overflow(),
        expected_width > 0.0 || expected_height > 0.0,
      )
      if populated {
        assert_eq(
          root_box_rect(result.items()[0].bounds()),
          (expected_left, expected_top, 0.0, 0.0),
        )
      }
    }
  }
}

///|
test "root-box children use the expanded root in all flow and wrap directions" {
  for
    direction in [
      @layout.FlowDirection::row(),
      @layout.FlowDirection::column(),
      @layout.FlowDirection::row_reverse(),
      @layout.FlowDirection::column_reverse(),
    ] {
    for
      wrap in [
        @layout.FlexWrap::no_wrap(),
        @layout.FlexWrap::wrap(),
        @layout.FlexWrap::wrap_reverse(),
      ] {
      let style = @layout.FlexTreeStyle::new(direction)
        .with_wrap(wrap)
        .with_insets(
          tree_insets(3.0, 5.0, 7.0, 11.0),
          tree_insets(2.0, 4.0, 6.0, 8.0),
        )
      let branch = @layout.FlexTreeNode::new(
        unwrap_item_flex(tree_item(2, 5.0, 4.0), 0.0, 0.0),
        1,
      ).with_children(
        @layout.FlexTreeStyle::new(@layout.FlowDirection::column()),
      )
      let nodes = [
        branch,
        @layout.FlexTreeNode::new(tree_item(3, 2.0, 2.0), 2),
        @layout.FlexTreeNode::new(
          unwrap_item_flex(tree_item(4, 6.0, 3.0), 0.0, 0.0),
          1,
        ),
      ]
      for
        (width, height) in [
          (27.0, 17.0),
          (28.0, 18.0),
          (29.0, 19.0),
          (70.0, 60.0),
        ] {
        let actual = root_box_layout(
          @layout.layout_flex_root_box(
            1,
            tree_size(width, height),
            style,
            nodes,
          ),
        )
        let expanded = tree_size(
          if width < 28.0 {
            28.0
          } else {
            width
          },
          if height < 18.0 {
            18.0
          } else {
            height
          },
        )
        let expected = root_box_layout(
          @layout.layout_flex_tree(1, expanded, style, nodes),
        )
        assert_true(actual.root_bounds() == expected.root_bounds())
        assert_eq(actual.items().map(item => item.id()), [2UL, 3UL, 4UL])
        assert_eq(
          actual
          .items()
          .map(item => (root_box_rect(item.bounds()), item.overflow())),
          expected
          .items()
          .map(item => (root_box_rect(item.bounds()), item.overflow())),
        )
        assert_eq(
          actual.overflow(),
          expected.overflow() || width < 28.0 || height < 18.0,
        )
      }
    }
  }
}

///|
test "root-box overflow preserves child overflow when root fits the offer" {
  let style = @layout.FlexTreeStyle::new(@layout.FlowDirection::row())
  let nodes = [
    @layout.FlexTreeNode::new(
      unwrap_item_flex(tree_item(2, 11.0, 10.0), 0.0, 0.0),
      1,
    ),
  ]
  let result = root_box_layout(
    @layout.layout_flex_root_box(1, tree_size(10.0, 10.0), style, nodes),
  )
  assert_eq(root_box_rect(result.root_bounds()), (0.0, 0.0, 10.0, 10.0))
  assert_true(result.overflow())
  assert_true(result.items()[0].overflow())
}

///|
test "legacy root APIs retain definite empty roots and their overflow behavior" {
  let style = @layout.FlexTreeStyle::new(@layout.FlowDirection::row()).with_insets(
    tree_insets(3.0, 5.0, 7.0, 9.0),
    @layout.Insets::zero(),
  )
  for (width, height) in [(13.0, 9.0), (14.0, 10.0), (15.0, 11.0)] {
    let result = root_box_layout(
      @layout.layout_flex_tree(1, tree_size(width, height), style, []),
    )
    assert_eq(root_box_rect(result.root_bounds()), (0.0, 0.0, width, height))
    assert_true(!result.overflow())
  }
  let scaled = root_box_layout(
    @layout.layout_flex_tree_with_device_scale(
      1,
      tree_size(1.3, 2.3),
      style,
      [],
      2.0,
    ),
  )
  assert_eq(root_box_rect(scaled.root_bounds()), (0.0, 0.0, 1.5, 2.5))
  assert_true(!scaled.overflow())
  assert_eq(
    scaled.bounds_before_edge_snap(1).map(root_box_rect),
    Some((0.0, 0.0, 1.3, 2.3)),
  )
}

///|
test "root-box device scale snaps insets before determining the root minimum" {
  let padding = tree_insets(0.4, 0.4, 0.4, 0.4)
  let style = @layout.FlexTreeStyle::new(@layout.FlowDirection::row()).with_insets(
    padding,
    @layout.Insets::zero(),
  )
  let raw = root_box_layout(
    @layout.layout_flex_root_box(1, tree_size(0.0, 0.0), style, []),
  )
  assert_eq(root_box_rect(raw.root_bounds()), (0.0, 0.0, 0.8, 0.8))
  for (scale, extent) in [(1.0, 0.0), (2.0, 1.0)] {
    let result = root_box_layout(
      @layout.layout_flex_root_box_with_device_scale(
        1,
        tree_size(0.0, 0.0),
        style,
        [],
        scale,
      ),
    )
    assert_eq(root_box_rect(result.root_bounds()), (0.0, 0.0, extent, extent))
    assert_eq(result.overflow(), extent > 0.0)
  }
}

///|
test "root-box scaled thresholds include asymmetric insets and positive stroke floors" {
  let style = @layout.FlexTreeStyle::new(@layout.FlowDirection::row()).with_insets(
    tree_insets(0.6, 1.4, 0.4, 2.6),
    tree_insets(0.1, 0.1, 0.1, 0.1),
  )
  for
    (scale, minimum_width, minimum_height, left, top) in [
      (1.0, 6.0, 3.0, 4.0, 2.0),
      (2.0, 5.0, 2.0, 3.0, 1.0),
    ] {
    let step = 1.0 / scale
    for width_delta in [-step, 0.0, step] {
      for height_delta in [-step, 0.0, step] {
        for populated in [false, true] {
          let nodes = if populated {
            [@layout.FlexTreeNode::new(tree_item(2, 0.0, 0.0), 1)]
          } else {
            []
          }
          let result = root_box_layout(
            @layout.layout_flex_root_box_with_device_scale(
              1,
              tree_size(
                minimum_width + width_delta,
                minimum_height + height_delta,
              ),
              style,
              nodes,
              scale,
            ),
          )
          assert_eq(
            root_box_rect(result.root_bounds()),
            (
              0.0,
              0.0,
              minimum_width +
              (if width_delta > 0.0 { width_delta } else { 0.0 }),
              minimum_height +
              (if height_delta > 0.0 { height_delta } else { 0.0 }),
            ),
          )
          assert_eq(result.overflow(), width_delta < 0.0 || height_delta < 0.0)
          assert_true(
            result.bounds_before_edge_snap(1) == Some(result.root_bounds()),
          )
          if populated {
            assert_eq(
              root_box_rect(result.items()[0].bounds()),
              (left, top, 0.0, 0.0),
            )
            assert_true(!result.items()[0].overflow())
          }
        }
      }
    }
  }
}

///|
test "root-box scaled geometry retains pre-edge root and compares final bounds to offer" {
  let style = @layout.FlexTreeStyle::new(@layout.FlowDirection::row()).with_insets(
    @layout.Insets::zero(),
    tree_insets(0.1, 0.1, 0.1, 0.1),
  )
  let expanded = root_box_layout(
    @layout.layout_flex_root_box_with_device_scale(
      1,
      tree_size(1.2, 0.2),
      style,
      [],
      2.0,
    ),
  )
  assert_eq(root_box_rect(expanded.root_bounds()), (0.0, 0.0, 1.0, 1.0))
  assert_eq(
    expanded.bounds_before_edge_snap(1).map(root_box_rect),
    Some((0.0, 0.0, 1.2, 1.0)),
  )
  assert_true(expanded.overflow())
  let no_insets = @layout.FlexTreeStyle::new(@layout.FlowDirection::row())
  for
    (offered_width, snapped_width, overflow) in [
      (1.2, 1.0, false),
      (1.3, 1.5, true),
    ] {
    let result = root_box_layout(
      @layout.layout_flex_root_box_with_device_scale(
        1,
        tree_size(offered_width, 2.0),
        no_insets,
        [],
        2.0,
      ),
    )
    assert_eq(
      root_box_rect(result.root_bounds()),
      (0.0, 0.0, snapped_width, 2.0),
    )
    assert_eq(
      result.bounds_before_edge_snap(1).map(root_box_rect),
      Some((0.0, 0.0, offered_width, 2.0)),
    )
    assert_eq(result.overflow(), overflow)
  }
}

///|
test "root-box rejects nonfinite inset sums on either axis including empty trees" {
  for
    (padding, border) in [
      (tree_insets(0.0, 1.0e308, 0.0, 1.0e308), @layout.Insets::zero()),
      (tree_insets(1.0e308, 0.0, 1.0e308, 0.0), @layout.Insets::zero()),
      (
        tree_insets(0.0, 8.0e307, 0.0, 8.0e307),
        tree_insets(0.0, 8.0e307, 0.0, 8.0e307),
      ),
      (
        tree_insets(8.0e307, 0.0, 8.0e307, 0.0),
        tree_insets(8.0e307, 0.0, 8.0e307, 0.0),
      ),
    ] {
    let style = @layout.FlexTreeStyle::new(@layout.FlowDirection::row()).with_insets(
      padding, border,
    )
    for populated in [false, true] {
      let nodes = if populated {
        [@layout.FlexTreeNode::new(tree_item(2, 0.0, 0.0), 1)]
      } else {
        []
      }
      assert_true(
        @layout.layout_flex_root_box(1, tree_size(0.0, 0.0), style, nodes)
        is Err(Flex(NonFiniteValue)),
      )
      for scale in [1.0, 2.0] {
        assert_true(
          @layout.layout_flex_root_box_with_device_scale(
            1,
            tree_size(0.0, 0.0),
            style,
            nodes,
            scale,
          )
          is Err(Flex(NonFiniteValue)),
        )
      }
    }
    // Compatibility control: the legacy empty-tree fast path is unchanged.
    let legacy = root_box_layout(
      @layout.layout_flex_tree(1, tree_size(0.0, 0.0), style, []),
    )
    assert_eq(root_box_rect(legacy.root_bounds()), (0.0, 0.0, 0.0, 0.0))
  }
}

///|
test "root-box accepts finite large inset totals and keeps invalid scale errors" {
  let large = @layout.FlexTreeStyle::new(@layout.FlowDirection::row()).with_insets(
    tree_insets(0.0, 5.0e307, 0.0, 5.0e307),
    @layout.Insets::zero(),
  )
  let result = root_box_layout(
    @layout.layout_flex_root_box(1, tree_size(0.0, 0.0), large, []),
  )
  assert_eq(root_box_rect(result.root_bounds()), (0.0, 0.0, 1.0e308, 0.0))
  assert_true(result.overflow())
  let style = @layout.FlexTreeStyle::new(@layout.FlowDirection::row())
  for scale in [0.0, -1.0] {
    assert_true(
      @layout.layout_flex_root_box_with_device_scale(
        1,
        tree_size(0.0, 0.0),
        style,
        [],
        scale,
      )
      is Err(Flex(NegativeValue)),
    )
  }
  for scale in [0.0 / 0.0, 1.0 / 0.0, -1.0 / 0.0] {
    assert_true(
      @layout.layout_flex_root_box_with_device_scale(
        1,
        tree_size(0.0, 0.0),
        style,
        [],
        scale,
      )
      is Err(Flex(NonFiniteValue)),
    )
  }
}

///|
test "root-box APIs preserve structural validation and missing-container failures" {
  let style = @layout.FlexTreeStyle::new(@layout.FlowDirection::row())
  let child = @layout.FlexTreeNode::new(tree_item(2, 1.0, 1.0), 1)
  for scaled in [false, true] {
    let run = fn(nodes) {
      if scaled {
        @layout.layout_flex_root_box_with_device_scale(
          1,
          tree_size(10.0, 10.0),
          style,
          nodes,
          2.0,
        )
      } else {
        @layout.layout_flex_root_box(1, tree_size(10.0, 10.0), style, nodes)
      }
    }
    assert_true(run([child, child]) is Err(DuplicateId))
    assert_true(
      run([@layout.FlexTreeNode::new(tree_item(2, 1.0, 1.0), 99)])
      is Err(MissingParent),
    )
    assert_true(
      run([child, @layout.FlexTreeNode::new(tree_item(3, 1.0, 1.0), 2)])
      is Err(MissingContainer),
    )
    assert_true(
      run([
        child,
        @layout.FlexTreeNode::new(tree_item(3, 1.0, 1.0), 1),
        @layout.FlexTreeNode::new(tree_item(4, 1.0, 1.0), 2),
      ])
      is Err(InvalidPreorder),
    )
  }
}
