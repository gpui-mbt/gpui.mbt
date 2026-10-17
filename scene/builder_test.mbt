///|
fn builder_rect(
  x : Double,
  y : Double,
  width : Double,
  height : Double,
) -> @primitives.Rect {
  @primitives.Rect::new(x, y, width, height).unwrap()
}

///|
fn builder_color(red : Int32, green : Int32, blue : Int32) -> @primitives.Color {
  @primitives.Color::rgba(red, green, blue, 255).unwrap()
}

///|
fn builder_snapshot(builder : @scene.SceneBuilder) -> @scene.SceneSnapshot {
  match builder.snapshot() {
    Ok(value) => value
    Err(_) => abort("valid builder scene should snapshot")
  }
}

///|
test "scene builder allocates monotonic item ids and emits quads" {
  let builder = @scene.SceneBuilder::new(
    builder_rect(0.0, 0.0, 100.0, 80.0),
    1.0,
  ).unwrap()
  let first = builder
    .quad(builder_rect(1.0, 2.0, 10.0, 12.0), builder_color(10, 20, 30))
    .unwrap()
  let second = builder
    .quad(builder_rect(3.0, 4.0, 5.0, 6.0), builder_color(40, 50, 60))
    .unwrap()
  assert_eq(first, 1UL)
  assert_eq(second, 2UL)
  assert_eq(builder.next_item_id(), 3UL)
  let snapshot = builder_snapshot(builder)
  assert_eq(snapshot.items().length(), 2)
  assert_eq(snapshot.items()[0].id(), 1UL)
  assert_eq(snapshot.items()[1].id(), 2UL)
}

///|
test "scene builder reserves ids for external control items" {
  let builder = @scene.SceneBuilder::new(
    builder_rect(0.0, 0.0, 100.0, 80.0),
    1.0,
  ).unwrap()
  let base = builder.reserve_ids(2).unwrap()
  assert_eq(base, 1UL)
  assert_eq(builder.next_item_id(), 3UL)
  let external = @scene.SceneItem::quad(
    base,
    builder_rect(0.0, 0.0, 10.0, 10.0),
    builder_color(1, 2, 3),
    @scene.AffineTransform::identity(),
    1.0,
    None,
  ).unwrap()
  builder.push_items([external]).unwrap()
  let next = builder
    .quad(builder_rect(1.0, 1.0, 2.0, 2.0), builder_color(4, 5, 6))
    .unwrap()
  assert_eq(next, 3UL)
  assert_eq(builder_snapshot(builder).items().length(), 2)
}

///|
test "scene builder rejects duplicate external item ids" {
  let builder = @scene.SceneBuilder::new(
    builder_rect(0.0, 0.0, 100.0, 80.0),
    1.0,
  ).unwrap()
  ignore(
    builder
    .quad(builder_rect(0.0, 0.0, 10.0, 10.0), builder_color(1, 2, 3))
    .unwrap(),
  )
  let duplicate = @scene.SceneItem::quad(
    1UL,
    builder_rect(0.0, 0.0, 10.0, 10.0),
    builder_color(1, 2, 3),
    @scene.AffineTransform::identity(),
    1.0,
    None,
  ).unwrap()
  assert_true(builder.push_items([duplicate]) is Err(@scene.DuplicateId(1UL)))
}

///|
test "scene builder border emits four edge quads" {
  let builder = @scene.SceneBuilder::new(
    builder_rect(0.0, 0.0, 100.0, 80.0),
    1.0,
  ).unwrap()
  builder
  .border(builder_rect(10.0, 20.0, 40.0, 30.0), 2.0, builder_color(1, 2, 3))
  .unwrap()
  let snapshot = builder_snapshot(builder)
  assert_eq(snapshot.items().length(), 4)
  assert_eq(builder.item_count(), 4)
}

///|
test "scene builder deduplicates identical clip chains" {
  let builder = @scene.SceneBuilder::new(
    builder_rect(0.0, 0.0, 100.0, 80.0),
    1.0,
  ).unwrap()
  let first = builder.clip([builder_rect(1.0, 2.0, 3.0, 4.0)]).unwrap()
  let second = builder.clip([builder_rect(1.0, 2.0, 3.0, 4.0)]).unwrap()
  let other = builder.clip([builder_rect(5.0, 6.0, 7.0, 8.0)]).unwrap()
  assert_eq(first, second)
  assert_true(first != other)
  assert_eq(builder.clip_count(), 2)
}

///|
test "scene builder applies horizontal and vertical text alignment" {
  let bounds = builder_rect(10.0, 20.0, 100.0, 40.0)
  let cases = [
    (@scene.TextAlign::Left, @scene.TextVerticalAlign::Top, 10.0, 20.0),
    (@scene.TextAlign::Center, @scene.TextVerticalAlign::Top, 49.0, 20.0),
    (@scene.TextAlign::Right, @scene.TextVerticalAlign::Top, 88.0, 20.0),
    (@scene.TextAlign::Left, @scene.TextVerticalAlign::Center, 10.0, 35.0),
    (@scene.TextAlign::Center, @scene.TextVerticalAlign::Center, 49.0, 35.0),
    (@scene.TextAlign::Right, @scene.TextVerticalAlign::Center, 88.0, 35.0),
    (@scene.TextAlign::Left, @scene.TextVerticalAlign::Bottom, 10.0, 50.0),
    (@scene.TextAlign::Center, @scene.TextVerticalAlign::Bottom, 49.0, 50.0),
    (@scene.TextAlign::Right, @scene.TextVerticalAlign::Bottom, 88.0, 50.0),
  ]
  for (align, vertical, expected_x, expected_y) in cases {
    let builder = @scene.SceneBuilder::new(
      builder_rect(0.0, 0.0, 200.0, 120.0),
      1.0,
    ).unwrap()
    ignore(
      builder
      .text(
        bounds,
        "Aligned",
        16.0,
        builder_color(10, 20, 30),
        align,
        vertical,
        20.0,
        10.0,
        None,
      )
      .unwrap(),
    )
    let snapshot = builder_snapshot(builder)
    match snapshot.items()[0] {
      @scene.TextItem(bounds~, text="Aligned", ..) => {
        assert_eq(bounds.left(), expected_x)
        assert_eq(bounds.top(), expected_y)
        assert_eq(bounds.size().width(), 22.0)
        assert_eq(bounds.size().height(), 10.0)
      }
      _ => fail("builder text should emit a text item")
    }
  }
}

///|
test "scene builder rejects invalid text metrics and clip limits" {
  let builder = @scene.SceneBuilder::new(
    builder_rect(0.0, 0.0, 100.0, 80.0),
    1.0,
  ).unwrap()
  assert_true(
    builder.text(
      builder_rect(0.0, 0.0, 100.0, 20.0),
      "bad",
      16.0,
      builder_color(1, 2, 3),
      @scene.TextAlign::Left,
      @scene.TextVerticalAlign::Top,
      0.0 / 0.0,
      10.0,
      None,
    )
    is Err(@scene.InvalidMetrics),
  )
  let rects : Array[@primitives.Rect] = []
  for index in 0..<65 {
    rects.push(builder_rect(index.to_double(), 0.0, 1.0, 1.0))
  }
  assert_true(builder.clip(rects) is Err(_))
}

///|
test "scene builder rejects invalid scale and exhausted ids" {
  assert_true(
    @scene.SceneBuilder::new(builder_rect(0.0, 0.0, 100.0, 80.0), 0.0)
    is Err(@scene.InvalidScale),
  )
  let builder = @scene.SceneBuilder::new(
    builder_rect(0.0, 0.0, 100.0, 80.0),
    1.0,
  ).unwrap()
  assert_true(builder.reserve_ids(0) is Ok(_))
  assert_true(builder.reserve_ids(-1) is Err(@scene.InvalidId))
}

///|
test "scene builder snapshots copy items and clips" {
  let builder = @scene.SceneBuilder::new(
    builder_rect(0.0, 0.0, 100.0, 80.0),
    1.0,
  ).unwrap()
  let clip = builder.clip([builder_rect(0.0, 0.0, 50.0, 50.0)]).unwrap()
  ignore(
    builder
    .text(
      builder_rect(0.0, 0.0, 100.0, 20.0),
      "copy",
      16.0,
      builder_color(1, 2, 3),
      @scene.TextAlign::Left,
      @scene.TextVerticalAlign::Top,
      20.0,
      10.0,
      Some(clip),
    )
    .unwrap(),
  )
  let snapshot = builder_snapshot(builder)
  let items = snapshot.items()
  ignore(items.pop())
  assert_eq(snapshot.items().length(), 1)
  let clips = snapshot.clip_chains()
  assert_eq(clips.length(), 1)
}
