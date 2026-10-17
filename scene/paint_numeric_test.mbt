///|
test "tiny convex polygons retain valid geometry and reject concavity and crossings" {
  let s = 1.0e-100
  let p = fn(x, y) { @primitives.Point::new(x * s, y * s).unwrap() }
  assert_true(
    @scene.PaintShape::convex_polygon([p(0, 0), p(2, 0), p(0.5, 0.5), p(0, 2)])
    is Err(InvalidGeometry),
  )
  assert_true(
    @scene.PaintShape::convex_polygon([p(0, 0), p(2, 2), p(2, 0), p(0, 2)])
    is Err(InvalidGeometry),
  )
  let triangle = @scene.PaintShape::convex_polygon([p(0, 0), p(1, 0), p(0, 1)]).unwrap()
  assert_true(triangle.contains(p(0.1, 0.1)))
  assert_false(triangle.contains(p(1, 1)))
}

///|
test "magnified tiny triangle samples and rasters preserve outside coverage" {
  let s = 1.0e-100
  let p = fn(x, y) { @primitives.Point::new(x * s, y * s).unwrap() }
  let triangle = @scene.PaintShape::convex_polygon([p(0, 0), p(1, 0), p(0, 1)]).unwrap()
  let fill = @scene.FloatSolid(
    @primitives.FloatColor::rgba(1, 0, 0, 1).unwrap(),
  )
  let transform = @scene.AffineTransform::new(1.0e100, 0, 0, 1.0e100, 0, 0).unwrap()
  let item = @scene.SceneItem::paint(1, triangle, fill, transform, 1, None).unwrap()
  let viewport = @primitives.Rect::new(0, 0, 1, 1).unwrap()
  let frame = @scene.SceneSnapshot::new(viewport, 1, [], [], [item]).unwrap()
  assert_true(
    frame.sample_paint(1, @primitives.Point::new(0.75, 0.75).unwrap())
    is Ok(None),
  )
  assert_eq(
    frame
    .rasterize_webgl2_linear(
      @primitives.Rect::new(0.7, 0.7, 0.1, 0.1).unwrap(),
      1,
      1,
      @primitives.FloatColor::rgba(0, 0, 0, 0).unwrap(),
    )
    .unwrap(),
    [0, 0, 0, 0],
  )
}

///|
test "tiny rounded corners remain outside after affine magnification" {
  let s = 1.0e-200
  let rect = @primitives.Rect::new(0, 0, 2 * s, 2 * s).unwrap()
  let shape = @scene.PaintShape::rounded_quad(rect, s).unwrap()
  assert_false(shape.contains(@primitives.Point::new(0, 0).unwrap()))
  assert_true(shape.contains(@primitives.Point::new(s, s).unwrap()))
  let transform = @scene.AffineTransform::new(1.0e200, 0, 0, 1.0e200, 0, 0).unwrap()
  let item = @scene.SceneItem::paint(
    1,
    shape,
    @scene.FloatSolid(@primitives.FloatColor::rgba(1, 0, 0, 1).unwrap()),
    transform,
    1,
    None,
  ).unwrap()
  let frame = @scene.SceneSnapshot::new(
    @primitives.Rect::new(0, 0, 2, 2).unwrap(),
    1,
    [],
    [],
    [item],
  ).unwrap()
  assert_true(
    frame.sample_paint(1, @primitives.Point::new(0.1, 0.1).unwrap()) is Ok(None),
  )
}

///|
test "finite distant points cannot poison polygon containment with nonfinite products" {
  let p = fn(x, y) { @primitives.Point::new(x, y).unwrap() }
  let diamond = @scene.PaintShape::convex_polygon([
    p(0, -1.0e9),
    p(1.0e9, 0),
    p(0, 1.0e9),
    p(-1.0e9, 0),
  ]).unwrap()
  assert_false(diamond.contains(p(1.0e308, 1.0e308)))
  let item = @scene.SceneItem::paint(
    1,
    diamond,
    @scene.FloatSolid(@primitives.FloatColor::rgba(1, 0, 0, 1).unwrap()),
    @scene.AffineTransform::identity(),
    1,
    None,
  ).unwrap()
  let viewport = @primitives.Rect::new(0, 0, 1.0e308, 1.0e308).unwrap()
  let frame = @scene.SceneSnapshot::new(viewport, 1, [], [], [item]).unwrap()
  assert_true(frame.sample_paint(1, p(1.0e308, 1.0e308)) is Ok(None))
}

///|
test "extent normalized orientation supports tiny representable convex polygons" {
  let s = 1.0e-200
  let p = fn(x, y) { @primitives.Point::new(x * s, y * s).unwrap() }
  assert_true(
    @scene.PaintShape::convex_polygon([p(0, 0), p(2, 0), p(0.5, 0.5), p(0, 2)])
    is Err(InvalidGeometry),
  )
  assert_true(
    @scene.PaintShape::convex_polygon([p(0, 0), p(2, 2), p(2, 0), p(0, 2)])
    is Err(InvalidGeometry),
  )
  let result = @scene.PaintShape::convex_polygon([p(0, 0), p(1, 0), p(0, 1)])
  assert_true(result is Ok(_))
  let triangle = result.unwrap()
  assert_true(triangle.contains(p(0.1, 0.1)))
  assert_false(triangle.contains(p(1, 1)))
  let item = @scene.SceneItem::paint(
    1,
    triangle,
    @scene.FloatSolid(@primitives.FloatColor::rgba(1, 0, 0, 1).unwrap()),
    @scene.AffineTransform::new(1.0e200, 0, 0, 1.0e200, 0, 0).unwrap(),
    1,
    None,
  ).unwrap()
  let frame = @scene.SceneSnapshot::new(
    @primitives.Rect::new(0, 0, 1, 1).unwrap(),
    1,
    [],
    [],
    [item],
  ).unwrap()
  assert_true(
    frame.sample_paint(1, @primitives.Point::new(0.75, 0.75).unwrap())
    is Ok(None),
  )
}
