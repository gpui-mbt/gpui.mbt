///|
fn grow_item(
  id : UInt64,
  basis : Double,
  grow : Double,
  shrink~ : Double = 1.0,
) -> @layout.FlexItem raise {
  unwrap_item_flex(
    @layout.FlexItem::new(
      id,
      unwrap_points(basis),
      unwrap_points(10.0),
      unwrap_size(0.0, 0.0),
    ),
    grow,
    shrink,
  )
}

///|
fn grow_pair(
  direction : @layout.FlowDirection,
  extent : Double,
  first_factor : Double,
  second_factor : Double,
  basis~ : Double = 20.0,
  gap~ : Double = 0.0,
  justify~ : @layout.JustifyContent = @layout.JustifyContent::start(),
  shrink~ : Double = 1.0,
) -> @layout.FlexLayout raise {
  let container = unwrap_gap(alignment_container(direction, extent, 20.0), gap).with_justify(
    justify,
  )
  unwrap_layout(
    @layout.layout_flex(container, [
      grow_item(1, basis, first_factor, shrink~),
      grow_item(2, basis, second_factor, shrink~),
    ]),
  )
}

///|
fn grow_main_bounds(
  result : @layout.FlexLayout,
  direction : @layout.FlowDirection,
) -> Array[(Double, Double)] {
  result
  .items()
  .map(item => {
    let bounds = item.bounds()
    if direction is @layout.Row {
      (bounds.left(), bounds.size().width())
    } else {
      (bounds.top(), bounds.size().height())
    }
  })
}

///|
test "fractional grow leaves unused space in rows and columns" {
  for
    direction in [@layout.FlowDirection::row(), @layout.FlowDirection::column()] {
    let result = grow_pair(direction, 100.0, 0.25, 0.25)
    assert_eq(grow_main_bounds(result, direction), [(0.0, 35.0), (35.0, 35.0)])
    assert_true(!result.overflow())
    for item in result.items() {
      assert_true(!item.overflow())
    }
  }
}

///|
test "zero grow leaves both bases unchanged" {
  for
    direction in [@layout.FlowDirection::row(), @layout.FlowDirection::column()] {
    let result = grow_pair(direction, 100.0, 0.0, 0.0)
    assert_eq(grow_main_bounds(result, direction), [(0.0, 20.0), (20.0, 20.0)])
    assert_true(!result.overflow())
  }
}

///|
test "asymmetric fractional grow retains each absolute free-space share" {
  for
    direction in [@layout.FlowDirection::row(), @layout.FlowDirection::column()] {
    for
      (first, second, first_size, second_size) in [
        (0.25, 0.0, 35.0, 20.0),
        (0.0, 0.25, 20.0, 35.0),
        (0.25, 0.5, 35.0, 50.0),
      ] {
      let result = grow_pair(direction, 100.0, first, second)
      assert_eq(grow_main_bounds(result, direction), [
        (0.0, first_size),
        (first_size, second_size),
      ])
      assert_true(!result.overflow())
    }
  }
}

///|
test "grow totals equal to or greater than one still fill free space" {
  for
    direction in [@layout.FlowDirection::row(), @layout.FlowDirection::column()] {
    for
      (first, second, first_size, second_size) in [
        (0.25, 0.75, 35.0, 65.0),
        (1.0, 1.0, 50.0, 50.0),
        (1.0, 3.0, 35.0, 65.0),
        (1.0e300, 1.0e300, 50.0, 50.0),
      ] {
      let result = grow_pair(direction, 100.0, first, second)
      assert_eq(grow_main_bounds(result, direction), [
        (0.0, first_size),
        (first_size, second_size),
      ])
      assert_true(!result.overflow())
    }
  }
}

///|
test "center and end place the unallocated fractional grow space" {
  for
    direction in [@layout.FlowDirection::row(), @layout.FlowDirection::column()] {
    for
      (justify, first_origin) in [
        (@layout.JustifyContent::center(), 15.0),
        (@layout.JustifyContent::end(), 30.0),
      ] {
      let result = grow_pair(direction, 100.0, 0.25, 0.25, justify~)
      assert_eq(grow_main_bounds(result, direction), [
        (first_origin, 35.0),
        (first_origin + 35.0, 35.0),
      ])
      assert_true(!result.overflow())
    }
  }
}

///|
test "fractional grow subtracts gaps before allocating and justifying" {
  for
    direction in [@layout.FlowDirection::row(), @layout.FlowDirection::column()] {
    for
      (justify, first_origin) in [
        (@layout.JustifyContent::start(), 0.0),
        (@layout.JustifyContent::center(), 12.5),
        (@layout.JustifyContent::end(), 25.0),
      ] {
      let result = grow_pair(direction, 100.0, 0.25, 0.25, gap=10.0, justify~)
      assert_eq(grow_main_bounds(result, direction), [
        (first_origin, 32.5),
        (first_origin + 42.5, 32.5),
      ])
      assert_true(!result.overflow())
    }
  }
}

///|
test "fractional grow does not change exact fits or shrink allocation" {
  for
    direction in [@layout.FlowDirection::row(), @layout.FlowDirection::column()] {
    let exact = grow_pair(direction, 40.0, 0.25, 0.25)
    assert_eq(grow_main_bounds(exact, direction), [(0.0, 20.0), (20.0, 20.0)])
    assert_true(!exact.overflow())
    let shrunk = grow_pair(direction, 20.0, 0.25, 0.25)
    assert_eq(grow_main_bounds(shrunk, direction), [(0.0, 10.0), (10.0, 10.0)])
    assert_true(!shrunk.overflow())
    let overflow = grow_pair(
      direction,
      20.0,
      0.25,
      0.25,
      shrink=0.0,
      justify=@layout.JustifyContent::end(),
    )
    assert_eq(grow_main_bounds(overflow, direction), [
      (-20.0, 20.0),
      (0.0, 20.0),
    ])
    assert_true(overflow.overflow())
    assert_true(overflow.items()[0].overflow())
    assert_true(!overflow.items()[1].overflow())
  }
}

///|
test "tiny positive grow remains a tiny share at finite large scales" {
  for
    direction in [@layout.FlowDirection::row(), @layout.FlowDirection::column()] {
    let result = grow_pair(direction, 1.0e300, 1.0e-300, 0.0, basis=0.0)
    assert_eq(grow_main_bounds(result, direction), [(0.0, 1.0), (1.0, 0.0)])
    assert_true(!result.overflow())
    let subnormal = grow_pair(direction, 100.0, 5.0e-324, 5.0e-324)
    assert_eq(grow_main_bounds(subnormal, direction), [
      (0.0, 20.0),
      (20.0, 20.0),
    ])
    assert_true(!subnormal.overflow())
  }
}

///|
test "fractional grow keeps one-pass clamping without redistribution" {
  for
    direction in [@layout.FlowDirection::row(), @layout.FlowDirection::column()] {
    let first = unwrap_main_limits(grow_item(1, 20.0, 0.25), 0.0, Some(30.0))
    let second = grow_item(2, 20.0, 0.25)
    let result = unwrap_layout(
      @layout.layout_flex(alignment_container(direction, 100.0, 20.0), [
        first, second,
      ]),
    )
    assert_eq(grow_main_bounds(result, direction), [(0.0, 30.0), (30.0, 35.0)])
    assert_true(!result.overflow())
  }
}
