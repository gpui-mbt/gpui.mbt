///|
fn between_size(width : Double, height : Double) -> @primitives.Size raise {
  match @primitives.Size::new(width, height) {
    Ok(value) => value
    Err(_) => fail("valid space-between size was rejected")
  }
}

///|
fn between_point(value : Double) -> @layout.Dimension raise {
  match @layout.Dimension::points(value) {
    Ok(result) => result
    Err(_) => fail("valid space-between point was rejected")
  }
}

///|
fn between_item(
  id : UInt64,
  width : Double,
  height : Double,
) -> @layout.FlexItem raise {
  let item = @layout.FlexItem::new(
    id,
    between_point(width),
    between_point(height),
    between_size(0.0, 0.0),
  )
  match item.with_flex(0.0, 0.0) {
    Ok(value) => value
    Err(_) => fail("valid space-between item was rejected")
  }
}

///|
fn between_container(
  direction : @layout.FlowDirection,
  main : Double,
  cross : Double,
  gap : Double,
) -> @layout.FlexContainer raise {
  let size = if direction is @layout.Row {
    between_size(main, cross)
  } else {
    between_size(cross, main)
  }
  let container = @layout.FlexContainer::new(direction, size)
  match container.with_gap(gap) {
    Ok(value) => value
    Err(_) => fail("valid space-between gap was rejected")
  }
}

///|
fn between_origin(
  item : @layout.LayoutBox,
  direction : @layout.FlowDirection,
) -> Double {
  let bounds = item.bounds()
  if direction is @layout.Row {
    bounds.left()
  } else {
    bounds.top()
  }
}

///|
test "space-between distributes positive free space in rows and columns" {
  for
    direction in [@layout.FlowDirection::row(), @layout.FlowDirection::column()] {
    let container = between_container(direction, 100.0, 30.0, 8.0).with_justify(
      @layout.JustifyContent::space_between(),
    )
    let result = match
      @layout.layout_flex(container, [
        between_item(1, 20.0, 10.0),
        between_item(2, 20.0, 10.0),
      ]) {
      Ok(value) => value
      Err(_) => fail("valid space-between layout was rejected")
    }
    assert_eq(result.items().map(item => between_origin(item, direction)), [
      0.0, 80.0,
    ])
    assert_true(!result.overflow())
  }
}

///|
test "space-between handles empty and singleton item lists" {
  let direction = @layout.FlowDirection::row()
  let container = between_container(direction, 100.0, 30.0, 8.0).with_justify(
    @layout.JustifyContent::space_between(),
  )
  let empty = match @layout.layout_flex(container, []) {
    Ok(value) => value
    Err(_) => fail("empty space-between layout was rejected")
  }
  assert_true(empty.items().length() == 0)
  assert_true(!empty.overflow())

  let singleton = match
    @layout.layout_flex(container, [between_item(1, 20.0, 10.0)]) {
    Ok(value) => value
    Err(_) => fail("singleton space-between layout was rejected")
  }
  assert_eq(singleton.items().map(item => item.bounds().left()), [0.0])
  assert_true(!singleton.overflow())
}

///|
test "space-between falls back to start placement during negative overflow" {
  let container = between_container(
    @layout.FlowDirection::row(),
    100.0,
    30.0,
    8.0,
  ).with_justify(@layout.JustifyContent::space_between())
  let result = match
    @layout.layout_flex(container, [
      between_item(1, 60.0, 10.0),
      between_item(2, 60.0, 10.0),
    ]) {
    Ok(value) => value
    Err(_) => fail("overflowing space-between layout was rejected")
  }
  assert_eq(result.items().map(item => item.bounds().left()), [0.0, 68.0])
  assert_true(result.overflow())
}

///|
test "wrapped space-between distributes free space independently per line" {
  let container = between_container(
      @layout.FlowDirection::row(),
      55.0,
      28.0,
      8.0,
    )
    .with_justify(@layout.JustifyContent::space_between())
    .with_wrap(@layout.FlexWrap::wrap())
  let result = match
    @layout.layout_flex(container, [
      between_item(1, 20.0, 10.0),
      between_item(2, 20.0, 10.0),
      between_item(3, 20.0, 10.0),
      between_item(4, 20.0, 10.0),
    ]) {
    Ok(value) => value
    Err(_) => fail("valid wrapped space-between layout was rejected")
  }
  let bounds = result
    .items()
    .map(item => {
      let rect = item.bounds()
      (rect.left(), rect.top(), rect.size().width(), rect.size().height())
    })
  assert_eq(bounds, [
    (0.0, 0.0, 20.0, 10.0),
    (35.0, 0.0, 20.0, 10.0),
    (0.0, 18.0, 20.0, 10.0),
    (35.0, 18.0, 20.0, 10.0),
  ])
  assert_true(!result.overflow())
}
