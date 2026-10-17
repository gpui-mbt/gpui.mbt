///|
test "freeze rejects package-level invalid gradient values and nonfinite transforms" {
  let rect = @primitives.Rect::new(0, 0, 10, 10).unwrap()
  let shape = PaintShape::rounded_quad(rect, 0).unwrap()
  let color = @primitives.FloatColor::rgba(1, 0, 0, 1).unwrap()
  let invalid = LinearGradient::{
    angle: 0.0 / 0.0,
    start: color,
    start_position: 0,
    end: color,
    end_position: 1,
    space: Srgb,
  }
  let fill = Gradient(invalid)
  assert_true(PaintCommand::paint(1, shape, fill, 1) is Err(InvalidGradient))
  let command = PaintCommand::PaintCommand(id=1, shape~, fill~, opacity=1)
  assert_true(
    Scene::new([command]).command_snapshot(rect, 1)
    is Err(InvalidPaint(InvalidGradient)),
  )
  let item = PaintItem(
    id=1,
    shape~,
    fill~,
    transform=AffineTransform::identity(),
    opacity=1,
    clip_chain_id=None,
  )
  assert_true(
    SceneSnapshot::new(rect, 1, [], [], [item])
    is Err(InvalidPaint(InvalidGradient)),
  )
  let transform = { ..AffineTransform::identity(), tx: 1.0 / 0.0, }
  let item = PaintItem(
    id=1,
    shape~,
    fill=FloatSolid(color),
    transform~,
    opacity=1,
    clip_chain_id=None,
  )
  assert_true(
    SceneSnapshot::new(rect, 1, [], [], [item]) is Err(NonFiniteTransform),
  )
}

///|
test "snapshot freeze rejects directly constructed tiny concave polygons" {
  let s = 1.0e-100
  let p = fn(x, y) { @primitives.Point::new(x * s, y * s).unwrap() }
  let bounds = @primitives.Rect::new(0, 0, 2 * s, 2 * s).unwrap()
  let shape = Polygon(ConvexPolygon::{
    points: [p(0, 0), p(2, 0), p(0.5, 0.5), p(0, 2)],
    bounds,
  })
  let fill = FloatSolid(@primitives.FloatColor::rgba(1, 0, 0, 1).unwrap())
  let command = PaintCommand::PaintCommand(id=1, shape~, fill~, opacity=1)
  assert_true(
    Scene::new([command]).snapshot_v1(bounds, 1)
    is Err(InvalidPaint(InvalidGeometry)),
  )
  let item = PaintItem(
    id=1,
    shape~,
    fill~,
    transform=AffineTransform::identity(),
    opacity=1,
    clip_chain_id=None,
  )
  assert_true(
    SceneSnapshot::new(bounds, 1, [], [], [item])
    is Err(InvalidPaint(InvalidGeometry)),
  )
}
