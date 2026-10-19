///|
test "reverse flow starts at the opposite physical content edge with stable ids" {
  for
    (direction, horizontal) in [
      (@layout.FlowDirection::row_reverse(), true),
      (@layout.FlowDirection::column_reverse(), false),
    ] {
    let container = axis_gaps(
      @layout.FlexContainer::new(direction, tree_size(100.0, 100.0))
      .with_insets(tree_insets(3.0, 7.0, 11.0, 13.0), @layout.Insets::zero())
      .with_align(@layout.AlignItems::start())
      .with_justify(@layout.JustifyContent::end()),
      5.0,
      9.0,
    )
    let result = unwrap_layout(
      @layout.layout_flex(container, [
        alignment_item(7, 20.0, 10.0),
        alignment_item(3, 30.0, 12.0),
      ]),
    )
    let items = result.items()
    assert_eq(items.map(item => item.id()), [7UL, 3UL])
    assert_eq(
      items.map(item => {
        if horizontal {
          item.bounds().left()
        } else {
          item.bounds().top()
        }
      }),
      if horizontal {
        [73.0, 38.0]
      } else {
        [69.0, 30.0]
      },
    )
    assert_eq(
      items.map(item => {
        if horizontal {
          item.bounds().top()
        } else {
          item.bounds().left()
        }
      }),
      if horizontal {
        [3.0, 3.0]
      } else {
        [13.0, 13.0]
      },
    )
    assert_true(!result.overflow())
  }
}

///|
test "reverse placement mirrors resolved boxes across wrapping alignment and flex budgets" {
  for
    (forward, reverse, horizontal) in [
      (@layout.FlowDirection::row(), @layout.FlowDirection::row_reverse(), true),
      (
        @layout.FlowDirection::column(),
        @layout.FlowDirection::column_reverse(),
        false,
      ),
    ] {
    for
      wrap in [
        @layout.FlexWrap::no_wrap(),
        @layout.FlexWrap::wrap(),
        @layout.FlexWrap::wrap_reverse(),
      ] {
      for
        justify in [
          @layout.JustifyContent::start(),
          @layout.JustifyContent::end(),
          @layout.JustifyContent::center(),
        ] {
        for
          align in [
            @layout.AlignItems::start(),
            @layout.AlignItems::end(),
            @layout.AlignItems::center(),
            @layout.AlignItems::stretch(),
          ] {
          for
            content in [
              @layout.AlignContent::start(),
              @layout.AlignContent::end(),
              @layout.AlignContent::center(),
              @layout.AlignContent::stretch(),
              @layout.AlignContent::space_between(),
              @layout.AlignContent::space_around(),
              @layout.AlignContent::space_evenly(),
            ] {
            for (grow, shrink) in [(0.0, 0.0), (0.3, 0.2), (1.0, 1.0)] {
              let items = [
                unwrap_item_flex(tree_item(1, 42.0, 12.0), grow, shrink),
                unwrap_item_flex(tree_item(2, 31.0, 18.0), grow, shrink),
                unwrap_item_flex(tree_item(3, 23.0, 10.0), grow, shrink),
              ]
              let make = fn(direction) raise {
                axis_gaps(
                  @layout.FlexContainer::new(direction, tree_size(100.0, 100.0))
                  .with_insets(
                    tree_insets(3.0, 7.0, 11.0, 13.0),
                    @layout.Insets::zero(),
                  )
                  .with_wrap(wrap)
                  .with_justify(
                    if direction == reverse {
                      match justify {
                        @layout.Start => @layout.JustifyContent::end()
                        @layout.End => @layout.JustifyContent::start()
                        _ => justify
                      }
                    } else {
                      justify
                    },
                  )
                  .with_align(align)
                  .with_align_content(content),
                  5.0,
                  9.0,
                )
              }
              let a = unwrap_layout(@layout.layout_flex(make(forward), items))
              let b = unwrap_layout(@layout.layout_flex(make(reverse), items))
              assert_eq(a.overflow(), b.overflow())
              for i = 0; i < 3; i = i + 1 {
                let x = a.items()[i]
                let y = b.items()[i]
                assert_eq(x.id(), y.id())
                assert_eq(x.overflow(), y.overflow())
                assert_true(x.bounds().size() == y.bounds().size())
                let expected = if horizontal {
                  106.0 - x.bounds().left() - x.bounds().size().width()
                } else {
                  92.0 - x.bounds().top() - x.bounds().size().height()
                }
                let actual = if horizontal {
                  y.bounds().left()
                } else {
                  y.bounds().top()
                }
                assert_true((expected - actual).abs() < 1.0e-10)
                assert_eq(
                  if horizontal {
                    x.bounds().top()
                  } else {
                    x.bounds().left()
                  },
                  if horizontal {
                    y.bounds().top()
                  } else {
                    y.bounds().left()
                  },
                )
              }
            }
          }
        }
      }
    }
  }
}

///|
test "reverse flex intrinsic measurement remains physical in pure and mixed trees" {
  for
    (direction, horizontal) in [
      (@layout.FlowDirection::row_reverse(), true),
      (@layout.FlowDirection::column_reverse(), false),
    ] {
    let style = axis_style(
      @layout.FlexTreeStyle::new(direction).with_align(
        @layout.AlignItems::start(),
      ),
      5.0,
      9.0,
    )
    let branch = unwrap_item_flex(
      tree_auto_item(
        2,
        @layout.Dimension::auto(),
        @layout.Dimension::auto(),
        tree_size(0.0, 0.0),
      ),
      0.0,
      0.0,
    )
    let nodes = [
      @layout.FlexTreeNode::new(branch, 1).with_children(style),
      @layout.FlexTreeNode::new(alignment_item(3, 20.0, 10.0), 2),
      @layout.FlexTreeNode::new(alignment_item(4, 30.0, 12.0), 2),
    ]
    let root = @layout.FlexTreeStyle::new(direction)
      .with_justify(@layout.JustifyContent::end())
      .with_align(@layout.AlignItems::start())
    let pure = axis_tree_layout(tree_size(100.0, 100.0), root, nodes)
    let mixed = match
      @layout.layout_mixed_tree_at(
        1,
        @primitives.Rect::new(0.0, 0.0, 100.0, 100.0).unwrap(),
        @layout.FlexStyle(root),
        [
          @layout.MixedTreeNode::new(
            @layout.FlexChild(branch),
            1,
            Some(@layout.FlexStyle(style)),
          ),
          @layout.MixedTreeNode::new(
            @layout.FlexChild(alignment_item(3, 20.0, 10.0)),
            2,
            None,
          ),
          @layout.MixedTreeNode::new(
            @layout.FlexChild(alignment_item(4, 30.0, 12.0)),
            2,
            None,
          ),
        ],
        None,
      ) {
      Ok(value) => value
      Err(_) => fail("valid mixed reverse tree rejected")
    }
    assert_eq(pure.items().map(item => item.id()), [2UL, 3UL, 4UL])
    assert_true(
      pure.items()[0].bounds().size() ==
      (if horizontal { tree_size(55.0, 12.0) } else { tree_size(12.0, 59.0) }),
    )
    for i = 0; i < 3; i = i + 1 {
      assert_true(pure.items()[i].bounds() == mixed.items()[i].bounds())
    }
    assert_eq(
      pure
      .items()
      .map(item => {
        if horizontal {
          item.bounds().left()
        } else {
          item.bounds().top()
        }
      }),
      if horizontal {
        [45.0, 80.0, 45.0]
      } else {
        [41.0, 80.0, 41.0]
      },
    )
  }
}

///|
test "reverse flow device boundary snaps final absolute edges" {
  let root = @layout.FlexTreeStyle::new(@layout.FlowDirection::row_reverse())
    .with_justify(@layout.JustifyContent::end())
    .with_align(@layout.AlignItems::start())
  let nodes = [@layout.FlexTreeNode::new(alignment_item(2, 20.6, 10.25), 1)]
  for (scale, width, left) in [(1.0, 21.0, 79.0), (2.0, 20.5, 79.5)] {
    let result = axis_tree_layout(
      tree_size(100.0, 40.0),
      root,
      nodes,
      scale=Some(scale),
    )
    assert_eq(result.items()[0].bounds().left(), left)
    assert_eq(result.items()[0].bounds().size().width(), width)
  }
}

///|
test "reverse physical justification and distributed overflow follow measured GPUI semantics" {
  for
    (direction, horizontal) in [
      (@layout.FlowDirection::row_reverse(), true),
      (@layout.FlowDirection::column_reverse(), false),
    ] {
    for
      (extent, justify, expected, overflow) in [
        (80.0, @layout.JustifyContent::start(), [34.0, 0.0], false),
        (80.0, @layout.JustifyContent::end(), [50.0, 16.0], false),
        (80.0, @layout.JustifyContent::center(), [42.0, 8.0], false),
        (40.0, @layout.JustifyContent::start(), [34.0, 0.0], true),
        (40.0, @layout.JustifyContent::end(), [10.0, -24.0], true),
        (40.0, @layout.JustifyContent::center(), [22.0, -12.0], true),
        (40.0, @layout.JustifyContent::space_between(), [34.0, 0.0], true),
        (40.0, @layout.JustifyContent::space_around(), [34.0, 0.0], true),
        (40.0, @layout.JustifyContent::space_evenly(), [34.0, 0.0], true),
      ] {
      let container = axis_gap_ok(
        @layout.FlexContainer::new(direction, tree_size(extent, extent))
        .with_justify(justify)
        .with_gap(4.0),
      )
      let result = unwrap_layout(
        @layout.layout_flex(container, [
          alignment_item(1, 30.0, 10.0),
          alignment_item(2, 30.0, 10.0),
        ]),
      )
      assert_eq(
        result
        .items()
        .map(item => {
          if horizontal {
            item.bounds().left()
          } else {
            item.bounds().top()
          }
        }),
        expected,
      )
      assert_eq(result.overflow(), overflow)
    }
    for
      (justify, expected) in [
        (@layout.JustifyContent::space_between(), 50.0),
        (@layout.JustifyContent::space_around(), 25.0),
        (@layout.JustifyContent::space_evenly(), 25.0),
      ] {
      for (extent, position) in [(80.0, expected), (20.0, 0.0)] {
        let result = unwrap_layout(
          @layout.layout_flex(
            @layout.FlexContainer::new(direction, tree_size(extent, extent)).with_justify(
              justify,
            ),
            [alignment_item(1, 30.0, 10.0)],
          ),
        )
        assert_eq(
          if horizontal {
            result.items()[0].bounds().left()
          } else {
            result.items()[0].bounds().top()
          },
          position,
        )
      }
    }
    let empty = unwrap_layout(
      @layout.layout_flex(
        @layout.FlexContainer::new(direction, tree_size(80.0, 80.0)),
        [],
      ),
    )
    assert_eq(empty.items().length(), 0)
    assert_true(!empty.overflow())
  }
}

///|
test "reverse physical anchors survive large finite ratios on both axes and wrap policies" {
  for
    (direction, horizontal) in [
      (@layout.FlowDirection::row_reverse(), true),
      (@layout.FlowDirection::column_reverse(), false),
    ] {
    for
      wrap in [
        @layout.FlexWrap::no_wrap(),
        @layout.FlexWrap::wrap(),
        @layout.FlexWrap::wrap_reverse(),
      ] {
      let container = axis_gap_ok(
        @layout.FlexContainer::new(
          direction,
          if horizontal {
            tree_size(1.0e16, 20.0)
          } else {
            tree_size(20.0, 1.0e16)
          },
        )
        .with_wrap(wrap)
        .with_align_content(@layout.AlignContent::start())
        .with_justify(@layout.JustifyContent::start())
        .with_gap(4.0),
      )
      let result = unwrap_layout(
        @layout.layout_flex(container, [
          alignment_item(1, 1.0, 1.0),
          alignment_item(2, 1.0, 1.0),
        ]),
      )
      assert_eq(
        result
        .items()
        .map(item => {
          if horizontal {
            item.bounds().left()
          } else {
            item.bounds().top()
          }
        }),
        [5.0, 0.0],
      )
      assert_true(!result.overflow())
      for item in result.items() {
        assert_true(!item.overflow())
      }
      for
        justify in [
          @layout.JustifyContent::start(),
          @layout.JustifyContent::space_between(),
          @layout.JustifyContent::space_around(),
          @layout.JustifyContent::space_evenly(),
        ] {
        let container = @layout.FlexContainer::new(
            direction,
            tree_size(21.0, 21.0),
          )
          .with_wrap(wrap)
          .with_justify(justify)
        let result = unwrap_layout(
          @layout.layout_flex(container, [alignment_item(1, 1.0e16, 1.0)]),
        )
        assert_eq(
          if horizontal {
            result.items()[0].bounds().left()
          } else {
            result.items()[0].bounds().top()
          },
          0.0,
        )
        assert_true(result.overflow())
        assert_true(result.items()[0].overflow())
      }
    }
    for
      justify in [
        @layout.JustifyContent::start(),
        @layout.JustifyContent::space_between(),
        @layout.JustifyContent::space_around(),
        @layout.JustifyContent::space_evenly(),
      ] {
      let container = axis_gap_ok(
        @layout.FlexContainer::new(direction, tree_size(21.0, 21.0))
        .with_justify(justify)
        .with_gap(4.0),
      )
      let result = unwrap_layout(
        @layout.layout_flex(container, [
          alignment_item(1, 1.0e16, 1.0),
          alignment_item(2, 1.0, 1.0),
        ]),
      )
      assert_eq(
        result
        .items()
        .map(item => {
          if horizontal {
            item.bounds().left()
          } else {
            item.bounds().top()
          }
        }),
        [5.0, 0.0],
      )
      assert_true(result.items()[0].overflow())
      assert_true(!result.items()[1].overflow())
      assert_true(result.overflow())
    }
  }
}

///|
test "reverse distributed placement retains both outer anchors across finite ratios" {
  for
    (direction, horizontal) in [
      (@layout.FlowDirection::row_reverse(), true),
      (@layout.FlowDirection::column_reverse(), false),
    ] {
    for
      wrap in [
        @layout.FlexWrap::no_wrap(),
        @layout.FlexWrap::wrap(),
        @layout.FlexWrap::wrap_reverse(),
      ] {
      for
        (justify, leading, gap) in [
          (@layout.JustifyContent::space_between(), 0.0, 6.0),
          (@layout.JustifyContent::space_around(), 2.0 / 3.0, 16.0 / 3.0),
          (@layout.JustifyContent::space_evenly(), 1.0, 5.0),
        ] {
        let size = if horizontal {
          tree_size(1.0e16 + 12.0, 20.0)
        } else {
          tree_size(20.0, 1.0e16 + 12.0)
        }
        let container = axis_gap_ok(
          @layout.FlexContainer::new(direction, size)
          .with_wrap(wrap)
          .with_justify(justify)
          .with_gap(4.0),
        )
        let result = unwrap_layout(
          @layout.layout_flex(container, [
            alignment_item(1, 1.0e16, 1.0),
            alignment_item(2, 1.0, 1.0),
            alignment_item(3, 1.0, 1.0),
          ]),
        )
        let origins = result
          .items()
          .map(item => {
            if horizontal {
              item.bounds().left()
            } else {
              item.bounds().top()
            }
          })
        assert_true((origins[2] - leading).abs() < 1.0e-12)
        assert_true((origins[1] - (leading + 1.0 + gap)).abs() < 1.0e-12)
        assert_eq(origins[0] + 1.0e16, 1.0e16 + 12.0 - leading)
        assert_true(!result.overflow())
        for item in result.items() {
          assert_true(!item.overflow())
        }
      }
    }
  }
}
