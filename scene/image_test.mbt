///|
fn image_test_data() -> @scene.ImageData {
  @scene.ImageData::new("77453d98d46494b3b34b94aa863b686ea299e0190030a5c7ca5377b238332522", 100, 200, 2).unwrap()
}

///|
fn image_test_rect(x : Double, y : Double, w : Double, h : Double) -> @primitives.Rect {
  @primitives.Rect::new(x, y, w, h).unwrap()
}

///|
test "image metadata validates identity dimensions and bounded prepared frames" {
  assert_true(@scene.ImageData::new("", 1, 1, 1) is Err(InvalidIdentity))
  let identity = image_test_data().content_identity()
  for dimensions in [(0, 1, 1), (1, 0, 1), (1, 1, 0), (1, 1, 257), (16385, 1, 1), (4096, 4096, 2)] {
    let (w, h, f) = dimensions
    assert_true(@scene.ImageData::new(identity, w, h, f) is Err(InvalidDimensions))
  }
  assert_eq(image_test_data().frame_count(), 2)
  assert_eq(image_test_data().pixel_width(), 100)
  assert_eq(image_test_data().pixel_height(), 200)
}

///|
test "image contain honors explicit square layout and cover preserves crop" {
  let data = image_test_data()
  let bounds = image_test_rect(0, 0, 100, 100)
  assert_true(data.fit_bounds(bounds, @scene.Contain).unwrap() == image_test_rect(25, 0, 50, 100))
  assert_true(data.fit_bounds(bounds, @scene.Cover).unwrap() == image_test_rect(0, -50, 100, 200))
  assert_true(data.fit_bounds(bounds, @scene.Fill).unwrap() == bounds)
  let empty = image_test_rect(10, 20, 0, 100)
  assert_true(data.fit_bounds(empty, @scene.Cover).unwrap() == image_test_rect(10, 20, 0, 0))
}

///|
test "image resource arrays are copied and prepared frame remains selected" {
  let data = image_test_data()
  let resource = @scene.SceneResource::image(7, data)
  let bounds = image_test_rect(0, 0, 100, 100)
  let item = @scene.SceneItem::image(2, 7, 1, data.fit_bounds(bounds, @scene.Contain).unwrap(), bounds, @scene.AffineTransform::identity(), 0.25, None).unwrap()
  let resources = [resource]
  let items = [item]
  let snapshot = @scene.SceneSnapshot::new(bounds, 1, resources, [], items).unwrap()
  let before = snapshot.canonical_json()
  resources[0] = @scene.SceneResource::new(99)
  items.clear()
  let exposed = snapshot.resources()
  exposed.clear()
  let exposed_items = snapshot.items()
  exposed_items.clear()
  assert_eq(snapshot.canonical_json(), before)
  assert_true(snapshot.resources()[0].image_data().unwrap() == data)
  match snapshot.items()[0] {
    @scene.ImageItem(resource_id~, frame_index~, opacity~, bounds=fitted, image_bounds~, ..) => {
      assert_eq(resource_id, 7UL)
      assert_eq(frame_index, 1)
      assert_eq(opacity, 0.25)
      assert_true(fitted == image_test_rect(25, 0, 50, 100))
      assert_true(image_bounds == bounds)
    }
    _ => abort("expected resource-backed image")
  }
  assert_true(snapshot.legacy_v1_subset() is Err(UnsupportedPaint))
  assert_true(snapshot.sample_paint(2, @primitives.Point::new(50, 50).unwrap()) is Err(UnsupportedPaint))
}

///|
test "image missing wrong duplicate and invalid frame resources fail closed" {
  let bounds = image_test_rect(0, 0, 100, 100)
  let resource = @scene.SceneResource::image(7, image_test_data())
  let item = @scene.SceneItem::image(1, 7, 0, bounds, bounds, @scene.AffineTransform::identity(), 1, None).unwrap()
  assert_true(@scene.SceneSnapshot::new(bounds, 1, [], [], [item]) is Err(InvalidImage(MissingResource)))
  assert_true(@scene.SceneSnapshot::new(bounds, 1, [@scene.SceneResource::new(7)], [], [item]) is Err(InvalidImage(MissingResource)))
  assert_true(@scene.SceneSnapshot::new(bounds, 1, [resource, resource], [], [item]) is Err(InvalidImage(DuplicateResource)))
  for index in [-1, 2] {
    assert_true(@scene.PaintCommand::image(1, resource, index, bounds, bounds, 1) is Err(InvalidFrame))
  }
  let stale = @scene.ImageItem(id=1, resource_id=7, frame_index=2, bounds~, image_bounds=bounds, transform=@scene.AffineTransform::identity(), opacity=1, clip_chain_id=None)
  assert_true(@scene.SceneSnapshot::new(bounds, 1, [resource], [], [stale]) is Err(InvalidImage(InvalidFrame)))
  let clipped = @scene.SceneItem::image(1, 7, 0, bounds, bounds, @scene.AffineTransform::identity(), 1, Some(99)).unwrap()
  assert_true(@scene.SceneSnapshot::new(bounds, 1, [resource], [], [clipped]) is Err(UnknownClipChain))
  for opacity in [-0.1, 1.1, 0.0 / 0.0] {
    assert_true(@scene.PaintCommand::image(1, resource, 0, bounds, bounds, opacity) is Err(InvalidOpacity))
  }
}

///|
test "image commands deduplicate identical resources and reject collisions before snapshot" {
  let bounds = image_test_rect(0, 0, 100, 100)
  let data = image_test_data()
  let resource = @scene.SceneResource::image(7, data)
  let first = @scene.PaintCommand::image(1, resource, 0, bounds, bounds, 0.5).unwrap()
  let second = @scene.PaintCommand::image(2, resource, 1, bounds, bounds, 0.5).unwrap().with_opacity(0.5).unwrap()
  assert_eq(second.opacity(), 0.25)
  assert_true(second.color() is None)
  let scene = @scene.Scene::new([first, second])
  let snapshot = scene.snapshot_v1(bounds, 1).unwrap()
  assert_eq(snapshot.resources().length(), 1)
  assert_eq(snapshot.items().length(), 2)
  let conflicting = @scene.SceneResource::image(7, @scene.ImageData::new(data.content_identity(), 200, 100, 2).unwrap())
  let bad = @scene.PaintCommand::image(3, conflicting, 0, bounds, bounds, 1).unwrap()
  assert_true(@scene.Scene::new([first, bad]).snapshot_v1(bounds, 1) is Err(InvalidImage(ConflictingResource)))
  let missing = @scene.ImageCommand(id=4, resource=@scene.SceneResource::new(8), frame_index=0, bounds~, image_bounds=bounds, opacity=1)
  assert_true(@scene.Scene::new([first, missing]).validate() is Err(InvalidImage(MissingResource)))
}

///|
test "image canonical transport keeps resource identity scalar and crop separate" {
  let bounds = image_test_rect(0, 0, 100, 100)
  let resource = @scene.SceneResource::image(7, image_test_data())
  let command = @scene.PaintCommand::image(2, resource, 1, image_test_rect(25, 0, 50, 100), bounds, 0.25).unwrap()
  let snapshot = @scene.Scene::new([command]).snapshot_v1(bounds, 1).unwrap()
  assert_eq(snapshot.canonical_json(), "{\"schema_version\":1,\"viewport\":{\"x\":0,\"y\":0,\"width\":100,\"height\":100},\"scale\":1,\"resources\":[{\"id\":7,\"kind\":\"image\",\"content_identity\":\"77453d98d46494b3b34b94aa863b686ea299e0190030a5c7ca5377b238332522\",\"pixel_width\":100,\"pixel_height\":200,\"frame_count\":2}],\"clip_chains\":[],\"items\":[{\"kind\":\"image\",\"id\":2,\"resource_id\":7,\"frame_index\":1,\"bounds\":{\"x\":25,\"y\":0,\"width\":50,\"height\":100},\"image_bounds\":{\"x\":0,\"y\":0,\"width\":100,\"height\":100},\"transform\":{\"a\":1,\"b\":0,\"c\":0,\"d\":1,\"tx\":0,\"ty\":0},\"opacity\":0.25,\"clip_chain_id\":null}]}")
  let background = @primitives.FloatColor::rgba(0, 0, 0, 0).unwrap()
  assert_true(snapshot.rasterize_webgl2_linear(bounds, 1, 1, background) is Err(UnsupportedPaint))
  assert_true(snapshot.rasterize_item_tile_webgl2_linear(0) is Err(UnsupportedPaint))
  assert_true(snapshot.rasterize_paint_run_webgl2_linear(0, 1) is Err(UnsupportedPaint))
}

///|
test "legacy id-only placeholders keep canonical bytes and image identity conflicts reject" {
  let bounds = image_test_rect(0, 0, 1, 1)
  let legacy = @scene.SceneSnapshot::new(bounds, 1, [@scene.SceneResource::new(9)], [], []).unwrap()
  assert_eq(legacy.canonical_json(), "{\"schema_version\":1,\"viewport\":{\"x\":0,\"y\":0,\"width\":1,\"height\":1},\"scale\":1,\"resources\":[{\"id\":9}],\"clip_chains\":[],\"items\":[]}")
  let data = image_test_data()
  let other = @scene.ImageData::new(data.content_identity(), 200, 100, 2).unwrap()
  assert_true(@scene.SceneSnapshot::new(bounds, 1, [@scene.SceneResource::image(7, data), @scene.SceneResource::image(8, other)], [], []) is Err(InvalidImage(ConflictingResource)))
}
