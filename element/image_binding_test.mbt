///|
fn bound_image(
  id : UInt64,
  fit : @scene.ImageFit,
  opacity : Double,
) -> @element.ElementImageBinding {
  let data = @scene.ImageData::new(
    "77453d98d46494b3b34b94aa863b686ea299e0190030a5c7ca5377b238332522", 100, 200,
    1,
  ).unwrap()
  @element.ElementImageBinding::new(
    id,
    @scene.SceneResource::image(7, data),
    0,
    fit,
    opacity,
  ).unwrap()
}

///|
test "actual image prepaint preserves explicit geometry opacity siblings and hit tree" {
  let color = @primitives.Color::rgba(20, 40, 60, 127).unwrap()
  let style = @layout.FlexTreeStyle::new(@layout.FlowDirection::row())
  let frame = @element.Element::root(1, style)
    .with_child(
      @element.Element::new(lifecycle_item(2, 100, 100))
      .with_opacity(0.5)
      .unwrap()
      .with_children_style(style)
      .with_child(
        @element.Element::new(lifecycle_item(3, 100, 100))
        .with_opacity(0.5)
        .unwrap(),
      ),
    )
    .with_child(
      @element.Element::new(lifecycle_item(4, 100, 100)).with_background(
        Some(color),
      ),
    )
    .request_layout(lifecycle_size(200, 100))
    .unwrap()
    .prepaint()
    .unwrap()
  let hit = frame.tree().hit_test(@primitives.Point::new(50, 50).unwrap())
  let binding = bound_image(3, @scene.Contain, 1)
  let scene = frame.paint_with_images([binding]).unwrap()
  match scene.command_at(0).unwrap() {
    @scene.ImageCommand(bounds~, image_bounds~, opacity~, resource~, ..) => {
      assert_eq(bounds.left(), 25)
      assert_eq(bounds.size().width(), 50)
      assert_eq(bounds.size().height(), 100)
      assert_true(image_bounds == frame.tree().node(3).unwrap().bounds())
      assert_eq(opacity, 0.25)
      assert_eq(resource.image_data().unwrap().pixel_height(), 200)
    }
    _ => abort("first command should be an image")
  }
  assert_eq(scene.command_at(1).unwrap().opacity(), 1)
  assert_true(scene.command_at(1).unwrap().color() == Some(color))
  assert_true(
    frame.tree().hit_test(@primitives.Point::new(50, 50).unwrap()) == hit,
  )
  assert_true(
    frame.paint_with_images([binding]).unwrap().commands() == scene.commands(),
  )
  assert_eq(frame.paint().command_count(), 1)
  let invisible = frame
    .paint_with_images([bound_image(3, @scene.Cover, 0)])
    .unwrap()
  assert_eq(invisible.command_at(0).unwrap().opacity(), 0)
  assert_true(
    frame.tree().hit_test(@primitives.Point::new(50, 50).unwrap()) == hit,
  )
}

///|
test "image bindings reject duplicate and missing elements without changing scene" {
  let bounds = @primitives.Rect::new(0, 0, 100, 100).unwrap()
  let tree = @element.ElementTree::new([
    @element.ElementNode::new(1, None, bounds),
  ]).unwrap()
  let binding = bound_image(1, @scene.Contain, 1)
  assert_true(
    tree.to_scene_with_images([binding, binding]) is Err(DuplicatePaintBinding),
  )
  assert_true(
    tree.to_scene_with_images([bound_image(99, @scene.Contain, 1)])
    is Err(UnknownElement),
  )
  assert_eq(tree.to_scene().command_count(), 0)
  let a = tree.to_scene_with_images([binding]).unwrap()
  assert_eq(a.command_count(), 1)
  let snapshot = a.snapshot_v1(bounds, 1).unwrap()
  assert_eq(snapshot.resources().length(), 1)
}

///|
test "image binding retains actual ancestor clip and distinct crop geometry" {
  let frame = @element.Element::root(
      1,
      @layout.FlexTreeStyle::new(@layout.FlowDirection::row()),
    )
    .with_opacity(0.5)
    .unwrap()
    .with_scroll_offset(@primitives.Point::new(0, 0).unwrap())
    .with_child(
      @element.Element::new(lifecycle_item(2, 100, 100))
      .with_opacity(0.5)
      .unwrap(),
    )
    .request_layout(lifecycle_size(100, 100))
    .unwrap()
    .prepaint()
    .unwrap()
  let scene = frame
    .paint_with_images([bound_image(2, @scene.Cover, 1)])
    .unwrap()
  assert_true(scene.validate() is Ok(_))
  let snapshot = scene
    .snapshot_v1(@primitives.Rect::new(0, 0, 100, 100).unwrap(), 1)
    .unwrap()
  assert_eq(snapshot.clip_chains().length(), 1)
  match snapshot.items()[0] {
    @scene.ImageItem(bounds~, image_bounds~, opacity~, clip_chain_id~, ..) => {
      assert_eq(bounds.top(), -50)
      assert_eq(bounds.size().height(), 200)
      assert_eq(image_bounds.top(), 0)
      assert_eq(image_bounds.size().height(), 100)
      assert_eq(opacity, 0.25)
      assert_true(clip_chain_id is Some(_))
    }
    _ => abort("expected clipped image")
  }
}
