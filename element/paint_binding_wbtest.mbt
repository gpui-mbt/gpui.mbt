///|
test "enhanced bindings use existing deferred order and restore exact clip stack" {
  let bounds = @primitives.Rect::new(0, 0, 80, 80).unwrap()
  let color = Some(@primitives.Color::rgba(10, 20, 30, 255).unwrap())
  let nodes = deferred_test_tree(true).nodes()
  let clipped = { ..nodes[1], window_clip: Some(bounds), }
  nodes[1] = clipped
  let tree = ElementTree::new(nodes).unwrap()
  let binding = ElementPaintBinding::new(4, bounds => {
    Ok(
      (
        @scene.PaintShape::rounded_quad(bounds, 0).unwrap(),
        @scene.FloatSolid(@primitives.FloatColor::rgba(0, 0.5, 0, 1).unwrap()),
        1.0,
      ),
    )
  })
  let old_scene = tree.to_scene()
  let scene = tree.to_scene_with_paints([binding]).unwrap()
  assert_eq(
    scene.commands().map(c => c.id()),
    old_scene.commands().map(c => c.id()),
  )
  assert_true(scene.validate() is Ok(_))
  let old_snapshot = old_scene.snapshot_v1(bounds, 1).unwrap()
  let snapshot = scene.snapshot_v1(bounds, 1).unwrap()
  assert_eq(snapshot.items().map(i => i.id()), [1, 2, 5, 3, 4])
  assert_eq(
    snapshot.items().map(i => i.clip_chain_id()),
    old_snapshot.items().map(i => i.clip_chain_id()),
  )
  assert_true(tree.hit_test(@primitives.Point::new(30, 30).unwrap()) == Some(4))
  // A sibling outside the clipped subtree does not inherit its clip.
  let simple = ElementTree::new([
    ElementNode::new(1, None, bounds).with_background(color),
    { ..ElementNode::new(2, Some(1), bounds), window_clip: Some(bounds), },
    ElementNode::new(3, Some(2), bounds).with_background(color),
    ElementNode::new(4, Some(1), bounds).with_background(color),
  ]).unwrap()
  let frame = simple
    .to_scene_with_paints([binding])
    .unwrap()
    .snapshot_v1(bounds, 1)
    .unwrap()
  assert_eq(frame.items().map(i => i.clip_chain_id()), [None, Some(0), None])
}
