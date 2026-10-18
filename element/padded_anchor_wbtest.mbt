///|
fn measured_test_owner() -> Element {
  let auto = @layout.Dimension::auto()
  let zero = @primitives.Size::new(0, 0).unwrap()
  let leaf = Element::new(
    @layout.FlexItem::new(3, auto, auto, @primitives.Size::new(60, 20).unwrap())
    .with_flex(0, 0)
    .unwrap(),
  )
  let attachment = Element::anchored_after_measured_leaf(
    20,
    3,
    anchored_test_popup(70),
    TopLeft,
    Local,
    @primitives.Point::new(0, 0).unwrap(),
  ).unwrap()
  Element::new(
    @layout.FlexItem::new(2, auto, auto, zero).with_flex(0, 0).unwrap(),
  )
  .with_children_style(
    @layout.FlexTreeStyle::new(@layout.FlowDirection::column()).with_insets(
      @layout.Insets::new(3, 7, 5, 11).unwrap(),
      @layout.Insets::new(1, 2, 3, 4).unwrap(),
    ),
  )
  .with_child(leaf)
  .with_child(attachment)
}

///|
test "measured leaf rejects fixed percent flex constrained or container references" {
  let owner = measured_test_owner()
  assert_true(validate_anchored_parent(owner) is Ok(_))
  let leaf = owner.children[0]
  let item = leaf.item.unwrap()
  let sized = fn(main : @layout.Dimension, cross : @layout.Dimension) {
    @layout.FlexItem::new(item.id(), main, cross, item.intrinsic)
    .with_flex(0, 0)
    .unwrap()
  }
  let changed_items = [
    sized(@layout.Dimension::points(20).unwrap(), item.cross),
    sized(item.main, @layout.Dimension::points(60).unwrap()),
    sized(@layout.Dimension::percent(0.5).unwrap(), item.cross),
    sized(item.main, @layout.Dimension::percent(0.5).unwrap()),
    item.with_flex(1, 0).unwrap(),
    item.with_flex(0, 1).unwrap(),
    item.with_main_limits(1, None).unwrap(),
    item.with_cross_limits(1, None).unwrap(),
    item.with_main_limits(0, Some(100)).unwrap(),
    item.with_cross_limits(0, Some(100)).unwrap(),
  ]
  for changed in changed_items {
    assert_true(
      validate_anchored_parent({
        ..owner,
        children: [{ ..leaf, item: Some(changed), }, owner.children[1]],
      })
      is Err(InvalidAnchoredShape),
    )
  }
  // Invalid flex factors cannot reach this package through the public layout
  // builders. Verify rejection there rather than fabricating foreign structs;
  // this is not coverage of malformed-item rejection inside the anchor guard.
  for invalid in [-1.0, 0.0 / 0.0, 1.0 / 0.0, -1.0 / 0.0] {
    assert_true(item.with_flex(invalid, 0) is Err(_))
    assert_true(item.with_flex(0, invalid) is Err(_))
  }
  for
    changed in [
      leaf.with_child(anchored_test_popup(10)),
      leaf.with_children_style(
        @layout.FlexTreeStyle::new(@layout.FlowDirection::column()),
      ),
      leaf.with_scroll_offset(@primitives.Point::new(0, 0).unwrap()),
      leaf.with_container_query(_ => abort("reference query must not execute")),
    ] {
    assert_true(
      validate_anchored_parent({
        ..owner,
        children: [changed, owner.children[1]],
      })
      is Err(InvalidAnchoredShape),
    )
  }
}

///|
test "measured parent restrictions and legacy rejection remain separate" {
  let owner = measured_test_owner()
  let style = owner.children_style.unwrap()
  for
    changed in [
      @layout.FlexTreeStyle::new(@layout.FlowDirection::row()).with_insets(
        style.padding,
        style.border,
      ),
      style.with_gap_x(1).unwrap(),
      style.with_gap_y(1).unwrap(),
      style.with_align(@layout.AlignItems::center()),
      style.with_justify(@layout.JustifyContent::center()),
    ] {
    assert_true(
      validate_anchored_parent({ ..owner, children_style: Some(changed), })
      is Err(InvalidAnchoredShape),
    )
  }
  let owner_item = owner.item.unwrap()
  let percentage_owner = @layout.FlexItem::new(
      owner_item.id(),
      @layout.Dimension::percent(0.5).unwrap(),
      owner_item.cross,
      owner_item.intrinsic,
    )
    .with_flex(0, 0)
    .unwrap()
  assert_true(
    validate_anchored_parent({ ..owner, item: Some(percentage_owner), })
    is Err(InvalidAnchoredShape),
  )
  let attachment = owner.children[1]
  let spec = attachment.anchored.unwrap()
  let legacy = {
    ..attachment,
    anchored: Some({ ..spec, measured_leaf: false, }),
  }
  assert_true(
    validate_anchored_parent({ ..owner, children: [owner.children[0], legacy], })
    is Err(InvalidAnchoredShape),
  )
  assert_true(
    validate_anchored_parent({
      ..owner,
      children: [owner.children[0], legacy],
      children_style: Some(
        style.with_insets(@layout.Insets::zero(), @layout.Insets::zero()),
      ),
    })
    is Err(InvalidAnchoredShape),
  )
  for
    children in [
      [owner.children[0], attachment, legacy],
      [owner.children[0], legacy, attachment],
      [owner.children[0], attachment, owner.children[0]],
      [owner.children[0]],
      [attachment, owner.children[0]],
      [
        owner.children[0],
        { ..attachment, anchored: Some({ ..spec, after: 99, }), },
      ],
    ] {
    assert_true(
      validate_anchored_parent({ ..owner, children, })
      is Err(InvalidAnchoredShape),
    )
  }
  // A fixed reference with decoration is still rejected by the old mode;
  // zero-inset fixed references retain the original acceptance boundary.
  let fixed = {
    ..owner.children[0],
    item: Some(
      @layout.FlexItem::new(
        owner.children[0].id,
        @layout.Dimension::points(20).unwrap(),
        @layout.Dimension::points(60).unwrap(),
        owner.children[0].item.unwrap().intrinsic,
      )
      .with_flex(0, 0)
      .unwrap(),
    ),
  }
  let old = { ..owner, children: [fixed, legacy], }
  assert_true(validate_anchored_parent(old) is Err(InvalidAnchoredShape))
  assert_true(
    validate_anchored_parent({
      ..old,
      children_style: Some(
        style.with_insets(@layout.Insets::zero(), @layout.Insets::zero()),
      ),
    })
    is Ok(_),
  )
}

///|
test "measured wrapper and popup guards remain on the production path" {
  let owner = measured_test_owner()
  let attachment = owner.children[1]
  let root = Element::root(
    1,
    @layout.FlexTreeStyle::new(@layout.FlowDirection::row()),
  )
  let viewport = @primitives.Size::new(640, 480).unwrap()
  for
    changed in [
      attachment.with_pointer_events(true),
      attachment.with_focusable(true),
      attachment.with_child(anchored_test_popup(80)),
    ] {
    assert_true(
      root
      .with_child({ ..owner, children: [owner.children[0], changed], })
      .request_layout(viewport)
      is Err(InvalidAnchoredShape),
    )
  }
  let queried = anchored_test_popup(70).with_container_query(_ => {
    abort("popup query must not execute")
  })
  assert_true(
    Element::anchored_after_measured_leaf(
      20,
      3,
      queried,
      TopLeft,
      Local,
      @primitives.Point::new(0, 0).unwrap(),
    )
    is Err(UnsupportedAnchoredComposition),
  )
  let request = root.with_child(owner).request_layout(viewport).unwrap()
  let tree = request.prepaint().unwrap().tree()
  let window = @primitives.Rect::new(0, 0, 640, 480).unwrap()
  assert_true(tree.node(20).unwrap().window_clip == Some(window))
  assert_true(!tree.node(20).unwrap().pointer_events)
  assert_true(
    tree.node(2).unwrap().bounds == requested_bounds(request, 2).unwrap(),
  )
}
