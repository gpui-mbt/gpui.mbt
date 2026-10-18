///|
test "scalar quad opacity preserves legacy geometry color and default command" {
  let color = @primitives.Color::rgba(100, 50, 20, 127).unwrap()
  for rect in [
    @primitives.Rect::new(0, 0, 0, 0).unwrap(),
    @primitives.Rect::new(2000000000, 0, 10, 10).unwrap(),
  ] {
    let original = @scene.PaintCommand::quad(1, rect, color)
    assert_true(original.with_opacity(1).unwrap() == original)
    let command = original.with_opacity(0.3).unwrap().with_opacity(0.7).unwrap()
    assert_eq(command.opacity(), 0.3 * 0.7)
    assert_true(command.bounds() == Some(rect))
    assert_true(command.color() == Some(color))
    assert_true(command.kind() == @scene.Quad)
    let scene = @scene.Scene::new([command])
    assert_true(scene.validate() is Ok(_))
    let snapshot = scene.snapshot_v1(@primitives.Rect::new(0, 0, 100, 100).unwrap(), 1).unwrap()
    assert_true(snapshot.items()[0] is @scene.QuadItem(opacity~, ..) && opacity == 0.3 * 0.7)
  }
}

///|
test "command opacity rejects invalid scalar including raw new variants" {
  let bounds = @primitives.Rect::new(0, 0, 10, 10).unwrap()
  let color = @primitives.Color::rgba(0, 0, 0, 255).unwrap()
  let original = @scene.PaintCommand::quad(1, bounds, color)
  for invalid in [-1.0, 1.1, 0.0 / 0.0, 1.0 / 0.0] {
    assert_true(original.with_opacity(invalid) is Err(InvalidOpacity))
    let raw = @scene.OpacityQuadCommand(id=1, bounds~, color~, opacity=invalid)
    assert_true(@scene.Scene::new([raw]).validate() is Err(InvalidPaint(InvalidOpacity)))
    assert_true(raw.with_opacity(0) is Err(InvalidOpacity))
  }
  let clip = @scene.PaintCommand::clip_push(1, bounds)
  assert_true(clip.with_opacity(0).unwrap() == clip)
}
