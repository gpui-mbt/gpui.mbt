///|
fn alignment_container(
  direction : @layout.FlowDirection,
  main : Double,
  cross : Double,
) -> @layout.FlexContainer raise {
  let size = if direction is @layout.Row {
    unwrap_size(main, cross)
  } else {
    unwrap_size(cross, main)
  }
  @layout.FlexContainer::new(direction, size)
}

///|
fn alignment_item(
  id : UInt64,
  main : Double,
  cross : Double,
) -> @layout.FlexItem raise {
  unwrap_item_flex(
    @layout.FlexItem::new(
      id,
      unwrap_points(main),
      unwrap_points(cross),
      unwrap_size(0.0, 0.0),
    ),
    0.0,
    0.0,
  )
}

///|
fn alignment_main_origin(
  bounds : @primitives.Rect,
  direction : @layout.FlowDirection,
) -> Double {
  if direction is @layout.Row {
    bounds.left()
  } else {
    bounds.top()
  }
}

///|
fn alignment_cross_origin(
  bounds : @primitives.Rect,
  direction : @layout.FlowDirection,
) -> Double {
  if direction is @layout.Row {
    bounds.top()
  } else {
    bounds.left()
  }
}

///|
test "main center preserves negative free space in rows and columns" {
  for
    direction in [@layout.FlowDirection::row(), @layout.FlowDirection::column()] {
    let container = alignment_container(direction, 40.0, 20.0).with_justify(
      @layout.JustifyContent::center(),
    )
    let result = unwrap_layout(
      @layout.layout_flex(container, [
        alignment_item(1, 40.0, 10.0),
        alignment_item(2, 40.0, 10.0),
      ]),
    )
    let items = result.items()
    assert_eq(alignment_main_origin(items[0].bounds(), direction), -20.0)
    assert_eq(alignment_main_origin(items[1].bounds(), direction), 20.0)
    assert_true(result.overflow())
    assert_true(items[0].overflow())
    assert_true(items[1].overflow())
  }
}

///|
test "main end reports leading overflow in rows and columns" {
  for
    direction in [@layout.FlowDirection::row(), @layout.FlowDirection::column()] {
    let container = alignment_container(direction, 40.0, 20.0).with_justify(
      @layout.JustifyContent::end(),
    )
    let result = unwrap_layout(
      @layout.layout_flex(container, [
        alignment_item(1, 40.0, 10.0),
        alignment_item(2, 40.0, 10.0),
      ]),
    )
    let items = result.items()
    assert_eq(alignment_main_origin(items[0].bounds(), direction), -40.0)
    assert_eq(alignment_main_origin(items[1].bounds(), direction), 0.0)
    assert_true(result.overflow())
    assert_true(items[0].overflow())
    assert_true(!items[1].overflow())
  }
}

///|
test "cross center centers oversized children in rows and columns" {
  for
    direction in [@layout.FlowDirection::row(), @layout.FlowDirection::column()] {
    let container = alignment_container(direction, 100.0, 20.0).with_align(
      @layout.AlignItems::center(),
    )
    let result = unwrap_layout(
      @layout.layout_flex(container, [
        alignment_item(1, 10.0, 40.0),
        alignment_item(2, 10.0, 60.0),
      ]),
    )
    let items = result.items()
    assert_eq(alignment_cross_origin(items[0].bounds(), direction), -10.0)
    assert_eq(alignment_cross_origin(items[1].bounds(), direction), -20.0)
    assert_true(result.overflow())
    assert_true(items[0].overflow())
    assert_true(items[1].overflow())
  }
}

///|
test "cross end aligns oversized children in rows and columns" {
  for
    direction in [@layout.FlowDirection::row(), @layout.FlowDirection::column()] {
    let container = alignment_container(direction, 100.0, 20.0).with_align(
      @layout.AlignItems::end(),
    )
    let result = unwrap_layout(
      @layout.layout_flex(container, [
        alignment_item(1, 10.0, 40.0),
        alignment_item(2, 10.0, 60.0),
      ]),
    )
    let items = result.items()
    assert_eq(alignment_cross_origin(items[0].bounds(), direction), -20.0)
    assert_eq(alignment_cross_origin(items[1].bounds(), direction), -40.0)
    assert_true(result.overflow())
    assert_true(items[0].overflow())
    assert_true(items[1].overflow())
  }
}

///|
test "start alignment preserves leading edges when children overflow" {
  for
    direction in [@layout.FlowDirection::row(), @layout.FlowDirection::column()] {
    let main_result = unwrap_layout(
      @layout.layout_flex(alignment_container(direction, 40.0, 20.0), [
        alignment_item(1, 40.0, 10.0),
        alignment_item(2, 40.0, 10.0),
      ]),
    )
    let main_items = main_result.items()
    assert_eq(alignment_main_origin(main_items[0].bounds(), direction), 0.0)
    assert_eq(alignment_main_origin(main_items[1].bounds(), direction), 40.0)
    assert_true(!main_items[0].overflow())
    assert_true(main_items[1].overflow())
    let cross_result = unwrap_layout(
      @layout.layout_flex(alignment_container(direction, 100.0, 20.0), [
        alignment_item(1, 10.0, 40.0),
        alignment_item(2, 10.0, 60.0),
      ]),
    )
    for item in cross_result.items() {
      assert_eq(alignment_cross_origin(item.bounds(), direction), 0.0)
      assert_true(item.overflow())
    }
  }
}

///|
test "center and end retain exact-fit and positive-space placement" {
  for
    direction in [@layout.FlowDirection::row(), @layout.FlowDirection::column()] {
    for
      (justify, align, main_offset, cross_offset) in [
        (
          @layout.JustifyContent::center(),
          @layout.AlignItems::center(),
          10.0,
          5.0,
        ),
        (@layout.JustifyContent::end(), @layout.AlignItems::end(), 20.0, 10.0),
      ] {
      for
        (main, cross, expected_main, expected_cross) in [
          (80.0, 10.0, 0.0, 0.0),
          (100.0, 20.0, main_offset, cross_offset),
        ] {
        let container = alignment_container(direction, main, cross)
          .with_justify(justify)
          .with_align(align)
        let result = unwrap_layout(
          @layout.layout_flex(container, [
            alignment_item(1, 40.0, 10.0),
            alignment_item(2, 40.0, 10.0),
          ]),
        )
        let items = result.items()
        assert_eq(
          alignment_main_origin(items[0].bounds(), direction),
          expected_main,
        )
        assert_eq(
          alignment_main_origin(items[1].bounds(), direction),
          expected_main + 40.0,
        )
        for item in items {
          assert_eq(
            alignment_cross_origin(item.bounds(), direction),
            expected_cross,
          )
          assert_true(!item.overflow())
        }
        assert_true(!result.overflow())
      }
    }
  }
}

///|
test "stretch keeps explicit oversized and auto cross dimensions at the start" {
  for
    direction in [@layout.FlowDirection::row(), @layout.FlowDirection::column()] {
    let container = alignment_container(direction, 100.0, 20.0).with_align(
      @layout.AlignItems::stretch(),
    )
    let auto_item = @layout.FlexItem::new(
      2,
      unwrap_points(10.0),
      @layout.Dimension::auto(),
      unwrap_size(5.0, 5.0),
    )
    let result = unwrap_layout(
      @layout.layout_flex(container, [alignment_item(1, 10.0, 40.0), auto_item]),
    )
    let items = result.items()
    for item in items {
      assert_eq(alignment_cross_origin(item.bounds(), direction), 0.0)
    }
    let cross_size = if direction is @layout.Row {
      items[1].bounds().size().height()
    } else {
      items[1].bounds().size().width()
    }
    assert_eq(cross_size, 20.0)
    assert_true(items[0].overflow())
    assert_true(!items[1].overflow())
  }
}

///|
test "negative aligned origins include insets and remain finite" {
  for
    direction in [@layout.FlowDirection::row(), @layout.FlowDirection::column()] {
    let container = alignment_container(direction, 46.0, 26.0)
      .with_insets(
        unwrap_insets(2.0, 2.0, 2.0, 2.0),
        unwrap_insets(1.0, 1.0, 1.0, 1.0),
      )
      .with_justify(@layout.JustifyContent::end())
      .with_align(@layout.AlignItems::end())
    let result = unwrap_layout(
      @layout.layout_flex(container, [
        alignment_item(1, 40.0, 40.0),
        alignment_item(2, 40.0, 40.0),
      ]),
    )
    let items = result.items()
    assert_eq(alignment_main_origin(items[0].bounds(), direction), -37.0)
    assert_eq(alignment_main_origin(items[1].bounds(), direction), 3.0)
    for item in items {
      let bounds = item.bounds()
      assert_eq(alignment_cross_origin(bounds, direction), -17.0)
      for
        value in [
          bounds.left(),
          bounds.top(),
          bounds.right(),
          bounds.bottom(),
          bounds.size().width(),
          bounds.size().height(),
        ] {
        assert_true(!value.is_nan() && !value.is_inf())
      }
      assert_true(item.overflow())
    }
    assert_true(result.overflow())
  }
}
