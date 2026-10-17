///|
fn nested_wb_leaf(id : UInt64, main : Double, cross : Double) -> Element {
  Element::new(
    @layout.FlexItem::new(
      id,
      @layout.Dimension::points(main).unwrap(),
      @layout.Dimension::points(cross).unwrap(),
      @primitives.Size::new(0, 0).unwrap(),
    )
    .with_flex(0, 0)
    .unwrap(),
  )
}

///|
fn nested_wb_outer(
  id : UInt64,
  priority : Int32,
  child_priority : Int32,
) -> Element {
  let popup = nested_wb_leaf(id, 96, 72)
    .with_children_style(
      @layout.FlexTreeStyle::new(@layout.FlowDirection::column()),
    )
    .with_child(nested_wb_leaf(id + 1, 0, 0))
    .with_child(
      Element::anchored_after(
        id + 2,
        id + 1,
        nested_wb_leaf(id + 3, 40, 32),
        TopLeft,
        Local,
        @primitives.Point::new(32, 24).unwrap(),
      )
      .unwrap()
      .deferred(priority=child_priority)
      .unwrap(),
    )
  Element::anchored_after(
    id + 10,
    2,
    popup,
    TopLeft,
    Local,
    @primitives.Point::new(24, 24).unwrap(),
  )
  .unwrap()
  .deferred(priority~)
  .unwrap()
}

///|
fn nested_wb_frame(
  ap : Int32,
  anp : Int32,
  bp : Int32,
  bnp : Int32,
) -> Prepainted {
  Element::root(1, @layout.FlexTreeStyle::new(@layout.FlowDirection::column()))
  .with_child(nested_wb_leaf(2, 0, 0))
  .with_child(nested_wb_outer(10, ap, anp))
  .with_child(nested_wb_outer(30, bp, bnp))
  .request_layout(@primitives.Size::new(320, 240).unwrap())
  .unwrap()
  .prepaint()
  .unwrap()
}

///|
test "nested discovery rounds and global paint differ from DFS and parent-contiguous order" {
  let nodes = nested_wb_frame(2, 3, 1, 3).tree.nodes
  assert_eq(nodes.map(node => node.id), [
    1, 2, 20, 10, 11, 12, 13, 40, 30, 31, 32, 33,
  ])
  let rounds = deferred_group_rounds(nodes)
  assert_eq(rounds.length(), 2)
  assert_eq(rounds[0].map(index => nodes[index].id), [20, 40])
  assert_eq(rounds[1].map(index => nodes[index].id), [32, 12])
  assert_eq(deferred_indices(nodes, false).map(index => nodes[index].id), [
    1, 2, 40, 30, 31, 20, 10, 11, 32, 33, 12, 13,
  ])
  assert_eq(deferred_paint_indices(nodes).map(index => nodes[index].id), [
    1, 2, 40, 30, 31, 20, 10, 11, 32, 33, 12, 13,
  ])
  let lower = nested_wb_frame(2, 0, 3, 1).tree.nodes
  assert_eq(deferred_indices(lower, false).map(index => lower[index].id), [
    1, 2, 20, 10, 11, 40, 30, 31, 12, 13, 32, 33,
  ])
  assert_eq(deferred_paint_indices(lower).map(index => lower[index].id), [
    1, 2, 12, 13, 32, 33, 20, 10, 11, 40, 30, 31,
  ])
  let equal = nested_wb_frame(2, 1, 1, 1).tree.nodes
  assert_eq(deferred_paint_indices(equal).map(index => equal[index].id), [
    1, 2, 40, 30, 31, 32, 33, 12, 13, 20, 10, 11,
  ])
  let maximum = nested_wb_frame(2147483647, 2147483647, 2147483646, 2147483647).tree.nodes
  assert_eq(deferred_paint_indices(maximum).map(index => maximum[index].id), [
    1, 2, 40, 30, 31, 20, 10, 11, 32, 33, 12, 13,
  ])
}

///|
test "nested metadata cannot merge equal-priority groups or detach inherited members" {
  let frame = nested_wb_frame(1, 1, 1, 1)
  let original = frame.tree.nodes
  assert_true(original[2].deferred_group == Some(20))
  assert_true(original[5].deferred_group == Some(12))
  assert_true(original[6].deferred_group == Some(12))
  for
    (index, replacement) in [
      (5, { ..original[5], deferred_group: Some(20), }),
      (5, { ..original[5], deferred_group: Some(99), }),
      (5, { ..original[5], deferred: None, deferred_group: None, }),
      (5, { ..original[5], anchored_after: None, }),
      (5, { ..original[5], deferred: Some(2), }),
      (6, { ..original[6], deferred_group: Some(13), }),
      (6, { ..original[6], deferred_group: Some(20), }),
      (6, { ..original[6], deferred: Some(2), }),
      (6, { ..original[6], deferred_group: None, }),
      (2, { ..original[2], deferred_group: Some(99), }),
    ] {
    let changed = original.copy()
    changed[index] = replacement
    assert_true(
      ElementTree::new(changed) is Err(UnsupportedAnchoredComposition),
    )
  }
  let negative = original.copy()
  negative[5] = { ..original[5], deferred: Some(-1), }
  assert_true(ElementTree::new(negative) is Err(InvalidDeferredPriority))
  let wrong_parent = original.copy()
  wrong_parent[5] = { ..original[5], parent: Some(1), }
  assert_true(ElementTree::new(wrong_parent) is Err(InvalidAnchoredShape))
  // Bounds-only refresh checks group membership independently of priority,
  // even if an internal caller bypasses the normal validated constructor.
  let changed = original.copy()
  changed[6] = { ..original[6], deferred_group: Some(20), }
  let malformed = { ..frame, tree: { ..frame.tree, nodes: changed, }, }
  assert_true(
    frame.tree.with_layout_bounds(malformed) is Err(LayoutBoundsMismatch),
  )
  assert_true(frame.tree.nodes[6].deferred_group == Some(12))
}

///|
test "nested nontrivial ancestor clips and reconstructed third group reject atomically" {
  let frame = nested_wb_frame(1, 1, 1, 1)
  let original = frame.tree.nodes
  let clip = @primitives.Rect::new(0, 0, 24, 24).unwrap()
  // The popup root is between the inner and outer attachment wrappers. A
  // different mask here must not disappear when the child paints separately.
  let clipped = original.copy()
  clipped[3] = { ..original[3], window_clip: Some(clip), }
  assert_true(ElementTree::new(clipped) is Err(UnsupportedAnchoredComposition))
  let changed_root = original.copy()
  changed_root[0] = { ..original[0], window_clip: Some(clip), }
  assert_true(
    ElementTree::new(changed_root) is Err(UnsupportedAnchoredComposition),
  )
  let deeper : Array[ElementNode] = []
  for index = 0; index < original.length(); index = index + 1 {
    deeper.push(original[index])
    if original[index].id == 13 {
      deeper.push({ ..original[6], id: 51, parent: Some(13), })
      deeper.push({
        ..original[5],
        id: 50,
        parent: Some(13),
        anchored_after: Some(51),
        deferred_group: Some(50),
      })
      deeper.push({
        ..original[6],
        id: 52,
        parent: Some(50),
        deferred_group: Some(50),
      })
    }
  }
  assert_true(ElementTree::new(deeper) is Err(UnsupportedAnchoredComposition))
  assert_true(ElementTree::new(original) is Ok(_))
}

///|
test "nested unsupported contextual composition rejects before query execution" {
  let outer = nested_wb_outer(10, 1, 1)
  let popup = outer.children[0]
  let queried = popup.with_container_query(_ => abort("query must not execute"))
  let scrolled = popup.with_scroll_offset(@primitives.Point::new(0, 0).unwrap())
  for unsupported in [queried, scrolled] {
    assert_true(
      Element::anchored_after(
        20,
        2,
        unsupported,
        TopLeft,
        Local,
        @primitives.Point::new(0, 0).unwrap(),
      )
      is Err(UnsupportedAnchoredComposition),
    )
  }
}

///|
test "nested measurement reads its live reference from the real parent popup layout" {
  let outer = nested_wb_outer(10, 1, 2)
  let popup = outer.children[0]
  let build = fn(height : Double) {
    let changed_popup = {
      ..popup,
      children: [nested_wb_leaf(11, height, 20), popup.children[1]],
    }
    Element::root(
      1,
      @layout.FlexTreeStyle::new(@layout.FlowDirection::column()),
    )
    .with_child(nested_wb_leaf(2, 0, 0))
    .with_child({ ..outer, children: [changed_popup], })
    .request_layout_with_device_scale(
      @primitives.Size::new(320, 240).unwrap(),
      1.25,
    )
    .unwrap()
  }
  let request = build(16)
  let measurements = request.anchored_layout.unwrap().measured
  let inner = measurements.filter(value => value.0 == 12)[0].1
  assert_true(
    inner.layout.root_bounds().origin() ==
    @primitives.Point::new(0, 16).unwrap(),
  )
  let first = request.prepaint().unwrap()
  assert_true(
    first.tree.node(12).unwrap().bounds ==
    @primitives.Rect::new(24, 40, 40, 32).unwrap(),
  )
  assert_true(
    first.tree.node(13).unwrap().bounds ==
    @primitives.Rect::new(56, 64, 40, 32).unwrap(),
  )
  let changed = build(24).prepaint().unwrap()
  let retained = first.tree.with_focus(13)
  assert_true(retained is Err(NotFocusable))
  let refreshed = first.tree.with_layout_bounds(changed).unwrap()
  assert_true(
    refreshed.node(13).unwrap().bounds ==
    @primitives.Rect::new(56, 72, 40, 32).unwrap(),
  )
  assert_true(
    first.tree.node(13).unwrap().bounds ==
    @primitives.Rect::new(56, 64, 40, 32).unwrap(),
  )
}
