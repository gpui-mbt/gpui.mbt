///|
test "enhanced guard preserves legacy macOS JSON bytes exactly" {
  let viewport = @primitives.Rect::new(0.0, 0.0, 100.0, 80.0).unwrap()
  let bounds = @primitives.Rect::new(5.0, 10.0, 40.0, 30.0).unwrap()
  let color = @primitives.Color::rgba(12, 34, 56, 128).unwrap()
  let item = @scene.SceneItem::quad(
    1,
    bounds,
    color,
    @scene.AffineTransform::identity(),
    0.5,
    None,
  ).unwrap()
  let snapshot = @scene.SceneSnapshot::new(viewport, 1.5, [], [], [item]).unwrap()
  let legacy = snapshot.legacy_v1_subset().unwrap()
  let golden = "{\"schema_version\":1,\"viewport\":{\"x\":0,\"y\":0,\"width\":100,\"height\":80},\"scale\":1.5,\"resources\":[],\"clip_chains\":[],\"items\":[{\"kind\":\"quad\",\"id\":1,\"bounds\":{\"x\":5,\"y\":10,\"width\":40,\"height\":30},\"color\":{\"red\":12,\"green\":34,\"blue\":56,\"alpha\":128},\"transform\":{\"a\":1,\"b\":0,\"c\":0,\"d\":1,\"tx\":0,\"ty\":0},\"opacity\":0.5,\"clip_chain_id\":null}]}"
  assert_eq(legacy.canonical_json(), golden)
  assert_true(@utf8.encode(legacy.canonical_json()) == @utf8.encode(golden))
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
  let host : Host = { marker: -1, text: Ref(text_input_owner()), }
  for paint in enhanced {
    let overloaded : Array[@scene.SceneItem] = []
    for i = 0; i < 1025; i = i + 1 {
      overloaded.push(text)
    }
    overloaded.push(paint)
    for items in [[paint], [text, paint], [paint, text], overloaded] {
      let snapshot = @scene.SceneSnapshot::new(viewport, 1.0, [], [], items).unwrap()
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
  let host : Host = { marker: -1, text: Ref(text_input_owner()), }
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
      // The stopped host must not be checked before image capability rejection.
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
