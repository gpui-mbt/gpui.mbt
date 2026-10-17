///|
fn paint_test_rect(
  x : Double,
  y : Double,
  w : Double,
  h : Double,
) -> @primitives.Rect {
  @primitives.Rect::new(x, y, w, h).unwrap()
}

///|
fn paint_test_point(x : Double, y : Double) -> @primitives.Point {
  @primitives.Point::new(x, y).unwrap()
}

///|
fn paint_test_color(
  r : Double,
  g : Double,
  b : Double,
  a : Double,
) -> @primitives.FloatColor {
  @primitives.FloatColor::rgba(r, g, b, a).unwrap()
}

///|
fn paint_test_fill() -> @scene.PaintFill {
  FloatSolid(paint_test_color(0.0, 0.5, 0.0, 1.0))
}

///|
fn paint_test_snapshot(
  commands : Array[@scene.PaintCommand],
) -> @scene.SceneSnapshot {
  @scene.Scene::new(commands)
  .snapshot_v1(paint_test_rect(0, 0, 200, 200), 1.0)
  .unwrap()
}

///|
test "enhanced shapes strictly validate direct enums and convex polygon domains" {
  let bounds = paint_test_rect(0, 0, 10, 20)
  for radius in [-1.0, 6.0, @double.not_a_number, @double.infinity] {
    assert_true(
      @scene.PaintShape::rounded_quad(bounds, radius) is Err(InvalidGeometry),
    )
    let direct = @scene.PaintCommand::PaintCommand(
      id=1,
      shape=RoundedQuad(bounds~, radius~),
      fill=paint_test_fill(),
      opacity=1.0,
    )
    assert_true(
      @scene.Scene::new([direct]).validate()
      is Err(InvalidPaint(InvalidGeometry)),
    )
    assert_true(
      @scene.Scene::new([direct]).snapshot_v1(bounds, 1)
      is Err(InvalidPaint(InvalidGeometry)),
    )
  }
  assert_true(
    @scene.PaintShape::rounded_quad(paint_test_rect(0, 0, 0, 1), 0)
    is Err(InvalidGeometry),
  )
  let a = paint_test_point(0, 0)
  let b = paint_test_point(10, 0)
  let c = paint_test_point(10, 10)
  let d = paint_test_point(0, 10)
  for
    invalid in [
      [],
      [a, b],
      [a, b, b, c],
      [a, c, b, d],
      [a, b, paint_test_point(5, 5), d],
      [a, b, paint_test_point(20, 0)],
    ] {
    assert_true(
      @scene.PaintShape::convex_polygon(invalid) is Err(InvalidGeometry),
    )
  }
  assert_true(@scene.PaintShape::convex_polygon([a, b, c, d]) is Ok(_))
  assert_true(@scene.PaintShape::convex_polygon([d, c, b, a]) is Ok(_))
  let too_many = []
  for _i = 0; _i < 65; _i = _i + 1 {
    too_many.push(a)
  }
  assert_true(
    @scene.PaintShape::convex_polygon(too_many) is Err(InvalidGeometry),
  )
}

///|
test "polygon owns vertices and computes actual clipped tight bounds" {
  let points = [
    paint_test_point(10, 30),
    paint_test_point(90, 30),
    paint_test_point(80, 80),
    paint_test_point(20, 80),
  ]
  let shape = @scene.PaintShape::convex_polygon(points).unwrap()
  points[0] = paint_test_point(0, 0)
  assert_true(shape.bounds() == paint_test_rect(10, 30, 80, 50))
  match shape {
    Polygon(p) => {
      let outgoing = p.points()
      outgoing[0] = paint_test_point(0, 0)
      assert_true(p.points()[0] == paint_test_point(10, 30))
    }
    _ => fail("expected polygon")
  }
  // Actual clipped trapezoid tight x range is 13..87, not bbox intersection 10..90.
  assert_true(
    shape.normalization_bounds([paint_test_rect(0, 45, 100, 50)]) ==
    Some(paint_test_rect(13, 45, 74, 35)),
  )
  assert_true(
    shape.normalization_bounds([paint_test_rect(100, 100, 10, 10)]) is None,
  )
  assert_true(shape.contains(paint_test_point(50, 50)))
  assert_false(shape.contains(paint_test_point(10, 79)))
}

///|
test "enhanced constructors and snapshot freeze validate the same direct items" {
  let bounds = paint_test_rect(0, 0, 10, 10)
  let shape = @scene.PaintShape::rounded_quad(bounds, 0).unwrap()
  let fill = paint_test_fill()
  let transform = @scene.AffineTransform::identity()
  for opacity in [-1.0, 1.1, @double.not_a_number, @double.infinity] {
    assert_true(
      @scene.SceneItem::paint(1, shape, fill, transform, opacity, None)
      is Err(InvalidPaint(InvalidOpacity)),
    )
    let direct = @scene.SceneItem::PaintItem(
      id=1,
      shape~,
      fill~,
      transform~,
      opacity~,
      clip_chain_id=None,
    )
    assert_true(
      @scene.SceneSnapshot::new(bounds, 1, [], [], [direct])
      is Err(InvalidPaint(InvalidOpacity)),
    )
  }
  let direct = @scene.SceneItem::PaintItem(
    id=1,
    shape=RoundedQuad(bounds~, radius=7),
    fill~,
    transform~,
    opacity=1,
    clip_chain_id=None,
  )
  assert_true(
    @scene.SceneSnapshot::new(bounds, 1, [], [], [direct])
    is Err(InvalidPaint(InvalidGeometry)),
  )
  let missing_clip = @scene.SceneItem::paint(
    1,
    shape,
    fill,
    transform,
    1,
    Some(99),
  ).unwrap()
  assert_true(
    @scene.SceneSnapshot::new(bounds, 1, [], [], [missing_clip])
    is Err(UnknownClipChain),
  )
}

///|
test "enhanced commands preserve clips order copies and legacy projection" {
  let rect = paint_test_rect(0, 0, 10, 10)
  let enhanced = @scene.PaintCommand::paint(
    2,
    @scene.PaintShape::rounded_quad(rect, 2).unwrap(),
    paint_test_fill(),
    0.5,
  ).unwrap()
  let solid = @scene.PaintCommand::quad(
    1,
    rect,
    @primitives.Color::rgba(1, 2, 3, 255).unwrap(),
  )
  let commands = [
    solid,
    @scene.PaintCommand::clip_push(9, rect),
    enhanced,
    @scene.PaintCommand::clip_pop(9),
    solid,
  ]
  let scene = @scene.Scene::new(commands)
  commands[2] = solid
  let snapshot = scene.snapshot_v1(rect, 1).unwrap()
  assert_eq(snapshot.items().map(item => item.id()), [1, 2, 1])
  assert_eq(snapshot.items().map(item => item.clip_chain_id()), [
    None,
    Some(0),
    None,
  ])
  assert_true(snapshot.legacy_v1_subset() is Err(UnsupportedPaint))
  assert_true(scene.command_at(2).unwrap().kind() == @scene.PaintKind::Paint)
  assert_true(scene.command_at(2).unwrap().color() is None)
  assert_true(scene.command_at(2).unwrap().bounds() == Some(rect))
  let legacy = paint_test_snapshot([solid, solid])
  assert_eq(
    legacy.legacy_v1_subset().unwrap().canonical_json(),
    legacy.canonical_json(),
  )
  assert_true(snapshot.canonical_json().contains("\"kind\":\"rounded_quad\""))
  assert_true(
    scene
    .command_snapshot(rect, 1)
    .unwrap()
    .canonical_json()
    .contains("\"kind\":\"paint\""),
  )
  assert_true(
    snapshot.sample_paint(1, paint_test_point(5, 5)) is Err(AmbiguousPaint),
  )
  assert_true(
    snapshot.sample_paint(99, paint_test_point(5, 5)) is Err(UnknownPaint),
  )
}

///|
test "shader-linear raster preserves float green straight alpha and opacity once" {
  let rect = paint_test_rect(0, 0, 1, 1)
  let shape = @scene.PaintShape::rounded_quad(rect, 0).unwrap()
  let solid = @scene.PaintCommand::paint(
    1,
    shape,
    FloatSolid(paint_test_color(0, 0.5, 0, 0.5)),
    1,
  ).unwrap()
  let snapshot = paint_test_snapshot([solid])
  assert_eq(
    snapshot
    .rasterize_webgl2_linear(rect, 1, 1, paint_test_color(1, 1, 1, 1))
    .unwrap(),
    [128, 191, 128, 255],
  )
  assert_eq(snapshot.rasterize_item_webgl2_linear(0, rect, 1, 1).unwrap(), [
    0, 128, 0, 128,
  ])
  let opacity = paint_test_snapshot([
    @scene.PaintCommand::paint(1, shape, paint_test_fill(), 0.5).unwrap(),
  ])
  assert_eq(
    opacity
    .rasterize_webgl2_linear(rect, 1, 1, paint_test_color(1, 1, 1, 1))
    .unwrap(),
    [128, 191, 128, 255],
  )
  let grad = @scene.LinearGradient::new(
    90,
    paint_test_color(1, 0, 0, 0),
    0,
    paint_test_color(0, 0, 1, 0.75),
    1,
    Srgb,
  ).unwrap()
  let snapshot = paint_test_snapshot([
    @scene.PaintCommand::paint(1, shape, Gradient(grad), 1).unwrap(),
  ])
  assert_eq(
    snapshot
    .rasterize_webgl2_linear(rect, 1, 1, paint_test_color(0, 0, 0, 1))
    .unwrap(),
    [20, 0, 20, 255],
  )
}

///|
test "sampling restores clips and uses polygon clipped normalization" {
  let shape = @scene.PaintShape::convex_polygon([
    paint_test_point(0, 30),
    paint_test_point(80, 30),
    paint_test_point(80, 80),
    paint_test_point(0, 80),
  ]).unwrap()
  let gradient = @scene.LinearGradient::new(
    180,
    paint_test_color(1, 0, 0, 1),
    0,
    paint_test_color(0, 0, 1, 1),
    1,
    Srgb,
  ).unwrap()
  let paint = @scene.PaintCommand::paint(1, shape, Gradient(gradient), 1).unwrap()
  let snapshot = paint_test_snapshot([
    @scene.PaintCommand::clip_push(9, paint_test_rect(0, 45, 80, 35)),
    paint,
    @scene.PaintCommand::clip_pop(9),
    @scene.PaintCommand::paint(2, shape, Gradient(gradient), 1).unwrap(),
  ])
  assert_true(snapshot.sample_paint(1, paint_test_point(40, 44)) is Ok(None))
  assert_true(snapshot.sample_paint(2, paint_test_point(40, 44)) is Ok(Some(_)))
  let clipped = snapshot
    .sample_paint(1, paint_test_point(40, 55.5))
    .unwrap()
    .unwrap()
  let unclipped = snapshot
    .sample_paint(2, paint_test_point(40, 55.5))
    .unwrap()
    .unwrap()
  assert_true(clipped.red() > unclipped.red())
  assert_true(clipped.blue() < unclipped.blue())
  let tile = snapshot.rasterize_item_tile_webgl2_linear(0).unwrap().unwrap()
  assert_eq([tile.x(), tile.y(), tile.width(), tile.height()], [0, 45, 80, 35])
  let bytes = tile.rgba()
  bytes[0] = 99
  assert_true(tile.rgba()[0] != 99)
}

///|
test "tile bounds are physical clipped tight and interleave explicit unsupported text" {
  let rect = paint_test_rect(1.25, 2.25, 3, 4)
  let shape = @scene.PaintShape::rounded_quad(rect, 1).unwrap()
  let transform = @scene.AffineTransform::new(2, 0, 0, 2, 3, 5).unwrap()
  let first = @scene.SceneItem::paint(
    1,
    shape,
    paint_test_fill(),
    transform,
    0.5,
    None,
  ).unwrap()
  let text = @scene.SceneItem::text(
    2,
    rect,
    "text",
    12,
    @primitives.Color::rgba(0, 0, 0, 255).unwrap(),
    @scene.AffineTransform::identity(),
    1,
    None,
  ).unwrap()
  let snapshot = @scene.SceneSnapshot::new(
    paint_test_rect(0, 0, 100, 100),
    2,
    [],
    [],
    [first, text, first],
  ).unwrap()
  let tile = snapshot.rasterize_item_tile_webgl2_linear(0).unwrap().unwrap()
  assert_eq([tile.x(), tile.y(), tile.width(), tile.height()], [11, 19, 12, 16])
  assert_true(
    snapshot.rasterize_item_tile_webgl2_linear(1) is Err(UnsupportedPaint),
  )
  assert_eq(
    snapshot.rasterize_item_tile_webgl2_linear(2).unwrap().unwrap().rgba(),
    tile.rgba(),
  )
  assert_true(
    snapshot.rasterize_webgl2_linear(rect, 1, 1, paint_test_color(0, 0, 0, 0))
    is Err(UnsupportedPaint),
  )
  assert_true(
    snapshot.rasterize_item_tile_webgl2_linear(-1) is Err(UnknownPaint),
  )
}

///|
test "bounded raster rejects budgets singular transforms and rotated transforms" {
  let rect = paint_test_rect(0, 0, 10, 10)
  let shape = @scene.PaintShape::rounded_quad(rect, 0).unwrap()
  let background = paint_test_color(0, 0, 0, 0)
  let snapshot = paint_test_snapshot([
    @scene.PaintCommand::paint(1, shape, paint_test_fill(), 1).unwrap(),
  ])
  for dims in [(0, 1), (1, 0), (2049, 1), (1025, 1025), (-1, 1)] {
    assert_true(
      snapshot.rasterize_webgl2_linear(rect, dims.0, dims.1, background)
      is Err(InvalidRaster),
    )
  }
  for
    transform in [
      @scene.AffineTransform::new(0, 0, 0, 1, 0, 0).unwrap(),
      @scene.AffineTransform::new(1, 1, 0, 1, 0, 0).unwrap(),
    ] {
    let item = @scene.SceneItem::paint(
      1,
      shape,
      paint_test_fill(),
      transform,
      1,
      None,
    ).unwrap()
    let frame = @scene.SceneSnapshot::new(rect, 1, [], [], [item]).unwrap()
    assert_true(
      frame.rasterize_webgl2_linear(rect, 1, 1, background)
      is Err(UnsupportedTransform),
    )
    assert_true(
      frame.sample_paint(1, paint_test_point(1, 1)) is Err(UnsupportedTransform),
    )
  }
}

///|
test "contiguous canonical paint run composites float alpha before final quantization" {
  let rect = paint_test_rect(0, 0, 1, 1)
  let white = @scene.SceneItem::quad(
    1,
    rect,
    @primitives.Color::rgba(255, 255, 255, 255).unwrap(),
    @scene.AffineTransform::identity(),
    1,
    None,
  ).unwrap()
  let shape = @scene.PaintShape::rounded_quad(rect, 0).unwrap()
  let paint = @scene.SceneItem::paint(
    2,
    shape,
    FloatSolid(paint_test_color(0, 0.5, 0, 0.5)),
    @scene.AffineTransform::identity(),
    1,
    None,
  ).unwrap()
  let text = @scene.SceneItem::text(
    3,
    rect,
    "x",
    12,
    @primitives.Color::rgba(0, 0, 0, 255).unwrap(),
    @scene.AffineTransform::identity(),
    1,
    None,
  ).unwrap()
  let frame = @scene.SceneSnapshot::new(rect, 1, [], [], [
    white, paint, text, paint,
  ]).unwrap()
  assert_eq(
    frame.rasterize_paint_run_webgl2_linear(0, 2).unwrap().unwrap().rgba(),
    [128, 191, 128, 255],
  )
  assert_true(
    frame.rasterize_paint_run_webgl2_linear(0, 3) is Err(UnsupportedPaint),
  )
  assert_eq(
    frame.rasterize_paint_run_webgl2_linear(3, 1).unwrap().unwrap().rgba(),
    [0, 128, 0, 128],
  )
  assert_true(
    frame.rasterize_paint_run_webgl2_linear(0, 0) is Err(UnknownPaint),
  )
  assert_true(
    frame.rasterize_paint_run_webgl2_linear(3, 2) is Err(UnknownPaint),
  )
}

///|
test "new canonical paint bytes are stable without changing envelope version" {
  let rect = paint_test_rect(0, 0, 1, 1)
  let paint = @scene.PaintCommand::paint(
    7,
    @scene.PaintShape::rounded_quad(rect, 0).unwrap(),
    paint_test_fill(),
    0.5,
  ).unwrap()
  let scene = @scene.Scene::new([paint])
  assert_eq(
    scene.snapshot_v1(rect, 1).unwrap().canonical_json(),
    "{\"schema_version\":1,\"viewport\":{\"x\":0,\"y\":0,\"width\":1,\"height\":1},\"scale\":1,\"resources\":[],\"clip_chains\":[],\"items\":[{\"kind\":\"paint\",\"id\":7,\"shape\":{\"kind\":\"rounded_quad\",\"bounds\":{\"x\":0,\"y\":0,\"width\":1,\"height\":1},\"radius\":0},\"fill\":{\"kind\":\"float_solid\",\"color\":{\"red\":0,\"green\":0.5,\"blue\":0,\"alpha\":1}},\"transform\":{\"a\":1,\"b\":0,\"c\":0,\"d\":1,\"tx\":0,\"ty\":0},\"opacity\":0.5,\"clip_chain_id\":null}]}",
  )
}
