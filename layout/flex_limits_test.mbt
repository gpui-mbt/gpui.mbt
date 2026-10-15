///|
fn limited_item(
  id : UInt64,
  basis : Double,
  minimum : Double,
  maximum : Double?,
  grow~ : Double = 1.0,
  shrink~ : Double = 1.0,
) -> @layout.FlexItem raise {
  unwrap_main_limits(grow_item(id, basis, grow, shrink~), minimum, maximum)
}

///|
test "capped growth redistributes remaining space on both axes" {
  for
    direction in [@layout.FlowDirection::row(), @layout.FlowDirection::column()] {
    for
      (justify, gap) in [
        (@layout.JustifyContent::start(), 0.0),
        (@layout.JustifyContent::center(), 0.0),
        (@layout.JustifyContent::end(), 0.0),
        (@layout.JustifyContent::start(), 8.0),
      ] {
      let container = unwrap_gap(
        alignment_container(direction, 100.0 + gap, 20.0),
        gap,
      ).with_justify(justify)
      let result = unwrap_layout(
        @layout.layout_flex(container, [
          limited_item(1, 20.0, 0.0, Some(30.0)),
          grow_item(2, 20.0, 1.0),
        ]),
      )
      assert_eq(grow_main_bounds(result, direction), [
        (0.0, 30.0),
        (30.0 + gap, 70.0),
      ])
      assert_true(!result.overflow())
    }
  }
}

///|
test "minimum shrink redistributes the deficit on both axes" {
  for
    direction in [@layout.FlowDirection::row(), @layout.FlowDirection::column()] {
    for
      (justify, gap) in [
        (@layout.JustifyContent::start(), 0.0),
        (@layout.JustifyContent::center(), 0.0),
        (@layout.JustifyContent::end(), 0.0),
        (@layout.JustifyContent::start(), 8.0),
      ] {
      let container = unwrap_gap(
        alignment_container(direction, 40.0 + gap, 20.0),
        gap,
      ).with_justify(justify)
      let result = unwrap_layout(
        @layout.layout_flex(container, [
          limited_item(1, 40.0, 30.0, None, grow=0.0),
          grow_item(2, 40.0, 0.0),
        ]),
      )
      assert_eq(grow_main_bounds(result, direction), [
        (0.0, 30.0),
        (30.0 + gap, 10.0),
      ])
      assert_true(!result.overflow())
    }
  }
}

///|
test "hypothetical clamped sizes choose growth shrink and exact fit" {
  let direction = @layout.FlowDirection::row()
  for
    (extent, first, second, expected) in [
      (
        80.0,
        limited_item(1, 40.0, 0.0, Some(30.0)),
        grow_item(2, 40.0, 1.0),
        [(0.0, 30.0), (30.0, 50.0)],
      ),
      (
        60.0,
        limited_item(1, 20.0, 30.0, None),
        grow_item(2, 40.0, 1.0),
        [(0.0, 30.0), (30.0, 30.0)],
      ),
      (
        100.0,
        limited_item(1, 40.0, 60.0, None),
        limited_item(2, 40.0, 0.0, Some(30.0)),
        [(0.0, 70.0), (70.0, 30.0)],
      ),
      (
        80.0,
        limited_item(1, 40.0, 0.0, Some(35.0)),
        limited_item(2, 40.0, 45.0, None),
        [(0.0, 35.0), (35.0, 45.0)],
      ),
    ] {
    let result = unwrap_layout(
      @layout.layout_flex(alignment_container(direction, extent, 20.0), [
        first, second,
      ]),
    )
    assert_eq(grow_main_bounds(result, direction), expected)
    assert_true(!result.overflow())
  }
}

///|
test "frozen limits retain the initial partial factor budget" {
  let direction = @layout.FlowDirection::row()
  for
    (extent, first, second, expected) in [
      (
        100.0,
        limited_item(1, 20.0, 0.0, Some(30.0), grow=0.25),
        grow_item(2, 20.0, 0.25),
        [(0.0, 30.0), (30.0, 35.0)],
      ),
      (
        100.0,
        limited_item(1, 20.0, 0.0, Some(30.0), grow=0.5),
        grow_item(2, 20.0, 0.5),
        [(0.0, 30.0), (30.0, 50.0)],
      ),
      (
        40.0,
        limited_item(1, 40.0, 35.0, None, grow=0.0, shrink=0.25),
        grow_item(2, 40.0, 0.0, shrink=0.25),
        [(0.0, 35.0), (35.0, 30.0)],
      ),
      (
        100.0,
        limited_item(1, 0.0, 0.0, Some(0.0), grow=0.25),
        grow_item(2, 20.0, 0.25),
        [(0.0, 0.0), (0.0, 40.0)],
      ),
    ] {
    let result = unwrap_layout(
      @layout.layout_flex(alignment_container(direction, extent, 20.0), [
        first, second,
      ]),
    )
    assert_eq(grow_main_bounds(result, direction), expected)
  }
}

///|
test "zero grow and zero maximum freeze at their hypothetical sizes" {
  let direction = @layout.FlowDirection::row()
  for
    (first, expected) in [
      (
        limited_item(1, 20.0, 0.0, Some(10.0), grow=0.0),
        [(0.0, 10.0), (10.0, 90.0)],
      ),
      (limited_item(1, 20.0, 0.0, Some(0.0)), [(0.0, 0.0), (0.0, 100.0)]),
    ] {
    let result = unwrap_layout(
      @layout.layout_flex(alignment_container(direction, 100.0, 20.0), [
        first,
        grow_item(2, 20.0, 1.0),
      ]),
    )
    assert_eq(grow_main_bounds(result, direction), expected)
    assert_true(!result.overflow())
  }
}

///|
// Three-child termination is a MoonBit unit contract, beyond the two-child oracle corpus.
test "successive limits freeze across multiple redistribution passes" {
  let direction = @layout.FlowDirection::row()
  let result = unwrap_layout(
    @layout.layout_flex(alignment_container(direction, 100.0, 20.0), [
      limited_item(1, 20.0, 0.0, Some(25.0)),
      grow_item(2, 20.0, 1.0),
      limited_item(3, 20.0, 0.0, Some(35.0)),
    ]),
  )
  assert_eq(grow_main_bounds(result, direction), [
    (0.0, 25.0),
    (25.0, 40.0),
    (65.0, 35.0),
  ])
  assert_true(!result.overflow())
}
