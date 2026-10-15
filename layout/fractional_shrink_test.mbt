///|
fn shrink_pair(
  direction : @layout.FlowDirection,
  extent : Double,
  first_factor : Double,
  second_factor : Double,
  first_basis~ : Double = 40.0,
  second_basis~ : Double = 40.0,
  gap~ : Double = 0.0,
  justify~ : @layout.JustifyContent = @layout.JustifyContent::start(),
) -> @layout.FlexLayout raise {
  let container = unwrap_gap(alignment_container(direction, extent, 20.0), gap).with_justify(
    justify,
  )
  unwrap_layout(
    @layout.layout_flex(container, [
      grow_item(1, first_basis, 0.0, shrink=first_factor),
      grow_item(2, second_basis, 0.0, shrink=second_factor),
    ]),
  )
}

///|
test "partial shrink retains measured overflow in rows and columns" {
  for
    direction in [@layout.FlowDirection::row(), @layout.FlowDirection::column()] {
    let result = shrink_pair(direction, 40.0, 0.25, 0.25)
    assert_eq(grow_main_bounds(result, direction), [(0.0, 30.0), (30.0, 30.0)])
    assert_true(result.overflow())
    assert_true(!result.items()[0].overflow())
    assert_true(result.items()[1].overflow())
  }
}

///|
test "partial shrink uses the raw factor total and scaled factor ratios" {
  for
    direction in [@layout.FlowDirection::row(), @layout.FlowDirection::column()] {
    for
      (first, second, first_size, second_size) in [
        (0.0, 0.5, 40.0, 20.0),
        (0.125, 0.375, 35.0, 25.0),
        (0.375, 0.5, 25.0, 20.0),
        (0.5, 0.5, 20.0, 20.0),
        (0.5, 1.5, 30.0, 10.0),
        (0.0, 0.0, 40.0, 40.0),
      ] {
      let result = shrink_pair(direction, 40.0, first, second)
      assert_eq(grow_main_bounds(result, direction), [
        (0.0, first_size),
        (first_size, second_size),
      ])
    }
    let unequal = shrink_pair(
      direction, 40.0, 0.25, 0.25, first_basis=20.0, second_basis=60.0,
    )
    assert_eq(grow_main_bounds(unequal, direction), [(0.0, 15.0), (15.0, 45.0)])
    let zero_basis = shrink_pair(
      direction, 40.0, 0.25, 0.25, first_basis=0.0, second_basis=80.0,
    )
    assert_eq(grow_main_bounds(zero_basis, direction), [(0.0, 0.0), (0.0, 60.0)])
  }
}

///|
test "partial shrink preserves signed center and end overflow placement" {
  for
    direction in [@layout.FlowDirection::row(), @layout.FlowDirection::column()] {
    for
      (justify, origin) in [
        (@layout.JustifyContent::center(), -10.0),
        (@layout.JustifyContent::end(), -20.0),
      ] {
      let result = shrink_pair(direction, 40.0, 0.25, 0.25, justify~)
      assert_eq(grow_main_bounds(result, direction), [
        (origin, 30.0),
        (origin + 30.0, 30.0),
      ])
      assert_true(result.overflow())
      assert_true(result.items()[0].overflow())
    }
  }
}

///|
test "partial shrink gap budget is bounded by the original negative space" {
  for
    direction in [@layout.FlowDirection::row(), @layout.FlowDirection::column()] {
    for (gap, extent, child_size) in [(8.0, 48.0, 26.0), (32.0, 72.0, 20.0)] {
      let result = shrink_pair(direction, extent, 0.25, 0.25, gap~)
      assert_eq(grow_main_bounds(result, direction), [
        (0.0, child_size),
        (child_size + gap, child_size),
      ])
    }
  }
}

///|
test "shrink factors do not allocate positive or zero free space" {
  for
    direction in [@layout.FlowDirection::row(), @layout.FlowDirection::column()] {
    for extent in [80.0, 100.0] {
      let result = shrink_pair(direction, extent, 0.25, 0.25)
      assert_eq(grow_main_bounds(result, direction), [(0.0, 40.0), (40.0, 40.0)])
      assert_true(!result.overflow())
    }
  }
}

///|
test "small shrink factors retain their measured small budget" {
  for
    direction in [@layout.FlowDirection::row(), @layout.FlowDirection::column()] {
    let result = shrink_pair(
      direction,
      1024.0,
      0.0009765625,
      0.0009765625,
      first_basis=1024.0,
      second_basis=1024.0,
    )
    assert_eq(grow_main_bounds(result, direction), [
      (0.0, 1023.0),
      (1023.0, 1023.0),
    ])
    assert_true(result.overflow())
  }
}

///|
test "finite large shrink factors with zero bases retain valid geometry" {
  for
    direction in [@layout.FlowDirection::row(), @layout.FlowDirection::column()] {
    let result = shrink_pair(
      direction, 0.0, 1.0e308, 1.0e308, first_basis=0.0, second_basis=0.0,
    )
    assert_eq(grow_main_bounds(result, direction), [(0.0, 0.0), (0.0, 0.0)])
    assert_true(!result.overflow())
  }
}
