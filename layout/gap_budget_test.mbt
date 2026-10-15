///|
test "partial grow gap budget can be positive zero or negative" {
  for
    direction in [@layout.FlowDirection::row(), @layout.FlowDirection::column()] {
    for
      (gap, extent, child_size) in [
        (0.0, 100.0, 35.0),
        (8.0, 108.0, 31.0),
        (16.0, 116.0, 27.0),
        (30.0, 130.0, 20.0),
        (32.0, 132.0, 19.0),
        (64.0, 164.0, 3.0),
        (80.0, 180.0, 0.0),
      ] {
      let result = grow_pair(direction, extent, 0.25, 0.25, gap~)
      assert_eq(grow_main_bounds(result, direction), [
        (0.0, child_size),
        (child_size + gap, child_size),
      ])
      assert_true(!result.overflow())
    }
  }
}

///|
test "gap budget preserves zero and unit grow controls" {
  for
    direction in [@layout.FlowDirection::row(), @layout.FlowDirection::column()] {
    for
      (first, second, first_size, second_size) in [
        (0.0, 0.0, 20.0, 20.0),
        (0.5, 0.5, 50.0, 50.0),
        (0.5, 1.5, 35.0, 65.0),
      ] {
      let result = grow_pair(direction, 108.0, first, second, gap=8.0)
      assert_eq(grow_main_bounds(result, direction), [
        (0.0, first_size),
        (first_size + 8.0, second_size),
      ])
      assert_true(!result.overflow())
    }
  }
}

///|
test "partial grow distributes the gap adjusted budget by factor ratio" {
  for
    direction in [@layout.FlowDirection::row(), @layout.FlowDirection::column()] {
    let zero_first = grow_pair(direction, 108.0, 0.0, 0.5, gap=8.0)
    assert_eq(grow_main_bounds(zero_first, direction), [
      (0.0, 20.0),
      (28.0, 42.0),
    ])
    let asymmetric = grow_pair(direction, 112.0, 0.125, 0.375, gap=8.0)
    assert_eq(grow_main_bounds(asymmetric, direction), [
      (0.0, 26.0),
      (34.0, 38.0),
    ])
  }
}

///|
test "gap budget does not change exact fit or shrink allocation" {
  for
    direction in [@layout.FlowDirection::row(), @layout.FlowDirection::column()] {
    let exact = grow_pair(direction, 48.0, 0.25, 0.25, gap=8.0)
    assert_eq(grow_main_bounds(exact, direction), [(0.0, 20.0), (28.0, 20.0)])
    let shrink = grow_pair(direction, 40.0, 0.25, 0.25, gap=8.0)
    assert_eq(grow_main_bounds(shrink, direction), [(0.0, 16.0), (24.0, 16.0)])
    assert_true(!exact.overflow())
    assert_true(!shrink.overflow())
  }
}
