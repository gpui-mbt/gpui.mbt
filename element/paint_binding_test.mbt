///|
fn bound_paint(id : UInt64) -> @element.ElementPaintBinding {
  @element.ElementPaintBinding::new(id, bounds => {
    match @scene.PaintShape::rounded_quad(bounds, 0.0) {
      Err(e) => Err(e)
      Ok(shape) =>
        Ok(
          (
            shape,
            @scene.FloatSolid(
              @primitives.FloatColor::rgba(0, 0.5, 0, 1).unwrap(),
            ),
            0.5,
          ),
        )
    }
  })
}

///|
test "paint binding resolves actual current prepainted layout without changing hit tree" {
  let element = @element.Element::root(
      1,
      @layout.FlexTreeStyle::new(@layout.FlowDirection::row()),
    )
    .with_child(@element.Element::new(lifecycle_item(2, 20, 40)))
    .with_child(@element.Element::new(lifecycle_item(3, 30, 40)))
  let first = element
    .request_layout(lifecycle_size(100, 40))
    .unwrap()
    .prepaint()
    .unwrap()
  let first_tree = first.tree()
  let hit = first_tree.hit_test(@primitives.Point::new(25, 5).unwrap())
  let scene = first.paint_with_paints([bound_paint(3)]).unwrap()
  assert_true(
    scene.command_at(0).unwrap().bounds() ==
    Some(first_tree.node(3).unwrap().bounds()),
  )
  assert_true(
    first.tree().hit_test(@primitives.Point::new(25, 5).unwrap()) == hit,
  )
  assert_eq(first.paint().command_count(), 0)
  let resized = @element.Element::root(
      1,
      @layout.FlexTreeStyle::new(@layout.FlowDirection::row()),
    )
    .with_child(@element.Element::new(lifecycle_item(2, 40, 40)))
    .with_child(@element.Element::new(lifecycle_item(3, 30, 40)))
    .request_layout(lifecycle_size(100, 40))
    .unwrap()
    .prepaint()
    .unwrap()
  let second = resized.paint_with_paints([bound_paint(3)]).unwrap()
  assert_eq(scene.command_at(0).unwrap().bounds().unwrap().left(), 20)
  assert_eq(second.command_at(0).unwrap().bounds().unwrap().left(), 40)
}

///|
test "paint binding duplicate and missing IDs reject before any resolution" {
  let calls = [0]
  let resolver = @element.ElementPaintBinding::new(1, bounds => {
    calls[0] = calls[0] + 1
    Ok(
      (
        @scene.PaintShape::rounded_quad(bounds, 0).unwrap(),
        @scene.FloatSolid(@primitives.FloatColor::rgba(1, 0, 0, 1).unwrap()),
        1.0,
      ),
    )
  })
  let rect = @primitives.Rect::new(0, 0, 10, 10).unwrap()
  let tree = @element.ElementTree::new([
    @element.ElementNode::new(1, None, rect),
  ]).unwrap()
  assert_true(
    tree.to_scene_with_paints([resolver, resolver])
    is Err(DuplicatePaintBinding),
  )
  assert_true(
    tree.to_scene_with_paints([resolver, bound_paint(99)])
    is Err(UnknownElement),
  )
  assert_eq(calls[0], 0)
  let invalid = @element.ElementPaintBinding::new(1, _bounds => {
    Err(@scene.PaintError::InvalidGeometry)
  })
  assert_true(
    tree.to_scene_with_paints([invalid]) is Err(PaintFailure(InvalidGeometry)),
  )
  assert_eq(tree.to_scene().command_count(), 0)
}
