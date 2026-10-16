///|
test "distributed spacing includes outer spaces in rows and columns with gaps" {
  for
    direction in [@layout.FlowDirection::row(), @layout.FlowDirection::column()] {
    for
      (justify, expected) in [
        (@layout.JustifyContent::space_around(), [15.0, 73.0]),
        (@layout.JustifyContent::space_evenly(), [20.0, 68.0]),
      ] {
      let container = between_container(direction, 108.0, 40.0, 8.0).with_justify(
        justify,
      )
      let result = match
        @layout.layout_flex(container, [
          between_item(1, 20.0, 10.0),
          between_item(2, 20.0, 10.0),
        ]) {
        Ok(value) => value
        Err(_) => fail("distributed layout was rejected")
      }
      assert_eq(
        result.items().map(item => between_origin(item, direction)),
        expected,
      )
      assert_true(!result.overflow())
    }
  }
}

///|
test "distributed spacing safely handles empty singleton exact-fit and overflow" {
  for
    justify in [
      @layout.JustifyContent::space_around(),
      @layout.JustifyContent::space_evenly(),
    ] {
    let container = between_container(
      @layout.FlowDirection::row(),
      40.0,
      30.0,
      4.0,
    ).with_justify(justify)
    for
      (items, expected, overflow) in [
        ([], [], false),
        ([between_item(1, 20.0, 10.0)], [10.0], false),
        ([between_item(1, 60.0, 10.0)], [0.0], true),
        (
          [between_item(1, 18.0, 10.0), between_item(2, 18.0, 10.0)],
          [0.0, 22.0],
          false,
        ),
        (
          [between_item(1, 30.0, 10.0), between_item(2, 30.0, 10.0)],
          [0.0, 34.0],
          true,
        ),
      ] {
      let result = match @layout.layout_flex(container, items) {
        Ok(value) => value
        Err(_) => fail("distributed boundary layout was rejected")
      }
      assert_eq(result.items().map(item => item.bounds().left()), expected)
      assert_eq(result.overflow(), overflow)
    }
  }
}

///|
test "distributed spacing uses resolved sizes after capped and fractional growth" {
  for
    (justify, expected) in [
      (@layout.JustifyContent::space_around(), [15.0, 65.0]),
      (@layout.JustifyContent::space_evenly(), [20.0, 60.0]),
    ] {
    let container = between_container(
      @layout.FlowDirection::row(),
      100.0,
      30.0,
      0.0,
    ).with_justify(justify)
    let items = [between_item(1, 20.0, 10.0), between_item(2, 20.0, 10.0)]
    let items = items.map(item => {
      match item.with_flex(1.0, 0.0) {
        Ok(value) =>
          match value.with_main_limits(0.0, Some(20.0)) {
            Ok(value) => value
            Err(_) => abort("invalid limit")
          }
        Err(_) => abort("invalid flex")
      }
    })
    let result = match @layout.layout_flex(container, items) {
      Ok(value) => value
      Err(_) => fail("capped growth was rejected")
    }
    assert_eq(result.items().map(item => item.bounds().left()), expected)
    assert_eq(result.items().map(item => item.bounds().size().width()), [
      20.0, 20.0,
    ])
  }
  let container = between_container(
    @layout.FlowDirection::row(),
    104.0,
    30.0,
    0.0,
  ).with_justify(@layout.JustifyContent::space_around())
  let items = [between_item(1, 20.0, 10.0), between_item(2, 20.0, 10.0)].map(item => {
    match item.with_flex(0.25, 0.0) {
      Ok(value) => value
      Err(_) => abort("invalid flex")
    }
  })
  let result = match @layout.layout_flex(container, items) {
    Ok(value) => value
    Err(_) => fail("fractional growth was rejected")
  }
  assert_eq(result.items().map(item => item.bounds().left()), [8.0, 60.0])
  assert_eq(result.items().map(item => item.bounds().size().width()), [
    36.0, 36.0,
  ])
}

///|
test "wrapped distributed spacing centers singleton lines independently" {
  for wrap in [@layout.FlexWrap::wrap(), @layout.FlexWrap::wrap_reverse()] {
    for
      (justify, expected) in [
        (@layout.JustifyContent::space_around(), [6.0, 42.0, 19.0]),
        (@layout.JustifyContent::space_evenly(), [8.0, 40.0, 19.0]),
      ] {
      let container = between_container(
          @layout.FlowDirection::row(),
          68.0,
          32.0,
          4.0,
        )
        .with_justify(justify)
        .with_wrap(wrap)
      let result = match
        @layout.layout_flex(container, [
          between_item(1, 20.0, 10.0),
          between_item(2, 20.0, 10.0),
          between_item(3, 30.0, 10.0),
        ]) {
        Ok(value) => value
        Err(_) => fail("wrapped distributed layout was rejected")
      }
      assert_eq(result.items().map(item => item.bounds().left()), expected)
      let cross = if wrap is @layout.Wrap {
        [0.0, 0.0, 18.0]
      } else {
        [22.0, 22.0, 4.0]
      }
      assert_eq(result.items().map(item => item.bounds().top()), cross)
      assert_true(!result.overflow())
    }
  }
}
