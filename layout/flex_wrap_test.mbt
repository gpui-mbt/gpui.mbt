///|
fn wrap_item(
  id : UInt64,
  width : Double,
  height : Double,
  shrink~ : Double = 0.0,
  grow~ : Double = 0.0,
) -> @layout.FlexItem raise {
  let item = @layout.FlexItem::new(
    id,
    unwrap_wrap_points(width),
    unwrap_wrap_points(height),
    unwrap_wrap_size(width, height),
  )
  match item.with_flex(grow, shrink) {
    Ok(value) => value
    Err(_) => fail("valid wrap flex factors were rejected")
  }
}

///|
fn wrap_column_item(
  id : UInt64,
  width : Double,
  height : Double,
) -> @layout.FlexItem raise {
  @layout.FlexItem::new(
    id,
    unwrap_wrap_points(height),
    unwrap_wrap_points(width),
    unwrap_wrap_size(width, height),
  )
}

///|
fn unwrap_wrap_size(width : Double, height : Double) -> @primitives.Size raise {
  match @primitives.Size::new(width, height) {
    Ok(value) => value
    Err(_) => fail("valid wrap size was rejected")
  }
}

///|
fn unwrap_wrap_points(value : Double) -> @layout.Dimension raise {
  match @layout.Dimension::points(value) {
    Ok(result) => result
    Err(_) => fail("valid wrap point dimension was rejected")
  }
}

///|
fn unwrap_wrap_gap(
  container : @layout.FlexContainer,
  gap : Double,
) -> @layout.FlexContainer raise {
  match container.with_gap(gap) {
    Ok(value) => value
    Err(_) => fail("valid wrap gap was rejected")
  }
}

///|
fn wrap_line_bounds(
  items : Array[@layout.LayoutBox],
) -> Array[(Double, Double, Double, Double)] {
  items.map(item => {
    let bounds = item.bounds()
    (bounds.left(), bounds.top(), bounds.size().width(), bounds.size().height())
  })
}

///|
test "wrap and wrap-reverse split fixed children across the cross axis" {
  let container = unwrap_wrap_gap(
    @layout.FlexContainer::new(
      @layout.FlowDirection::row(),
      unwrap_wrap_size(60.0, 30.0),
    ),
    2.0,
  ).with_align(@layout.AlignItems::start())
  let children = [wrap_item(1, 40.0, 10.0), wrap_item(2, 40.0, 10.0)]
  let normal = unwrap_layout(
    @layout.layout_flex(container.with_wrap(@layout.FlexWrap::wrap()), children),
  )
  assert_eq(wrap_line_bounds(normal.items()), [
    (0.0, 0.0, 40.0, 10.0),
    (0.0, 16.0, 40.0, 10.0),
  ])
  let reverse = unwrap_layout(
    @layout.layout_flex(
      container.with_wrap(@layout.FlexWrap::wrap_reverse()),
      children,
    ),
  )
  assert_eq(wrap_line_bounds(reverse.items()), [
    (0.0, 20.0, 40.0, 10.0),
    (0.0, 4.0, 40.0, 10.0),
  ])
  assert_true(!normal.overflow() && !reverse.overflow())
}

///|
test "wrapped line alignment uses stretched line boxes in both directions" {
  let base = unwrap_wrap_gap(
    @layout.FlexContainer::new(
      @layout.FlowDirection::row(),
      unwrap_wrap_size(60.0, 30.0),
    ),
    2.0,
  )
  let children = [wrap_item(1, 40.0, 10.0), wrap_item(2, 40.0, 10.0)]
  for
    (align, normal_y, reverse_y) in [
      (@layout.AlignItems::center(), [2.0, 18.0], [18.0, 2.0]),
      (@layout.AlignItems::end(), [4.0, 20.0], [16.0, 0.0]),
    ] {
    let normal = unwrap_layout(
      @layout.layout_flex(
        base.with_wrap(@layout.FlexWrap::wrap()).with_align(align),
        children,
      ),
    )
    let reverse = unwrap_layout(
      @layout.layout_flex(
        base.with_wrap(@layout.FlexWrap::wrap_reverse()).with_align(align),
        children,
      ),
    )
    let normal_bounds = normal.items()
    let reverse_bounds = reverse.items()
    assert_eq(normal_bounds.map(item => item.bounds().top()), normal_y)
    assert_eq(reverse_bounds.map(item => item.bounds().top()), reverse_y)
  }
}

///|
test "wrapped min and max sizes determine line breaks before per-line growth" {
  let base = unwrap_wrap_gap(
    @layout.FlexContainer::new(
      @layout.FlowDirection::row(),
      unwrap_wrap_size(50.0, 40.0),
    ),
    2.0,
  ).with_wrap(@layout.FlexWrap::wrap())
  let first = wrap_item(1, 20.0, 10.0, grow=1.0)
  let second = wrap_item(2, 20.0, 10.0, grow=1.0)
  let third = wrap_item(3, 20.0, 10.0, grow=1.0)
  let first = match first.with_main_limits(40.0, None) {
    Ok(value) => value
    Err(_) => fail("valid first-item min was rejected")
  }
  let second = match second.with_main_limits(0.0, Some(23.0)) {
    Ok(value) => value
    Err(_) => fail("valid second-item max was rejected")
  }
  let result = unwrap_layout(@layout.layout_flex(base, [first, second, third]))
  assert_eq(wrap_line_bounds(result.items()), [
    (0.0, 0.0, 50.0, 10.0),
    (0.0, 21.0, 23.0, 10.0),
    (25.0, 21.0, 25.0, 10.0),
  ])
  assert_true(!result.overflow())
}

///|
test "wrapped decimal exact fit ignores binary64 residue but still breaks above it" {
  let base = @layout.FlexContainer::new(
      @layout.FlowDirection::row(),
      unwrap_wrap_size(100.3, 20.0),
    )
    .with_align(@layout.AlignItems::start())
    .with_wrap(@layout.FlexWrap::wrap())
  let exact = unwrap_layout(
    @layout.layout_flex(base, [
      wrap_item(1, 50.1, 10.0),
      wrap_item(2, 50.2, 10.0),
    ]),
  )
  assert_eq(wrap_line_bounds(exact.items()), [
    (0.0, 0.0, 50.1, 10.0),
    (50.1, 0.0, 50.2, 10.0),
  ])
  assert_true(!exact.overflow())

  let above = unwrap_layout(
    @layout.layout_flex(base, [
      wrap_item(3, 50.1, 10.0),
      wrap_item(4, 50.2001, 10.0),
    ]),
  )
  assert_eq(wrap_line_bounds(above.items()), [
    (0.0, 0.0, 50.1, 10.0),
    (0.0, 10.0, 50.2001, 10.0),
  ])
  assert_true(!above.overflow())
}

///|
test "wrap-reverse uses safe cross-start placement when lines overflow" {
  let base = unwrap_wrap_gap(
    @layout.FlexContainer::new(
      @layout.FlowDirection::row(),
      unwrap_wrap_size(60.0, 15.0),
    ),
    2.0,
  ).with_align(@layout.AlignItems::start())
  let children = [wrap_item(1, 40.0, 10.0), wrap_item(2, 40.0, 10.0)]
  let normal = unwrap_layout(
    @layout.layout_flex(base.with_wrap(@layout.FlexWrap::wrap()), children),
  )
  assert_eq(normal.items().map(item => item.bounds().top()), [0.0, 12.0])
  assert_true(normal.overflow())
  let reverse = unwrap_layout(
    @layout.layout_flex(
      base.with_wrap(@layout.FlexWrap::wrap_reverse()),
      children,
    ),
  )
  assert_eq(reverse.items().map(item => item.bounds().top()), [12.0, 0.0])
  assert_true(reverse.overflow())
}

///|
test "wrapped auto cross size stretches within a line and respects limits" {
  let base = unwrap_wrap_gap(
      @layout.FlexContainer::new(
        @layout.FlowDirection::row(),
        unwrap_wrap_size(60.0, 30.0),
      ),
      2.0,
    )
    .with_align(@layout.AlignItems::stretch())
    .with_wrap(@layout.FlexWrap::wrap())
  let auto_cross = @layout.FlexItem::new(
    1,
    unwrap_wrap_points(40.0),
    @layout.Dimension::auto(),
    unwrap_wrap_size(40.0, 0.0),
  )
  let auto_cross = match auto_cross.with_cross_limits(12.0, None) {
    Ok(value) => value
    Err(_) => fail("valid auto-cross minimum was rejected")
  }
  let result = unwrap_layout(
    @layout.layout_flex(base, [auto_cross, wrap_item(2, 40.0, 10.0)]),
  )
  assert_eq(wrap_line_bounds(result.items()), [
    (0.0, 0.0, 40.0, 15.0),
    (0.0, 17.0, 40.0, 10.0),
  ])
  assert_true(!result.overflow())
}

///|
test "column wrapping and reverse use the width cross axis" {
  let base = unwrap_wrap_gap(
    @layout.FlexContainer::new(
      @layout.FlowDirection::column(),
      unwrap_wrap_size(30.0, 60.0),
    ),
    2.0,
  ).with_align(@layout.AlignItems::start())
  let children = [
    wrap_column_item(1, 10.0, 40.0),
    wrap_column_item(2, 10.0, 40.0),
  ]
  let normal = unwrap_layout(
    @layout.layout_flex(base.with_wrap(@layout.FlexWrap::wrap()), children),
  )
  assert_eq(wrap_line_bounds(normal.items()), [
    (0.0, 0.0, 10.0, 40.0),
    (16.0, 0.0, 10.0, 40.0),
  ])
  let reverse = unwrap_layout(
    @layout.layout_flex(
      base.with_wrap(@layout.FlexWrap::wrap_reverse()),
      children,
    ),
  )
  assert_eq(wrap_line_bounds(reverse.items()), [
    (20.0, 0.0, 10.0, 40.0),
    (4.0, 0.0, 10.0, 40.0),
  ])
  assert_true(!normal.overflow() && !reverse.overflow())
}

///|
test "oversized wrapped singleton shrinks on its own line" {
  let base = unwrap_wrap_gap(
      @layout.FlexContainer::new(
        @layout.FlowDirection::row(),
        unwrap_wrap_size(50.0, 22.0),
      ),
      2.0,
    )
    .with_align(@layout.AlignItems::start())
    .with_wrap(@layout.FlexWrap::wrap())
  let children = [
    wrap_item(1, 20.0, 10.0),
    wrap_item(2, 70.0, 10.0, shrink=1.0),
  ]
  let result = unwrap_layout(@layout.layout_flex(base, children))
  assert_eq(wrap_line_bounds(result.items()), [
    (0.0, 0.0, 20.0, 10.0),
    (0.0, 12.0, 50.0, 10.0),
  ])
  assert_true(!result.overflow())
}

///|
test "nowrap preserves the prior single-line placement" {
  let container = unwrap_wrap_gap(
    @layout.FlexContainer::new(
      @layout.FlowDirection::row(),
      unwrap_wrap_size(100.0, 30.0),
    ),
    2.0,
  )
  let result = unwrap_layout(
    @layout.layout_flex(container.with_wrap(@layout.FlexWrap::no_wrap()), [
      wrap_item(1, 40.0, 10.0),
      wrap_item(2, 40.0, 10.0),
    ]),
  )
  assert_eq(wrap_line_bounds(result.items()), [
    (0.0, 0.0, 40.0, 10.0),
    (42.0, 0.0, 40.0, 10.0),
  ])
  assert_true(!result.overflow())
}
