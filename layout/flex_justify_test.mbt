///|
test "flex relative justification agrees with physical edges by direction" {
  for
    (direction, reverse) in [
      (@layout.FlowDirection::row(), false),
      (@layout.FlowDirection::column(), false),
      (@layout.FlowDirection::row_reverse(), true),
      (@layout.FlowDirection::column_reverse(), true),
    ] {
    for
      wrap in [
        @layout.FlexWrap::no_wrap(),
        @layout.FlexWrap::wrap(),
        @layout.FlexWrap::wrap_reverse(),
      ] {
      for extent in [35.0, 75.0, 140.0] {
        let base = axis_gaps(
          @layout.FlexContainer::new(direction, tree_size(extent, extent))
          .with_wrap(wrap)
          .with_insets(
            tree_insets(3.0, 7.0, 11.0, 13.0),
            @layout.Insets::zero(),
          ),
          5.0,
          9.0,
        )
        let items = [
          unwrap_item_flex(alignment_item(7, 30.0, 10.0), 0.0, 0.0),
          unwrap_item_flex(alignment_item(3, 40.0, 12.0), 0.0, 0.0),
        ]
        for
          (relative, physical) in [
            (
              @layout.JustifyContent::flex_start(),
              if reverse {
                @layout.JustifyContent::end()
              } else {
                @layout.JustifyContent::start()
              },
            ),
            (
              @layout.JustifyContent::flex_end(),
              if reverse {
                @layout.JustifyContent::start()
              } else {
                @layout.JustifyContent::end()
              },
            ),
          ] {
          let a = unwrap_layout(
            @layout.layout_flex(base.with_justify(relative), items),
          )
          let b = unwrap_layout(
            @layout.layout_flex(base.with_justify(physical), items),
          )
          assert_eq(a.items().map(item => item.id()), [7UL, 3UL])
          assert_true(
            a.items().map(item => item.bounds()) ==
            b.items().map(item => item.bounds()),
          )
          assert_eq(a.overflow(), b.overflow())
        }
      }
    }
  }
}

///|
test "flex main start and end preserve signed overflow on reverse axes" {
  for
    (direction, horizontal) in [
      (@layout.FlowDirection::row_reverse(), true),
      (@layout.FlowDirection::column_reverse(), false),
    ] {
    let base = @layout.FlexContainer::new(direction, tree_size(30.0, 30.0))
    let item = unwrap_item_flex(alignment_item(1, 50.0, 10.0), 0.0, 0.0)
    for
      (justify, expected) in [
        (@layout.JustifyContent::flex_start(), -20.0),
        (@layout.JustifyContent::flex_end(), 0.0),
      ] {
      let result = unwrap_layout(
        @layout.layout_flex(base.with_justify(justify), [item]),
      )
      let bounds = result.items()[0].bounds()
      assert_eq(if horizontal { bounds.left() } else { bounds.top() }, expected)
      assert_true(result.overflow())
    }
  }
}

///|
test "reverse flex end keeps small near edge positions at huge magnitudes" {
  for
    (direction, horizontal) in [
      (@layout.FlowDirection::row_reverse(), true),
      (@layout.FlowDirection::column_reverse(), false),
    ] {
    for extent in [1.0, 1.0e16] {
      let container = axis_gaps(
        @layout.FlexContainer::new(direction, tree_size(extent, extent)).with_justify(
          @layout.JustifyContent::flex_end(),
        ),
        1.0,
        1.0,
      )
      let items = [
        unwrap_item_flex(alignment_item(1, 1.0e16, 1.0), 0.0, 0.0),
        unwrap_item_flex(alignment_item(2, 1.0, 1.0), 0.0, 0.0),
      ]
      let result = unwrap_layout(@layout.layout_flex(container, items)).items()
      assert_eq(
        if horizontal {
          result[1].bounds().left()
        } else {
          result[1].bounds().top()
        },
        0.0,
      )
      assert_eq(
        if horizontal {
          result[0].bounds().left()
        } else {
          result[0].bounds().top()
        },
        2.0,
      )
    }
  }
}

///|
test "flow relative justify survives recursive device scale preparation" {
  let style = @layout.FlexTreeStyle::new(@layout.FlowDirection::row_reverse()).with_justify(
    @layout.JustifyContent::flex_start(),
  )
  let node = @layout.FlexTreeNode::new(tree_item(2, 20.0, 10.0), 1)
  match
    @layout.layout_flex_tree_with_device_scale(
      1,
      tree_size(100.0, 80.0),
      style,
      [node],
      2.0,
    ) {
    Err(_) => fail("valid relative justification rejected")
    Ok(result) => assert_eq(result.items()[0].bounds().left(), 80.0)
  }
}

///|
test "flow relative constructors remain distinct and accept empty containers" {
  assert_true(
    @layout.JustifyContent::flex_start() != @layout.JustifyContent::start(),
  )
  assert_true(
    @layout.JustifyContent::flex_end() != @layout.JustifyContent::end(),
  )
  for
    justify in [
      @layout.JustifyContent::flex_start(),
      @layout.JustifyContent::flex_end(),
    ] {
    let result = unwrap_layout(
      @layout.layout_flex(
        @layout.FlexContainer::new(
          @layout.FlowDirection::row_reverse(),
          tree_size(100.0, 80.0),
        ).with_justify(justify),
        [],
      ),
    )
    assert_eq(result.items().length(), 0)
    assert_true(!result.overflow())
  }
}
