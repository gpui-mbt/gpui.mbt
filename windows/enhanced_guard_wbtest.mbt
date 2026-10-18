///|
test "enhanced guard preserves full legacy quad and mixed ABI golden records" {
  let viewport = @primitives.Rect::new(0.0, 0.0, 100.0, 80.0).unwrap()
  let bounds = @primitives.Rect::new(5.0, 10.0, 40.0, 30.0).unwrap()
  let color = @primitives.Color::rgba(12, 34, 56, 128).unwrap()
  let transform = @scene.AffineTransform::identity()
  let quad = @scene.SceneItem::quad(1, bounds, color, transform, 0.5, None).unwrap()
  let legacy = @scene.SceneSnapshot::new(viewport, 1.5, [], [], [quad]).unwrap()
  let actual = frame_data(legacy).unwrap()
  let golden : Array[Double] = [
    0, 0, 100, 80, 1.5, 5, 10, 40, 30, 12, 34, 56, 128, 1, 0, 0, 1, 0, 0, 0.5, 0,
    0, 100, 80,
  ]
  assert_eq(actual.length(), golden.length())
  for i = 0; i < golden.length(); i = i + 1 {
    assert_eq(actual[i], golden[i])
  }
  let text = @scene.SceneItem::text(
    2,
    bounds,
    "Hi",
    12.0,
    color,
    transform,
    0.5,
    None,
  ).unwrap()
  let origin = @primitives.Point::new(2.0, 3.0).unwrap()
  let run = @scene.SceneItem::text_run(
    3,
    bounds,
    origin,
    "Hi",
    12.0,
    color,
    transform,
    0.5,
    None,
  ).unwrap()
  for item in [text, run] {
    let snapshot = @scene.SceneSnapshot::new(viewport, 1.5, [], [], [item]).unwrap()
    let frame = mixed_frame_data(snapshot).unwrap()
    let is_origin = item is @scene.TextRunItem(..)
    let expected : Array[Double] = [
      0,
      0,
      100,
      80,
      1.5,
      if is_origin {
        2
      } else {
        1
      },
      5,
      10,
      40,
      30,
      12,
      34,
      56,
      128,
      1,
      0,
      0,
      1,
      0,
      0,
      0.5,
      0,
      0,
      100,
      80,
      0,
      2,
      12,
    ]
    expected.push(if is_origin { 2.0 } else { 0.0 })
    expected.push(if is_origin { 3.0 } else { 0.0 })
    assert_eq(frame.data.length(), expected.length())
    for i = 0; i < expected.length(); i = i + 1 {
      assert_eq(frame.data[i], expected[i])
    }
    assert_true(frame.text_bytes == b"Hi")
  }
}

///|
test "enhanced paint fails before native staging including mixed and oversized text" {
  let viewport = @primitives.Rect::new(0.0, 0.0, 100.0, 80.0).unwrap()
  let color = @primitives.Color::rgba(12, 34, 56, 255).unwrap()
  let start = @primitives.FloatColor::rgba(1.0, 0.0, 0.0, 1.0).unwrap()
  let end = @primitives.FloatColor::rgba(0.0, 0.0, 1.0, 1.0).unwrap()
  let gradient = @scene.LinearGradient::new(
    90.0,
    start,
    0.0,
    end,
    1.0,
    @scene.Srgb,
  ).unwrap()
  let quad = @scene.PaintShape::rounded_quad(viewport, 0.0).unwrap()
  let rounded = @scene.PaintShape::rounded_quad(viewport, 8.0).unwrap()
  let polygon = @scene.PaintShape::convex_polygon([
    @primitives.Point::new(0.0, 0.0).unwrap(),
    @primitives.Point::new(30.0, 0.0).unwrap(),
    @primitives.Point::new(15.0, 20.0).unwrap(),
  ]).unwrap()
  let identity = @scene.AffineTransform::identity()
  let text = @scene.SceneItem::text(
    2,
    viewport,
    "Hi",
    12.0,
    color,
    identity,
    1.0,
    None,
  ).unwrap()
  let enhanced = [
    @scene.SceneItem::paint(
      1,
      quad,
      @scene.Gradient(gradient),
      identity,
      1.0,
      None,
    ).unwrap(),
    @scene.SceneItem::paint(
      1,
      rounded,
      @scene.FloatSolid(start),
      identity,
      1.0,
      None,
    ).unwrap(),
    @scene.SceneItem::paint(
      1,
      polygon,
      @scene.Gradient(gradient),
      identity,
      1.0,
      None,
    ).unwrap(),
    // The public variant must get the same guard as validated constructors.
    @scene.PaintItem(
      id=1,
      shape=rounded,
      fill=@scene.Gradient(gradient),
      transform=identity,
      opacity=1.0,
      clip_chain_id=None,
    ),
  ]
  let host : Host = { token: -1, stopped: true, }
  for paint in enhanced {
    let overloaded : Array[@scene.SceneItem] = []
    for i = 0; i < 1025; i = i + 1 {
      overloaded.push(text)
    }
    overloaded.push(paint)
    for items in [[paint], [text, paint], [paint, text], overloaded] {
      let snapshot = @scene.SceneSnapshot::new(viewport, 1.0, [], [], items).unwrap()
      match frame_data(snapshot) {
        Ok(_) => fail("enhanced paint reached legacy native presentation")
        Err(error) => {
          assert_eq(
            error.code().label(),
            @diagnostics.UnsupportedCapability.label(),
          )
          assert_eq(error.operation(), "present")
        }
      }
      match mixed_frame_data(snapshot) {
        Ok(_) => fail("enhanced paint reached legacy native presentation")
        Err(error) => {
          assert_eq(
            error.code().label(),
            @diagnostics.UnsupportedCapability.label(),
          )
          assert_eq(error.operation(), "present")
        }
      }
      match host.present(@platform.WindowId::new(-1), snapshot) {
        Ok(_) => fail("enhanced paint reached legacy native presentation")
        Err(error) => {
          assert_eq(
            error.code().label(),
            @diagnostics.UnsupportedCapability.label(),
          )
          assert_eq(error.operation(), "present")
        }
      }
    }
  }
}

///|
test "image paint fails atomically before native staging and host checks" {
  let viewport = @primitives.Rect::new(0.0, 0.0, 100.0, 80.0).unwrap()
  let outside = @primitives.Rect::new(200.0, 200.0, 1.0, 1.0).unwrap()
  let color = @primitives.Color::rgba(12, 34, 56, 255).unwrap()
  let identity = @scene.AffineTransform::identity()
  let metadata = @scene.ImageData::new(
    "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef", 2, 2, 2,
  ).unwrap()
  let resource = @scene.SceneResource::image(7, metadata)
  let quad = @scene.SceneItem::quad(1, viewport, color, identity, 1.0, None).unwrap()
  let text = @scene.SceneItem::text(
    2,
    viewport,
    "Hi",
    12.0,
    color,
    identity,
    1.0,
    None,
  ).unwrap()
  let images = [
    @scene.SceneItem::image(3, 7, 0, viewport, viewport, identity, 1.0, None).unwrap(),
    // Public construction and invisible images must never bypass the gate.
    @scene.ImageItem(
      id=3,
      resource_id=7,
      frame_index=1,
      bounds=viewport,
      image_bounds=viewport,
      transform=identity,
      opacity=0.0,
      clip_chain_id=None,
    ),
    @scene.SceneItem::image(3, 7, 0, viewport, viewport, identity, 1.0, Some(7)).unwrap(),
  ]
  let host : Host = { token: -1, stopped: true, }
  for image in images {
    let overloaded : Array[@scene.SceneItem] = []
    for i = 0; i < 1025; i = i + 1 {
      overloaded.push(text)
    }
    overloaded.push(image)
    for
      items in [
        [image],
        [quad, image],
        [text, image],
        [image, text],
        overloaded,
      ] {
      let snapshot = @scene.SceneSnapshot::new(
        viewport,
        1.0,
        [resource],
        [@scene.ClipChain::new(7, [outside])],
        items,
      ).unwrap()
      match frame_data(snapshot) {
        Ok(_) => fail("image paint reached legacy quad serialization")
        Err(error) => {
          assert_eq(
            error.code().label(),
            @diagnostics.UnsupportedCapability.label(),
          )
          assert_eq(error.operation(), "present")
        }
      }
      match mixed_frame_data(snapshot) {
        Ok(_) => fail("image paint reached legacy mixed serialization")
        Err(error) => {
          assert_eq(
            error.code().label(),
            @diagnostics.UnsupportedCapability.label(),
          )
          assert_eq(error.operation(), "present")
        }
      }
      match host.present(@platform.WindowId::new(-1), snapshot) {
        Ok(_) => fail("image paint reached legacy native presentation")
        Err(error) => {
          assert_eq(
            error.code().label(),
            @diagnostics.UnsupportedCapability.label(),
          )
          assert_eq(error.operation(), "present")
        }
      }
    }
  }
}
