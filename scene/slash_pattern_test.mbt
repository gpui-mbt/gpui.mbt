///|
fn slash_test_pattern(width : Double, interval : Double) -> @scene.SlashPattern {
  @scene.SlashPattern::new(paint_test_color(1, 0, 0, 0.5), width, interval).unwrap()
}

///|
test "slash validates bounded dimensions before integer conversion" {
  let color = paint_test_color(1, 0, 0, 1)
  for invalid in [-1.0, 0.0, 0.001, 256.01, 1.0e308, @double.infinity, @double.not_a_number] {
    assert_true(@scene.SlashPattern::new(color, invalid, 4.5) is Err(InvalidPattern))
    assert_true(@scene.SlashPattern::new(color, 4.5, invalid) is Err(InvalidPattern))
  }
  assert_true(@scene.SlashPattern::new(color, 1.0 / 255.0, 256.0) is Ok(_))
  assert_eq(slash_test_pattern(256, 256).packed(), 4278190080.0)
}

///|
test "slash packing retains authored dimensions and the f32 transport loss" {
  let p = slash_test_pattern(4.5, 4.5)
  assert_eq(p.width(), 4.5)
  assert_eq(p.interval(), 4.5)
  assert_eq(p.color(), paint_test_color(1, 0, 0, 0.5))
  assert_eq(p.packed(), 75169792.0)
  // These independent integer/f32 fixtures detect unquantized shader models.
  assert_eq(slash_test_pattern(4.5, 9).packed(), 75170944.0)
  assert_eq(slash_test_pattern(56, 6).packed(), 935841344.0)
  assert_eq(p.validate(), Ok(()))
  assert_eq(p, slash_test_pattern(4.5, 4.5))
  assert_true(p != slash_test_pattern(4.5, 9))
}

///|
test "slash has stripe gap and fractional coverage with original quad phase" {
  let p = slash_test_pattern(4.5, 4.5)
  let bounds = paint_test_rect(10, 20, 100, 100)
  assert_eq(p.sample(paint_test_point(10, 20), bounds).unwrap().alpha(), 0.5)
  assert_eq(p.sample(paint_test_point(14.5, 20), bounds).unwrap().alpha(), 0.0)
  let edge = p.sample_shader_linear(paint_test_point(12.25, 20), bounds).unwrap()
  assert_true(edge.alpha() > 0.2 && edge.alpha() < 0.3)
  assert_eq(edge.red(), 1.0)
  assert_eq(edge.green(), 0.0)
  assert_eq(edge.blue(), 0.0)
  assert_eq(
    edge,
    p.sample(paint_test_point(102.25, -30), paint_test_rect(100, -30, 100, 100)).unwrap(),
  )
  assert_true(p.sample(paint_test_point(1.0e308, 0), bounds) is Err(InvalidGeometry))
  assert_true(p.sample(paint_test_point(0, 0), paint_test_rect(0, 0, 0, 1)) is Err(InvalidGeometry))
}

///|
test "slash clips preserve phase and item opacity is applied once" {
  let bounds = paint_test_rect(10, 20, 100, 100)
  let shape = @scene.PaintShape::rounded_quad(bounds, 0).unwrap()
  let fill = @scene.Slash(slash_test_pattern(4.5, 4.5))
  let transform = @scene.AffineTransform::new(1, 0, 0, 1, 30, 40).unwrap()
  let item = @scene.SceneItem::paint(1, shape, fill, transform, 0.5, Some(7)).unwrap()
  let viewport = paint_test_rect(0, 0, 200, 200)
  let frame = @scene.SceneSnapshot::new(viewport, 1, [], [
    @scene.ClipChain::new(7, [paint_test_rect(42, 60, 50, 50)]),
  ], [item]).unwrap()
  let expected = fill.sample(paint_test_point(12.25, 20.25), bounds).unwrap()
  match frame.sample_paint(1, paint_test_point(42.25, 60.25)).unwrap() {
    Some(c) => assert_eq(c.alpha(), expected.alpha() * 0.5)
    None => fail("visible slash sample was clipped"),
  }
  assert_true(frame.sample_paint(1, paint_test_point(40.25, 60.25)) is Ok(None))
}

///|
test "slash ordered raster uses translucent source over and rejects legacy backend" {
  let bounds = paint_test_rect(0, 0, 10, 10)
  let shape = @scene.PaintShape::rounded_quad(bounds, 0).unwrap()
  let pattern = slash_test_pattern(56, 6)
  let item = @scene.SceneItem::paint(1, shape, @scene.Slash(pattern),
    @scene.AffineTransform::identity(), 0.5, None).unwrap()
  let frame = @scene.SceneSnapshot::new(bounds, 1, [], [], [item]).unwrap()
  assert_eq(frame.rasterize_webgl2_linear(paint_test_rect(0, 0, 1, 1), 1, 1,
    paint_test_color(0, 0, 1, 1)).unwrap(), [64, 0, 191, 255])
  assert_true(frame.legacy_v1_subset() is Err(UnsupportedPaint))
  assert_true(frame.canonical_json().contains("\"kind\":\"slash_pattern\""))
  assert_true(frame.canonical_json().contains(pattern.canonical_json()))
  assert_eq(pattern.canonical_json(),
    "{\"color\":{\"red\":1,\"green\":0,\"blue\":0,\"alpha\":0.5},\"width\":56,\"interval\":6,\"packed\":935841344}")
}

///|
test "slash does not silently use clipped polygon gradient normalization" {
  let polygon = @scene.PaintShape::convex_polygon([
    paint_test_point(0, 0), paint_test_point(10, 0), paint_test_point(0, 10),
  ]).unwrap()
  assert_true(@scene.PaintCommand::paint(1, polygon,
    @scene.Slash(slash_test_pattern(4.5, 9)), 1) is Err(UnsupportedPaint))
  let direct = @scene.PaintCommand::PaintCommand(id=1, shape=polygon,
    fill=@scene.Slash(slash_test_pattern(4.5, 9)), opacity=1)
  assert_true(@scene.Scene::new([direct]).validate() is Err(InvalidPaint(UnsupportedPaint)))
}
